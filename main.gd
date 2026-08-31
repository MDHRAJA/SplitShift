extends Node2D

# SPLIT SHIFT: two runners, two worlds, one player at a time.
const SCREEN := Vector2(900, 600)
const HALF_WIDTH := 450.0
const PLAYER_Y := 460.0
const RUNNER_SIZE := Vector2(62, 78)
const LANE_COUNT := 4
const LANE_WIDTH := HALF_WIDTH / float(LANE_COUNT)
const OBSTACLE_SIZE := Vector2(48, 48)
const FOREST_OBSTACLE_SIZE := Vector2(50, 34)
const LEFT_BACKGROUND := preload("res://assets/sprites/left_background.png")
const RIGHT_BACKGROUND := preload("res://assets/sprites/right_background.png")
const LEFT_RUNNER := preload("res://assets/sprites/runner_left.png")
const RIGHT_RUNNER := preload("res://assets/sprites/runner_right.png")
const LEFT_RUNNER_B := preload("res://assets/sprites/runner_left_b.png")
const RIGHT_RUNNER_B := preload("res://assets/sprites/runner_right_b.png")
const OBSTACLE := preload("res://assets/sprites/obstacle.png")
const FOREST_SPIKES := preload("res://assets/sprites/forest_spikes.png")
const LEFT_FLOOR := preload("res://assets/sprites/left_floor.png")
const RIGHT_FLOOR := preload("res://assets/sprites/right_floor.png")
const SFX_HIT := preload("res://assets/audio/hit.ogg")
const SFX_BEAT_LOW := preload("res://assets/audio/beat_low.ogg")
const SFX_BEAT_ACCENT := preload("res://assets/audio/beat_accent.ogg")
const SCORE_FILE := "user://split_shift_scores.cfg"
const DISPLAY_FONT := preload("res://assets/fonts/kenvector_future.ttf")

var lanes: Array[int] = [1, 2]
var runner_xs: Array[float] = [137.75, 700.25]
var obstacles: Array[Dictionary] = []
var lane_particles: Array[Dictionary] = []
var forest_leaves: Array[Dictionary] = []
var sand_particles: Array[Dictionary] = []
var spawn_timers: Array[float] = [0.7, 1.2]
var active_side := 0
var elapsed := 0.0
var score := 0
var best_score := 0
var new_high_score := false
var dodges := 0
var combo := 0
var best_combo := 0
var shift_bonus := 0
var next_switch_at := 14.0
var warning_visible := false
var switch_flash := 0.0
var started := false
var game_over := false
var menu_page := 0
var selected_mode := "endless"
var objective_complete := false
var objective_data: Dictionary = {}
var end_mouse_position := Vector2(-100.0, -100.0)
var level_intro_time := 0.0
var lane_scroll := 0.0
var switch_shake_time := 0.0
var shift_synth_time := 2.0
var shift_synth_phase := 0.0
var percussion_timer := 0.0
var accent_timer := 0.0
const OBJECTIVE_DODGES := 12
const OBJECTIVE_SHIFTS := 3
var rng := RandomNumberGenerator.new()
var sfx: AudioStreamPlayer
var percussion_low: AudioStreamPlayer
var percussion_accent: AudioStreamPlayer
var shift_synth_player: AudioStreamPlayer
var shift_synth_playback: AudioStreamGeneratorPlayback

func _ready() -> void:
	rng.randomize()
	create_weather()
	selected_mode = GameSession.selected_mode
	if selected_mode == "objectives":
		objective_data = GameSession.get_objective(GameSession.objective_level)
		level_intro_time = 2.3
	started = true
	load_high_score()
	sfx = AudioStreamPlayer.new()
	sfx.volume_db = GameSession.get_sfx_volume_db(-5.0)
	add_child(sfx)
	create_shift_synth()
	create_music_layers()
	queue_redraw()

func _process(delta: float) -> void:
	fill_shift_synth_buffer()
	if not started:
		queue_redraw()
		return
	if game_over:
		if Input.is_key_pressed(KEY_R) or Input.is_action_just_pressed("ui_accept"):
			reset_game()
		return

	move_active_runner()
	update_autopilot(1 - active_side)
	update_runner_positions(delta)
	update_lane_particles(delta)
	update_weather(delta)
	elapsed += delta
	lane_scroll += delta * 120.0 * difficulty_multiplier()
	level_intro_time = maxf(0.0, level_intro_time - delta)
	switch_flash = maxf(0.0, switch_flash - delta)
	switch_shake_time = maxf(0.0, switch_shake_time - delta)
	update_switch_shake()
	score = int(elapsed * 10.0) + dodges * 25 + shift_bonus * 50
	update_music_layers(delta)
	update_switch()
	spawn_obstacles(delta)
	move_obstacles(delta)
	check_active_collision()
	if selected_mode == "objectives" and not game_over and objective_is_complete():
		objective_complete = true
		game_over = true
	queue_redraw()

