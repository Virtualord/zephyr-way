#!/usr/bin/env python3
"""Write the [input] section of project.godot.

Godot's serialized InputEventKey form is verbose and easy to hand-write
incorrectly, and an action may only be defined once, so the action table lives
here and is generated. Re-run after changing the bindings:

    python3 scripts/core/generate_input_map.py

Keep the action names in sync with FlightInput's exported defaults.
"""

from pathlib import Path

PROJECT_FILE = Path(__file__).resolve().parents[2] / "project.godot"

# Godot's physical keycodes. Arrow keys and modifiers live in a high range.
KEYCODES = {
    "KEY_W": 87,
    "KEY_S": 83,
    "KEY_A": 65,
    "KEY_D": 68,
    "KEY_Q": 81,
    "KEY_E": 69,
    "KEY_R": 82,
    "KEY_UP": 4194320,
    "KEY_DOWN": 4194322,
    "KEY_LEFT": 4194319,
    "KEY_RIGHT": 4194321,
    "KEY_SHIFT": 4194325,
    "KEY_CTRL": 4194326,
    "KEY_SPACE": 32,
}

# Godot's JoyButton enum.
JOY_BUTTONS = {
    "JOY_BUTTON_B": 1,
    "JOY_BUTTON_X": 2,
    "JOY_BUTTON_Y": 3,
    "JOY_BUTTON_LEFT_SHOULDER": 9,
    "JOY_BUTTON_RIGHT_SHOULDER": 10,
}

# Godot's JoyAxis enum.
JOY_AXES = {
    "JOY_AXIS_LEFT_X": 0,
    "JOY_AXIS_LEFT_Y": 1,
    "JOY_AXIS_TRIGGER_LEFT": 4,
    "JOY_AXIS_TRIGGER_RIGHT": 5,
}

# Every action maps to a list of event names. A "key:" entry becomes an
# InputEventKey, "button:" an InputEventJoypadButton and "axis:" an
# InputEventJoypadMotion with a trailing + or - giving the direction.
ACTIONS = {
    # WASD is the primary set; the arrow keys are separate actions so a player
    # can rebind one without losing the other.
    "pitch_up": ["key:KEY_W", "axis:JOY_AXIS_LEFT_Y-"],
    "pitch_up_arrow": ["key:KEY_UP"],
    "pitch_down": ["key:KEY_S", "axis:JOY_AXIS_LEFT_Y+"],
    "pitch_down_arrow": ["key:KEY_DOWN"],
    "roll_left": ["key:KEY_A", "axis:JOY_AXIS_LEFT_X-"],
    "roll_left_arrow": ["key:KEY_LEFT"],
    "roll_right": ["key:KEY_D", "axis:JOY_AXIS_LEFT_X+"],
    "roll_right_arrow": ["key:KEY_RIGHT"],
    "yaw_left": ["key:KEY_Q", "button:JOY_BUTTON_LEFT_SHOULDER"],
    "yaw_right": ["key:KEY_E", "button:JOY_BUTTON_RIGHT_SHOULDER"],
    "throttle_up": ["key:KEY_SHIFT"],
    "throttle_down": ["key:KEY_CTRL"],
    # Analogue throttle position, read by FlightInput as a target rather than a
    # rate. Right trigger by default, so the left trigger stays free for airbrake.
    "throttle_axis": ["axis:JOY_AXIS_TRIGGER_RIGHT+"],
    "airbrake": ["key:KEY_SPACE", "axis:JOY_AXIS_TRIGGER_LEFT+"],
    "reset_aircraft": ["key:KEY_R", "button:JOY_BUTTON_Y"],
}


def render_event(spec: str) -> str:
    kind, _, name = spec.partition(":")
    if kind == "key":
        return (
            'Object(InputEventKey,"resource_local_to_scene":false,'
            '"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,'
            '"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,'
            '"pressed":false,"keycode":0,'
            f'"physical_keycode":{KEYCODES[name]},"key_label":0,"unicode":0,'
            '"location":0,"echo":false,"script":null)'
        )
    if kind == "button":
        return (
            'Object(InputEventJoypadButton,"resource_local_to_scene":false,'
            '"resource_name":"","device":-1,"button_index":'
            f'{JOY_BUTTONS[name]},"pressure":0.0,"pressed":false,"script":null)'
        )
    if kind == "axis":
        axis, direction = name[:-1], name[-1]
        return (
            'Object(InputEventJoypadMotion,"resource_local_to_scene":false,'
            '"resource_name":"","device":-1,"axis":'
            f'{JOY_AXES[axis]},"axis_value":{1.0 if direction == "+" else -1.0},'
            '"script":null)'
        )
    raise ValueError(f"Unknown event spec: {spec}")


def render_input_section() -> str:
    lines = ["[input]", ""]
    for action, specs in ACTIONS.items():
        events = ", ".join(render_event(spec) for spec in specs)
        lines.append(f"{action}={{")
        lines.append('"deadzone": 0.2,')
        lines.append(f'"events": [{events}]')
        lines.append("}")
        lines.append("")
    return "\n".join(lines)


def main() -> None:
    text = PROJECT_FILE.read_text(encoding="utf-8")
    end = text.index("[physics]")

    # Replace an existing section if the script is re-run, otherwise insert one.
    start = text.index("[input]") if "[input]" in text else end

    PROJECT_FILE.write_text(
        text[:start] + render_input_section() + text[end:], encoding="utf-8"
    )
    print(f"Wrote {len(ACTIONS)} input actions to {PROJECT_FILE}")


if __name__ == "__main__":
    main()