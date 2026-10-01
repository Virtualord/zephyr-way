## Read-only accessor for design/color_palette.json.
##
## The palette JSON is the design contract, so this loads it at runtime instead
## of duplicating colours in code. References use "$group.name" syntax and are
## resolved on lookup. Weighted sets are exposed for procedural generation.
##
## Loading happens once and is cached. Any missing key logs a warning and
## returns a readable magenta so mistakes are obvious instead of silent.
class_name Palette
extends RefCounted

const PALETTE_PATH := "res://design/color_palette.json"

## How an unresolved lookup is reported.
enum Fallback {
	MAGENTA, ## Obvious, unmistakable placeholder for authoring mistakes.
	TRANSPARENT, ## Invisible result for optional stylisation passes.
}

static var _document: Dictionary = {}
static var _load_attempted := false

## Groups and ramps, or an empty dictionary when the contract file is absent.
static func document() -> Dictionary:
	_ensure_loaded()
	return _document


static func has_group(group: String) -> bool:
	return _ensure_loaded() and _document.get("groups", {}).has(group)


## Resolve a colour. Accepts "aircraft.cream" or the contract's "$aircraft.cream".
static func color(ref: String, fallback: Fallback = Fallback.MAGENTA) -> Color:
	_ensure_loaded()
	var key := ref.trim_prefix("$")
	var separator := key.find(".")
	if separator < 0:
		_warn_missing(ref)
		return _fallback_color(fallback)

	var group := key.substr(0, separator)
	var name := key.substr(separator + 1)

	var groups: Dictionary = _document.get("groups", {})
	if groups.has(group) and groups[group] is Dictionary and (groups[group] as Dictionary).has(name):
		return _parse_color(str(groups[group][name]), ref)

	# Ramps such as "ocean_depth" are indexed numerically via ramp_color().
	_warn_missing(ref)
	return _fallback_color(fallback)


## Sample a depth/elevation ramp, e.g. ramp_color("ocean_depth", 12.0).
## Stops are sorted by their key and clamped at both ends.
static func ramp_color(ref: String, value: float) -> Color:
	_ensure_loaded()
	var key := ref.trim_prefix("$")
	var ramps: Dictionary = _document.get("ramps", {})
	if not ramps.has(key) or not (ramps[key] as Array) is Array or (ramps[key] as Array).is_empty():
		_warn_missing(ref)
		return Color.MAGENTA

	var stops: Array = ramps[key]
	if stops.size() == 1:
		return color(str((stops[0] as Dictionary).get("color", "")), Fallback.MAGENTA)

	var previous: Dictionary = stops[0]
	for stop in stops:
		var stop_value := float((stop as Dictionary).get(_ramp_key(key), 0.0))
		if value <= stop_value:
			var span := stop_value - float(previous.get(_ramp_key(key), 0.0))
			var weight := 0.0 if is_zero_approx(span) else (value - float(previous.get(_ramp_key(key), 0.0))) / span
			var from := color(str(previous.get("color", "")), Fallback.MAGENTA)
			var to := color(str((stop as Dictionary).get("color", "")), Fallback.MAGENTA)
			return from.lerp(to, clampf(weight, 0.0, 1.0))
		previous = stop

	return color(str((previous as Dictionary).get("color", "")), Fallback.MAGENTA)


## Pick a colour from a weighted set such as "building_wall".
## Deterministic for a given RandomNumberGenerator state, as generators are seeded.
static func weighted(ref: String, rng: RandomNumberGenerator) -> Color:
	_ensure_loaded()
	var key := ref.trim_prefix("$")
	var sets: Dictionary = _document.get("weighted_sets", {})
	if not sets.has(key) or not (sets[key] as Array) is Array:
		_warn_missing(ref)
		return Color.MAGENTA

	var total := 0.0
	var entries: Array = sets[key]
	for entry in entries:
		total += float((entry as Dictionary).get("weight", 0.0))
	if total <= 0.0:
		return color(str((entries[0] as Dictionary).get("color", "")), Fallback.MAGENTA)

	var roll := rng.randf() * total
	var running := 0.0
	for entry in entries:
		running += float((entry as Dictionary).get("weight", 0.0))
		if roll <= running:
			return color(str((entry as Dictionary).get("color", "")), Fallback.MAGENTA)

	return color(str((entries[entries.size() - 1] as Dictionary).get("color", "")), Fallback.MAGENTA)


## Livery record from the contract's "liveries" array, e.g. "sunrise_coral".
## Returns a Dictionary keyed by livery field with resolved Colors. The `id`
## field is metadata rather than a colour, so it is not included.
static func livery(id: String) -> Dictionary:
	_ensure_loaded()
	var resolved := {}
	for entry in _document.get("liveries", []):
		var livery_entry := entry as Dictionary
		if str(livery_entry.get("id", "")) != id:
			continue
		for field in livery_entry.keys():
			if field == "id":
				continue
			resolved[field] = color(str(livery_entry[field]))
		return resolved
	push_warning("Palette: unknown livery '%s'." % id)
	return resolved


## Deterministic per-face jitter within the contract's stated bounds. Used by
## procedural generators to break up flat colour fields without new palettes.
static func jitter(base: Color, rng: RandomNumberGenerator, strict := true) -> Color:
	if not strict:
		return base
	var rules: Dictionary = _document.get("rules", {})
	var per_face: Dictionary = rules.get("per_face_jitter", {})
	var value_jitter := float(per_face.get("value", 0.0))
	var hue_shift := float(per_face.get("hue_deg", 0.0))
	var saturation_jitter := float(per_face.get("saturation", 0.0))

	var h := base.h + rng.randf_range(-hue_shift, hue_shift) * 0.005555556
	var s := clampf(base.s + rng.randf_range(-saturation_jitter, saturation_jitter), 0.0, 1.0)
	var v := clampf(base.v + rng.randf_range(-value_jitter, value_jitter), 0.0, 1.0)
	return Color.from_hsv(fposmod(h, 1.0), s, v, base.a)


static func _ramp_key(ramp_name: String) -> String:
	match ramp_name:
		"ocean_depth", "seabed_by_depth":
			return "depth_m"
		_:
			return "value"


static func _parse_color(text: String, ref: String) -> Color:
	if text.begins_with("$"):
		return color(text)
	if Color.html_is_valid(text):
		return Color.html(text)
	push_warning("Palette: '%s' is not a colour literal ('%s')." % [ref, text])
	return Color.MAGENTA


static func _fallback_color(fallback: Fallback) -> Color:
	return Color(0, 0, 0, 0) if fallback == Fallback.TRANSPARENT else Color.MAGENTA


static func _warn_missing(ref: String) -> void:
	push_warning("Palette: could not resolve '%s'." % ref)


static func _ensure_loaded() -> bool:
	if _load_attempted:
		return not _document.is_empty()
	_load_attempted = true

	if not FileAccess.file_exists(PALETTE_PATH):
		push_warning("Palette: %s not found. Run the project from the project root." % PALETTE_PATH)
		return false

	var file := FileAccess.open(PALETTE_PATH, FileAccess.READ)
	if file == null:
		push_warning("Palette: could not open %s (error %d)." % [PALETTE_PATH, FileAccess.get_open_error()])
		return false

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_document = parsed
	else:
		push_warning("Palette: %s is not a JSON object." % PALETTE_PATH)
	return not _document.is_empty()