func _input(event: InputEvent) -> void:
	if game_over and event is InputEventMouseMotion:
		end_mouse_position = event.position
		queue_redraw()
		return
	if game_over and event is InputEventMouseButton:
		var end_click := event as InputEventMouseButton
		if end_click.pressed and end_click.button_index == MOUSE_BUTTON_LEFT:
			if Rect2(220, 422, 135, 54).has_point(end_click.position):
				GameSession.play_ui_click()
				if objective_complete and selected_mode == "objectives":
					GameSession.advance_objective()
				reset_game()
			elif Rect2(382, 422, 135, 54).has_point(end_click.position):
				GameSession.play_ui_click()
				GameSession.menu_page = 1
				get_tree().change_scene_to_file("res://MainMenu.tscn")
			elif Rect2(545, 422, 135, 54).has_point(end_click.position):
				GameSession.play_ui_click()
				GameSession.menu_page = 0
				get_tree().change_scene_to_file("res://MainMenu.tscn")
		return
	if started:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	var mouse_position: Vector2 = mouse_event.position
	if menu_page == 0 and Rect2(335, 365, 230, 62).has_point(mouse_position):
		menu_page = 1
	elif menu_page == 1:
		if Rect2(165, 330, 260, 145).has_point(mouse_position):
			start_mode("endless")
		elif Rect2(475, 330, 260, 145).has_point(mouse_position):
			start_mode("objectives")
	queue_redraw()

func start_mode(new_mode: String) -> void:
	selected_mode = new_mode
	reset_game()
	started = true

func move_active_runner() -> void:
	# ui_left/ui_right already include A/D as well as the arrow keys.
	if Input.is_action_just_pressed("ui_left"):
		change_active_lane(-1)
	if Input.is_action_just_pressed("ui_right"):
		change_active_lane(1)

func change_active_lane(direction: int) -> void:
	var previous_lane := lanes[active_side]
	lanes[active_side] = clampi(lanes[active_side] + direction, 0, LANE_COUNT - 1)
	if lanes[active_side] != previous_lane:
		spawn_lane_particles(active_side, direction)

func spawn_lane_particles(side: int, direction: int) -> void:
	var particle_color := Color("62f2c4") if side == 0 else Color("d99dff")
	for index in range(7):
		var spread := rng.randf_range(-13.0, 13.0)
		lane_particles.append({
			"position": Vector2(runner_xs[side] + RUNNER_SIZE.x * 0.5 + spread, PLAYER_Y + RUNNER_SIZE.y - rng.randf_range(4.0, 18.0)),
			"velocity": Vector2(float(-direction) * rng.randf_range(45.0, 100.0) + spread * 1.2, rng.randf_range(18.0, 60.0)),
			"life": rng.randf_range(0.28, 0.46),
			"max_life": 0.46,
			"color": particle_color,
		})

func update_lane_particles(delta: float) -> void:
	for particle in lane_particles:
		var particle_position: Vector2 = particle["position"]
		var particle_velocity: Vector2 = particle["velocity"]
		particle_position += particle_velocity * delta
		particle_velocity.y += 72.0 * delta
		particle["position"] = particle_position
		particle["velocity"] = particle_velocity
		particle["life"] -= delta
	for index in range(lane_particles.size() - 1, -1, -1):
		if lane_particles[index]["life"] <= 0.0:
			lane_particles.remove_at(index)

func create_weather() -> void:
	forest_leaves.clear()
	sand_particles.clear()
	for index in range(13):
		forest_leaves.append({
			"position": Vector2(rng.randf_range(12.0, HALF_WIDTH - 12.0), rng.randf_range(112.0, 510.0)),
			"speed": rng.randf_range(16.0, 31.0),
			"phase": rng.randf_range(0.0, TAU),
			"color": Color("9ce07a") if index % 2 == 0 else Color("e6c66a"),
		})
	for index in range(22):
		sand_particles.append({
			"position": Vector2(rng.randf_range(HALF_WIDTH, SCREEN.x), rng.randf_range(135.0, 505.0)),
			"speed": rng.randf_range(38.0, 88.0),
			"wave": rng.randf_range(0.0, TAU),
		})

func update_weather(delta: float) -> void:
	for leaf in forest_leaves:
		var leaf_position: Vector2 = leaf["position"]
		leaf_position.y += leaf["speed"] * delta
		leaf_position.x += sin(elapsed * 1.8 + leaf["phase"]) * 18.0 * delta
		if leaf_position.y > 520.0:
			leaf_position = Vector2(rng.randf_range(12.0, HALF_WIDTH - 12.0), 106.0)
		leaf["position"] = leaf_position
	for particle in sand_particles:
		var sand_position: Vector2 = particle["position"]
		sand_position.x -= particle["speed"] * delta
		sand_position.y += sin(elapsed * 2.0 + particle["wave"]) * 9.0 * delta
		if sand_position.x < HALF_WIDTH:
			sand_position = Vector2(SCREEN.x + rng.randf_range(0.0, 28.0), rng.randf_range(135.0, 505.0))
		particle["position"] = sand_position

