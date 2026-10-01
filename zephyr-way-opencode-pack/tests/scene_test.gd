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


func _check_environment(main: Node) -> void:
	var environment := main.get_node_or_null(^"TestEnvironment") as TestEnvironment
	_check("environment is present", environment != null)
	if environment == null:
		return
	_check("environment samples flat ground", is_zero_approx(environment.ground_height_at(Vector3(123.0, 0.0, -456.0))))

	var sun: DirectionalLight3D = environment.sun()
	_check("sun light exists", sun != null)
	if sun != null:
		_check("sun points upward", environment.sun_direction().y > 0.0, "y = %.2f" % environment.sun_direction().y)


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
	_check_near("aircraft sits at gear height", state.altitude, aircraft.tuning.gear_height, 0.05)
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