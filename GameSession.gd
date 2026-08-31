extends Node

var selected_mode := "endless"
var menu_page := 0
var objective_level := 1
var music_level := 0.68
var sfx_level := 0.80
const MAX_OBJECTIVE_LEVEL := 50
const PROGRESS_FILE := "user://split_shift_progress.cfg"
const UI_CLICK := preload("res://assets/audio/ui_click.ogg")
const BACKGROUND_TRACK := preload("res://assets/audio/background_loop.mp3")
var ui_audio: AudioStreamPlayer
var background_player: AudioStreamPlayer

func _ready() -> void:
	load_progress()
	ui_audio = AudioStreamPlayer.new()
	ui_audio.stream = UI_CLICK
	add_child(ui_audio)
	create_background_track()
	set_music_level(music_level)
	set_sfx_level(sfx_level)

func play_ui_click() -> void:
	ui_audio.volume_db = get_sfx_volume_db(-8.0)
	ui_audio.play()

func set_music_level(value: float) -> void:
	music_level = clampf(value, 0.0, 1.0)
	if is_instance_valid(background_player):
		background_player.volume_db = get_music_volume_db(-8.0)

func set_sfx_level(value: float) -> void:
	sfx_level = clampf(value, 0.0, 1.0)
	if is_instance_valid(ui_audio):
		ui_audio.volume_db = get_sfx_volume_db(-8.0)

func get_music_volume_db(base_db: float) -> float:
	return -80.0 if music_level <= 0.01 else base_db + linear_to_db(music_level)

func get_sfx_volume_db(base_db: float) -> float:
	return -80.0 if sfx_level <= 0.01 else base_db + linear_to_db(sfx_level)

func create_background_track() -> void:
	var looping_track := BACKGROUND_TRACK.duplicate() as AudioStreamMP3
	looping_track.loop = true
	background_player = AudioStreamPlayer.new()
	background_player.stream = looping_track
	add_child(background_player)
	background_player.play()

func load_progress() -> void:
	var save_data := ConfigFile.new()
	if save_data.load(PROGRESS_FILE) == OK:
		objective_level = clampi(int(save_data.get_value("objectives", "level", 1)), 1, MAX_OBJECTIVE_LEVEL)
		var legacy_audio: float = float(save_data.get_value("settings", "audio_level", 0.72))
		music_level = clampf(float(save_data.get_value("settings", "music_level", legacy_audio)), 0.0, 1.0)
		sfx_level = clampf(float(save_data.get_value("settings", "sfx_level", legacy_audio)), 0.0, 1.0)

func advance_objective() -> void:
	if objective_level < MAX_OBJECTIVE_LEVEL:
		objective_level += 1
		var save_data := ConfigFile.new()
		save_data.set_value("objectives", "level", objective_level)
		save_data.set_value("settings", "music_level", music_level)
		save_data.set_value("settings", "sfx_level", sfx_level)
		save_data.save(PROGRESS_FILE)

func save_settings() -> void:
	var save_data := ConfigFile.new()
	save_data.load(PROGRESS_FILE)
	save_data.set_value("settings", "music_level", music_level)
	save_data.set_value("settings", "sfx_level", sfx_level)
	save_data.save(PROGRESS_FILE)

func get_objective(level: int) -> Dictionary:
	if level == MAX_OBJECTIVE_LEVEL:
		return {"title": "FINAL SHIFT", "detail": "42 dodges • 8 shifts • combo 12", "dodges": 42, "shifts": 8, "combo": 12, "score": 0}
	var tier := int((level - 1) / 10)
	var pattern := (level - 1) % 5
	match pattern:
		0:
			return {"title": "CLEAR THE ROUTE", "detail": "%d dodges" % (8 + level * 2), "dodges": 8 + level * 2, "shifts": 0, "combo": 0, "score": 0}
		1:
			return {"title": "TRUST THE SHIFT", "detail": "%d safe shifts" % (2 + tier + int(level / 12)), "dodges": 0, "shifts": 2 + tier + int(level / 12), "combo": 0, "score": 0}
		2:
			return {"title": "STAY SHARP", "detail": "combo x%d" % (4 + tier * 2 + int(level / 15)), "dodges": 0, "shifts": 0, "combo": 4 + tier * 2 + int(level / 15), "score": 0}
		3:
			return {"title": "DISTANCE RUN", "detail": "score %d" % (350 + level * 85), "dodges": 0, "shifts": 0, "combo": 0, "score": 350 + level * 85}
		_:
			return {"title": "DOUBLE DOWN", "detail": "%d dodges • %d shifts" % [6 + level, 2 + tier], "dodges": 6 + level, "shifts": 2 + tier, "combo": 0, "score": 0}

