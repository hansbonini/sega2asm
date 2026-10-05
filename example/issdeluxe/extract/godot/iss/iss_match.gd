class_name ISSMatch
extends Node2D
## A match on screen: the stadium, both teams, the ball, the officials, the
## weather, the HUD and the sound, driven by ISSMatchEngine at 60 frames per
## second. Put it in a 256 x 224 viewport (ISSGame does). Emits match_over
## with the result once the final whistle's banner has been shown.

signal match_over(result: Dictionary)

const SCREEN := Vector2(256, 224)

var engine := ISSMatchEngine.new()
var options := {}
## Start pauses the match (match_rules_update spawns matchflow_func_018BD8
## for a 3-button pad, matchflow_func_018A7A for a 6-button one, or
## challenge_pause in a challenge): the game freezes (g_frame_state 1) and
## a menu opens in the window band.
var paused := false
## The pause object's state: the band's half-height in lines ($964, 2 a
## frame up to the menu's), the cursor ($8C), the closing flag
## (obj_distance), the side that paused and the menu kind ("" = a
## challenge's pause, which has no menu).
var _pause := {}
## The strategy item's position in the four slots ($1846 / $18CE).
var _strategy_cycle := [0, 0]

var _pitch := ISSPitch.new()
var _weather := ISSWeather.new()
var _flags := ISSFlags.new()
var _hud := ISSHud.new()
var _camera := Camera2D.new()
var _sound := ISSSound.new()
var _ball := ISSBallSprite.new()
var _marker := Sprite2D.new()
var _referee := ISSNPCSprite.new()
var _linesman := ISSNPCSprite.new()
var _cursor := Cursor.new()
var _pk_text := PKText.new()
var _props := ChallengeProps.new()
var _sprites := {}
var _cam := Vector2.ZERO
var _lead := Vector2.ZERO
var _cam_z := 0.0
var _end_wait := -1
var _fade := ColorRect.new()
## fade_out_start: the frames the picture takes to go black.
const FADE := 16
var _fade_dir := 0
var _fade_t := 0
var _fade_then := Callable()

## The replay ring (state_match_frame_2): 45 snapshots at $FFD0A6, one every
## 8 frames with the positions, the camera and who is controlled, plus the
## animation of frames 2 and 6 in between; $17E8 is the frame being
## recorded, $17E6 the oldest kept, $17EC the goal mark that freezes it 16
## frames into a goal (the ring restarts at the kick-off).
const RING := 45
const RING_FRAMES := RING * 8
var _ring: Array = []
var _rec_frame := 0
var _rec_start := 0
var _rec_frozen := false
var _goal_timer := -1
## The replay running ($17DC = 2): {"frame": $17EA, "start", "end", "auto":
## $17E2 (1 to start, 2 playing by itself, 0 once a button was pressed),
## "back": $17DE, "slow": $17E0, "blink": $17E4, "manual"}; empty = none.
var _replay := {}


## The penalty tally during a shoot-out.
class PKText:
	extends Node2D
	var pk := ""

	func _draw() -> void:
		if pk != "":
			ISSText.draw_centred(self, pk, 128, 36, false, true)


