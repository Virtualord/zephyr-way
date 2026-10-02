// Stylized ocean for Zephyr Way.
//
// Deliberately cheap. The visual target is a calm, readable, low-poly sea: banded
// depth from the palette's own ocean tones, a bright foam line and a wet edge where
// the water meets the beach, and a soft sun sheen. No refraction, no screen-space
// reflection, no normal map texture -- a handful of sin() calls and a texture read per
// fragment, on a single quad, which is not measurable.
//
// Depth comes from the terrain the island already generates, handed in as a height
// field. That is why the shallows and the foam line follow the real seabed instead of
// a hand-tuned curve that drifts out of step with it.

shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// --- Palette. The scene passes these in from design/color_palette.json's ocean
// group, which specifies five tones; the defaults only matter if the shader is used
// standalone.

uniform vec4 shallow_color : source_color = vec4(0.278, 0.839, 0.812, 1.0);
uniform vec4 deep_color : source_color = vec4(0.039, 0.310, 0.561, 1.0);
uniform vec4 abyss_color : source_color = vec4(0.024, 0.169, 0.341, 1.0);
uniform vec4 foam_color : source_color = vec4(0.957, 1.0, 0.984, 1.0);
uniform vec4 edge_color : source_color = vec4(0.804, 0.937, 0.902, 1.0);
uniform vec4 sun_tint : source_color = vec4(1.0, 0.93, 0.85, 1.0);

// --- How the water reads.

// Distance over which the water reaches the mid tone, in metres of depth.
uniform float mid_depth = 90.0;
// Distance over which it reaches the abyss, in metres of depth.
uniform float depth_fade_distance = 700.0;
// Width of the innermost foam band, in metres of depth.
uniform float foam_width = 14.0;
// Width of the soft edge outside it, in metres of depth.
uniform float foam_softness = 9.0;
uniform float swell_height = 0.55;
uniform float swell_scale = 0.0016;
uniform float sheen_power = 90.0;
uniform float sheen_strength = 0.45;
// Wind direction for the swell, in radians.
uniform float swell_direction = 0.6;
// Direction the light comes from. Passed in by the scene so the sheen and the world
// cannot disagree about where the sun is, and so no `LIGHT` built-in is needed.
uniform vec3 light_direction = vec3(0.0, 1.0, 0.0);

// --- Terrain, for depth and foam.

// Sampled with linear filtering, not nearest. Nearest gave hard rectangular steps
// through the shallows, because a texel is tens of metres across and the foam line
// follows the seabed exactly; the banding read as a blocky artifact rather than a
// coastline.
uniform sampler2D height_field : filter_linear, repeat_disable;
uniform float world_extent = 16000.0;
uniform float sea_level = 0.0;
// Range the height field encodes over, in metres, symmetrically about zero.
uniform float height_range = 800.0;
// How much of the water's own colour survives without direct light, 0 to 1.
uniform float self_light = 0.55;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Terrain height at this point, read back from the field the island generated.
float terrain_height_at(vec2 xz) {
	// Clamped to the field rather than special-cased outside it.
	//
	// There was a branch here that declared the water abyss-deep past the field's
	// edge, on the reasoning that the island "stops generating" there. It does not:
	// the height field is an analytic function and returns a uniform ~85 m of water
	// offshore. So the branch painted deep water just outside the field and ordinary
	// deep water just inside it, which drew a hard straight seam across the ocean at
	// exactly the field's extent -- very visible from the air as a square of darker
	// water around the island. Clamping makes the offshore water match the water at
	// the edge, so there is nothing to see.
	vec2 uv = clamp((xz / world_extent) + vec2(0.5, 0.5), vec2(0.0), vec2(1.0));
	// The field stores height normalised symmetrically about zero over
	// -height_range to +height_range, so undo that here.
	return (texture(height_field, uv).g - 0.5) * 2.0 * height_range;
}