func update_runner_positions(delta: float) -> void:
	for side in 2:
		runner_xs[side] = lerpf(runner_xs[side], lane_x(side, lanes[side]), minf(1.0, delta * 15.0))
func update_autopilot(side: int) -> void:
	# The autopilot sees the upcoming route and moves before it becomes dangerous.
	var blocked: Array[bool] = [false, false, false, false]
	for item in obstacles:
		if item["side"] == side and item["y"] > 265.0 and item["y"] < 535.0:
			blocked[item["lane"]] = true
	if blocked[lanes[side]]:
		for candidate in LANE_COUNT:
			if not blocked[candidate]:
				lanes[side] = candidate
				return

func update_switch() -> void:
	if not warning_visible and elapsed >= next_switch_at - 2.0:
		warning_visible = true
	if elapsed >= next_switch_at:
		active_side = 1 - active_side
		warning_visible = false
		switch_flash = 1.1
		switch_shake_time = 0.20
		shift_bonus += 1
		next_switch_at = elapsed + next_switch_delay()
		trigger_shift_synth()

func spawn_obstacles(delta: float) -> void:
	for side in 2:
		spawn_timers[side] -= delta
		if spawn_timers[side] <= 0.0:
			spawn_obstacle(side)
			spawn_timers[side] = max(0.46, (rng.randf_range(1.05, 1.60) - elapsed * 0.008) / difficulty_multiplier())

func spawn_obstacle(side: int) -> void:
	var speed: float = (rng.randf_range(165.0, 205.0) if side == 0 else rng.randf_range(205.0, 255.0)) * difficulty_multiplier()
	var first_lane := rng.randi_range(0, LANE_COUNT - 1)
	add_obstacle(side, first_lane, -OBSTACLE_SIZE.y, speed)
	# Forest creates staggered zig-zags; desert sends quick repeat blocks.
	if side == 0 and rng.randf() < minf(0.68, 0.28 + difficulty_multiplier() * 0.08):
		var second_lane := (first_lane + rng.randi_range(1, LANE_COUNT - 1)) % LANE_COUNT
		add_obstacle(side, second_lane, -190.0, speed * 0.94)
	elif side == 1 and rng.randf() < minf(0.62, 0.23 + difficulty_multiplier() * 0.08):
		add_obstacle(side, first_lane, -150.0, speed * 1.12)

func add_obstacle(side: int, lane: int, start_y: float, speed: float) -> void:
	obstacles.append({
		"side": side,
		"lane": lane,
		"y": start_y,
		"speed": speed + elapsed * 4.5,
		"scored": false,
	})

func move_obstacles(delta: float) -> void:
	for item in obstacles:
		item["y"] += item["speed"] * delta
		if not item["scored"] and item["side"] == active_side and item["y"] > PLAYER_Y + RUNNER_SIZE.y:
			item["scored"] = true
			dodges += 1
			combo += 1
			best_combo = max(best_combo, combo)
	for index in range(obstacles.size() - 1, -1, -1):
		if obstacles[index]["y"] > SCREEN.y + 70.0:
			obstacles.remove_at(index)

func check_active_collision() -> void:
	var player_rect := Rect2(runner_xs[active_side], PLAYER_Y, RUNNER_SIZE.x, RUNNER_SIZE.y)
	for index in range(obstacles.size() - 1, -1, -1):
		var item: Dictionary = obstacles[index]
		if item["side"] == active_side:
			var collision_size := FOREST_OBSTACLE_SIZE if item["side"] == 0 else OBSTACLE_SIZE
			var obstacle_rect := Rect2(lane_x(active_side, item["lane"]), item["y"], collision_size.x, collision_size.y)
			if player_rect.intersects(obstacle_rect):
				game_over = true
				combo = 0
				record_endless_score()
				play_sound(SFX_HIT)
				return

func lane_x(side: int, lane: int) -> float:
	return side * HALF_WIDTH + (LANE_WIDTH - RUNNER_SIZE.x) * 0.5 + float(lane) * LANE_WIDTH

func play_sound(stream: AudioStream) -> void:
	sfx.stream = stream
	sfx.play()

func create_shift_synth() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = 0.08
	shift_synth_player = AudioStreamPlayer.new()
	shift_synth_player.stream = generator
	shift_synth_player.volume_db = GameSession.get_sfx_volume_db(2.5)
	add_child(shift_synth_player)
	shift_synth_player.play()
	shift_synth_playback = shift_synth_player.get_stream_playback() as AudioStreamGeneratorPlayback