## The challenges' props: the dribble's flags (flag_draw frames, waving like
## restart_setup_practice_target_1) and the goal target panel
## (goal_target_draw: drawn every other frame so that it looks see-through,
## the second colour once a goal hits it).
class ChallengeProps:
	extends Node2D
	var engine: ISSMatchEngine
	var _flags: Array[Sprite2D] = []
	var _target := Sprite2D.new()
	var _frames: Array = []
	var _ticks := 6
	var _targets: Array = []
	var _t := 0

	func _ready() -> void:
		var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/iss/flags/flags.json"))
		_frames = doc["actions"][0]
		_ticks = int(doc["frame_ticks"])
		var misc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/iss/misc/misc.json"))
		_targets = misc["goal_target"]
		var mat := ShaderMaterial.new()
		mat.shader = load("res://md/md_indexed.gdshader")
		mat.set_shader_parameter("palette", load(ISSFlags.PALETTE))
		for i in 5:
			var f := Sprite2D.new()
			f.centered = false
			f.material = mat
			f.visible = false
			add_child(f)
			_flags.append(f)
		_target.centered = false
		_target.material = mat
		_target.visible = false
		add_child(_target)

	func sync() -> void:
		_t += 1
		var r: Dictionary = _frames[(_t / _ticks) % _frames.size()]
		for i in _flags.size():
			var f := _flags[i]
			f.visible = i < engine.ch_flags.size()
			if f.visible:
				var at: Vector2 = engine.ch_flags[i]
				f.texture = load(r["png"])
				f.offset = Vector2(-int(r["origin_x"]), -int(r["origin_y"]))
				f.position = ISSProjection.to_map(at)
				f.z_index = int(at.y)
		_target.visible = not is_nan(engine.ch_target_y) and _t % 2 == 0
		if _target.visible:
			var g: Dictionary = _targets[1 if engine.ch_bonus_on else 0]
			_target.texture = load(g["png"])
			_target.offset = Vector2(-int(g["origin_x"]), -int(g["origin_y"]))
			var at := Vector2(engine.rect.end.x, engine.ch_target_y)
			_target.position = ISSProjection.to_map(at)
			_target.z_index = int(at.y)


## Arrow over the controlled players (home / away colours).
class Cursor:
	extends Node2D
	var points: Array = [] # [map position, colour]

	func _draw() -> void:
		for p in points:
			var at: Vector2 = p[0]
			draw_colored_polygon(PackedVector2Array([at + Vector2(-3, -4), at + Vector2(3, -4), at]), p[1])


func start(home: int, away: int, opts: Dictionary) -> void:
	options = opts
	ISSMatchData.ensure_loaded()
	ISSInput.ensure_actions()
	engine.setup(home, away, opts)
	add_child(_sound)
	_pitch.stadium = engine.stadium
	_pitch.weather = engine.weather
	_pitch.z_index = -4096
	add_child(_pitch)
	_flags.stadium = engine.stadium
	add_child(_flags)
	_weather.stadium = engine.stadium
	_weather.weather = engine.weather
	_weather.area = _pitch.pixel_size()
	_weather.z_index = 4000
	add_child(_weather)
	for t in engine.teams:
		for p in t.players:
			# The keepers have their own frame set (obj_set_frame_draw).
			var s: Sprite2D = ISSKeeperSprite.new() if p.is_keeper() else ISSPlayerSprite.new()
			s.team = t.team_id
			s.second_kit = t.second_kit
			add_child(s)
			if not p.is_keeper():
				# His own head (shirt number), hair and the team's kit tiles.
				s.set_look(t.team_id, t.second_kit, p.number, p.hair)
			_sprites[p] = s
	add_child(_ball)
	_marker.texture = load("res://assets/iss/misc/landing_marker.png")
	var marker_mat := ShaderMaterial.new()
	marker_mat.shader = load("res://md/md_indexed.gdshader")
	marker_mat.set_shader_parameter("palette", load(ISSFlags.PALETTE))
	_marker.material = marker_mat
	_marker.visible = false
	_marker.z_index = -100
	add_child(_marker)
	_referee.kit = engine.referee_kit
	add_child(_referee)
	_referee.set_kit(engine.referee_kit)
	add_child(_linesman)
	_linesman.set_kit(engine.referee_kit)
	_cursor.z_index = 4001
	add_child(_cursor)
	var size := Vector2(_pitch.pixel_size())
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(size.x)
	_camera.limit_bottom = int(size.y)
	_camera.offset = Vector2(0, 8)
	add_child(_camera)
	_camera.make_current()
	var layer := CanvasLayer.new()
	layer.layer = 10
	_hud.home_team = engine.teams[0].team_id
	_hud.away_team = engine.teams[1].team_id
	layer.add_child(_hud)
	layer.add_child(_pk_text)
	add_child(layer)
	_hud.set_stadium(engine.stadium)
	_hud.set_teams(engine.teams[0].team_id, engine.teams[1].team_id)
	engine.sound.connect(_sound.play_sfx)
	engine.speech.connect(_sound.say)
	engine.banner.connect(_hud.show_banner)
	engine.banner_off.connect(_hud.hide_banner)
	engine.finished.connect(func() -> void: _end_wait = FADE if engine.half_only else (180 if engine.challenge < 0 else 1))
	engine.music.connect(func(id: int) -> void: _sound.play_music(id))
	_props.engine = engine
	add_child(_props)
	_ring_reset()
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 20
	_fade.color = Color(0, 0, 0, 0)
	_fade.size = SCREEN
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade)
	add_child(fade_layer)
	_sound.play_sfx(0x63) # crowd
	_cam = engine.ball.pos
	_sync()


