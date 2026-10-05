extends Node2D
## Demo of the exported ISS Deluxe assets: a stadium, players running in all
## directions with alternating kits, a bouncing ball, the officials and the
## dog, with the crowd. Arrow keys scroll, +/- change the stadium, W changes
## the weather, K the officials' kit, B kicks the ball, G and C play the
## goal and corner-kick commentary (with the banner), M the next song (needs the rendered sound).

const SPEED := 60.0
## Ball physics per 60 Hz frame (NTSC values of ball_update / sub_00A1C6).
const GRAVITY := float(0x1400) / 65536.0
const BALL_SPEED := 1.5

var _pitch := ISSPitch.new()
var _weather := ISSWeather.new()
var _flags := ISSFlags.new()
var _hud := ISSHud.new()
var _camera := Camera2D.new()
var _players: Array[ISSPlayerSprite] = []
var _pitch_pos: Array[Vector2] = []
var _ball := ISSBallSprite.new()
var _ball_pos := Vector2(820, 520)
var _ball_vz := 0.0
var _npcs: Array[ISSNPCSprite] = []
var _sound := ISSSound.new()
var _song := -1


func _ready() -> void:
	add_child(_sound)
	_sound.play_sfx(0x62) # crowd ambience (loops)
	add_child(_pitch)
	var size := _pitch.pixel_size()
	_weather.area = size
	_weather.z_index = 4000 # plane A is high priority: above the players
	add_child(_weather)
	add_child(_flags)
	var layer := CanvasLayer.new()
	_hud.scale = Vector2(3, 3)
	_hud.home_team = 0
	_hud.away_team = 1
	layer.add_child(_hud)
	add_child(layer)
	_camera.position = Vector2(size) / 2.0
	_camera.zoom = Vector2(3, 3)
	add_child(_camera)
	for i in 16:
		var p := ISSPlayerSprite.new()
		p.facing = (i * 4) & 63
		p.team = (i / 2) % 43
		p.second_kit = i % 2 == 1
		p.action = 1 + i % 3
		add_child(p)
		_players.append(p)
		_pitch_pos.append(Vector2(700 + (i % 4) * 80, 400 + (i / 4) * 60))
	add_child(_ball)
	_kick()
	# Referee running, linesman signalling, dog running with the flag.
	for spec in [[2, 16, Vector2(760, 470)], [7, 48, Vector2(900, 380)], [16, 20, Vector2(640, 560)]]:
		var n := ISSNPCSprite.new()
		n.action = spec[0]
		n.facing = spec[1]
		n.position = ISSProjection.to_map(spec[2])
		n.z_index = int(spec[2].y)
		add_child(n)
		_npcs.append(n)


## Kick the ball up and back the way it came.
func _kick() -> void:
	_ball_vz = 3.0
	_sound.play_sfx(0x4D) # ball kick
	_ball.facing = (_ball.facing + 28 + randi() % 9) & 63


func _process(delta: float) -> void:
	for i in _players.size():
		_pitch_pos[i] += ISSProjection.heading_vector(_players[i].facing) * SPEED * delta
		_players[i].position = ISSProjection.to_map(_pitch_pos[i])
		_players[i].z_index = int(_pitch_pos[i].y)
	# One physics step per 60 Hz frame, like the game.
	var steps := maxi(1, roundi(delta * 60.0))
	for _i in steps:
		_ball_vz -= GRAVITY
		_ball.height += _ball_vz
		if _ball.height <= 0.0:
			_ball.height = 0.0
			_ball_vz = -_ball_vz * 0.5 if _ball_vz < -0.25 else 0.0
			if _ball_vz == 0.0:
				_kick()
		_ball_pos += ISSProjection.heading_vector(_ball.facing) * BALL_SPEED
		_ball.spin += BALL_SPEED / 4.0 if _ball.height == 0.0 else 0.125
	_ball.position = ISSProjection.to_map(_ball_pos)
	_ball.z_index = int(_ball_pos.y)
	# HUD: clock and radar.
	_hud.clock_seconds = maxf(0.0, _hud.clock_seconds - delta)
	var dots: Array = [[_ball_pos, "ball"]]
	for i in _players.size():
		dots.append([_pitch_pos[i], "home" if _players[i].team % 2 == 0 else "away"])
	_hud.set_radar(dots)
	var move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	_camera.position += move * 300.0 * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_EQUAL, KEY_KP_ADD:
				_pitch.stadium = (_pitch.stadium + 1) % 8
				_weather.stadium = _pitch.stadium
				_flags.stadium = _pitch.stadium
				_hud.set_stadium(_pitch.stadium)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_pitch.stadium = (_pitch.stadium + 7) % 8
				_weather.stadium = _pitch.stadium
				_flags.stadium = _pitch.stadium
				_hud.set_stadium(_pitch.stadium)
			KEY_W:
				_pitch.weather = (_pitch.weather + 1) % 3
				_weather.weather = _pitch.weather
			KEY_K:
				for n in _npcs:
					n.set_kit((n.kit + 1) % 4)
			KEY_B:
				_kick()
			KEY_G:
				_sound.say(0x2F) # goal
			KEY_C:
				_sound.say(0x01) # corner kick
				_hud.show_banner("corner_kick")
				get_tree().create_timer(2.0).timeout.connect(_hud.hide_banner)
			KEY_M:
				for i in 26:
					_song = (_song + 1) % 26
					if _sound.play_music(_song):
						break
