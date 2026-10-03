extends Node3D

const WALK_SPEED := 6.5
const SPRINT_SPEED := 10.0
const ACCELERATION := 28.0
const DECELERATION := 34.0
const GRAVITY := 24.0
const JUMP_VELOCITY := 8.0
const INTERACT_RANGE := 3.5
const MOUSE_SENSITIVITY := 0.0022
const CITY_HALF_SIZE := 70.0
const COYOTE_TIME := 0.12
const CAMERA_FOV_RESPONSE := 7.0

var player: CharacterBody3D
var player_mesh: MeshInstance3D
var camera_yaw: Node3D
var camera_pitch: Node3D
var camera: Camera3D
var objective_label: Label
var prompt_label: Label
var status_label: Label
var help_label: Label
var pause_panel: ColorRect
var objective_index := 0
var coyote_timer := 0.0
var is_paused := false
var focused_interactable: Node3D
var interactables: Array[Node3D] = []
var objectives := [
	"Open the transit gate",
	"Collect the north district access chip",
	"Activate the East relay",
	"Restore power at the market relay",
	"Upload the survey data at the rooftop uplink",
	"Signal the extraction beacon",
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_controls()
	_build_city()
	_build_interface()
	_set_objective()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	if player.is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		coyote_timer = maxf(0.0, coyote_timer - delta)
	var move_input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward := -camera_yaw.global_transform.basis.z
	var right := camera_yaw.global_transform.basis.x
	forward.y = 0.0
	right.y = 0.0
	var movement := right.normalized() * move_input.x + forward.normalized() * move_input.y
	var sprinting := Input.is_action_pressed("sprint") and movement.length_squared() > 0.01
	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	var target_velocity := movement.normalized() * speed
	var rate := ACCELERATION if movement.length_squared() > 0.01 else DECELERATION
	player.velocity.x = move_toward(player.velocity.x, target_velocity.x, rate * delta)
	player.velocity.z = move_toward(player.velocity.z, target_velocity.z, rate * delta)
	if not player.is_on_floor():
		player.velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump") and coyote_timer > 0.0:
		player.velocity.y = JUMP_VELOCITY
		coyote_timer = 0.0
	else:
		player.velocity.y = -0.1
	player.move_and_slide()
	if movement.length_squared() > 0.01:
		var facing := atan2(-movement.x, -movement.z)
		player_mesh.rotation.y = lerp_angle(player_mesh.rotation.y, facing - player.rotation.y, minf(14.0 * delta, 1.0))
	camera.fov = lerpf(camera.fov, 76.0 if sprinting else 72.0, minf(CAMERA_FOV_RESPONSE * delta, 1.0))
	_update_prompt()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif is_paused and event.is_action_pressed("restart"):
		get_tree().paused = false
		get_tree().reload_current_scene()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if is_paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pitch.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera_pitch.rotation.x = clampf(camera_pitch.rotation.x, -0.72, 0.18)
	if event.is_action_pressed("interact"):
		_interact()
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()

func _register_controls() -> void:
	var bindings := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "interact": KEY_E, "restart": KEY_R, "sprint": KEY_SHIFT, "jump": KEY_SPACE, "pause": KEY_ESCAPE}
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
	env.ambient_light_color = Color("607a99")
	env.ambient_light_energy = 0.58
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	_add_static_box("Ground", Vector3(0, -0.5, 0), Vector3(CITY_HALF_SIZE * 2.0, 1, CITY_HALF_SIZE * 2.0), Color("16222b"))
	_build_streets()
	_build_blocks()
	_build_landmarks()
	_spawn_player()
	_spawn_door(Vector3(0, 1.5, -15), 0)
	_spawn_terminal(Vector3(-48, 0.9, -25), 1, "North access chip", "Retrieve access chip")
	_spawn_terminal(Vector3(25, 0.9, -12), 2, "East relay", "Activate East relay")
	_spawn_terminal(Vector3(-25, 0.9, 25), 3, "Market relay", "Restore market relay")
	_spawn_terminal(Vector3(48, 0.9, 25), 4, "Rooftop uplink", "Upload survey data")
	_spawn_extraction(Vector3(0, 0.5, -52))
	_spawn_guard(Vector3(10, 0.9, 9), [Vector3(10, 0.9, 9), Vector3(28, 0.9, 9), Vector3(28, 0.9, -15), Vector3(10, 0.9, -15)])
	_spawn_guard(Vector3(-12, 0.9, -5), [Vector3(-12, 0.9, -5), Vector3(-30, 0.9, -5), Vector3(-30, 0.9, 20), Vector3(-12, 0.9, 20)])
	_spawn_guard(Vector3(3, 0.9, -31), [Vector3(3, 0.9, -31), Vector3(21, 0.9, -31), Vector3(21, 0.9, -48), Vector3(3, 0.9, -48)])
	_spawn_guard(Vector3(-42, 0.9, -30), [Vector3(-42, 0.9, -30), Vector3(-55, 0.9, -30), Vector3(-55, 0.9, -8), Vector3(-42, 0.9, -8)])
	_spawn_civilians()
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55, -28, 0)
	moon.light_color = Color("9bbfff")
	moon.light_energy = 1.4
	add_child(moon)