void fragment() {
	vec2 p = world_pos.xz;

	// Swell: two crossed waves at different scales, which reads as water without the
	// cost or the visible repetition of a normal map.
	vec2 axis = vec2(cos(swell_direction), sin(swell_direction));
	vec2 across = vec2(-axis.y, axis.x);
	float a = dot(p, axis) * swell_scale;
	float b = dot(p, across) * swell_scale * 0.7;
	float swell = (sin(a) * 0.6 + sin(b + 1.7) * 0.4) * swell_height;

	// Depth from the terrain underneath.
	float ground = terrain_height_at(p);
	float depth = max(sea_level - ground, 0.0);

	// Colour, through the palette's five ocean tones.
	//
	// Three bands rather than one gradient. A smooth shallow-to-deep gradient was
	// tried first and read as a photographic sea, which is not the art direction:
	// this is a faceted low-poly world and the water should band the way the land
	// does. The band edges are smoothed just enough to avoid a visible seam.
	float mid_t = clamp(depth / mid_depth, 0.0, 1.0);
	float deep_t = clamp((depth - mid_depth) / max(depth_fade_distance - mid_depth, 1.0), 0.0, 1.0);
	float abyss_t = clamp((depth - depth_fade_distance) / max(depth_fade_distance, 1.0), 0.0, 1.0);
	vec3 water = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.35, 0.65, mid_t));
	water = mix(water, abyss_color.rgb, smoothstep(0.45, 0.8, deep_t) + abyss_t);

	// Foam and the wet edge at the shore, banded rather than smooth.
	//
	// Two thresholds with a narrow gap produce distinct steps, which is the low-poly
	// language the rest of the island is in; a soft blur would read as a different art
	// style sitting next to it.
	//
	// The wobble is a sine along the shore so the band breaks up, because no real
	// coastline is a perfect ring around an island.
	float wobble = sin(dot(p, across) * 0.021) * 3.5 + sin(dot(p, axis) * 0.013) * 2.0;
	float d = depth + wobble;

	// Wet edge: the pale band the water leaves on the sand.
	float wet = step(foam_width + foam_softness, d) * (1.0 - step(foam_width + foam_softness + 22.0, d));
	water = mix(water, edge_color.rgb, wet * 0.55);

	// Foam: the bright band at the waterline, plus a broken second band out into the
	// shallows.
	float foam_inner = foam_width;
	float foam_outer = foam_width + foam_softness;
	float foam_mask = step(foam_inner, d) * (1.0 - step(foam_outer, d));
	float foam2 = step(foam_inner - 16.0, d) * (1.0 - step(foam_outer - 16.0, d));
	foam_mask = clamp(foam_mask + foam2 * 0.55, 0.0, 1.0);
	water = mix(water, foam_color.rgb, foam_mask);

	// Sun sheen, tight and weak.
	//
	// VIEW and the passed-in light direction, not vVIEW or LIGHT: neither of those is
	// usable in this context, and getting either wrong fails the whole shader to
	// compile, which leaves the sea plane drawing nothing at all. That reads from the
	// air as the sky's lower half, so it looks like a flat sea rather than a missing
	// one -- which is how this cost a while to find.
	vec3 view_dir = normalize(VIEW);
	vec3 halfway = normalize(light_direction + view_dir);
	float sheen = pow(max(dot(normalize(NORMAL), halfway), 0.0), sheen_power);
	water += sun_tint.rgb * sheen * sheen_strength;

	// ALBEDO is a vec3 in Godot 4. Writing a vec4 to it does not compile, and the
	// resulting error ("Invalid arguments to operator '=': 'vec3, vec4'") is reported
	// against the whole shader with no line of context, so it read as the water
	// expression being wrong when it was the assignment. Alpha is a separate ALPHA
	// output in Godot 4, not a fourth component of the albedo.
	ALBEDO = water;

	// Part of the water's colour is emitted rather than lit, so the sea keeps
	// reading as sea when the sun is dim. Without this the water darkens in exact
	// proportion to the sun, and the sun is dimmed deliberately so the rock keeps its
	// palette value -- the same correction that fixes the mountains would otherwise
	// turn the ocean to slate.
	EMISSION = water * self_light;

	// The swell lives in the colour and the normal rather than in a reflection pass.
	ROUGHNESS = mix(0.5, 0.15, clamp(depth / depth_fade_distance, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = 0.25;
	NORMAL = normalize(NORMAL + vec3(0.0, 0.0, swell * 0.05));
}
