extends Node2D

const SCREEN := Vector2(900, 600)
const FONT := preload("res://assets/fonts/kenvector_future.ttf")
var page := 0
var mouse_position := Vector2(-100.0, -100.0)
var settings_open := false
var synopsis_open := false
var ui_time := 0.0

func _ready() -> void:
	page = GameSession.menu_page
	queue_redraw()

func _process(delta: float) -> void:
	ui_time += delta
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_position = event.position
		queue_redraw()
	elif event is InputEventMouseButton:
		var click_event := event as InputEventMouseButton
		if click_event.pressed and click_event.button_index == MOUSE_BUTTON_LEFT:
			var click_position: Vector2 = click_event.position
			if page == 0 and settings_open:
				if Rect2(300, 330, 300, 16).has_point(click_position):
					GameSession.set_music_level((click_position.x - 300.0) / 300.0)
					GameSession.save_settings()
				elif Rect2(300, 410, 300, 16).has_point(click_position):
					GameSession.set_sfx_level((click_position.x - 300.0) / 300.0)
					GameSession.save_settings()
				elif Rect2(365, 475, 170, 42).has_point(click_position):
					GameSession.play_ui_click()
					settings_open = false
				queue_redraw()
				return
			if page == 0 and synopsis_open:
				if Rect2(365, 452, 170, 42).has_point(click_position):
					GameSession.play_ui_click()
					synopsis_open = false
				queue_redraw()
				return
			if page == 0 and Rect2(330, 420, 240, 64).has_point(click_position):
				GameSession.play_ui_click()
				page = 1
				GameSession.menu_page = 1
			elif page == 0 and Rect2(225, 500, 205, 42).has_point(click_position):
				GameSession.play_ui_click()
				settings_open = true
			elif page == 0 and Rect2(470, 500, 205, 42).has_point(click_position):
				GameSession.play_ui_click()
				synopsis_open = true
			elif page == 1:
				if Rect2(128, 300, 290, 180).has_point(click_position):
					GameSession.play_ui_click()
					GameSession.selected_mode = "endless"
					get_tree().change_scene_to_file("res://Main.tscn")
				elif Rect2(482, 300, 290, 180).has_point(click_position):
					GameSession.play_ui_click()
					GameSession.selected_mode = "objectives"
					get_tree().change_scene_to_file("res://Main.tscn")
				elif Rect2(368, 520, 164, 40).has_point(click_position):
					GameSession.play_ui_click()
					page = 0
					GameSession.menu_page = 0
			queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color("0b1020"))
	# The menu is one shared space: two worlds overlap here before they split in play.
	draw_circle(Vector2(145, 315), 290, Color(0.10, 0.24, 0.46, 0.32))
	draw_circle(Vector2(755, 315), 290, Color(0.34, 0.16, 0.45, 0.30))
	draw_circle(Vector2(450, 410), 185, Color(0.35, 0.24, 0.65, 0.13))
	for index in 22:
		var x: float = float((index * 71 + 43) % 880) + 10.0
		var y: float = fmod(float((index * 113 + 29) % 560) + ui_time * (9.0 + index % 4 * 3.0), 560.0) + 18.0
		draw_circle(Vector2(x, y), 1.5 if index % 3 else 2.5, Color(0.75, 0.84, 1.0, 0.65))
	if page == 0:
		draw_home()
	else:
		draw_modes()

func draw_home() -> void:
	draw_string(FONT, Vector2(0, 170), "SPLIT", HORIZONTAL_ALIGNMENT_CENTER, 900, 66, Color("f5f2ff"))
	draw_string(FONT, Vector2(0, 245), "SHIFT", HORIZONTAL_ALIGNMENT_CENTER, 900, 66, Color("bda6ff"))
	draw_string(FONT, Vector2(0, 315), "TWO WORLDS. ONE MOMENT OF CONTROL.", HORIZONTAL_ALIGNMENT_CENTER, 900, 18, Color("d8d2ed"))
	draw_string(FONT, Vector2(0, 350), "Your other runner is safe—until the shift makes them yours.", HORIZONTAL_ALIGNMENT_CENTER, 900, 15, Color("a7b2d7"))
	draw_button(Rect2(330, 420, 240, 64), "PLAY", Color("7f62ff"))
	draw_button(Rect2(225, 500, 205, 42), "SETTINGS", Color("38466d"))
	draw_button(Rect2(470, 500, 205, 42), "SYNOPSIS", Color("5d497f"))
	draw_string(FONT, Vector2(0, 398), "ENDLESS RUNNER  •  OBJECTIVES", HORIZONTAL_ALIGNMENT_CENTER, 900, 11, Color("9da8ce"))
	draw_string(FONT, Vector2(0, 574), "A GAME ABOUT TRUSTING THE OTHER HALF", HORIZONTAL_ALIGNMENT_CENTER, 900, 12, Color("7983a6"))
	if settings_open:
		draw_settings_panel()
	elif synopsis_open:
		draw_synopsis_panel()

