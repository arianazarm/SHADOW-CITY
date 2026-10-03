extends Node3D

const WALK_SPEED := 6.0
const ACCELERATION := 22.0
const INTERACT_RANGE := 3.2
const MOUSE_SENSITIVITY := 0.0024

var player: CharacterBody3D
var player_mesh: MeshInstance3D
var camera_yaw: Node3D
var camera_pitch: Node3D
var objective_label: Label
var prompt_label: Label
var status_label: Label
var objective_index := 0
var interactables: Array[Node3D] = []
var objectives := ["Reach the transit gate", "Activate the East relay", "Activate the Market relay", "Reach the extraction beacon"]

func _ready() -> void:
	_register_controls()
	_build_city()
	_build_interface()
	_set_objective()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	var move_input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward := -camera_yaw.global_transform.basis.z
	var right := camera_yaw.global_transform.basis.x
	forward.y = 0.0
	right.y = 0.0
	var movement := (right.normalized() * move_input.x + forward.normalized() * move_input.y)
	var target_velocity := movement.normalized() * WALK_SPEED
	player.velocity.x = move_toward(player.velocity.x, target_velocity.x, ACCELERATION * delta)
	player.velocity.z = move_toward(player.velocity.z, target_velocity.z, ACCELERATION * delta)
	if not player.is_on_floor():
		player.velocity.y -= 20.0 * delta
	else:
		player.velocity.y = -0.1
	player.move_and_slide()
	if movement.length_squared() > 0.01:
		var facing := atan2(-movement.x, -movement.z)
		player_mesh.rotation.y = lerp_angle(player_mesh.rotation.y, facing - player.rotation.y, 12.0 * delta)
	_update_prompt()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pitch.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera_pitch.rotation.x = clampf(camera_pitch.rotation.x, -0.65, 0.25)
	if event.is_action_pressed("interact"):
		_interact()
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _register_controls() -> void:
	var bindings := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "interact": KEY_E, "restart": KEY_R}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = bindings[action]
		InputMap.action_add_event(action, key)

func _build_city() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("07101b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("58708c")
	env.ambient_light_energy = 0.52
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	_add_static_box("Ground", Vector3(0, -0.5, 0), Vector3(96, 1, 96), Color("16222b"))
	_build_streets()
	_build_blocks()
	_build_landmarks()
	_spawn_player()
	_spawn_door(Vector3(0, 1.5, -13), 0)
	_spawn_terminal(Vector3(22, 0.9, -10), 1, "East relay")
	_spawn_terminal(Vector3(-22, 0.9, 13), 2, "Market relay")
	_spawn_extraction(Vector3(0, 0.5, -35))
	_spawn_guard(Vector3(9, 0.9, 7), [Vector3(9, 0.9, 7), Vector3(23, 0.9, 7), Vector3(23, 0.9, -12), Vector3(9, 0.9, -12)])
	_spawn_guard(Vector3(-9, 0.9, -4), [Vector3(-9, 0.9, -4), Vector3(-25, 0.9, -4), Vector3(-25, 0.9, 15), Vector3(-9, 0.9, 15)])
	_spawn_guard(Vector3(2, 0.9, -22), [Vector3(2, 0.9, -22), Vector3(16, 0.9, -22), Vector3(16, 0.9, -32), Vector3(2, 0.9, -32)])
	for position in [Vector3(14, 0.85, 15), Vector3(-15, 0.85, 3), Vector3(20, 0.85, -25), Vector3(-20, 0.85, -19), Vector3(2, 0.85, 23)]:
		_spawn_civilian(position)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55, -28, 0)
	moon.light_color = Color("9bbfff")
	moon.light_energy = 1.4
	add_child(moon)

func _build_streets() -> void:
	for x in [-24.0, 0.0, 24.0]:
		_add_box("NorthSouthStreet", Vector3(x, 0.02, 0), Vector3(8, 0.05, 88), Color("28343a"))
	for z in [-24.0, 0.0, 24.0]:
		_add_box("EastWestStreet", Vector3(0, 0.03, z), Vector3(88, 0.06, 8), Color("28343a"))
	for x in [-36.0, -12.0, 12.0, 36.0]:
		for z in [-36.0, -12.0, 12.0, 36.0]:
			_add_box("StreetLamp", Vector3(x, 2.1, z), Vector3(0.18, 4.2, 0.18), Color("303a45"))
			_add_light(Vector3(x, 4.0, z), Color("ffba65"), 8.0)

