## Headless scene-wiring checks.
##
## Parsing clean and the flight model passing are not enough: the scenes also
## have to load, wire themselves together and step without errors. This
## instantiates the main scene, simulates it, and asserts the pieces that are
## easy to break by accident: the terrain sampler is connected, the camera finds
## the aircraft, and the procedural airframe actually produced geometry.
##
## [codeblock]
## godot --headless --path . --script res://tests/scene_test.gd
## [/codeblock]
extends SceneTree

const MAIN_SCENE := "res://scenes/main/Main.tscn"
## Frames awaited after adding the scene, before inspecting it.
const SETTLE_FRAMES := 5
## Frames simulated afterwards, to check the running state.
const SIMULATED_FRAMES := 30

var _failures := 0
var _checks := 0


func _initialize() -> void:
	print("Scene wiring checks")

	var scene: PackedScene = load(MAIN_SCENE)
	_check("main scene loads", scene != null)
	if scene == null:
		_finish()
		return

	var main: Node = scene.instantiate()
	_check("main scene instantiates", main != null)
	if main == null:
		_finish()
		return

	root.add_child(main)

	# _ready and the first physics frames have to run before any of this can be
	# inspected: the sun, the airframe and the camera are all built during _ready
	# or on the first tick.
	await _settle()

	_check_environment(main)
	_check_world_wiring(main)
	_check_aircraft(main)
	_check_airframe(main)
	_check_camera(main)
	# Awaited, because stepping frames suspends and the remaining checks would
	# otherwise run after _finish().
	await _check_steps(main)

	_finish()


## Let the scene enter the tree, run its _ready callbacks and complete a few
## physics ticks.
func _settle() -> void:
	for _frame in SETTLE_FRAMES:
		await process_frame


## The world provides terrain and lighting.
##
## The flat TestEnvironment this checked was replaced by the island in milestone 03,
## so the ground is no longer flat. What still has to hold is that the world is
## present, that it reports terrain, and that the island's sun is above the horizon.
func _check_environment(main: Node) -> void:
	var world := main.get_node_or_null(^"Island") as Island
	_check("island is present", world != null)
	if world == null:
		return

	_check("island has a generator", world.generator != null)
	if world.generator == null:
		return

	# The island must have relief, or the terrain function is returning a constant and
	# every other terrain check is passing for the wrong reason.
	var low := INF
	var high := -INF
	for x in range(-12, 13, 3):
		for z in range(-12, 13, 3):
			var height := world.ground_height_at(Vector3(float(x) * 100.0, 0.0, float(z) * 100.0))
			low = minf(low, height)
			high = maxf(high, height)
	_check("island has relief", high - low > 100.0, "%.0f m to %.0f m" % [low, high])

	var atmosphere := world.get_node_or_null(^"Atmosphere") as IslandAtmosphere
	_check("atmosphere is present", atmosphere != null)
	if atmosphere == null:
		return
	var sun: DirectionalLight3D = atmosphere.sun()
	_check("sun light exists", sun != null)
	if sun != null:
		_check("sun points upward", atmosphere.sun_direction().y > 0.0,
			"y = %.2f" % atmosphere.sun_direction().y)


## The aircraft must actually be flying over the island.
##
## This is the check that justifies putting terrain behind a single function. When
## the island was first added to the scene, `Main` never resolved the world, so the
## aircraft spawned at the world origin, assumed the ground was at y = 0, and flew
## over nothing. Nothing errored: the flight suite passed, the scene ran, and the
## only symptom was that the player was not over the island.
##
## So the wiring is asserted directly rather than inferred from the aircraft behaving
## plausibly.
func _check_world_wiring(main: Node) -> void:
	var typed := main as Main
	if typed == null:
		_check("main is a Main node", false, str(main))
		return

	_check("main resolves a world", typed.world != null)
	if typed.world == null:
		return
	_check("world exposes ground_height_at", typed.world.has_method(&"ground_height_at"))

	var island := typed.world as Island
	if island == null or island.generator == null:
		_check("island generator is available", false)
		return

	var controller: AircraftController = typed.aircraft
	if controller == null:
		_check("aircraft controller is available", false)
		return

	# The ground sampler must be the island, not the controller's flat-world default.
	var sampler := controller.ground_height_sampler()
	_check("ground sampler is connected", sampler.is_valid())
	if sampler.is_valid():
		# Probe a point well inland, where the terrain is hundreds of metres above sea
		# level. A sampler stuck at zero would return 0.0 here.
		var probe := Vector3(0.0, 0.0, 0.0)
		_check("ground sampler reads the island",
			absf(float(sampler.call(probe)) - island.ground_height_at(probe)) < 0.01,
			"sampler %.2f, island %.2f" % [
				float(sampler.call(probe)), island.ground_height_at(probe)])

	# The aircraft starts on the airport, on the surface, facing down the runway.
	var start := controller.start_position
	var airport := island.generator.airport_position
	_check("aircraft starts at the airport",
		Vector2(start.x, start.z).distance_to(airport) < 1.0,
		"at %v, airport %v" % [Vector2(start.x, start.z), airport])
	_check("aircraft starts on the surface",
		absf(start.y - island.ground_height_at(start)) < 0.5,
		"y %.2f, ground %.2f" % [start.y, island.ground_height_at(start)])
	_check("aircraft faces down the runway",
		absf(controller.start_heading_degrees - island.generator.airport_heading_degrees) < 1.0,
		"%.0f deg, runway %.0f deg" % [
			controller.start_heading_degrees, island.generator.airport_heading_degrees])

	# The island must generate geometry, and stay low-poly. Both bounds matter: too
	# few triangles and the terrain is invisible, too many and the design's low-poly
	# look is gone.
	await _settle()
	_check("island builds chunks", island.built_chunk_count() > 0,
		"%d chunks" % island.built_chunk_count())
	var triangles := island.triangle_count()
	_check("island has terrain geometry", triangles > 1000, "%d triangles" % triangles)
	_check("island stays low poly", triangles < 250000, "%d triangles" % triangles)