func _physics_process(_delta: float) -> void:
	if engine.teams.is_empty():
		return
	var sides := _human_sides()
	# Controller n drives the engine's slot n; what is on the screen limits
	# AREA A control. The pads are read every frame so that presses have
	# edges even while the picture fades.
	var pads: Array = []
	for i in sides.size():
		pads.append(ISSInput.read(i))
	if _fade_dir != 0:
		_fade_step()
		return
	if engine.drill >= 0 and ISSInput.start_pressed(0):
		# Training: Start goes to the training menu (match_rules_update_3).
		match_over.emit({"training_menu": true})
		return
	if engine.demo and _end_wait < 0 and (ISSInput.start_pressed(0) or ISSInput.start_pressed(1)):
		# The attract demo: Start on either pad leaves for the title.
		engine.demo_start()
	if not _replay.is_empty():
		_replay_frame(pads)
		return
	if paused:
		_pause_frame(sides, pads)
		return
	if _end_wait >= 0:
		_end_wait -= 1
		if engine.half_only:
			_fade.color.a = 1.0 - float(_end_wait) / FADE
		if _end_wait == 0:
			match_over.emit(result())
		_sync()
		return
	for i in sides.size():
		if pads[i]["raw_press"] & ISSInput.START:
			_pause_open(i, sides[i])
			return
	for i in sides.size():
		if engine.half_only and engine.drill < 0 and pads[i]["raw_press"] & ISSInput.X:
			# match_players_update: X asks for (or cancels) the match menu.
			engine.menu_request[sides[i]] ^= 1
	var vp := get_viewport_rect().size
	engine.view = Rect2(_camera.get_screen_center_position() - vp / 2.0, vp)
	engine.step(pads)
	_record()
	_sync()


## Pad n plays for the side of the engine's slot n.
func _human_sides() -> Array:
	var out := []
	for sl in engine.slots:
		out.append(sl.side)
	return out


# ---------------------------------------------------------------------------
# The pause menu.

## Start on pad i: the pause object for its side and pad type.
func _pause_open(i: int, side: int) -> void:
	paused = true
	var six: bool = engine.slots[i].six if i < engine.slots.size() else true
	var kind := ""
	if engine.challenge < 0:
		kind = "six_button" if six else "three_button"
	_pause = {"band": 0, "cursor": 0, "closing": false, "side": side, "kind": kind}
	_hud.pause = {}