func _build_blocks() -> void:
	var block_centers := [Vector2(-12, -12), Vector2(12, -12), Vector2(-12, 12), Vector2(12, 12), Vector2(-36, -12), Vector2(36, 12), Vector2(-36, 12), Vector2(36, -12)]
	for center in block_centers:
		for offset in [Vector2(-4, -4), Vector2(4, -4), Vector2(-4, 4), Vector2(4, 4)]:
			var seed_height := 5.0 + absf(offset.x * 0.35) + absf(center.y * 0.08)
			var position := Vector3(center.x + offset.x, seed_height * 0.5, center.y + offset.y)
			var color := Color("1b2b37") if int(center.x + offset.y) % 2 == 0 else Color("253341")
			_add_static_box("ProceduralBuilding", position, Vector3(6.2, seed_height, 6.2), color)

func _build_landmarks() -> void:
	_add_box("MarketCanopy", Vector3(-22, 2.8, 13), Vector3(8, 0.35, 7), Color("833f65"))
	for x in [-25.0, -22.0, -19.0]:
		_add_box("MarketStall", Vector3(x, 1, 16), Vector3(2.0, 2, 1.2), Color("425d65"))
	_add_box("TransitSign", Vector3(0, 4, -16), Vector3(9, 1.2, 0.3), Color("2e5872"))
	_add_light(Vector3(0, 3.5, -16), Color("4bd9ff"), 7.0)

func _spawn_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.add_to_group("player")
	player.position = Vector3(0, 1.0, 28)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.75
	shape.shape = capsule
	player.add_child(shape)
	player_mesh = _make_mesh(Vector3(0.75, 1.5, 0.55), Color("60b8d8"))
	player_mesh.position.y = 0.75
	player.add_child(player_mesh)
	camera_yaw = Node3D.new()
	camera_yaw.position.y = 1.45
	player.add_child(camera_yaw)
	camera_pitch = Node3D.new()
	camera_yaw.add_child(camera_pitch)
	var arm := SpringArm3D.new()
	arm.spring_length = 5.8
	arm.margin = 0.25
	camera_pitch.add_child(arm)
	var camera := Camera3D.new()
	camera.fov = 68.0
	camera.position = Vector3(0, 0.5, 0)
	camera.current = true
	arm.add_child(camera)
	add_child(player)

func _spawn_door(position: Vector3, required_objective: int) -> void:
	var door := Door.new()
	door.position = position
	door.required_objective = required_objective
	door.opened.connect(func() -> void: _advance_objective("Transit gate opened. Reach the East relay."))
	add_child(door)
	interactables.append(door)

func _spawn_terminal(position: Vector3, required_objective: int, terminal_name: String) -> void:
	var terminal := RelayTerminal.new()
	terminal.position = position
	terminal.required_objective = required_objective
	terminal.terminal_name = terminal_name
	terminal.activated.connect(func() -> void: _advance_objective(terminal_name + " online."))
	add_child(terminal)
	interactables.append(terminal)

func _spawn_extraction(position: Vector3) -> void:
	var extraction := ExtractionBeacon.new()
	extraction.position = position
	extraction.required_objective = 3
	extraction.completed.connect(func() -> void: _advance_objective("District escaped. Mission complete."))
	add_child(extraction)
	interactables.append(extraction)

func _spawn_guard(position: Vector3, route: Array[Vector3]) -> void:
	var guard := PatrolGuard.new()
	guard.position = position
	guard.route = route
	guard.alerted.connect(func() -> void: _set_status("GUARD ALERT — move out of the patrol cone."))
	add_child(guard)

func _spawn_civilian(position: Vector3) -> void:
	var civilian := Civilian.new()
	civilian.position = position
	add_child(civilian)

func _interact() -> void:
	var target := _nearest_interactable()
	if target != null:
		target.call("interact", objective_index)

func _nearest_interactable() -> Node3D:
	var closest: Node3D = null
	var nearest := INTERACT_RANGE
	for candidate in interactables:
		if not is_instance_valid(candidate) or not candidate.call("can_interact", objective_index):
			continue
		var distance := player.global_position.distance_to(candidate.global_position)
		if distance < nearest:
			nearest = distance
			closest = candidate
	return closest

func _update_prompt() -> void:
	var target := _nearest_interactable()
	prompt_label.text = "[E] " + str(target.call("interaction_text", objective_index)) if target != null else ""

func _advance_objective(message: String) -> void:
	objective_index += 1
	_set_status(message)
	_set_objective()