func trigger_shift_synth() -> void:
	shift_synth_time = 0.0
	shift_synth_phase = 0.0

func fill_shift_synth_buffer() -> void:
	if shift_synth_playback == null:
		return
	var frames := shift_synth_playback.get_frames_available()
	for _frame in frames:
		var sample := 0.0
		if shift_synth_time < 0.92:
			var attack := minf(1.0, shift_synth_time * 105.0)
			var decay := exp(-shift_synth_time * 3.5)
			var frequency := lerpf(132.0, 38.0, minf(1.0, shift_synth_time * 2.35))
			shift_synth_phase += TAU * frequency / 44100.0
			var sub := sin(shift_synth_phase)
			var growl := sin(shift_synth_phase * 1.97) * 0.42
			var punch := sin(TAU * 168.0 * shift_synth_time) * exp(-shift_synth_time * 16.0) * 0.68
			var vibration := sin(TAU * 31.0 * shift_synth_time) * 0.30
			var buzz := sin(TAU * 312.0 * shift_synth_time) * exp(-shift_synth_time * 7.5) * 0.16
			sample = clampf((sub + growl + punch + buzz) * (1.0 + vibration) * attack * decay * 0.94, -0.95, 0.95)
		shift_synth_playback.push_frame(Vector2(sample, sample))
		shift_synth_time += 1.0 / 44100.0

func create_music_layers() -> void:
	percussion_low = AudioStreamPlayer.new()
	percussion_low.stream = SFX_BEAT_LOW
	percussion_low.volume_db = GameSession.get_music_volume_db(-12.0)
	add_child(percussion_low)
	percussion_accent = AudioStreamPlayer.new()
	percussion_accent.stream = SFX_BEAT_ACCENT
	percussion_accent.volume_db = GameSession.get_music_volume_db(-16.0)
	add_child(percussion_accent)

func update_music_layers(delta: float) -> void:
	var intensity := difficulty_multiplier()
	if intensity < 1.13:
		return
	percussion_timer -= delta
	if percussion_timer <= 0.0:
		percussion_low.pitch_scale = 0.88 + minf(0.24, (intensity - 1.13) * 0.45)
		percussion_low.play()
		percussion_timer = maxf(0.46, 0.78 - (intensity - 1.13) * 0.32)
	if intensity < 1.36:
		return
	accent_timer -= delta
	if accent_timer <= 0.0:
		percussion_accent.pitch_scale = 0.94 + minf(0.28, (intensity - 1.36) * 0.5)
		percussion_accent.play()
		accent_timer = maxf(0.25, 0.44 - (intensity - 1.36) * 0.18)

func load_high_score() -> void:
	var save_data := ConfigFile.new()
	if save_data.load(SCORE_FILE) == OK:
		best_score = int(save_data.get_value("endless", "high_score", 0))

func record_endless_score() -> void:
	if selected_mode != "endless" or score <= best_score:
		return
	best_score = score
	new_high_score = true
	var save_data := ConfigFile.new()
	save_data.set_value("endless", "high_score", best_score)
	save_data.save(SCORE_FILE)

func difficulty_multiplier() -> float:
	if selected_mode == "objectives":
		return 1.0 + float(GameSession.objective_level - 1) * 0.035
	return 1.0 + minf(0.75, elapsed * 0.008)

func next_switch_delay() -> float:
	var delay := rng.randf_range(12.0, 20.0)
	if selected_mode == "objectives":
		delay -= float(GameSession.objective_level - 1) * 0.14
	return maxf(5.5, delay)

func objective_is_complete() -> bool:
	var dodge_goal: int = int(objective_data.get("dodges", 0))
	var shift_goal: int = int(objective_data.get("shifts", 0))
	var combo_goal: int = int(objective_data.get("combo", 0))
	var score_goal: int = int(objective_data.get("score", 0))
	return (dodge_goal == 0 or dodges >= dodge_goal) and (shift_goal == 0 or shift_bonus >= shift_goal) and (combo_goal == 0 or best_combo >= combo_goal) and (score_goal == 0 or score >= score_goal)

func reset_game() -> void:
	lanes = [1, 2]
	runner_xs = [137.75, 700.25]
	obstacles.clear()
	lane_particles.clear()
	spawn_timers = [0.7, 1.2]
	active_side = 0
	elapsed = 0.0
	lane_scroll = 0.0
	score = 0
	dodges = 0
	combo = 0
	shift_bonus = 0
	new_high_score = false
	if selected_mode == "objectives":
		objective_data = GameSession.get_objective(GameSession.objective_level)
		level_intro_time = 2.3
	next_switch_at = next_switch_delay()
	warning_visible = false
	switch_flash = 0.0
	switch_shake_time = 0.0
	percussion_timer = 0.0
	accent_timer = 0.0
	position = Vector2.ZERO
	objective_complete = false
	game_over = false
	queue_redraw()