## One frame of the pause object: the band opens 2 lines a frame each way;
## up / down move the cursor (a 6-button pad's two items just swap), Start
## closes, C takes the item: RESUME, REPLAY (after a fade), STRATEGY (the
## side's next strategy slot, then none) and EDIT SCREEN (the match menu
## request, as X does). Closing shrinks the band before play resumes.
func _pause_frame(sides: Array, pads: Array) -> void:
	var press := 0
	for i in sides.size():
		if sides[i] == int(_pause["side"]):
			press |= int(pads[i]["raw_press"])
	var kind: String = _pause["kind"]
	if kind == "":
		# challenge_pause: Start again resumes.
		if press & ISSInput.START:
			paused = false
		return
	var layout := _hud.pause_layout(kind)
	var items: Array = layout.get("items", ["RESUME", "REPLAY"])
	var side := int(_pause["side"])
	if _pause["closing"]:
		_pause["band"] = maxi(0, int(_pause["band"]) - 2)
		if int(_pause["band"]) == 0:
			paused = false
			_hud.pause = {}
			return
	else:
		_pause["band"] = mini(int(layout.get("band", 36)), int(_pause["band"]) + 2)
		var cursor := int(_pause["cursor"])
		if kind == "six_button":
			if press & (ISSInput.UP | ISSInput.DOWN):
				cursor ^= 1
		else:
			if press & ISSInput.UP:
				cursor = cursor - 1 if cursor > 0 else items.size() - 1
			if press & ISSInput.DOWN:
				cursor = (cursor + 1) % items.size()
		if press & ISSInput.START:
			cursor = 0
			_pause["closing"] = true
		if press & ISSInput.C:
			match cursor:
				0:
					_pause["closing"] = true
				1:
					_fade_out(_replay_start)
				2:
					_strategy_next(side)
				3:
					engine.menu_request[side] ^= 1
					_hud.menu_request = [engine.menu_request[0] != 0, engine.menu_request[1] != 0]
		_pause["cursor"] = cursor
	_hud.pause = {"kind": kind, "cursor": _pause["cursor"], "band": _pause["band"]}


## The STRATEGY item: the side's strategy slots in turn, then none
## (tm_strategy_on is set for every match).
func _strategy_next(side: int) -> void:
	var t := engine.teams[side]
	var c := int(_strategy_cycle[side])
	if c > 3:
		t.strategy = -1
		_strategy_cycle[side] = 0
	else:
		t.strategy = int(t.strategy_slots[c])
		_strategy_cycle[side] = c + 1
	t.strategy_run = -1
	if side == 0:
		_hud.home_strategy = t.strategy
	else:
		_hud.away_strategy = t.strategy


# ---------------------------------------------------------------------------
# The replay.

func _ring_reset() -> void:
	_ring = []
	_ring.resize(RING)
	_rec_frame = 0
	_rec_start = 0
	_rec_frozen = false
	_goal_timer = -1


## state_match_frame_2 after each engine frame.
func _record() -> void:
	var goal := engine.restart_type == ISSMatchEngine.R.GOAL or engine.restart_type == ISSMatchEngine.R.OWN_GOAL
	if goal:
		if _goal_timer < 0:
			_goal_timer = 16
		elif _goal_timer > 0:
			_goal_timer -= 1
			if _goal_timer == 0:
				_rec_frozen = true
	elif _goal_timer >= 0:
		# The kick-off re-enters state_match, which empties the ring.
		_ring_reset()
	if _rec_frozen or engine.over:
		return
	var f := _rec_frame
	_rec_frame = (f + 1) % RING_FRAMES
	if _rec_frame == _rec_start:
		_rec_start = (_rec_start + 8) % RING_FRAMES
	match f & 7:
		0:
			_snapshot(f / 8)
		2:
			_snapshot_anim(f / 8, 0)
		6:
			_snapshot_anim(f / 8, 1)


## state_match_6: the positions, heights and facings, the ball, the camera
## and the controlled players.
func _snapshot(slot: int) -> void:
	var b := engine.ball
	var s := {"players": [], "anim": [null, null], "ball": [b.pos, b.z, b.heading], "cam": [_cam, _cam_z, _lead], "ctl": []}
	for t in engine.teams:
		for p in t.players:
			s["players"].append([p.pos, p.z, p.facing])
	for sl in engine.slots:
		s["ctl"].append(sl.player)
	_ring[slot] = s


## state_match_7: the animation (action and frame) of everyone, the ball's spin.
func _snapshot_anim(slot: int, k: int) -> void:
	if _ring[slot] == null:
		return
	var a := [[engine.ball.spin, engine.ball.heading]]
	for t in engine.teams:
		for p in t.players:
			a.append([p.action, p.anim_frame])
	_ring[slot]["anim"][k] = a