func _build_streets() -> void:
	for x in [-48.0, -24.0, 0.0, 24.0, 48.0]:
		_add_box("NorthSouthStreet", Vector3(x, 0.02, 0), Vector3(8, 0.05, 132), Color("28343a"))
	for z in [-48.0, -24.0, 0.0, 24.0, 48.0]:
		_add_box("EastWestStreet", Vector3(0, 0.03, z), Vector3(132, 0.06, 8), Color("28343a"))
	for x in [-60.0, -36.0, -12.0, 12.0, 36.0, 60.0]:
		for z in [-60.0, -36.0, -12.0, 12.0, 36.0, 60.0]:
			_add_box("StreetLamp", Vector3(x, 2.1, z), Vector3(0.18, 4.2, 0.18), Color("303a45"))
			_add_light(Vector3(x, 4.0, z), Color("ffba65"), 7.0)

func _build_blocks() -> void:
	for x in [-36.0, -12.0, 12.0, 36.0]:
		for z in [-36.0, -12.0, 12.0, 36.0]:
			_build_block(Vector2(x, z))

func _build_block(center: Vector2) -> void:
	var block_type := posmod(int(absf(center.x) + absf(center.y)) / 12, 4)
	if block_type == 0:
		for offset in [Vector2(-5, -5), Vector2(5, -5), Vector2(-5, 5), Vector2(5, 5)]:
			var height := 6.0 + absf(offset.x) * 0.55 + absf(center.y) * 0.08
			_add_static_box("TowerBlock", Vector3(center.x + offset.x, height * 0.5, center.y + offset.y), Vector3(7.0, height, 7.0), Color("1b2b37"))
	elif block_type == 1:
		_add_static_box("CourtyardBlock", Vector3(center.x - 5, 4, center.y), Vector3(5, 8, 17), Color("253341"))
		_add_static_box("CourtyardBlock", Vector3(center.x + 5, 5, center.y), Vector3(5, 10, 17), Color("32404c"))
		_add_box("CourtyardGarden", Vector3(center.x, 0.18, center.y), Vector3(5, 0.12, 9), Color("31524a"))
	elif block_type == 2:
		for offset in [Vector2(-5, 0), Vector2(5, 0), Vector2(0, -5), Vector2(0, 5)]:
			_add_static_box("Warehouse", Vector3(center.x + offset.x, 3.0, center.y + offset.y), Vector3(7.5, 6, 7.5), Color("3b4049"))
	else:
		_add_static_box("SlabBuilding", Vector3(center.x, 7, center.y - 4), Vector3(17, 14, 7), Color("273747"))
		_add_static_box("Annex", Vector3(center.x - 4, 3, center.y + 5), Vector3(8, 6, 5), Color("4b3d4d"))
		_add_static_box("Annex", Vector3(center.x + 5, 4, center.y + 5), Vector3(5, 8, 5), Color("344655"))

func _build_landmarks() -> void:
	_add_box("MarketCanopy", Vector3(-25, 2.8, 25), Vector3(10, 0.35, 8), Color("833f65"))
	for x in [-29.0, -25.0, -21.0]:
		_add_box("MarketStall", Vector3(x, 1, 29), Vector3(2.4, 2, 1.4), Color("425d65"))
	_add_box("TransitSign", Vector3(0, 4, -18), Vector3(10, 1.2, 0.3), Color("2e5872"))
	_add_light(Vector3(0, 3.5, -18), Color("4bd9ff"), 7.0)
	_add_box("SkylineMarker", Vector3(49, 8, 25), Vector3(3, 16, 3), Color("4d5b80"))