func _set_objective() -> void:
	if objective_index >= objectives.size():
		objective_label.text = "MISSION COMPLETE — The city network is yours"
		prompt_label.text = "Press R to replay"
		return
	objective_label.text = "OBJECTIVE %d/%d: %s" % [objective_index + 1, objectives.size(), objectives[objective_index]]

func _set_status(message: String) -> void:
	status_label.text = message

func _build_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	objective_label = Label.new()
	objective_label.position = Vector2(28, 24)
	objective_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(objective_label)
	status_label = Label.new()
	status_label.position = Vector2(28, 56)
	status_label.add_theme_font_size_override("font_size", 16)
	layer.add_child(status_label)
	prompt_label = Label.new()
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.position = Vector2(-220, -92)
	prompt_label.size = Vector2(440, 36)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 20)
	layer.add_child(prompt_label)

func _add_static_box(label: String, position: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = position
	body.add_child(_make_mesh(size, color))
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	add_child(body)

func _add_box(label: String, position: Vector3, size: Vector3, color: Color) -> void:
	var item := _make_mesh(size, color)
	item.name = label
	item.position = position
	add_child(item)

func _make_mesh(size: Vector3, color: Color) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	item.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.2
	material.roughness = 0.72
	item.material_override = material
	return item

func _add_light(position: Vector3, color: Color, energy: float) -> void:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 12.0
	add_child(light)

class CityInteractable extends Node3D:
	var required_objective := 0
	func can_interact(current_objective: int) -> bool: return current_objective == required_objective
	func interaction_text(_current_objective: int) -> String: return "Interact"
	func interact(_current_objective: int) -> void: pass
	func make_box(size: Vector3, color: Color) -> MeshInstance3D:
		var item := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		item.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color * 0.18
		item.material_override = material
		add_child(item)
		return item

class Door extends CityInteractable:
	signal opened
	var panel: MeshInstance3D
	func _ready() -> void:
		panel = make_box(Vector3(5.5, 3.0, 0.35), Color("b9643c"))
	func interaction_text(_current_objective: int) -> String: return "Open transit gate"
	func interact(_current_objective: int) -> void:
		panel.visible = false
		required_objective = -1
		opened.emit()

class RelayTerminal extends CityInteractable:
	signal activated
	var terminal_name := "Relay"
	func _ready() -> void:
		make_box(Vector3(0.9, 1.8, 0.7), Color("31d8ee"))
	func interaction_text(_current_objective: int) -> String: return "Activate " + terminal_name
	func interact(_current_objective: int) -> void:
		required_objective = -1
		activated.emit()

class ExtractionBeacon extends CityInteractable:
	signal completed
	func _ready() -> void:
		make_box(Vector3(2.0, 0.4, 2.0), Color("82f5a2"))
		var light := OmniLight3D.new()
		light.light_color = Color("82f5a2")
		light.omni_range = 10.0
		light.position.y = 2.0
		add_child(light)
	func interaction_text(_current_objective: int) -> String: return "Signal extraction"
	func interact(_current_objective: int) -> void:
		required_objective = -1
		completed.emit()

class PatrolGuard extends Node3D:
	signal alerted
	var route: Array[Vector3] = []
	var route_index := 0
	var player_ref: CharacterBody3D
	var cooldown := 0.0
	func _ready() -> void:
		player_ref = get_tree().get_first_node_in_group("player") as CharacterBody3D
		var body := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.75, 1.8, 0.75)
		body.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("d7b45a")
		body.material_override = material
		body.position.y = 0.9
		add_child(body)
	func _physics_process(delta: float) -> void:
		if player_ref == null or route.is_empty(): return
		var offset := route[route_index] - global_position
		offset.y = 0.0
		if offset.length() < 0.3:
			route_index = (route_index + 1) % route.size()
		else:
			global_position += offset.normalized() * 2.0 * delta
			look_at(global_position + offset.normalized(), Vector3.UP)
		cooldown = maxf(0.0, cooldown - delta)
		var to_player := player_ref.global_position - global_position
		if to_player.length() < 9.0 and (-global_transform.basis.z).dot(to_player.normalized()) > 0.7 and cooldown <= 0.0:
			cooldown = 3.0
			alerted.emit()

class Civilian extends Node3D:
	var phase := 0.0
	func _ready() -> void:
		phase = global_position.x * 0.3 + global_position.z * 0.2
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.32
		capsule.height = 1.5
		body.mesh = capsule
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("ad6c9c")
		body.material_override = material
		body.position.y = 0.75
		add_child(body)
	func _process(delta: float) -> void:
		phase += delta
		rotation.y = sin(phase * 0.65) * 0.8