## The REPLAY item once the picture is black (state_match_5 with $17DC = 1):
## the ring's end is completed with the current frame unless the goal mark
## froze it, then the replay starts from the oldest snapshot.
func _replay_start() -> void:
	if not _rec_frozen:
		_rec_frame &= ~7
		_snapshot(_rec_frame / 8)
		_snapshot_anim(_rec_frame / 8, 0)
	else:
		_rec_frame = posmod((_rec_frame & ~7) - 8, RING_FRAMES)
	_replay = {"frame": _rec_start, "start": _rec_start, "end": _rec_frame, "auto": 1, "back": false,
		"slow": 0, "blink": 0, "manual": false}
	_hud.pause = {}
	_referee.visible = false
	_linesman.visible = false
	_marker.visible = false
	_apply_replay(int(_replay["frame"]))
	_fade_in()


## One frame of the replay (state_match_frame_2 with $17DC = 2): it plays by
## itself to the end unless a button is pressed; then C plays forward, A
## backward, B toggles slow motion (half speed while the direction's button
## is held) and only Start leaves. Leaving fades out and returns to the
## pause menu, or to play when the goal mark had frozen the ring.
func _replay_frame(pads: Array) -> void:
	var r := _replay
	if int(r["auto"]) == 1:
		r["auto"] = 2
		_sound.play_sfx(0x3F)
	var press := 0
	var held := 0
	for pd in pads:
		press |= int(pd["raw_press"])
		held |= int(pd["raw"])
	if (int(r["auto"]) != 0 and r["frame"] == r["end"]) or press & ISSInput.START:
		_fade_out(_replay_end)
		return
	if not engine.slots.is_empty():
		if held & (ISSInput.A | ISSInput.C) or press & ISSInput.B:
			r["auto"] = 0
			r["manual"] = true
		if press & ISSInput.B:
			r["slow"] = 0 if int(r["slow"]) != 0 else 1
		if held & ISSInput.C:
			r["back"] = false
		if held & ISSInput.A:
			r["back"] = true
	var move := 0
	var button: int = ISSInput.A if r["back"] else ISSInput.C
	if int(r["slow"]) == 0:
		move = -1 if r["back"] else 1
	elif held & button:
		if int(r["slow"]) <= 1:
			r["slow"] = 2
			move = -1 if r["back"] else 1
		else:
			r["slow"] = int(r["slow"]) - 1
	if move > 0 and r["frame"] != r["end"]:
		r["frame"] = (int(r["frame"]) + 1) % RING_FRAMES
	elif move < 0 and r["frame"] != r["start"]:
		r["frame"] = posmod(int(r["frame"]) - 1, RING_FRAMES)
	r["blink"] = int(r["blink"]) + 1
	_apply_replay(int(r["frame"]))


func _replay_end() -> void:
	_replay = {}
	_hud.set_replay({})
	_referee.visible = true
	_linesman.visible = true
	if _rec_frozen:
		_ring_reset()
		paused = false
		_pause = {}
		_hud.pause = {}
	else:
		_pause["cursor"] = 0
		_pause["closing"] = false
		_hud.pause = {"kind": _pause["kind"], "cursor": 0, "band": _pause["band"]}
	_sync()
	_fade_in()