func _draw() -> void:
	draw_texture_rect(LEFT_BACKGROUND, Rect2(0, 0, HALF_WIDTH, SCREEN.y), false)
	draw_texture_rect(RIGHT_BACKGROUND, Rect2(HALF_WIDTH, 0, HALF_WIDTH, SCREEN.y), false)
	draw_weather()
	if is_final_objective():
		draw_final_objective_palette()
	draw_rect(Rect2(HALF_WIDTH - 3, 0, 6, SCREEN.y), Color("ffffff"))
	draw_rect(Rect2(HALF_WIDTH - 1, 0, 2, SCREEN.y), Color("5f48c8"))
	var left_lane_color := Color(0.24, 0.18, 0.62, 0.46) if is_final_objective() else Color(0.18, 0.48, 0.22, 0.35)
	var right_lane_color := Color(0.66, 0.16, 0.48, 0.46) if is_final_objective() else Color(0.76, 0.48, 0.17, 0.35)
	draw_lanes(0, left_lane_color, LEFT_FLOOR)
	draw_lanes(1, right_lane_color, RIGHT_FLOOR)
	for item in obstacles:
		draw_obstacle_telegraph(item)
		draw_obstacle(item)
	draw_lane_particles()

	var alternate_frame := int(elapsed * 9.0) % 2 == 0
	draw_runner(0, LEFT_RUNNER if alternate_frame else LEFT_RUNNER_B)
	draw_runner(1, RIGHT_RUNNER if alternate_frame else RIGHT_RUNNER_B)
	if switch_flash > 0.0:
		var flash_color := Color(0.85, 0.73, 1.0, switch_flash * 0.20)
		draw_rect(Rect2(active_side * HALF_WIDTH, 94, HALF_WIDTH, SCREEN.y - 94), flash_color)
	var autopilot_side := 1 - active_side
	draw_rect(Rect2(autopilot_side * HALF_WIDTH, 78, HALF_WIDTH, SCREEN.y - 78), Color(0.02, 0.03, 0.08, 0.18))
	draw_string(ThemeDB.fallback_font, Vector2(autopilot_side * HALF_WIDTH + 16, 112), "AUTO PILOT • SAFE ROUTE", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.92, 1.0, 0.7))
	draw_hud()
	if not started:
		if menu_page == 0:
			draw_home_screen()
		else:
			draw_mode_picker()
	elif game_over:
		draw_game_over()
	elif warning_visible:
		var map_name := "DESERT" if active_side == 0 else "FOREST"
		var seconds_left: int = int(ceil(next_switch_at - elapsed))
		draw_rect(Rect2(245, 145, 410, 62), Color(0.10, 0.06, 0.24, 0.92))
		draw_string(ThemeDB.fallback_font, Vector2(278, 184), "SHIFT IN %d → %s" % [seconds_left, map_name], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("fff08a"))
	elif switch_flash > 0.0:
		var handoff_map := "FOREST" if active_side == 0 else "DESERT"
		draw_rect(Rect2(290, 145, 320, 62), Color(0.12, 0.22, 0.10, 0.92))
		draw_string(ThemeDB.fallback_font, Vector2(370, 184), "YOU'RE UP: %s" % handoff_map, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("b9ff86"))
	elif level_intro_time > 0.0 and selected_mode == "objectives":
		draw_level_intro()

func draw_lanes(side: int, color: Color, floor_texture: Texture2D) -> void:
	var left := side * HALF_WIDTH
	draw_rect(Rect2(left, 520, HALF_WIDTH, 80), color)
	for lane in range(1, LANE_COUNT):
		draw_line(Vector2(left + float(lane) * LANE_WIDTH, 105), Vector2(left + float(lane) * LANE_WIDTH, 520), Color(1, 1, 1, 0.28), 2.0)
	for marker in 5:
		var marker_y := 118.0 + fmod(float(marker) * 92.0 + lane_scroll, 380.0)
		for lane in LANE_COUNT:
			var marker_left := lane_x(side, lane) + 8.0
			draw_line(Vector2(marker_left, marker_y), Vector2(marker_left + 42.0, marker_y), Color(1.0, 1.0, 1.0, 0.22), 2.0)
	for tile in 8:
		draw_texture_rect(floor_texture, Rect2(left + tile * 64, 520, 66, 66), false)

func is_final_objective() -> bool:
	return selected_mode == "objectives" and GameSession.objective_level == 50