func _check_aircraft(main: Node) -> void:
	var aircraft := main.get_node_or_null(^"Aircraft/FlightController")
	_check("flight controller is present", aircraft != null)
	if aircraft == null:
		return
	_check("controller exposes flight state", aircraft.state != null)
	_check("controller has an input node", aircraft.get_node_or_null(^"FlightInput") != null)
	_check("controller has visuals", aircraft.get_node_or_null(^"Visuals") != null)
	_check("tuning resource is assigned", aircraft.tuning != null)

	if aircraft.tuning != null:
		_check("tuning carries contract max speed", is_equal_approx(aircraft.tuning.max_speed_knots, 145.0))
		_check("tuning carries contract cruise speed", is_equal_approx(aircraft.tuning.cruise_speed_knots, 110.0))
		_check("tuning carries contract acceleration", is_equal_approx(aircraft.tuning.acceleration, 24.0))


func _check_airframe(main: Node) -> void:
	var visuals := main.get_node_or_null(^"Aircraft/FlightController/Visuals")
	_check("visuals node is present", visuals != null)
	if visuals == null:
		return

	var meshes := _collect_meshes(visuals)
	_check("airframe generated mesh instances", meshes.size() >= 10, "found %d" % meshes.size())

	# Every visible part needs geometry, otherwise something built silently empty.
	var empty: Array[String] = []
	for mesh in meshes:
		if mesh.mesh == null:
			empty.append(str(mesh.get_path()))
	_check("no mesh instance lacks geometry", empty.is_empty(), "empty: %s" % ", ".join(empty))

	var with_materials := 0
	for mesh in meshes:
		if mesh.material_override != null:
			with_materials += 1
	_check("meshes have materials", with_materials > 0, "%d of %d" % [with_materials, meshes.size()])


func _check_camera(main: Node) -> void:
	var camera := _find_camera(main)
	_check("chase camera was spawned", camera != null)
	if camera == null:
		return
	_check("camera targets the aircraft", camera.target != null and is_instance_valid(camera.target))
	_check("camera is not at the world origin", camera.global_position.length() > 0.01, "at %v" % camera.global_position)


## The camera is spawned from code rather than placed in the scene, so it is
## found by type rather than by path.
func _find_camera(node: Node) -> ChaseCamera:
	if node is ChaseCamera:
		return node
	for child in node.get_children():
		var found := _find_camera(child)
		if found != null:
			return found
	return null


func _collect_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			found.append(child)
		found.append_array(_collect_meshes(child))
	return found


## Step the scene a little so lifecycle code runs, then confirm the aircraft is
## still consistent afterwards.
func _check_steps(main: Node) -> void:
	var aircraft := main.get_node_or_null(^"Aircraft/FlightController")
	if aircraft == null:
		return
	var state: FlightState = aircraft.state

	for _frame in SIMULATED_FRAMES:
		await process_frame

	_check("state survives simulation", is_finite(state.position.x) and is_finite(state.position.y) and is_finite(state.position.z))
	_check("state stays finite", is_finite(state.velocity.length()))
	_check("throttle stays in range", state.throttle >= 0.0 and state.throttle <= 1.0, "%.3f" % state.throttle)
	_check("aircraft rests on the ground at spawn", state.grounded, "altitude %.2f" % state.altitude)

	# Height above the *ground*, not above sea level.
	#
	# state.altitude is height above sea level, so on the airport plateau — which sits
	# 14 m up — it reads 15.05 rather than the 1.05 m of gear height. Comparing
	# altitude against gear height only worked while the whole world was flat at zero,
	# and would have passed on any island by accident if the plateau were lower.
	var world := main.get_node_or_null(^"Island") as Island
	if world != null:
		var ground := world.ground_height_at(state.position)
		_check_near("aircraft sits at gear height above the ground",
			state.position.y - ground, aircraft.tuning.gear_height, 0.05)

	_check("transform follows the state", aircraft.global_position.is_equal_approx(state.position))

	var camera := _find_camera(main)
	if camera != null:
		_check("camera moved off its spawn position", camera.global_position.length() > 0.01)


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s%s" % [label, (" (%s)" % detail) if detail != "" else ""])


func _check_near(label: String, actual: float, expected: float, tolerance: float) -> void:
	_check(label, absf(actual - expected) <= tolerance, "expected %.3f +/- %.3f, got %.3f" % [expected, tolerance, actual])


func _finish() -> void:
	if _failures == 0:
		print("  %d checks passed" % _checks)
	quit(0 if _failures == 0 else 1)