## state_match_8: frame f of the replay on the screen, the positions between
## its snapshot and the next (eighths), the animation of the nearer sampled
## frame, the camera likewise.
func _apply_replay(f: int) -> void:
	var s0: Variant = _ring[f / 8]
	if s0 == null:
		return
	var s1: Variant = _ring[((f & ~7) + 8) % RING_FRAMES / 8]
	if s1 == null:
		s1 = s0
	var t := float(f & 7) / 8.0
	var anim: Variant = s0["anim"][(f & 4) >> 2]
	if anim == null:
		anim = s0["anim"][0]
	var dots: Array = []
	var cursors: Array = []
	var k := 0
	for team in engine.teams:
		for p in team.players:
			var a0: Array = s0["players"][k]
			var a1: Array = s1["players"][k]
			var pos: Vector2 = a0[0] + (a1[0] - a0[0]) * t
			var z: float = a0[1] + (a1[1] - a0[1]) * t
			var spr: Sprite2D = _sprites[p]
			if anim != null:
				_pose(spr, p, int(anim[k + 1][0]), int(anim[k + 1][1]), int(a0[2]))
			spr.position = ISSProjection.to_map(pos, z).round()
			spr.z_index = int(pos.y)
			var mine: bool = s0["ctl"].has(p)
			dots.append([pos, ("controlled_" if mine else "") + ("home" if team.side == 0 else "away")])
			if mine:
				cursors.append([spr.position + Vector2(0, -42), Color(1, 1, 0.3) if team.side == 0 else Color(0.4, 1, 1)])
			k += 1
	var b0: Array = s0["ball"]
	var b1: Array = s1["ball"]
	var bpos: Vector2 = b0[0] + (b1[0] - b0[0]) * t
	_ball.position = ISSProjection.to_map(bpos).round()
	_ball.height = b0[1] + (b1[1] - b0[1]) * t
	_ball.facing = roundi(b0[2]) & 63
	if anim != null:
		_ball.spin = anim[0][0]
	_ball.z_index = int(bpos.y) + 1
	dots.append([bpos, "ball"])
	var c0: Array = s0["cam"]
	var c1: Array = s1["cam"]
	var cam: Vector2 = c0[0] + (c1[0] - c0[0]) * t
	var cam_z: float = c0[1] + (c1[1] - c0[1]) * t
	_camera.position = ISSProjection.to_map(cam, cam_z).round()
	_cursor.points = cursors
	_cursor.queue_redraw()
	_hud.set_radar(dots)
	var r := _replay
	_hud.set_replay({"manual": r["manual"], "back": r["back"], "slow": int(r["slow"]) != 0, "blink": r["blink"]})


# ---------------------------------------------------------------------------
# Fades (fade_out_start): the game freezes while the picture goes black or
# comes back over FADE frames.

func _fade_out(then: Callable) -> void:
	_fade_dir = 1
	_fade_t = 0
	_fade_then = then


func _fade_in() -> void:
	_fade_dir = -1
	_fade_t = 0
	_fade_then = Callable()


func _fade_step() -> void:
	_fade_t += 1
	_fade.color.a = float(_fade_t) / FADE if _fade_dir > 0 else 1.0 - float(_fade_t) / FADE
	if _fade_t >= FADE:
		var then := _fade_then
		_fade_dir = 0
		if then.is_valid():
			then.call()


func _exit_tree() -> void:
	engine.dispose()


func result() -> Dictionary:
	var r := _result_core()
	if options.has("scenario_index"):
		r["scenario"] = int(options["scenario_index"])
	if engine.challenge >= 0:
		r["challenge"] = engine.challenge_result()
	return r


func _result_core() -> Dictionary:
	return {"home": engine.teams[0].team_id, "away": engine.teams[1].team_id,
		"home_score": engine.teams[0].score, "away_score": engine.teams[1].score,
		"penalties": engine.pk_scores if engine.shootout else [],
		"comp": bool(options.get("comp", false)),
		"scorers": engine.scorers, "home_stats": engine.teams[0].stats, "away_stats": engine.teams[1].stats}


# ---------------------------------------------------------------------------
# Drawing the engine's state.

const LOOPING := [0, 1, 2, 6, 7, 9, 27, 30, 31, 32, 33, 34, 38, 50, 53]
const KEEPER_LOOPING := [0, 2, 5, 6, 7, 8, 9]


## The keeper's action in his own set (tbl_keeper_anims) for the engine's
## action: the keeper routines' numbers are the ones the engine uses for
## him (run 6, walk 7, knee trap 12, kick from the hands 14, throw 17 / 18,
## jump 21, full-length dive 22, side dives 23 / 24, get up 25); the
## player-only ones (headers, celebrations) show him standing.
static func keeper_action(a: int) -> int:
	if a in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 21, 22, 23, 24, 25, 26]:
		return a
	return 0