func draw_final_objective_palette() -> void:
	var pulse := 0.10 + sin(elapsed * 2.5) * 0.035
	draw_rect(Rect2(0, 94, HALF_WIDTH, 426), Color(0.30, 0.06, 0.64, pulse))
	draw_rect(Rect2(HALF_WIDTH, 94, HALF_WIDTH, 426), Color(0.82, 0.05, 0.38, pulse))
	for index in range(7):
		var ray_y := 115.0 + float(index) * 58.0
		draw_line(Vector2(0, ray_y), Vector2(HALF_WIDTH, ray_y - 40.0), Color(0.58, 0.32, 1.0, 0.18), 2.0)
		draw_line(Vector2(HALF_WIDTH, ray_y - 40.0), Vector2(SCREEN.x, ray_y), Color(1.0, 0.30, 0.68, 0.18), 2.0)

func update_switch_shake() -> void:
	if switch_shake_time <= 0.0:
		position = Vector2.ZERO
		return
	var strength := 3.5 * (switch_shake_time / 0.20)
	position = Vector2(rng.randf_range(-strength, strength), rng.randf_range(-strength * 0.45, strength * 0.45))

func draw_runner(side: int, texture: Texture2D) -> void:
	var rect := Rect2(runner_xs[side], PLAYER_Y, RUNNER_SIZE.x, RUNNER_SIZE.y)
	if side == active_side:
		var pulse := 0.55 + sin(elapsed * 7.0) * 0.25
		draw_rect(Rect2(rect.position - Vector2(8, 8), rect.size + Vector2(16, 16)), Color(1.0, 0.91, 0.42, pulse), false, 3.0)
		draw_line(Vector2(rect.get_center().x, PLAYER_Y + RUNNER_SIZE.y + 12), Vector2(rect.get_center().x, PLAYER_Y + RUNNER_SIZE.y + 32), Color(1.0, 0.91, 0.42, pulse), 3.0)
	draw_texture_rect(texture, rect, false)

func draw_lane_particles() -> void:
	for particle in lane_particles:
		var alpha: float = clampf(particle["life"] / particle["max_life"], 0.0, 1.0)
		var particle_color: Color = particle["color"]
		particle_color.a = alpha * 0.78
		draw_circle(particle["position"], 2.5 + alpha * 2.5, particle_color)

func draw_weather() -> void:
	for leaf in forest_leaves:
		var leaf_position: Vector2 = leaf["position"]
		var leaf_color: Color = leaf["color"]
		leaf_color.a = 0.38
		var leaf_tilt: float = sin(elapsed * 3.2 + leaf["phase"]) * 4.0
		draw_line(leaf_position - Vector2(leaf_tilt, 3.0), leaf_position + Vector2(leaf_tilt, 3.0), leaf_color, 2.4)
	for particle in sand_particles:
		var sand_position: Vector2 = particle["position"]
		draw_line(sand_position, sand_position + Vector2(-6.0, 1.0), Color(1.0, 0.84, 0.53, 0.18), 1.0)

