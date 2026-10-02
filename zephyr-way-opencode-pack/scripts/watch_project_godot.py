#!/usr/bin/env python3
"""Watch project.godot for a writer, and identify the process if one shows up.

Godot has rewritten this file destructively twice during milestone work -- dropping
[physics], renderer/rendering_method="forward_plus", vsync and the debug warning
suppressions -- and neither occurrence could be reproduced by running any of the
project's own commands. `inotifywait` and `strace` are not installed here, so this
calls inotify directly through ctypes and, the moment an event fires, reads
/proc/*/cmdline for every live process to name whoever was running.

Usage:  python3 scripts/watch_project_godot.py <command> [args...]

Runs the command with the watcher already attached, then reports every event seen and,
if the file's contents actually changed, which processes were alive at that moment.
Exit status is the command's own.
"""
import ctypes
import ctypes.util
import hashlib
import os
import subprocess
import sys
import threading

IN_MODIFY = 0x00000002
IN_CLOSE_WRITE = 0x00000008
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
IN_ATTRIB = 0x00000004
IN_DELETE = 0x00000400

WATCH = IN_MODIFY | IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE | IN_ATTRIB | IN_DELETE

EVENT_NAMES = {
    IN_MODIFY: "IN_MODIFY",
    IN_CLOSE_WRITE: "IN_CLOSE_WRITE",
    IN_MOVED_TO: "IN_MOVED_TO",
    IN_CREATE: "IN_CREATE",
    IN_ATTRIB: "IN_ATTRIB",
    IN_DELETE: "IN_DELETE",
}


def digest(path: str) -> str:
    try:
        with open(path, "rb") as handle:
            return hashlib.sha256(handle.read()).hexdigest()[:16]
    except OSError:
        return "<unreadable>"


def running_processes() -> list:
    """Command lines of every live process, for attributing a write."""
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as handle:
                raw = handle.read()
        except OSError:
            continue
        cmd = raw.replace(b"\0", b" ").decode("utf-8", "replace").strip()
        if not cmd:
            continue
        # Godot binaries only; a wall of unrelated processes helps nobody.
        if "godot" in cmd.lower() or "verify" in cmd.lower() or "run_tests" in cmd.lower():
            found.append((entry, cmd[:200]))
    return found


def watch(path: str, stop: threading.Event, events: list) -> None:
    libc_name = ctypes.util.find_library("c")
    libc = ctypes.CDLL(libc_name, use_errno=True)

    fd = libc.inotify_init1(os.O_NONBLOCK)
    if fd < 0:
        print("watch: inotify_init1 failed", file=sys.stderr)
        return
    directory = os.path.dirname(os.path.abspath(path)) or "."
    wd = libc.inotify_add_watch(fd, directory.encode(), WATCH)
    if wd < 0:
        print("watch: inotify_add_watch failed", file=sys.stderr)
        os.close(fd)
        return

    before = digest(path)
    try:
        while not stop.is_set():
            try:
                data = os.read(fd, 65536)
            except BlockingIOError:
                continue
            if not data:
                continue
            offset = 0
            # struct inotify_event { int wd; uint32_t mask; uint32_t cookie;
            #                         uint32_t len; char name[]; }
            while offset + 16 <= len(data):
                _, mask, _, name_len = (
                    int.from_bytes(data[offset:offset + 4], "little"),
                    int.from_bytes(data[offset + 4:offset + 8], "little"),
                    int.from_bytes(data[offset + 8:offset + 12], "little"),
                    int.from_bytes(data[offset + 12:offset + 16], "little"),
                )
                name = data[offset + 16:offset + 16 + name_len].split(b"\0")[0].decode(
                    "utf-8", "replace"
                )
                offset += 16 + name_len
                if name != os.path.basename(path):
                    continue
                names = [n for bit, n in EVENT_NAMES.items() if mask & bit]
                after = digest(path)
                events.append((names, after, before))
                before = after
    finally:
        os.close(fd)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    target = "project.godot"
    if not os.path.exists(target):
        print(f"watch: {target} not found in {os.getcwd()}")
        return 2

    stop = threading.Event()
    events: list = []
    thread = threading.Thread(target=watch, args=(target, stop, events), daemon=True)
    thread.start()
    # Give the watcher a moment to attach before the command can possibly write.
    thread.join(timeout=0.5)

    print(f"watch: attached to {os.path.abspath(target)}")
    print(f"watch: baseline digest {digest(target)}")
    print("")
    status = subprocess.call(sys.argv[1:])
    stop.set()
    thread.join(timeout=2.0)

    print("")
    print(f"watch: {len(events)} event(s) on {target}")
    for names, after, before in events:
        marker = "  CONTENT CHANGED" if after != before else "  (no content change)"
        print(f"  {', '.join(names)}{marker}: {before} -> {after}")
    if not events:
        print("  none")
    print(f"watch: final digest {digest(target)}")
    if events:
        print("")
        print("processes alive at the end of the run (godot/verify only):")
        for pid, cmd in running_processes():
            print(f"  {pid}: {cmd}")
    return status


if __name__ == "__main__":
    sys.exit(main())