func _spawn_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.add_to_group("player")
	player.position = Vector3(0, 1.0, 52)
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
	camera_yaw.position = Vector3(0, 1.45, 0)
	player.add_child(camera_yaw)
	camera_pitch = Node3D.new()
	camera_yaw.add_child(camera_pitch)
	var arm := SpringArm3D.new()
	arm.spring_length = 6.6
	arm.margin = 0.3
	arm.position = Vector3(0.7, 0.25, 0)
	camera_pitch.add_child(arm)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.position = Vector3(0, 0.35, 0)
	camera.current = true
	arm.add_child(camera)
	add_child(player)

func _spawn_door(position: Vector3, required_objective: int) -> void:
	var door := Door.new()
	door.position = position
	door.required_objective = required_objective
	door.opened.connect(func() -> void: _advance_objective("Transit gate opened. Find the north access chip."))
	add_child(door)
	interactables.append(door)

func _spawn_terminal(position: Vector3, required_objective: int, terminal_name: String, action_text: String) -> void:
	var terminal := RelayTerminal.new()
	terminal.position = position
	terminal.required_objective = required_objective
	terminal.terminal_name = terminal_name
	terminal.action_text = action_text
	terminal.activated.connect(func() -> void: _advance_objective(terminal_name + " complete."))
	add_child(terminal)
	interactables.append(terminal)

func _spawn_extraction(position: Vector3) -> void:
	var extraction := ExtractionBeacon.new()
	extraction.position = position
	extraction.required_objective = 5
	extraction.completed.connect(func() -> void: _advance_objective("District escaped. Mission complete."))
	add_child(extraction)
	interactables.append(extraction)

func _spawn_guard(position: Vector3, route: Array[Vector3]) -> void:
	var guard := PatrolGuard.new()
	guard.position = position
	guard.route = route
	guard.alerted.connect(func() -> void: _set_status("GUARD ALERT — break line of sight and move on."))
	add_child(guard)

func _spawn_civilians() -> void:
	var routes := [
		[Vector3(-55, 0.85, 8), Vector3(-31, 0.85, 8), Vector3(-31, 0.85, 20), Vector3(-55, 0.85, 20)],
		[Vector3(8, 0.85, 32), Vector3(20, 0.85, 32), Vector3(20, 0.85, 52), Vector3(8, 0.85, 52)],
		[Vector3(31, 0.85, -42), Vector3(55, 0.85, -42), Vector3(55, 0.85, -30), Vector3(31, 0.85, -30)],
		[Vector3(-18, 0.85, -55), Vector3(-6, 0.85, -55), Vector3(-6, 0.85, -31), Vector3(-18, 0.85, -31)],
		[Vector3(-31, 0.85, 32), Vector3(-31, 0.85, 55), Vector3(-43, 0.85, 55), Vector3(-43, 0.85, 32)],
		[Vector3(31, 0.85, 8), Vector3(55, 0.85, 8), Vector3(55, 0.85, 20), Vector3(31, 0.85, 20)],
		[Vector3(-7, 0.85, 8), Vector3(7, 0.85, 8), Vector3(7, 0.85, 20), Vector3(-7, 0.85, 20)],
		[Vector3(8, 0.85, -18), Vector3(20, 0.85, -18), Vector3(20, 0.85, -6), Vector3(8, 0.85, -6)],
	]
	for route in routes:
		var civilian := Civilian.new()
		civilian.position = route[0]
		civilian.route = route
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
	if objective_index >= objectives.size():
		return
	var target := _nearest_interactable()
	if focused_interactable != target:
		if is_instance_valid(focused_interactable):
			focused_interactable.call("set_focused", false)
		focused_interactable = target
		if is_instance_valid(focused_interactable):
			focused_interactable.call("set_focused", true)
	if target == null:
		prompt_label.text = ""
		return
	var meters := ceili(player.global_position.distance_to(target.global_position))
	prompt_label.text = "[E] " + str(target.call("interaction_text", objective_index)) + "  •  %dm" % meters

func _advance_objective(message: String) -> void:
	objective_index += 1
	_set_status(message)
	_set_objective()

func _set_objective() -> void:
	if objective_index >= objectives.size():
		objective_label.text = "MISSION COMPLETE — The city network is yours"
		prompt_label.text = "Press R to replay"
		return
	objective_label.text = "OBJECTIVE %d/%d  ·  %s" % [objective_index + 1, objectives.size(), objectives[objective_index]]

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
	help_label = Label.new()
	help_label.position = Vector2(28, 88)
	help_label.text = "SHIFT sprint  ·  SPACE jump  ·  ESC pause"
	help_label.modulate = Color(0.68, 0.76, 0.84, 0.85)
	layer.add_child(help_label)
	prompt_label = Label.new()
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.position = Vector2(-220, -92)
	prompt_label.size = Vector2(440, 36)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 20)
	layer.add_child(prompt_label)
	_build_pause_menu(layer)