func draw_obstacle(item: Dictionary) -> void:
	var obstacle_texture: Texture2D = FOREST_SPIKES if item["side"] == 0 else OBSTACLE
	var obstacle_size := FOREST_OBSTACLE_SIZE if item["side"] == 0 else OBSTACLE_SIZE
	var obstacle_rect := Rect2(lane_x(item["side"], item["lane"]), item["y"], obstacle_size.x, obstacle_size.y)
	if item["side"] == 0:
		draw_set_transform(obstacle_rect.get_center(), PI)
		draw_texture_rect(obstacle_texture, Rect2(-obstacle_size * 0.5, obstacle_size), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect(obstacle_texture, obstacle_rect, false)

func draw_obstacle_telegraph(item: Dictionary) -> void:
	if item["y"] < 88.0 or item["y"] > 205.0:
		return
	var alpha := 0.35 + sin(elapsed * 10.0) * 0.18
	var marker_rect := Rect2(lane_x(item["side"], item["lane"]) + 2.0, 104.0, 58.0, 4.0)
	draw_rect(marker_rect, Color(1.0, 0.88, 0.36, alpha))

func draw_level_intro() -> void:
	var fade := minf(1.0, level_intro_time * 2.0)
	draw_rect(Rect2(260, 154, 380, 92), Color(0.06, 0.05, 0.16, 0.88 * fade))
	draw_rect(Rect2(260, 154, 380, 92), Color(0.63, 0.50, 1.0, fade), false, 2.0)
	draw_string(DISPLAY_FONT, Vector2(260, 190), "LEVEL %02d / 50" % GameSession.objective_level, HORIZONTAL_ALIGNMENT_CENTER, 380, 20, Color(1.0, 1.0, 1.0, fade))
	draw_string(DISPLAY_FONT, Vector2(260, 221), str(objective_data.get("title", "OBJECTIVE")), HORIZONTAL_ALIGNMENT_CENTER, 380, 14, Color(0.98, 0.91, 0.63, fade))

func draw_hud() -> void:
	draw_rect(Rect2(0, 0, SCREEN.x, 94), Color(0.025, 0.03, 0.09, 0.88))
	draw_rect(Rect2(0, 92, SCREEN.x, 2), Color("7158df"))
	draw_hud_card(Rect2(16, 16, 264, 62), Color("2e5e99"))
	draw_hud_card(Rect2(318, 16, 264, 62), Color("7657c7"))
	draw_hud_card(Rect2(620, 16, 264, 62), Color("9b6344"))
	var mode_title := "ENDLESS RUN" if selected_mode == "endless" else "LEVEL %02d / 50" % GameSession.objective_level
	var mode_detail := "SURVIVE AND SET A RECORD" if selected_mode == "endless" else str(objective_data.get("title", "OBJECTIVE")) + "  •  " + str(objective_data.get("detail", ""))
	draw_string(DISPLAY_FONT, Vector2(34, 41), mode_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
	draw_string(DISPLAY_FONT, Vector2(34, 64), mode_detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("cddbf4"))
	if selected_mode == "objectives":
		var tier: int = mini(5, 1 + int((GameSession.objective_level - 1) / 10))
		for pip in 5:
			var pip_color := Color("ffdf75") if pip < tier else Color("536080")
			draw_rect(Rect2(230 + pip * 8, 31, 5, 10), pip_color)
	var active_label := "FOREST" if active_side == 0 else "DESERT"
	var auto_label := "DESERT" if active_side == 0 else "FOREST"
	draw_string(DISPLAY_FONT, Vector2(336, 41), "YOU CONTROL: " + active_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("fff09a"))
	draw_string(DISPLAY_FONT, Vector2(336, 64), "AUTO PILOT: " + auto_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("d8d0ff"))
	draw_string(DISPLAY_FONT, Vector2(638, 41), "SCORE  %04d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
	var score_detail := "BEST %04d  •  COMBO x%d" % [best_score, combo] if selected_mode == "endless" else "DODGES %d  •  SAFE SHIFTS %d" % [dodges, shift_bonus]
	draw_string(DISPLAY_FONT, Vector2(638, 64), score_detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("ffe0bd"))

func draw_hud_card(rect: Rect2, accent: Color) -> void:
	draw_rect(rect, Color("131a32"))
	draw_rect(Rect2(rect.position, Vector2(5, rect.size.y)), accent)
	draw_rect(rect, Color(accent, 0.65), false, 1.0)

func draw_home_screen() -> void:
	draw_rect(Rect2(125, 125, 650, 340), Color(0.04, 0.03, 0.12, 0.94))
	draw_rect(Rect2(125, 125, 650, 340), Color("7f62ff"), false, 3.0)
	draw_string(ThemeDB.fallback_font, Vector2(180, 225), "SPLIT SHIFT", HORIZONTAL_ALIGNMENT_CENTER, 540, 50, Color("f1edff"))
	draw_string(ThemeDB.fallback_font, Vector2(190, 280), "Two runners race through different worlds at once.", HORIZONTAL_ALIGNMENT_CENTER, 520, 20, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(190, 315), "Trust the autopilot—until control suddenly shifts to you.", HORIZONTAL_ALIGNMENT_CENTER, 520, 19, Color("d3ccef"))
	draw_button(Rect2(335, 365, 230, 62), "PLAY", Color("7f62ff"))

func draw_mode_picker() -> void:
	draw_rect(Rect2(115, 125, 670, 390), Color(0.04, 0.03, 0.12, 0.95))
	draw_rect(Rect2(115, 125, 670, 390), Color("7f62ff"), false, 3.0)
	draw_string(ThemeDB.fallback_font, Vector2(170, 195), "CHOOSE YOUR MODE", HORIZONTAL_ALIGNMENT_CENTER, 560, 34, Color("f1edff"))
	draw_rect(Rect2(165, 330, 260, 145), Color("244c83"))
	draw_rect(Rect2(165, 330, 260, 145), Color("8cc8ff"), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(185, 370), "ENDLESS RUNNER", HORIZONTAL_ALIGNMENT_CENTER, 220, 23, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(185, 405), "Survive, score, and chase", HORIZONTAL_ALIGNMENT_CENTER, 220, 16, Color("d6eaff"))
	draw_string(ThemeDB.fallback_font, Vector2(185, 430), "your highest combo.", HORIZONTAL_ALIGNMENT_CENTER, 220, 16, Color("d6eaff"))
	draw_rect(Rect2(475, 330, 260, 145), Color("6b3d70"))
	draw_rect(Rect2(475, 330, 260, 145), Color("ffb4ee"), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(495, 370), "OBJECTIVES", HORIZONTAL_ALIGNMENT_CENTER, 220, 23, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(495, 405), "Dodge %d obstacles and" % OBJECTIVE_DODGES, HORIZONTAL_ALIGNMENT_CENTER, 220, 16, Color("ffe1fa"))
	draw_string(ThemeDB.fallback_font, Vector2(495, 430), "survive %d safe shifts." % OBJECTIVE_SHIFTS, HORIZONTAL_ALIGNMENT_CENTER, 220, 16, Color("ffe1fa"))
	draw_string(ThemeDB.fallback_font, Vector2(170, 275), "Click a card to begin.", HORIZONTAL_ALIGNMENT_CENTER, 560, 18, Color("fff08a"))

func draw_button(rect: Rect2, label: String, color: Color) -> void:
	draw_rect(rect, color)
	draw_rect(rect, Color("e7e4ff"), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(rect.position.x, rect.position.y + 40.0), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 25, Color.WHITE)

func draw_game_over() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.01, 0.01, 0.04, 0.72))
	draw_rect(Rect2(150, 86, 600, 432), Color("10142b"))
	draw_rect(Rect2(150, 86, 600, 432), Color("9d85ff"), false, 3.0)
	draw_rect(Rect2(150, 86, 600, 102), Color("251b4d"))
	var title := "LEVEL %02d COMPLETE" % GameSession.objective_level if objective_complete else "RUN ENDED"
	var subtitle := "MISSION CLEAR" if objective_complete else "SHIFT SUMMARY"
	draw_string(DISPLAY_FONT, Vector2(180, 128), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("c5b8ff"))
	draw_string(DISPLAY_FONT, Vector2(180, 168), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 31, Color("f4f1ff"))
	draw_string(ThemeDB.fallback_font, Vector2(570, 151), "MODE: " + selected_mode.to_upper(), HORIZONTAL_ALIGNMENT_RIGHT, 145, 15, Color("d8d2ed"))

	draw_summary_stat(Rect2(180, 215, 165, 105), "SCORE", "%04d" % score, Color("6f8df0"))
	draw_summary_stat(Rect2(368, 215, 165, 105), "DODGES", str(dodges), Color("63c5a2"))
	draw_summary_stat(Rect2(556, 215, 165, 105), "SHIFTS", str(shift_bonus), Color("c184e8"))
	if selected_mode == "endless" and new_high_score:
		draw_rect(Rect2(180, 342, 540, 44), Color("42355c"))
		draw_string(DISPLAY_FONT, Vector2(180, 370), "WOW! YOU HAVE REACHED A NEW HIGHSCORE OF %d" % best_score, HORIZONTAL_ALIGNMENT_CENTER, 540, 13, Color("fff09a"))

	var retry_label := "NEXT" if objective_complete and selected_mode == "objectives" and GameSession.objective_level < GameSession.MAX_OBJECTIVE_LEVEL else "RETRY"
	draw_end_button(Rect2(220, 422, 135, 54), retry_label, Color("5278d5"))
	draw_end_button(Rect2(382, 422, 135, 54), "MODES", Color("8063d9"))
	draw_end_button(Rect2(545, 422, 135, 54), "HOME", Color("a65fbe"))

func draw_summary_stat(rect: Rect2, label: String, value: String, accent: Color) -> void:
	draw_rect(rect, Color("18203b"))
	draw_rect(Rect2(rect.position, Vector2(5, rect.size.y)), accent)
	draw_string(DISPLAY_FONT, Vector2(rect.position.x + 18, rect.position.y + 34), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("aeb8da"))
	draw_string(DISPLAY_FONT, Vector2(rect.position.x + 18, rect.position.y + 77), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color.WHITE)

func draw_end_button(rect: Rect2, label: String, color: Color) -> void:
	var hovered := rect.has_point(end_mouse_position)
	var fill := color.lightened(0.16) if hovered else color
	draw_rect(rect, fill)
	draw_rect(rect, Color("f0edff"), false, 2.0 if hovered else 1.0)
	draw_string(DISPLAY_FONT, Vector2(rect.position.x, rect.position.y + 35), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 15, Color.WHITE)

func draw_panel(title: String, first_line: String, second_line: String, prompt: String) -> void:
	draw_rect(Rect2(150, 180, 600, 230), Color(0.06, 0.04, 0.16, 0.94))
	draw_rect(Rect2(150, 180, 600, 230), Color("7f62ff"), false, 3.0)
	draw_string(ThemeDB.fallback_font, Vector2(320, 245), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 38, Color("f1edff"))
	draw_string(ThemeDB.fallback_font, Vector2(245, 295), first_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(245, 330), second_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("d3ccef"))
	draw_string(ThemeDB.fallback_font, Vector2(215, 375), prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("fff08a"))