func _sync() -> void:
	var e := engine
	var dots: Array = []
	var cursors: Array = []
	for t in e.teams:
		for p in t.players:
			var s: Sprite2D = _sprites[p]
			s.visible = p.state != ISSFootballer.S.SENT_OFF
			if not s.visible:
				continue
			if not p.is_keeper() and (s.look_number != p.number or s.look_hair != p.hair):
				# A substitute came on in his place.
				s.set_look(t.team_id, t.second_kit, p.number, p.hair)
			_pose(s, p, p.action, p.anim_frame, p.facing)
			s.position = ISSProjection.to_map(p.pos, p.z).round()
			s.z_index = int(p.pos.y)
			var mine := false
			for sl in e.slots:
				if sl.player == p:
					mine = true
			dots.append([p.pos, ("controlled_" if mine else "") + ("home" if t.side == 0 else "away")])
			if mine:
				var colour := Color(1, 1, 0.3) if t.side == 0 else Color(0.4, 1, 1)
				cursors.append([s.position + Vector2(0, -42), colour])
	var b := e.ball
	_ball.position = ISSProjection.to_map(b.pos).round()
	_ball.height = b.z
	_ball.facing = roundi(b.heading) & 63
	_ball.spin = b.spin
	_ball.z_index = int(b.pos.y) + 1
	_ball.visible = true
	dots.append([b.pos, "ball"])
	# Landing marker for balls in the air (landing_marker_start).
	if b.is_loose() and b.z > 20.0 and b.live:
		_marker.visible = true
		_marker.position = ISSProjection.to_map(b.landing()[0]).round()
	else:
		_marker.visible = false
	_referee.position = ISSProjection.to_map(e.referee_pos).round()
	_referee.z_index = int(e.referee_pos.y)
	_referee.facing = int(ISSFootballer.heading_to(e.referee_pos, b.pos)) & 63
	_referee.play(2 if (e.referee_pos - b.pos).length() > 90.0 else 1)
	_linesman.position = ISSProjection.to_map(e.linesman_pos).round()
	_linesman.z_index = int(e.linesman_pos.y)
	_linesman.facing = 16 if b.pos.x > e.linesman_pos.x else 48
	_linesman.play(6 if absf(b.pos.x - e.linesman_pos.x) > 8.0 else 5)
	_cursor.points = cursors
	_cursor.queue_redraw()
	_props.sync()
	_hud.home_score = e.teams[0].score
	_hud.away_score = e.teams[1].score
	_hud.clock_seconds = e.clock_seconds()
	_hud.second_half = e.half & 1 == 1
	_hud.menu_request = [e.menu_request[0] != 0, e.menu_request[1] != 0]
	_hud.home_strategy = e.teams[0].strategy
	_hud.away_strategy = e.teams[1].strategy
	_hud.set_radar(dots)
	var pk := "PK %d-%d" % [e.pk_scores[0], e.pk_scores[1]] if e.shootout else ""
	if pk != _pk_text.pk:
		_pk_text.pk = pk
		_pk_text.queue_redraw()
	_update_camera()


## The sprite's pose for an action, frame and facing (the keepers have their
## own frame set).
func _pose(s: Sprite2D, p: ISSFootballer, action: int, frame: int, facing: int) -> void:
	if p.is_keeper():
		var ka := keeper_action(action)
		s.set_pose(ka, frame, facing, ka in KEEPER_LOOPING)
	else:
		s.set_pose(action, frame, facing, action in LOOPING)


## camera_update: follow the ball (or whoever has it) with a lead that eases
## 1/32 per frame toward 32 px ahead in the direction the focus's team attacks.
func _update_camera() -> void:
	var e := engine
	var focus := e.ball.pos
	var team := e.ball.team if e.ball.team >= 0 else 0
	var want := Vector2(32.0 * e.attack_dir(team), 0.0)
	_lead += (want - _lead) / 32.0
	var target := focus + _lead
	var r := e.rect
	target.x = clampf(target.x, r.position.x - 32.0, r.end.x + 32.0)
	_cam += (target - _cam) / 4.0
	_cam_z += (e.ball.z * 0.25 - _cam_z) / 8.0
	_camera.position = ISSProjection.to_map(_cam, _cam_z).round()