func _build_pause_menu(layer: CanvasLayer) -> void:
	pause_panel = ColorRect.new()
	pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.color = Color(0.02, 0.05, 0.09, 0.88)
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_panel.visible = false
	layer.add_child(pause_panel)
	var menu := VBoxContainer.new()
	menu.set_anchors_preset(Control.PRESET_CENTER)
	menu.position = Vector2(-180, -105)
	menu.size = Vector2(360, 210)
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_panel.add_child(menu)
	var title := Label.new()
	title.text = "SHADOW CITY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	menu.add_child(title)
	var divider := HSeparator.new()
	menu.add_child(divider)
	var paused := Label.new()
	paused.text = "PAUSED"
	paused.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paused.add_theme_font_size_override("font_size", 22)
	menu.add_child(paused)
	var instructions := Label.new()
	instructions.text = "ESC  Resume mission\nR  Restart district"
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.add_theme_font_size_override("font_size", 16)
	menu.add_child(instructions)

func _toggle_pause() -> void:
	is_paused = not is_paused
	get_tree().paused = is_paused
	pause_panel.visible = is_paused
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if is_paused else Input.MOUSE_MODE_CAPTURED)

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
	var visual: MeshInstance3D
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
		visual = item
		return item
	func set_focused(focused: bool) -> void:
		if visual != null:
			visual.scale = Vector3.ONE * (1.12 if focused else 1.0)

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
	var action_text := "Activate relay"
	func _ready() -> void:
		make_box(Vector3(0.9, 1.8, 0.7), Color("31d8ee"))
	func interaction_text(_current_objective: int) -> String: return action_text
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
	var investigation_time := 0.0
	var last_known_position := Vector3.ZERO
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
		cooldown = maxf(0.0, cooldown - delta)
		var to_player := player_ref.global_position - global_position
		to_player.y = 0.0
		var can_see_player := to_player.length() < 9.0 and to_player.length() > 0.01 and (-global_transform.basis.z).dot(to_player.normalized()) > 0.7
		if can_see_player:
			last_known_position = player_ref.global_position
			investigation_time = 2.5
			if cooldown <= 0.0:
				cooldown = 3.0
				alerted.emit()
		var target := route[route_index]
		if investigation_time > 0.0:
			investigation_time -= delta
			target = last_known_position
		var offset := target - global_position
		offset.y = 0.0
		if offset.length() < 0.3:
			if investigation_time <= 0.0:
				route_index = (route_index + 1) % route.size()
		else:
			global_position += offset.normalized() * (2.8 if investigation_time > 0.0 else 2.0) * delta
			look_at(global_position + offset.normalized(), Vector3.UP)

class Civilian extends Node3D:
	var route: Array[Vector3] = []
	var route_index := 1
	var pause_time := 0.0
	var speed := 1.5
	var player_ref: CharacterBody3D
	func _ready() -> void:
		player_ref = get_tree().get_first_node_in_group("player") as CharacterBody3D
		speed = 1.25 + posmod(global_position.x * 0.07 + global_position.z * 0.03, 0.65)
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.32
		capsule.height = 1.5
		body.mesh = capsule
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("ad6c9c") if int(absf(global_position.x)) % 2 == 0 else Color("76b79c")
		body.material_override = material
		body.position.y = 0.75
		add_child(body)
	func _physics_process(delta: float) -> void:
		if route.is_empty(): return
		var direction := Vector3.ZERO
		if player_ref != null:
			var from_player := global_position - player_ref.global_position
			from_player.y = 0.0
			if from_player.length() < 2.4 and from_player.length() > 0.01:
				direction = from_player.normalized()
				global_position += direction * speed * 1.35 * delta
				rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(10.0 * delta, 1.0))
				return
		if pause_time > 0.0:
			pause_time -= delta
			return
		var offset := route[route_index] - global_position
		offset.y = 0.0
		if offset.length() < 0.18:
			route_index = (route_index + 1) % route.size()
			pause_time = 0.35 + posmod(float(route_index) * 0.23, 0.5)
			return
		direction = offset.normalized()
		global_position += direction * speed * delta
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(8.0 * delta, 1.0))