func draw_settings_panel() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.01, 0.02, 0.07, 0.94))
	draw_rect(Rect2(180, 155, 540, 385), Color("091128"))
	draw_rect(Rect2(180, 155, 540, 385), Color("8871e8"), false, 2.0)
	draw_string(FONT, Vector2(180, 210), "SETTINGS", HORIZONTAL_ALIGNMENT_CENTER, 540, 30, Color("f5f2ff"))
	draw_string(ThemeDB.fallback_font, Vector2(300, 286), "Background music", HORIZONTAL_ALIGNMENT_LEFT, 220, 18, Color("e6e4f5"))
	draw_string(ThemeDB.fallback_font, Vector2(520, 286), "%d%%" % int(GameSession.music_level * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, 80, 18, Color("bfaeff"))
	draw_rect(Rect2(300, 330, 300, 16), Color("20294d"))
	draw_rect(Rect2(300, 330, 300 * GameSession.music_level, 16), Color("8b70ff"))
	draw_circle(Vector2(300 + 300 * GameSession.music_level, 338), 10.0, Color("f5f2ff"))
	draw_string(ThemeDB.fallback_font, Vector2(300, 366), "Sound effects", HORIZONTAL_ALIGNMENT_LEFT, 220, 18, Color("e6e4f5"))
	draw_string(ThemeDB.fallback_font, Vector2(520, 366), "%d%%" % int(GameSession.sfx_level * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, 80, 18, Color("75ead5"))
	draw_rect(Rect2(300, 410, 300, 16), Color("20294d"))
	draw_rect(Rect2(300, 410, 300 * GameSession.sfx_level, 16), Color("60d9c2"))
	draw_circle(Vector2(300 + 300 * GameSession.sfx_level, 418), 10.0, Color("f5f2ff"))
	draw_string(ThemeDB.fallback_font, Vector2(180, 455), "Music plays continuously. Effects include shifts and buttons.", HORIZONTAL_ALIGNMENT_CENTER, 540, 14, Color("aeb8d9"))
	draw_button(Rect2(365, 475, 170, 42), "CLOSE", Color("38466d"))

func draw_synopsis_panel() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.01, 0.02, 0.07, 0.72))
	draw_rect(Rect2(180, 165, 540, 355), Color(0.035, 0.045, 0.13, 1.0))
	draw_rect(Rect2(180, 165, 540, 355), Color("8871e8"), false, 2.0)
	draw_string(FONT, Vector2(180, 218), "SYNOPSIS", HORIZONTAL_ALIGNMENT_CENTER, 540, 30, Color("f5f2ff"))
	draw_string(ThemeDB.fallback_font, Vector2(220, 274), "Two runners travel through separate worlds.", HORIZONTAL_ALIGNMENT_CENTER, 460, 18, Color("f1eeff"))
	draw_string(ThemeDB.fallback_font, Vector2(220, 309), "You control one runner at a time.", HORIZONTAL_ALIGNMENT_CENTER, 460, 16, Color("cdd3ec"))
	draw_string(ThemeDB.fallback_font, Vector2(220, 338), "The other runner follows a safe route.", HORIZONTAL_ALIGNMENT_CENTER, 460, 16, Color("cdd3ec"))
	draw_string(ThemeDB.fallback_font, Vector2(220, 367), "At unpredictable moments, control transfers", HORIZONTAL_ALIGNMENT_CENTER, 460, 16, Color("cdd3ec"))
	draw_string(ThemeDB.fallback_font, Vector2(220, 391), "to the other world.", HORIZONTAL_ALIGNMENT_CENTER, 460, 16, Color("cdd3ec"))
	draw_string(ThemeDB.fallback_font, Vector2(220, 430), "Keep both runners safe for as long as possible.", HORIZONTAL_ALIGNMENT_CENTER, 460, 17, Color("ffe78d"))
	draw_button(Rect2(365, 452, 170, 42), "CLOSE", Color("38466d"))

func draw_modes() -> void:
	draw_string(FONT, Vector2(0, 125), "SELECT MODE", HORIZONTAL_ALIGNMENT_CENTER, 900, 34, Color("f5f2ff"))
	draw_string(FONT, Vector2(0, 165), "HOW DO YOU WANT TO HANDLE THE SHIFT?", HORIZONTAL_ALIGNMENT_CENTER, 900, 14, Color("a7b2d7"))
	draw_mode_card(Rect2(128, 300, 290, 180), "ENDLESS", "RUN AS LONG AS YOU CAN", "SCORE • COMBO • HIGH SCORE", Color("427bd4"))
	var level_data := GameSession.get_objective(GameSession.objective_level)
	draw_mode_card(Rect2(482, 300, 290, 180), "LEVEL %02d / 50" % GameSession.objective_level, str(level_data.get("title", "OBJECTIVES")), str(level_data.get("detail", "")), Color("9a5cc6"))
	draw_button(Rect2(368, 520, 164, 40), "BACK", Color("38466d"))

func draw_mode_card(rect: Rect2, title: String, subtitle: String, detail: String, color: Color) -> void:
	var hovered := rect.has_point(mouse_position)
	var fill := color.lightened(0.14) if hovered else color.darkened(0.18)
	draw_rect(rect, fill)
	draw_rect(rect, Color("eeeaff"), false, 3.0 if hovered else 2.0)
	draw_string(FONT, Vector2(rect.position.x, rect.position.y + 58), title, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 27, Color.WHITE)
	draw_string(FONT, Vector2(rect.position.x, rect.position.y + 98), subtitle, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 13, Color("e7e4ff"))
	draw_string(FONT, Vector2(rect.position.x, rect.position.y + 130), detail, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 12, Color("d5ccf1"))

func draw_button(rect: Rect2, label: String, color: Color) -> void:
	var hovered := rect.has_point(mouse_position)
	var fill := color.lightened(0.18) if hovered else color
	var label_size: int = min(24, int(rect.size.y * 0.52))
	var label_baseline: float = rect.position.y + (rect.size.y + float(label_size)) * 0.5 - 3.0
	draw_rect(rect, fill)
	draw_rect(rect, Color("f1edff"), false, 3.0)
	draw_string(FONT, Vector2(rect.position.x, label_baseline), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, label_size, Color.WHITE)

