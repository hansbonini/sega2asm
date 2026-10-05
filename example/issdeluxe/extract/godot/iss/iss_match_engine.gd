class_name ISSMatchEngine
extends RefCounted
## The match, without any drawing: both teams, the ball, the referee's rules
## (match_rules_update) and the restart scripts run by the g_director object
## (tbl_restart_setup). step() is one 60 Hz frame of state_match_frame:
## controllers -> AI scheduling and team analysis -> every player's update ->
## the ball -> the referee. The view (ISSMatch) draws the state and turns the
## signals into sound, commentary and banners, so the same engine also runs
## headless (iss_selftest.gd plays whole matches with it).

signal sound(id: int)
signal speech(id: int)
signal banner(message: String)
signal banner_off
signal goal_scored(side: int, scorer: ISSFootballer, own_goal: bool)
signal finished
## A song to play (the challenge's end: 16 cleared, 17 missed).
signal music(id: int)

## g_restart_type; OFFSIDE is the offside branch of restart 5.
enum R { NONE = -1, THROW_IN, GOAL_KICK, CORNER, KICKOFF, MATCH_START, FREE_KICK, PENALTY,
	PENALTY_SPOT, OWN_GOAL, HALF_TIME, TIME_UP, GOAL, OFFSIDE = 20 }

var ball := ISSBall.new()
var teams: Array[ISSTeam] = []
var rect := Rect2()
var mid := Vector2.ZERO
var stadium := 0
var weather := 1
var options := {}
var referee_kit := 1

## Team defending the left goal (g_left_goal_team); ends swap at half time.
var left_goal_team := 0
var kickoff_side := 0
var frame := 0
var half := 0
var half_frames := 0
## Frames left in the half (g_match_clock).
var clock := 0
var over := false
var scorers: Array = []
var said_rush := false

var restart_type := R.NONE
var restart_side := 0
var restart_pos := Vector2.ZERO
var restart_phase := 0
var restart_timer := 0
var restart_taker: ISSFootballer = null
var restart_after := R.NONE
## A penalty in a match (restart 7, back from the shoot-out's view): the
## kick as the view decided it ({"order0", "aim", "power", "dive_dir",
## "dive_input"}), its taker, the frames until the keeper's dive, and the
## keeper held still until then.
var pk_spot := {}
var pk_spot_taker: ISSFootballer = null
var pk_spot_wait := 0
var scripted_keeper: ISSFootballer = null
var ball_entered := true
var offside_side := -1

## Knockout match ($1274): a draw goes to extra time and penalties.
var knockout := false
## g_game_time: 1-3, one less in extra time.
var game_time := 2
var shootout := false
var pk_scores := [0, 0]
var pk_taken := [0, 0]
var pk_side := 0
## 0 waiting for the kick, 1 ball on its way, 2 showing the outcome.
var pk_phase := 0
var pk_timer := 0
var pk_next := [10, 10]
var shootout_over := false
var last_pads: Array = []

## Started from the front end's RAM (ISSMatchSetup.from_ram): one half at a
## time as state_match plays it, ending where the cartridge leaves the match
## for screen $39 (end_reason "half", "time_up", "golden_goal", "result")
## or for screen 6 ("menu": a side asked for the match menu, $182A /
## $18B2, and the ball went dead).
var half_only := false
## The attract demo (mode $B): the match ends after a minute of play, or
## at Start.
var demo := false
var end_reason := ""
## end_reason "presentation": the goal's picture to show ({"side", "kind"}).
var presentation := {}
## $182A / $18B2: a side asked for the match menu (X, or the pause menu's
## last item); taken at the next restart.
var menu_request := [0, 0]

## A controller playing in the match (g_control_slots, $1A bytes each): its
## side, the player it controls and its Change control settings.
class Slot:
	extends RefCounted
	var side := 0
	var player: ISSFootballer = null
	## TYPE A-D (slot+$A): who Y hands control to; AREA A (only players on
	## the screen) or B (slot+$C); CURSOR CHANGE auto (0) or manual (slot+$E).
	var type := 0
	var area := 0
	var manual := 0
	## A 6-button pad (slot+8): its pause menu has two items, a 3-button
	## pad's four (ISSMatch).
	var six := true

var slots: Array = []
## The part of the stadium map on the screen (ISSMatch sets it each frame;
## empty = all of it, as headless).
var view := Rect2()

var referee_pos := Vector2.ZERO
var linesman_pos := Vector2.ZERO
var event_counts := {}

## Training (mode 0): the drill (g_training_drill) 0 free, 1 defence, 2 free kick,
## 3 keeper, or -1 outside training; drill_wait counts down the frames
## (match_rules_update_1) before the drill is set up again.
var drill := -1
var drill_wait := -1
## Where players go for the restart being set up when its script puts them
## somewhere else than restart_place: the free kick wall and its runners.
var set_places := {}
var _wall: Array[ISSFootballer] = []

## Challenge (mode 1): the event (g_training_drill) 0 dribble, 1 pass,
## 2 shoot, 3 defence, 4 corner kick, 5 free kick, and the level
## (g_challenge_level) 0-3; -1 outside the challenges.
var challenge := -1
var challenge_level := 0
## $13C4-$13C7: the time left as four digits from 30.00, the third wrapping
## at 5 (60 frames a second); $13C8-$13CB: the bonus, plain decimal digits.
var ch_time: Array = [3, 0, 0, 0]
var ch_bonus: Array = [3, 0, 0, 0]
## $13CC: flags taken or team-mates who touched the ball; ch_done when it is
## $B (the task is done); ch_bonus_on when $13CE is $B (the bonus counts).
var ch_count := 0
var ch_done := false
var ch_bonus_on := false
var ch_touched := {}
## The dribble's flags still standing, and the goal target panel's y (shoot,
## corner kick, free kick; NAN without one).
var ch_flags: Array[Vector2] = []
var ch_target_y := NAN
## Frames left of the end banner (-1 while the attempt runs).
var ch_end := -1


## options: stadium 0-7, weather 0 snow / 1 fine / 2 rain, time 1-3 (minutes
## per half = 2 * time + 1), level 0-4, fouls, cards, offside (bools),
## referee 0-3 (3 = random), pads [home, away] (0 = CPU), half_seconds
## (optional override of the half length).
func setup(home: int, away: int, opts: Dictionary) -> void:
	ISSMatchData.ensure_loaded()
	options = opts
	stadium = int(opts.get("stadium", 0))
	weather = int(opts.get("weather", 1))
	ball.weather = weather
	referee_kit = int(opts.get("referee", 1))
	if referee_kit == 3:
		referee_kit = randi() % 3
	rect = ISSMatchData.pitch_rect(stadium)
	mid = rect.get_center()
	var level := int(opts.get("level", 2))
	var pads: Array = opts.get("pads", [1, 0])
	# The controllers: "controllers" [{side, type, area, manual}], or one per
	# pad counted in "pads" [home, away].
	var ctl: Array = opts.get("controllers", [])
	if ctl.is_empty():
		for side in 2:
			for k in int(pads[side]):
				ctl.append({"side": side})
	var per_side := [0, 0]
	for c: Dictionary in ctl:
		var sl := Slot.new()
		sl.side = int(c["side"])
		sl.type = int(c.get("type", 0))
		sl.area = int(c.get("area", 0))
		sl.manual = int(c.get("manual", 0))
		sl.six = bool(c.get("six", true))
		slots.append(sl)
		per_side[sl.side] += 1
	pads = per_side
	var clash_home := int(ISSMatchData.teams[home]["kit_clash"])
	var clash_away := int(ISSMatchData.teams[away]["kit_clash"])
	for s in 2:
		var t := ISSTeam.new()
		var human: bool = int(pads[s]) > 0
		# Handicap: condition, players on the pitch, goalkeeper skill.
		t.condition = int(opts.get("conditions", [5, 5])[s])
		t.on_pitch = int(opts.get("players", [11, 11])[s])
		var formations: Array = opts.get("formations", [-1, -1])
		# Training puts the practice team in its second kit (g_kit_away = 1).
		var kit2 := s == 1 and (home == away or clash_home == clash_away or opts.has("training"))
		if opts.has("kits"):
			# The front end's choice (g_kit_home / g_kit_away: 1 = second kit).
			kit2 = int(opts["kits"][s]) == 1
		t.setup(self, s, home if s == 0 else away, 2 if human else level, kit2, int(formations[s]))
		t.pads = int(pads[s])
		t.keeper_mode = int(opts.get("keepers", [0, 0])[s])
		if opts.has("keeper_skills"):
			t.keeper_skill = int(opts["keeper_skills"][s])
		# screen_handicap: with fewer than 11, players 1, 2, ... stay off
		# (from RAM: those with +$55 set, the handicap's and the sent off).
		var squad_s: Array = opts.get("squads", [[], []])[s]
		for i in range(1, 11):
			var off := i <= 11 - clampi(t.on_pitch, 7, 11)
			if not squad_s.is_empty():
				off = bool((squad_s[i] as Dictionary).get("off", false))
			if off:
				t.players[i].set_state(ISSFootballer.S.SENT_OFF, ISSFootballer.A_STAND)
				t.players[i].pos = Vector2(rect.get_center().x, rect.position.y - 300.0)
		if opts.has("strategies_by_side"):
			# tm_strategy_slots as screen_strategy left them (-1 = none).
			t.strategy_slots = (opts["strategies_by_side"][s] as Array).duplicate()
		elif human:
			var slots: Array = opts.get("strategies", [0, 2, 4, 7])
			t.strategy_slots = slots.duplicate()
		t.strategy_label = int(opts.get("strategy_labels", [2, 2])[s])
		teams.append(t)
	knockout = bool(opts.get("knockout", false))
	demo = bool(opts.get("demo", false))
	game_time = int(opts.get("time", 2))
	half_frames = _half_length()
	clock = half_frames
	left_goal_team = 0
	kickoff_side = randi() % 2
	for t in teams:
		t.reset_lines()
	_place_for_kickoff(kickoff_side)
	referee_pos = mid + Vector2(-48, 64)
	linesman_pos = Vector2(mid.x, rect.position.y - 20)
	if opts.has("training"):
		# No referee in training: no fouls, cards or offside.
		for k in ["fouls", "cards", "offside"]:
			options[k] = false
		start_drill(int(opts["training"]))
	elif opts.has("challenge"):
		for k in ["fouls", "cards", "offside"]:
			options[k] = false
		var c: Dictionary = opts["challenge"]
		start_challenge(int(c["event"]), int(c["level"]))
	elif bool(opts.get("pk_only", false)):
		_start_shootout() # PK mode (mode_start_pk)
	elif opts.has("scenario"):
		_start_scenario(opts["scenario"])
	elif opts.has("half"):
		_start_from_ram(opts)
	else:
		start_restart(R.MATCH_START, kickoff_side, mid)


## state_match from the RAM the front end keeps between the halves and the
## match menu: the half (g_half), the ends (g_left_goal_team), the side
## kicking off the half ($1634), the clock (g_match_clock), the scores,
## statistics and scorers so far, and the restart to take (g_restart_type:
## 4 the half's kick-off, 3 a kick-off after a goal, any other the restart
## that was waiting when the match menu was asked for).
func _start_from_ram(opts: Dictionary) -> void:
	half_only = true
	half = int(opts["half"])
	left_goal_team = int(opts.get("left_goal_team", 0))
	kickoff_side = int(opts.get("kickoff_team", 0))
	clock = int(opts.get("clock", half_frames))
	var sc: Array = opts.get("scores", [0, 0])
	var st: Array = opts.get("stats", [])
	for s in 2:
		teams[s].score = int(sc[s])
		if s < st.size():
			for i in STAT_KEYS.size():
				teams[s].stats[STAT_KEYS[i]] = int(st[s][i])
	scorers = (opts.get("scorers", []) as Array).duplicate(true)
	for t in teams:
		t.reset_lines()
	var r: Dictionary = opts.get("restart", {"type": R.MATCH_START})
	var type := int(r.get("type", R.MATCH_START))
	match type:
		R.MATCH_START, -1:
			_place_for_kickoff(kickoff_side)
			start_restart(R.MATCH_START, kickoff_side, mid)
		R.KICKOFF, R.GOAL, R.OWN_GOAL:
			_start_kickoff(int(r.get("team", kickoff_side)))
		R.PENALTY_SPOT:
			_start_penalty_spot(int(r.get("team", 0)), opts.get("penalty", {}))
		_:
			# Back from the match menu: everyone at his place, the restart
			# that was waiting set up again.
			var pos := Vector2(int(r.get("x", mid.x)), int(r.get("y", mid.y)))
			for t in teams:
				for p in t.active():
					p.speed = 0.0
					p.pos = t.home_position(p) if not p.is_keeper() else goal_center(t.side) + Vector2(attack_dir(t.side) * 32.0, 0)
			ball.pos = pos
			start_restart(type, int(r.get("team", 0)), pos)
			restart_timer = 30


## The goal's presentation on the stadium's big screen (state_screen $1730
## = 1) as restart_own_goal_1 and restart_goal_1 choose it once the banner
## is over: after an own goal always (the side that conceded, picture 0);
## after a goal when the scorers' side has a human on it and now leads by
## one (picture 1), or when the last three goals were the same player's
## (picture 2, a hat-trick: g_scorers' side, team and record alike).
## {"side", "kind"}, or empty.
func goal_presentation() -> Dictionary:
	if restart_type == R.OWN_GOAL:
		return {"side": restart_side, "kind": 0}
	var side := 1 - restart_side
	var pads: Array = options.get("pads", [1, 0])
	if int(pads[side]) == 0:
		return {}
	var kind := -1
	if teams[side].score - teams[1 - side].score == 1:
		kind = 1
	var n := teams[0].score + teams[1].score
	if n >= 3 and scorers.size() >= n:
		var last: Dictionary = scorers[n - 1]
		var same := true
		for k in [n - 2, n - 3]:
			var g: Dictionary = scorers[k]
			for f in ["side", "team", "record"]:
				if int(g.get(f, -1)) != int(last.get(f, -2)):
					same = false
		if same:
			kind = 2
	return {} if kind < 0 else {"side": side, "kind": kind}


## A penalty back from the shoot-out's view (restart_setup_penalty_spot,
## restart_resume_penalty_spot): the ball 256 px in front of the goal, the
## defending side's players 160-640 px out from their goal line
## (tbl_penalty_spot_defenders) and their keeper 16 px in front of it, the
## kicking side's players 10-5 400-450 px from the goal
## (tbl_penalty_spot_attackers), its kicker (the first in the order list,
## the one the order screen chose) 64 px behind the ball.
func _start_penalty_spot(side: int, pk: Dictionary) -> void:
	var d := attack_dir(side)
	var g := goal_center(1 - side)
	restart_type = R.PENALTY_SPOT
	restart_side = side
	restart_pos = g - Vector2(d * 256.0, 0)
	restart_phase = 4
	restart_timer = 0x80
	restart_taker = null
	set_places.clear()
	_wall.clear()
	event_counts[R.PENALTY_SPOT] = int(event_counts.get(R.PENALTY_SPOT, 0)) + 1
	ball.owner = null
	ball.stop()
	ball.pos = restart_pos
	ball.live = false
	pk_spot = pk
	var att := teams[side]
	var dfd := teams[1 - side]
	const DEFENDERS := [[10, -26], [10, 26], [25, -16], [25, -8], [28, 0], [25, 8], [25, 16], [32, -10], [36, 14],
		[40, 0], [10, 10]]
	const ATTACKERS := [[-25, -20], [-25, -12], [-25, -4], [-28, 4], [-25, 12], [-25, 20]]
	for i in 10:
		var e: Array = DEFENDERS[i]
		set_places[dfd.players[i + 1]] = Vector2(g.x - d * float(e[0]) * 16.0, mid.y + float(e[1]) * 16.0)
	for i in 6:
		var e: Array = ATTACKERS[i]
		set_places[att.players[10 - i]] = Vector2(g.x + d * float(e[0]) * 16.0, mid.y + float(e[1]) * 16.0)
	scripted_keeper = dfd.players[0]
	set_places[scripted_keeper] = g - Vector2(d * 16.0, 0)
	var taker := att.players[clampi(int(pk.get("order0", 10)), 1, 10)]
	if taker.state == ISSFootballer.S.SENT_OFF:
		for p in att.active():
			if not p.is_keeper():
				taker = p
	pk_spot_taker = taker
	set_places[taker] = restart_pos - Vector2(d * 64.0, 0)
	for t in teams:
		for p in t.active():
			if not p.busy():
				p.set_state(ISSFootballer.S.MOVE, ISSFootballer.A_STAND)
			p.speed = 0.0


## penalty_spot_taker: 128 frames behind the ball, then to it; within 16 px
## the ball is his and he kicks it toward the aim chosen in the view
## ($14F2: across the goal from the middle, to his right), low or high as
## chosen ($14F4).
func _penalty_spot_step() -> void:
	var taker := pk_spot_taker
	if taker == null or taker.state == ISSFootballer.S.SENT_OFF:
		restart_type = R.NONE
		restart_phase = 0
		ball.live = true
		return
	if restart_timer > 0:
		restart_timer -= 1
		if restart_timer == 0:
			set_places[taker] = ball.pos
		return
	if (taker.pos - ball.pos).length() > 16.0:
		set_places[taker] = ball.pos
		return
	var side := restart_side
	var d := attack_dir(side)
	ball.live = true
	ball_entered = true
	ball.owner = taker
	ball.team = side
	ball.last_touch = taker
	taker.speed = 0.0
	var target := Vector2(goal_center(1 - side).x, mid.y + float(int(pk_spot.get("aim", 0))) * d)
	var h := ISSFootballer.heading_to(ball.pos, target)
	taker.facing = int(h) & 63
	restart_taker = taker
	restart_phase = 1
	var power := int(pk_spot.get("power", 0))
	taker.start_kick(ISSFootballer.K.SHOT, h, null, 0 if power == 0 else (8 if power >= 0x10 else 7))


## penalty_spot_keeper_dive: the save chosen in the view: with a direction
## ($14F6, left or right of the taker) the jump (lofted) or the low dive
## (pass) up or down the goal line; lofted alone the one-arm reach; pass
## alone the step across (his own save here).
func _penalty_spot_dive() -> void:
	var k := scripted_keeper
	scripted_keeper = null
	if k == null or k.busy():
		return
	var h := 30 if int(pk_spot.get("dive_dir", 0x20)) > 0x20 else 2
	if k.team != left_goal_team:
		h = (h + 32) & 63
	var sd: Array = ISSMatchData.consts["keeper"]["side_dive"]
	match int(pk_spot.get("dive_input", 0x10)):
		0x2C:
			k.start_dive(h, float(sd[0]), float(sd[1]))
		0x1C:
			k.start_dive(h, float(sd[0]), float(sd[1]) * 0.5)
		0x20:
			k.start_dive(k.facing)


## The eight statistics words of g_stats_home / g_stats_away in order.
const STAT_KEYS := ["shots", "free_kicks", "corners", "penalties", "yellow", "red", "offsides", "goals"]


## Start during the attract demo (match_rules_update_3): the match leaves
## for the title (warm_start).
func demo_start() -> void:
	if demo and not over:
		_end("demo_title")


## The match leaves for the front end (half_only).
func _end(reason: String) -> void:
	end_reason = reason
	banner_off.emit()
	over = true
	finished.emit()


## scenario_setup ($05D4C2): the second half with the score and time of the
## scenario, the home side (the human's) defending the left goal, starting
## with the scenario's restart for the home side.
func _start_scenario(sc: Dictionary) -> void:
	teams[0].score = int(sc["home_score"])
	teams[1].score = int(sc["away_score"])
	half = 1
	left_goal_team = 0
	clock = int(sc["clock_seconds"]) * 60
	for t in teams:
		t.reset_lines()
	var pos := Vector2(int(sc["restart_x"]), int(sc["restart_y"]))
	var type := int(sc["restart"])
	for t in teams:
		for p in t.active():
			p.speed = 0.0
			p.pos = t.home_position(p) if not p.is_keeper() else goal_center(t.side) + Vector2(attack_dir(t.side) * 32.0, 0)
	ball.pos = pos
	start_restart(type, 0, pos)
	restart_timer = 30


## Frames in a half: 2 * g_game_time + 1 minutes (g_game_time is one less in
## extra time); "half_seconds" overrides it for tests.
func _half_length() -> int:
	if options.has("half_seconds"):
		return int(options["half_seconds"]) * (60 if half < 2 else 30)
	return (2 * game_time + 1) * 3600


## Break the engine / team / player references so that everything is freed.
func dispose() -> void:
	for t in teams:
		for p in t.players:
			p.eng = null
			p.kick_target = null
		t.players.clear()
		t.eng = null
		t.controlled = null
		t.nearest = null
		t.second = null
		t.front = null
		t.back = null
		t.cover = null
	teams.clear()
	ball.owner = null
	ball.kicker = null
	ball.last_touch = null
	restart_taker = null
	for sl: Slot in slots:
		sl.player = null
	slots.clear()
	set_places.clear()
	_wall.clear()


# ---------------------------------------------------------------------------
# Geometry.

## +1 when the side attacks toward +x (it defends the left goal).
func attack_dir(side: int) -> float:
	return 1.0 if side == left_goal_team else -1.0


func goal_center(side: int) -> Vector2:
	return Vector2(rect.position.x if side == left_goal_team else rect.end.x, mid.y)


func goal_heading(p: ISSFootballer) -> float:
	var g := goal_center(1 - p.team) + Vector2(0, (randf() * 2.0 - 1.0) * 60.0)
	return ISSFootballer.heading_to(p.pos, g)


## Where the ball will be played from next: its landing point while in the
## air (obj_target_x of the ball), else where it is.
func ball_target() -> Vector2:
	if ball.owner == null and ball.z > 8.0:
		return ball.landing()[0]
	return ball.pos


func in_own_box(p: ISSFootballer) -> bool:
	var g := goal_center(p.team)
	return absf(p.pos.x - g.x) < 256.0 and absf(p.pos.y - g.y) < 220.0


func emit_sound(id: int) -> void:
	sound.emit(id)


func say(id: int) -> void:
	speech.emit(id)


func stats_shot_on_target(_side: int) -> void:
	pass


func all_players() -> Array[ISSFootballer]:
	var out: Array[ISSFootballer] = []
	for t in teams:
		out.append_array(t.active())
	return out


# ---------------------------------------------------------------------------
# One frame. pads[slot] = {"dir": -1 or 0-63, "press": bits, "held": bits},
# one per controller in slots order (the home side's first).

func step(pads: Array = []) -> void:
	if over:
		return
	frame += 1
	last_pads = pads
	var slot := frame & 15
	# Formation lines: one role per frame, home on slots 0-3, away on 4-7.
	var order: Array = ISSMatchData.consts["team_lines"]["order"]
	teams[(slot >> 2) & 1].update_line(int(order[slot & 3]))
	for t in teams:
		t.analyse()
		if restart_type == R.NONE:
			t.apply_strategy()
	_control_all(pads)
	for t in teams:
		for p in t.active():
			if p.human:
				continue
			p.press = 0
			if slot == p.index:
				t.think(p)
			if p.state == ISSFootballer.S.KEEPER_HOLD:
				if not shootout:
					t.keeper_distribute(p)
			elif p.state == ISSFootballer.S.SET_PIECE:
				_cpu_set_piece(p)
			else:
				t.steer(p)
		if t.has_ball():
			t.stats["possession"] += 1
	for p in all_players():
		p.step()
	ball.step()
	_contacts()
	_bounds()
	if shootout:
		_shootout_step()
	elif restart_type == R.NONE and ball.live:
		_check_out()
	if drill >= 0:
		_drill_step()
	elif challenge >= 0:
		_challenge_step()
	elif not shootout:
		_clock()
	if not shootout:
		_director()
	if pk_spot_wait > 0:
		pk_spot_wait -= 1
		if pk_spot_wait == 0:
			_penalty_spot_dive()
	_officials()


## Human control (match_players_update): every controller drives its player.
func _control_all(pads: Array) -> void:
	for t in teams:
		for p in t.players:
			p.human = false
	for sl: Slot in slots:
		var c := sl.player
		# ai_func_00F91A_8: in its AI slot a goalkeeper on AUTO is handed back
		# to the computer unless he has the ball.
		if c != null and c.is_keeper() and teams[sl.side].keeper_mode == 0 and ball.owner != c \
				and (frame & 15) == c.index:
			sl.player = null
	for i in slots.size():
		var pad: Dictionary = pads[i] if i < pads.size() and pads[i] != null else {}
		_control_slot(slots[i], pad)
	for t in teams:
		t.controlled = null
		for sl: Slot in slots:
			if sl.side == t.side and t.controlled == null:
				t.controlled = sl.player


func _control_slot(sl: Slot, pad: Dictionary) -> void:
	var t := teams[sl.side]
	var pressed := int(pad.get("press", 0))
	var held := int(pad.get("held", 0))
	var dir := int(pad.get("dir", -1))
	var c := sl.player
	if c != null and c.state == ISSFootballer.S.SENT_OFF:
		c = null
	var owner := ball.owner
	if c == null:
		# A controller without a player takes the first free one, from
		# player 10 down to the goalkeeper.
		c = _first_free(t, sl)
	elif owner == c:
		pass
	elif owner != null and owner.team == t.side and _free(owner, sl):
		c = owner
	elif restart_taker != null and restart_taker.team == t.side and restart_phase == 1 and _free(restart_taker, sl):
		c = restart_taker
	else:
		c = _switch(sl, c, pressed, held, dir)
	sl.player = c
	if c == null:
		return
	# Strategies: the strategy button (Mode) switches the current one off;
	# held with dash, pass, lofted or shoot it picks the strategy assigned
	# to that button ($184C). The kick buttons do nothing else meanwhile.
	if pressed & ISSFootballer.STRATEGY:
		t.strategy = -1
		t.strategy_run = -1
	if held & ISSFootballer.STRATEGY:
		var slot_of := {ISSFootballer.DASH: 0, ISSFootballer.PASS: 1, ISSFootballer.LOFT: 2, ISSFootballer.SHOOT: 3}
		for bit: int in slot_of:
			if pressed & bit:
				t.strategy = int(t.strategy_slots[slot_of[bit]])
				t.strategy_run = -1
		pressed &= ~(ISSFootballer.DASH | ISSFootballer.PASS | ISSFootballer.LOFT | ISSFootballer.SHOOT)
		held &= ~(ISSFootballer.DASH | ISSFootballer.PASS | ISSFootballer.LOFT | ISSFootballer.SHOOT)
	# During a restart only the taker is the human's; the rest walk into place.
	if restart_type != R.NONE and c != restart_taker:
		return
	c.human = true
	c.input_dir = dir
	c.press |= pressed
	c.held = held


## Not controlled by another controller, on the pitch.
func _free(p: ISSFootballer, sl: Slot) -> bool:
	if p == null or p.state == ISSFootballer.S.SENT_OFF:
		return false
	for o: Slot in slots:
		if o != sl and o.player == p:
			return false
	return true


func _first_free(t: ISSTeam, sl: Slot) -> ISSFootballer:
	for i in range(10, -1, -1):
		if _free(t.players[i], sl):
			return t.players[i]
	return null


## The player on the screen (AREA A); everybody without a view.
func is_visible(p: ISSFootballer) -> bool:
	return view.size == Vector2.ZERO or view.has_point(ISSProjection.to_map(p.pos, p.z))


## Y and the automatic changes of control (match_players_update).
func _switch(sl: Slot, c: ISSFootballer, pressed: int, held: int, dir: int) -> ISSFootballer:
	var t := teams[sl.side]
	if pressed & ISSFootballer.SWITCH:
		if held & ISSFootballer.STRATEGY:
			# Mode + Y: the goalkeeper (keeper SEMI-AUTO or MANUAL).
			if t.keeper_mode != 0 and _free(t.players[0], sl):
				return t.players[0]
			return c
		var n: ISSFootballer = null
		if restart_type != R.NONE:
			n = _next_free(sl, c, false)
		else:
			match sl.type:
				1:
					n = _closest(sl, true)
				2:
					n = _toward(sl, ball.pos, dir, true) if dir >= 0 else _closest(sl, false)
				3:
					n = _toward(sl, c.pos, dir, false) if dir >= 0 else _closest(sl, false)
				_:
					n = _closest(sl, false)
		return n if n != null else c
	if held & ISSFootballer.SWITCH:
		return c
	# A high ball: the team's player nearest to where it comes down.
	if ball.z > 80.0:
		return t.nearest if t.nearest != null and _free(t.nearest, sl) else c
	if sl.area == 0 and not is_visible(c):
		var v := _next_free(sl, c, true)
		if v != null:
			return v
	if sl.manual == 0 and ball.team >= 0 and ball.team != t.side and restart_type == R.NONE:
		var cand := t.nearest
		if cand != null and not _free(cand, sl):
			cand = t.second
		if cand != null and _free(cand, sl) and _auto_change(t, c, cand):
			return cand
	return c


## AUTO CHANGE: to the team's player nearest the ball when the controlled
## one is caught up the pitch, or when the ball comes down within 128 px of
## the other and not of him; never to a player 32 px or more beyond the ball.
func _auto_change(t: ISSTeam, c: ISSFootballer, cand: ISSFootballer) -> bool:
	var d := attack_dir(t.side)
	var land := ball_target()
	var beyond := ball.owner != null and (c.pos.x - ball.pos.x) * d >= 32.0
	if not beyond:
		if (c.pos - land).length() <= 128.0 or (cand.pos - land).length() > 128.0:
			return false
	return (cand.pos.x - ball.pos.x) * d < 32.0 and is_visible(cand)


## TYPE A: the free player nearest the ball; TYPE B (goal_side): only those
## between the ball and their own goal while it is held.
func _closest(sl: Slot, goal_side: bool) -> ISSFootballer:
	var t := teams[sl.side]
	var d := attack_dir(t.side)
	var best: ISSFootballer = null
	var best_d := INF
	for i in range(1, 11):
		var p := t.players[i]
		if not _free(p, sl) or p == sl.player:
			continue
		if goal_side and ball.owner != null and (p.pos.x - ball.pos.x) * d >= 0.0:
			continue
		var dist := (p.pos - ball.pos).length()
		if dist < best_d:
			best_d = dist
			best = p
	return best


## TYPE C (from the ball, nearest it) and D (from the controlled player,
## nearest him): the free player within 8 of the pad's direction.
func _toward(sl: Slot, from: Vector2, dir: int, ball_dist: bool) -> ISSFootballer:
	var t := teams[sl.side]
	var best: ISSFootballer = null
	var best_d := INF
	for i in range(1, 11):
		var p := t.players[i]
		if not _free(p, sl) or p == sl.player:
			continue
		var a := ISSFootballer.angle_diff(ISSFootballer.heading_to(from, p.pos), dir)
		if absf(a) >= 8.0:
			continue
		var dist := (p.pos - ball.pos).length() if ball_dist else absf(p.pos.x - from.x) + absf(p.pos.y - from.y)
		if dist < best_d:
			best_d = dist
			best = p
	return best


## The next free player after c in squad order (players 1-10), on the
## screen if asked.
func _next_free(sl: Slot, c: ISSFootballer, visible: bool) -> ISSFootballer:
	var t := teams[sl.side]
	var at := c.index if c != null else 0
	for k in range(1, 11):
		var p := t.players[(at - 1 + k) % 10 + 1]
		if p != c and _free(p, sl) and (not visible or is_visible(p)):
			return p
	return null


## The pad of a side's first controller ({} when it has none).
func side_pad(side: int) -> Dictionary:
	for i in slots.size():
		if slots[i].side == side:
			return last_pads[i] if i < last_pads.size() and last_pads[i] != null else {}
	return {}


# ---------------------------------------------------------------------------
# Ball contacts.

func _contacts() -> void:
	if not ball.live:
		return
	if ball.owner != null:
		_steals()
		return
	var best: ISSFootballer = null
	var best_d := INF
	for p in all_players():
		if not p.can_touch_ball():
			continue
		if p.state == ISSFootballer.S.SLIDE:
			continue # slide_contact handles it
		var dz := ball.z - p.z
		var reach := 10.0
		var top := 36.0
		if p.is_keeper() and in_own_box(p):
			reach = 14.0 + float(teams[p.team].keeper_skill)
			top = 56.0
		if dz < -4.0 or dz >= top:
			continue
		var d := (ball.pos - p.pos).length()
		if d < reach and d < best_d:
			best_d = d
			best = p
	if best != null:
		_touch(best)


func _touch(p: ISSFootballer) -> void:
	var b := ball
	if offside_side >= 0:
		if p.team == offside_side and p.offside and bool(options.get("offside", true)):
			_clear_offside()
			teams[p.team].stats["offsides"] += 1
			start_restart(R.OFFSIDE, 1 - p.team, p.pos)
			return
		_clear_offside()
	var keeper_catch := p.is_keeper() and in_own_box(p)
	var c: Dictionary = ISSMatchData.consts["ball"]
	if b.speed + b.vz > float(c["deflect_speed"]) and not keeper_catch:
		# ball_in_reach: too fast to control, it comes off the player.
		b.heading = fposmod(b.heading + 32.0 + float(randi() % 16 - 8), 64.0)
		b.speed /= 2.0
		b.vz -= b.vz / 4.0
		b.team = p.team
		b.last_touch = p
		b.kicker = p
		b.kick_cooldown = 8
		emit_sound(0x5A)
		return
	b.owner = p
	b.team = p.team
	b.last_touch = p
	b.kicker = null
	b.stop()
	said_rush = false
	p.ai_turns = 0
	p.protect = 24
	if keeper_catch:
		p.start_hold(true)
		emit_sound(0x5A)
	elif b.z > 12.0 or b.speed > 3.0:
		p.set_state(ISSFootballer.S.TRAP, ISSFootballer.A_TRAP, 10)


## The ROM's contest tables (match.json "contests"): the signed byte
## `index` past table `t` ("slide", "charge", or "keeper" with the keeper's
## skill), read as the 68000 does: past a table's end comes what follows.
static func contest(t: String, index: int, skill := -1) -> int:
	var c: Dictionary = ISSMatchData.consts["contests"]
	var addr := int(c["keeper"][skill]) if skill >= 0 else int(c[t])
	var bytes: Array = c["bytes"]
	var b := int(bytes[clampi(addr - int(c["base"]) + index, 0, bytes.size() - 1)])
	return b - 256 if b >= 128 else b


## The card for knocking the carrier over (the slide and charge contests):
## one when the tackle came from behind, the carrier facing within 9 of
## the tackler (g_foul_card 0), none otherwise (-1).
static func _card_for(tackler: ISSFootballer, victim: ISSFootballer) -> int:
	var d := (int(victim.facing) - int(tackler.facing)) & 63
	return 0 if d < 10 or d > 54 else -1


## Standing challenges: an opponent at the ball runs into the carrier
## (player_start_chip_0070AE_1, the crouched run's charge): his
## intelligence against the carrier's, + 2, x 4 and a random 0-3 into the
## charge table: -1 he falls backwards off the carrier, 0 the ball comes
## loose, 1 the carrier is knocked over and fouled.
func _steals() -> void:
	var o := ball.owner
	if o.holding_in_hands() or o.protect > 0 or restart_type != R.NONE:
		return
	if frame % 6 != 0:
		return
	for p in teams[1 - o.team].active():
		if p.busy() or p.is_keeper() and not in_own_box(p):
			continue
		if (p.pos - ball.pos).length() > 9.0:
			continue
		var idx := maxi(p.a("intelligence") - o.a("intelligence") + 2, 0) * 4 + (randi() & 3)
		var r := contest("charge", idx)
		if r < 0:
			p.knock_over(p.facing)
		elif r == 0:
			ball.owner = null
			ball.launch(p, p.facing + float(randi() % 9 - 4), 1.5 + p.speed * 0.4, 0.3)
			ball.kick_cooldown = 4
			o.stumble()
			emit_sound(0x58)
		else:
			o.knock_over(p.facing)
			_foul(p, o, _card_for(p, o))
		return


## A sliding tackle meeting the ball or a player (player_slide).
func slide_contact(s: ISSFootballer) -> void:
	var foot := s.pos + ISSProjection.heading_vector(s.facing) * 6.0
	var b := ball
	var hits_ball := b.live and b.z < 16.0 and (b.pos - foot).length() < 12.0
	if b.owner != null and (b.owner.team == s.team or b.owner.holding_in_hands()):
		hits_ball = false
	if hits_ball:
		var victim := b.owner
		s.timer = maxi(s.timer, 27)
		if victim != null:
			# player_start_sit_after_a_slide_008F16_1: the carrier's (position
			# bonus + energy) x 2 + intelligence + dribble, halved, x 4 and a
			# random 0-3 into the slide table: -1 he rides the tackle (a leap)
			# and keeps the ball, 0 he loses it, 1 he is knocked over and
			# fouled (a card from behind).
			var score := (ISSMatchData.position_bonus(victim.position) + victim.energy) * 2 \
				+ victim.a("intelligence") + victim.a("dribble")
			var r := contest("slide", (score / 2) * 4 + (randi() & 3))
			if r < 0:
				victim.set_state(ISSFootballer.S.TRAP, ISSFootballer.A_LEAP, 12)
				return
			if r > 0:
				victim.knock_over(s.facing)
				_foul(s, victim, _card_for(s, victim))
				return
			victim.stumble()
			say(0x0F)
		b.owner = null
		b.launch(s, s.facing + float(randi() % 9 - 4), 1.5 + s.speed * 0.5, 0.5)
		_clear_offside()
		emit_sound(0x58)
		return
	for o in teams[1 - s.team].active():
		if o.state not in [ISSFootballer.S.MOVE, ISSFootballer.S.KICK, ISSFootballer.S.TRAP]:
			continue
		if (o.pos - foot).length() > 10.0:
			continue
		var from_behind := absf(ISSFootballer.angle_diff(s.facing, o.facing)) < 16.0
		var had_ball := b.owner == o or (b.pos - o.pos).length() < 40.0
		o.knock_over(s.facing)
		s.timer = maxi(s.timer, 27)
		if had_ball or from_behind:
			_foul(s, o, _card_for(s, o))
		return


## A foul by `fouler` on `victim`; card as g_foul_card: -1 none, 0 a card
## (yellow, or red once booked), 1 a card and, half the time, a point of
## the victim's energy (a keeper's never).
func _foul(fouler: ISSFootballer, victim: ISSFootballer, card: int) -> void:
	if not bool(options.get("fouls", true)) or restart_type != R.NONE or not ball.live:
		return
	var strict: Array = ISSMatchData.consts["referee_strictness"][referee_kit]
	if int(strict[randi() & 3]) == 0:
		return # the referee did not see it
	teams[fouler.team].stats["fouls"] += 1
	emit_sound(0x48)
	var own_goal_x := goal_center(fouler.team).x
	var penalty := absf(victim.pos.x - own_goal_x) < float(ISSMatchData.consts["penalty_distance"])
	if card == 1 and not victim.is_keeper() and randi() & 1 == 0 and victim.energy > 0:
		victim.energy -= 1
	# No cards for a side already down to seven (tm_players 0).
	if card >= 0 and bool(options.get("cards", true)) and teams[fouler.team].active().size() > 7:
		# g_player_status: booked in this match (bit 7) makes it red; with
		# a red card or a third yellow over the competition (2 so far) no
		# card at all once eight of the squad are out ($83 / $84).
		var red := fouler.booked
		if (red or fouler.status & 7 == 2) and _squad_out(fouler.team) >= 8:
			pass
		elif red:
			fouler.status = 0x84
			_send_off(fouler)
			banner.emit("red_card")
			teams[fouler.team].stats["red"] += 1
			say(0x29)
		else:
			fouler.status = ((fouler.status + 1) | 0x80) & 0xFF
			fouler.booked = true
			banner.emit("yellow_card")
			teams[fouler.team].stats["yellow"] += 1
			say(0x29)
	if ball.owner != null:
		ball.owner = null
	if penalty:
		teams[victim.team].stats["penalties"] += 1
		start_restart(R.PENALTY, victim.team, goal_center(fouler.team) + Vector2(attack_dir(victim.team) * -256.0, 0))
	else:
		teams[victim.team].stats["free_kicks"] += 1
		start_restart(R.FREE_KICK, victim.team, victim.pos)


## Players of the side's squad sent off or out on yellow cards (status
## above $82).
func _squad_out(side: int) -> int:
	var n := 0
	for p in teams[side].players:
		if p.status > 0x82:
			n += 1
	for rec: Dictionary in teams[side].bench:
		if int(rec.get("status", 0)) > 0x82:
			n += 1
	return n


func _send_off(p: ISSFootballer) -> void:
	if ball.owner == p:
		ball.owner = null
	p.set_state(ISSFootballer.S.SENT_OFF, ISSFootballer.A_STAND)
	p.pos = Vector2(mid.x, rect.position.y - 200.0)


## The goalkeeper's hands during a dive.
func keeper_reach(k: ISSFootballer) -> void:
	var b := ball
	if b.kicker == k:
		return
	var skill := float(teams[k.team].keeper_skill)
	var d := (b.pos - k.pos).length()
	# The diving body lies from the ground to about 40 px above his height.
	var dz := b.z - k.z
	if d > 16.0 + skill * 2.0 or dz < -28.0 or dz > 40.0:
		return
	var held := b.speed < 5.0 + skill * 0.5 or randf() < 0.35 + skill * 0.1
	if b.high and b.last_touch != null:
		# ball_check_00A67A: a lofted ball against the kicker's balance + 4
		# less the keeper's energy, x 4 and a random 0-3 into his skill's
		# keeper table: -1 it gets past him, 0 it bounces back off him at a
		# quarter of its speed, 1 he pushes it on at half speed, 2 he holds it.
		var idx := (b.last_touch.a("balance") + 4 - k.energy) * 4 + (randi() & 3)
		var r := contest("keeper", idx, teams[k.team].keeper_skill)
		if r < 0:
			return
		held = r >= 2
		if r == 0:
			event_counts["parries"] = int(event_counts.get("parries", 0)) + 1
			b.launch(k, b.heading + 32.0, b.speed * 0.25, 1.0, b.z)
			emit_sound(0x5A)
			return
		if r == 1:
			event_counts["parries"] = int(event_counts.get("parries", 0)) + 1
			var on := goal_center(k.team).direction_to(b.pos)
			b.launch(k, ISSFootballer.heading_to(Vector2.ZERO, on) + float(randi() % 17 - 8), b.speed * 0.5, 1.0, b.z)
			emit_sound(0x5A)
			return
	if held:
		event_counts["saves"] = int(event_counts.get("saves", 0)) + 1
		_clear_offside()
		b.owner = k
		b.team = k.team
		b.last_touch = k
		b.stop()
		emit_sound(0x6A)
		say(0x0A)
	else:
		# Parried: pushed away from the goal.
		event_counts["parries"] = int(event_counts.get("parries", 0)) + 1
		var away := goal_center(k.team).direction_to(b.pos)
		b.launch(k, ISSFootballer.heading_to(Vector2.ZERO, away) + float(randi() % 17 - 8), b.speed * 0.4, 1.0, b.z)
		emit_sound(0x5A)


## A header or volley (ball_launch_shot / a header pass).
func head_ball(p: ISSFootballer) -> void:
	var b := ball
	_clear_offside()
	if p.kick_kind == ISSFootballer.K.SHOT:
		var r: Array = ISSMatchData.kick("rising")[clampi(4 + p.a("jump") / 2, 0, 8)]
		b.launch(p, goal_heading(p), float(r[0]) * 1.5, float(r[1]) * 0.3, b.z)
		teams[p.team].stats["shots"] += 1
		emit_sound(0x57)
		if randi() % 3 == 0:
			say(0x0E)
	else:
		b.launch(p, p.kick_heading, 3.0, 1.5, b.z)
		emit_sound(0x56)
	_mark_offside(p)


## The ball leaves the kicker's foot (or hands).
func kick_ball(p: ISSFootballer) -> void:
	var b := ball
	if b.owner != p:
		return
	var h := p.kick_heading
	var power := clampi(p.kick_power, 0, 8)
	var target := p.kick_target
	var kind := p.kick_kind
	if p.human and target == null and kind in [ISSFootballer.K.PASS, ISSFootballer.K.LOFT, ISSFootballer.K.THROW_IN, ISSFootballer.K.KEEPER_THROW, ISSFootballer.K.KICKOFF]:
		target = _assist(p, h)
		if target != null:
			var lead := target.pos + ISSProjection.heading_vector(target.facing) * target.speed * 10.0
			h = ISSFootballer.heading_to(p.pos, lead)
			if kind == ISSFootballer.K.LOFT:
				power = teams[p.team]._lofted_power((lead - p.pos).length())
	var spd := 0.0
	var v := 0.0
	var z0 := 0.0
	var sfx := 0x56
	# Kicks gain strength with the shot power, the position and the energy.
	var bonus := float(p.a("shot_power") + ISSMatchData.position_bonus(p.position) + p.energy)
	match kind:
		ISSFootballer.K.PASS, ISSFootballer.K.KICKOFF:
			var k: Array = ISSMatchData.kick("pass")
			spd = float(k[0]) * (0.7 if kind == ISSFootballer.K.KICKOFF else 1.0)
			v = float(k[1])
			if target != null and (target.pos - p.pos).length() < 90.0:
				spd *= 0.8
		ISSFootballer.K.LOFT, ISSFootballer.K.PUNT:
			var k: Array = ISSMatchData.kick("lofted")[power]
			spd = float(k[0])
			v = float(k[1])
			sfx = 0x54
			if kind == ISSFootballer.K.PUNT:
				z0 = 12.0
		ISSFootballer.K.SHOT, ISSFootballer.K.DRIVE:
			if kind == ISSFootballer.K.SHOT and p.human:
				h = _human_shot_heading(p, h)
			var k: Array = ISSMatchData.kick("drive")
			var r: Array = ISSMatchData.kick("rising")[power]
			spd = float(k[0]) + 0.12 * bonus
			v = float(r[1]) * (0.35 if kind == ISSFootballer.K.SHOT else 0.6)
			sfx = 0x57
			if kind == ISSFootballer.K.SHOT or restart_type == R.PENALTY:
				teams[p.team].stats["shots"] += 1
				if randi() % 3 == 0:
					say(0x0E)
		ISSFootballer.K.THROW_IN:
			spd = 3.0
			v = 1.2
			z0 = 20.0
		ISSFootballer.K.KEEPER_THROW:
			spd = 3.2
			v = 1.2
			z0 = 16.0
	b.launch(p, h, spd, v, z0)
	emit_sound(sfx)
	var was := restart_type
	if was == R.PENALTY and p == restart_taker:
		_penalty_keeper(teams[1 - p.team].players[0])
		if shootout:
			pk_phase = 1
			pk_timer = 0
	elif was == R.PENALTY_SPOT and p == restart_taker:
		# penalty_spot_keeper_1: the keeper's dive 16 frames after the kick.
		pk_spot_wait = 16
	if restart_type != R.NONE and restart_phase == 1 and p == restart_taker:
		restart_type = R.NONE
		restart_taker = null
		restart_phase = 0
		set_places.clear()
	# No offside from throw-ins, goal kicks and corners.
	if was not in [R.THROW_IN, R.GOAL_KICK, R.CORNER] and kind != ISSFootballer.K.SHOT:
		_mark_offside(p)


## A human's shot goes at the goal when he faces it: up or down on the pad
## picks the near or far post side, otherwise the middle.
func _human_shot_heading(p: ISSFootballer, h: float) -> float:
	var g := goal_center(1 - p.team)
	var at_goal := ISSFootballer.heading_to(p.pos, g)
	if absf(ISSFootballer.angle_diff(at_goal, p.facing)) > 16.0:
		return h
	var aim := g.y + (randf() * 2.0 - 1.0) * 24.0
	if p.input_dir >= 0:
		var v := ISSProjection.heading_vector(p.input_dir)
		if absf(v.y) > 0.3:
			aim = g.y + signf(v.y) * (56.0 + randf() * 24.0)
	var spread := (100.0 - float(p.a("shot_power")) * 6.0) * (g - p.pos).length() / 800.0
	return ISSFootballer.heading_to(p.pos, Vector2(g.x, aim + (randf() * 2.0 - 1.0) * spread))


## Pass assist: the team-mate closest to the aimed direction.
func _assist(p: ISSFootballer, h: float) -> ISSFootballer:
	var best: ISSFootballer = null
	var best_score := INF
	for m in teams[p.team].active():
		if m == p or m.is_keeper():
			continue
		var off := m.pos - p.pos
		var dist := off.length()
		if dist > 520.0:
			continue
		var ang := absf(ISSFootballer.angle_diff(ISSFootballer.heading_to(p.pos, m.pos), h))
		if ang > 10.0:
			continue
		var score := ang * 12.0 + dist * 0.3
		if score < best_score:
			best_score = score
			best = m
	return best


## Offside (match_rules_update): when a pass is played, the team's players
## beyond the opponents' last defender (16 px tolerance), in the opponents'
## half and ahead of the ball are flagged; the first flagged one to touch
## the ball is offside.
func _mark_offside(p: ISSFootballer) -> void:
	_clear_offside()
	var t := teams[p.team]
	var o := teams[1 - p.team]
	var d := attack_dir(p.team)
	var last := -INF
	for q in o.active():
		if q.is_keeper():
			continue
		last = maxf(last, q.pos.x * d)
	if last == -INF:
		return
	var any := false
	for m in t.active():
		if m == p:
			continue
		var x := m.pos.x * d
		if x > last + 16.0 and x > mid.x * d and x > ball.pos.x * d:
			m.offside = true
			any = true
	if any:
		offside_side = p.team


func _clear_offside() -> void:
	if offside_side < 0:
		return
	for m in teams[offside_side].players:
		m.offside = false
	offside_side = -1


# ---------------------------------------------------------------------------
# Out of play, goals, posts and the bar.

func _bounds() -> void:
	var r := rect.grow(48.0)
	for p in all_players():
		p.pos = p.pos.clamp(r.position, r.end)


func _check_out() -> void:
	var b := ball
	var g: Dictionary = ISSMatchData.consts["goal"]
	var rs: Dictionary = ISSMatchData.consts["restart"]
	# A throw-in starts outside the pitch: the ball is only out once it has
	# been back in (or if it dies outside).
	if not ball_entered:
		if rect.has_point(b.pos):
			ball_entered = true
		elif b.owner != null or b.speed > 0.2 or b.z > 0.0:
			return
	if (drill > 0 or challenge >= 0) and (b.pos.y < rect.position.y or b.pos.y > rect.end.y):
		_practice_out()
		return
	if b.pos.y < rect.position.y or b.pos.y > rect.end.y:
		_release()
		var y := rect.position.y - float(rs["throw_in_outside"]) if b.pos.y < rect.position.y else rect.end.y + float(rs["throw_in_outside"])
		var x := clampf(b.pos.x, rect.position.x + float(rs["throw_in_clamp"]), rect.end.x - float(rs["throw_in_clamp"]))
		emit_sound(0x59)
		# Free training: every restart is the home side's (nobody else is on).
		start_restart(R.THROW_IN, 0 if drill == 0 else 1 - b.team, Vector2(x, y))
		return
	if b.pos.x >= rect.position.x and b.pos.x <= rect.end.x:
		return
	var left := b.pos.x < rect.position.x
	var defending := left_goal_team if left else 1 - left_goal_team
	var dy := absf(b.pos.y - mid.y)
	var line_x := rect.position.x if left else rect.end.x
	if dy < float(g["post_inner"]) and b.z < float(g["bar"]):
		_goal(defending)
		return
	if dy < float(g["post_outer"]) and b.z < float(g["bar_top"]):
		# Post or bar: back into play.
		_release()
		b.heading = fposmod(64.0 - b.heading, 64.0)
		b.speed *= 0.6
		if b.z >= float(g["bar"]):
			b.vz = -absf(b.vz) * 0.5
		b.pos.x = line_x + (2.0 if left else -2.0)
		emit_sound(0x4B)
		return
	_release()
	if drill > 0 or challenge >= 0:
		_practice_out()
		return
	var rsx := float(rs["goal_kick_x"])
	if b.team == defending:
		var cy := rect.position.y + float(rs["corner_inside"]) if b.pos.y < mid.y else rect.end.y - float(rs["corner_inside"])
		var cx := line_x + (float(rs["corner_inside"]) if left else -float(rs["corner_inside"]))
		teams[1 - defending].stats["corners"] += 1
		start_restart(R.CORNER, 1 - defending, Vector2(cx, cy))
	else:
		var gy := mid.y + (float(rs["goal_kick_y"]) if b.pos.y > mid.y else -float(rs["goal_kick_y"]))
		start_restart(R.GOAL_KICK, defending, Vector2(line_x + (rsx if left else -rsx), gy))


func _release() -> void:
	if ball.owner != null:
		var o := ball.owner
		ball.owner = null
		ball.speed = o.speed


func _goal(defending: int) -> void:
	_release()
	var scorer := ball.last_touch
	var own := scorer != null and scorer.team == defending
	var side := 1 - defending
	teams[side].score += 1
	teams[side].stats["goals"] += 1
	var minute := (half_frames - clock) / 3600 + half * (half_frames / 3600)
	# g_scorers keeps 32: seconds into the half, the half, the side
	# credited, the scorer's side and squad record (+$56).
	scorers.append({"side": side, "name": scorer.name if scorer != null else "", "minute": minute, "own_goal": own,
		"seconds": (half_frames - clock) / 60, "half": half, "team": scorer.team if scorer != null else side,
		"record": scorer.record if scorer != null else 0})
	goal_scored.emit(side, scorer, own)
	if drill > 0 or challenge >= 0:
		# A drill counts it and starts again; a challenge ends.
		emit_sound(0x64)
		say(0x2F)
		if challenge >= 0:
			_challenge_end(true)
		else:
			_drill_over()
		return
	for p in teams[side].active():
		if not p.is_keeper():
			p.celebrate()
	for p in teams[defending].active():
		p.deject()
	start_restart(R.OWN_GOAL if own else R.GOAL, defending, mid)


# ---------------------------------------------------------------------------
# Clock (g_match_clock) and halves.

func _clock() -> void:
	if restart_type in [R.GOAL, R.OWN_GOAL, R.HALF_TIME, R.TIME_UP, R.KICKOFF, R.MATCH_START]:
		return
	if clock > 0:
		clock -= 1
		if demo and restart_type == R.NONE and clock < half_frames - 3600:
			# match_rules_update: the demo leaves once the clock's minutes
			# fall below 4 (from 5), for main_init.
			_end("demo_over")
		return
	if restart_type == R.NONE and ball.live:
		# match_rules_update: half time after halves 0 and 2 (the first
		# halves of the match and of extra time), time up after 1 and 3.
		_release()
		start_restart(R.HALF_TIME if half % 2 == 0 else R.TIME_UP, 0, ball.pos)


func clock_seconds() -> float:
	return float(clock) / 60.0


# ---------------------------------------------------------------------------
# Restarts (g_director).

const ANNOUNCE := {
	R.THROW_IN: ["throw_in", 0x03, 70], R.GOAL_KICK: ["goal_kick", 0x02, 80],
	R.CORNER: ["corner_kick", 0x01, 90], R.FREE_KICK: ["free_kick", 0x04, 90],
	R.PENALTY: ["penalty_kick", 0x05, 120], R.OFFSIDE: ["offside", 0x06, 90],
	R.GOAL: ["", 0x2F, 220], R.OWN_GOAL: ["own_goal", 0x32, 220],
	R.HALF_TIME: ["half_time", 0x08, 240], R.TIME_UP: ["time_up", 0x42, 240],
	R.KICKOFF: ["", 0x27, 60], R.MATCH_START: ["", 0x27, 90],
}


func start_restart(type: int, side: int, pos: Vector2) -> void:
	restart_type = type
	restart_side = side
	restart_pos = pos
	restart_phase = 0
	restart_taker = null
	set_places.clear()
	_wall.clear()
	if type in [R.FREE_KICK, R.OFFSIDE]:
		_free_kick_places()
	event_counts[type] = int(event_counts.get(type, 0)) + 1
	var a: Array = ANNOUNCE.get(type, ["", -1, 60])
	restart_timer = int(a[2])
	# Dead ball: no contacts and no rules until the restart is taken (the
	# ball itself rolls on, into the net after a goal).
	ball.live = false
	if type in [R.HALF_TIME, R.TIME_UP]:
		emit_sound(0x49)
	elif type in [R.FREE_KICK, R.PENALTY, R.OFFSIDE, R.THROW_IN, R.GOAL_KICK, R.CORNER]:
		emit_sound(0x61)
	if type == R.GOAL:
		emit_sound(0x64)
		# The scorer's name, centred in the 12-letter banner.
		var s := ball.last_touch
		var n := s.name.to_upper().left(12) if s != null else "GOAL"
		var pad := (12 - n.length()) / 2
		banner.emit(" ".repeat(pad) + n + " ".repeat(12 - n.length() - pad))
	elif a[0] != "":
		banner.emit(a[0])
	if int(a[1]) >= 0:
		if type == R.GOAL and randi() % 2 == 0:
			say(0x44)
		say(int(a[1]))
	for t in teams:
		for p in t.active():
			if p.state in [ISSFootballer.S.SET_PIECE, ISSFootballer.S.KEEPER_HOLD] and type not in [R.GOAL, R.OWN_GOAL]:
				p.set_state(ISSFootballer.S.MOVE, ISSFootballer.A_STAND)


func _director() -> void:
	if restart_type == R.NONE:
		return
	if restart_phase == 0:
		if restart_type in [R.GOAL, R.OWN_GOAL]:
			_ball_in_net()
		restart_timer -= 1
		if restart_timer > 0:
			return
		banner_off.emit()
		var level := teams[0].score == teams[1].score
		match restart_type:
			R.GOAL, R.OWN_GOAL:
				if half > 1 and int(options.get("vgoal", 1)) == 0 and drill < 0 and challenge < 0:
					# V-goal (g_opt_vgoal 0): a goal in extra time ends the
					# match (rules_state_017FFC: straight to screen $39).
					if half_only:
						_end("golden_goal")
					else:
						_result_end()
					return
				if half_only and drill < 0 and challenge < 0:
					var pres := goal_presentation()
					if not pres.is_empty():
						# state_screen's big screen, then the kick-off.
						presentation = pres
						_end("presentation")
						return
				_start_kickoff(0 if drill >= 0 else restart_side)
			R.HALF_TIME:
				if half_only:
					_end("half")
					return
				# screen $39's routing: V-goal extra time with a side
				# ahead ends the match, else the next half.
				if half > 1 and not level and int(options.get("vgoal", 1)) == 0:
					_result_end()
					return
				_next_half()
			R.TIME_UP:
				if knockout and level:
					# Straight to screen $39, which plays extra time after
					# the second half and the shoot-out after extra time.
					if half_only:
						_end("time_up")
					elif half == 1:
						_next_half()
					else:
						_start_shootout()
					return
				_result_end()
			_:
				if half_only and (menu_request[0] != 0 or menu_request[1] != 0) and restart_type in [R.THROW_IN,
						R.GOAL_KICK, R.CORNER, R.FREE_KICK, R.PENALTY, R.OFFSIDE]:
					# rules_state_0185BA: a side asked for the match menu;
					# 128 frames, then screen 6 with this restart waiting.
					restart_phase = 3
					restart_timer = 0x80
					return
				if restart_type == R.PENALTY and half_only and drill < 0 and challenge < 0:
					# restart_penalty_1: the kick is taken in the shoot-out's
					# view (a human side picks its kicker on the order screen
					# first), then the match finishes it from the spot.
					_end("penalty")
					return
				_setup_restart()
	elif restart_phase == 2:
		restart_timer -= 1
		if restart_timer <= 0:
			if half_only:
				_end("result")
				return
			banner_off.emit()
			over = true
			finished.emit()
	elif restart_phase == 3:
		restart_timer -= 1
		if restart_timer <= 0:
			menu_request = [0, 0]
			_end("menu")
	elif restart_phase == 4:
		_penalty_spot_step()
	elif restart_phase == 1:
		if restart_taker == null or ball.owner != restart_taker:
			restart_type = R.NONE
			restart_phase = 0
			restart_taker = null
			set_places.clear()


## match_result_banner: the result for $200 frames, then the end.
func _result_end() -> void:
	banner.emit(_result_banner())
	restart_type = R.TIME_UP
	restart_phase = 2
	restart_timer = 150


## The next half: ends changed, the other side kicks off; extra time (half
## 2) is one g_game_time shorter.
func _next_half() -> void:
	half += 1
	if half == 2:
		game_time = maxi(0, game_time - 1)
	half_frames = _half_length()
	left_goal_team = 1 - left_goal_team
	clock = half_frames
	for t in teams:
		t.reset_lines()
	_start_kickoff(kickoff_side if half % 2 == 0 else 1 - kickoff_side)


## YOU WIN / YOU LOSE against the computer, else MATCH DRAWN or TEAM WINS.
func _result_banner() -> String:
	var diff := teams[0].score - teams[1].score
	if shootout:
		diff = int(pk_scores[0]) - int(pk_scores[1])
	if diff == 0:
		return "match_drawn"
	var winner := 0 if diff > 0 else 1
	var human_w := teams[winner].pads > 0
	var human_l := teams[1 - winner].pads > 0
	if human_w and not human_l:
		return "you_win"
	if human_l and not human_w:
		return "you_lose"
	# team_wins ("  T  WINS  ") with the winner's name in place of the T.
	return (teams[winner].name.to_upper().left(7) + " WINS").lpad(12)


func _ball_in_net() -> void:
	var b := ball
	var depth := 24.0
	if b.pos.x < rect.position.x - depth or b.pos.x > rect.end.x + depth:
		b.speed = 0.0
		b.pos.x = clampf(b.pos.x, rect.position.x - depth, rect.end.x + depth)


func _start_kickoff(side: int) -> void:
	for t in teams:
		for p in t.active():
			if p.state in [ISSFootballer.S.CELEBRATE, ISSFootballer.S.DEJECTED]:
				p.set_state(ISSFootballer.S.MOVE, ISSFootballer.A_STAND)
	_place_for_kickoff(side)
	restart_type = R.KICKOFF
	restart_side = side
	restart_pos = mid
	restart_phase = 0
	restart_timer = 60
	say(0x27)
	event_counts[R.KICKOFF] = int(event_counts.get(R.KICKOFF, 0)) + 1
	# The kick-off itself: straight to the set piece.
	_setup_restart()


func _place_for_kickoff(side: int) -> void:
	ball.owner = null
	ball.stop()
	ball.pos = mid
	for t in teams:
		t.reset_lines()
		for p in t.active():
			p.pos = kickoff_place(p, side)
			p.speed = 0.0
			p.z = 0.0
			p.facing = 16 if attack_dir(p.team) > 0.0 else 48
			p.set_state(ISSFootballer.S.MOVE, ISSFootballer.A_STAND)


## tbl_kickoff_positions: (dx, dy) x16 px from the centre spot, negative dx
## toward the own goal; the kicking side's last two stand on the spot.
func kickoff_place(p: ISSFootballer, side: int) -> Vector2:
	var t := teams[p.team]
	var d := attack_dir(p.team)
	if p.is_keeper():
		return goal_center(p.team) + Vector2(d * 32.0, 0)
	var k: Array = t.kickoff_layout[clampi(p.index - 1, 0, 9)]
	var dx := float(k[0])
	var dy := float(k[1])
	if p.team != side:
		dx = minf(dx, -7.0)
	return mid + Vector2(dx * 16.0 * d, dy * 16.0)


## Where a player stands while a restart is being set up.
func restart_place(p: ISSFootballer) -> Vector2:
	if set_places.has(p):
		return set_places[p]
	var t := teams[p.team]
	if restart_type in [R.KICKOFF, R.MATCH_START]:
		return kickoff_place(p, restart_side)
	var home := t.home_position(p)
	if restart_type == R.PENALTY:
		var g := goal_center(1 - restart_side)
		var d := attack_dir(restart_side)
		if absf(home.x - g.x) < 320.0:
			home.x = g.x - d * 320.0
		return home
	# Keep the opponents 80 px from the ball.
	if p.team != restart_side and (home - restart_pos).length() < 80.0:
		home = restart_pos + restart_pos.direction_to(home) * 80.0 if home != restart_pos else restart_pos + Vector2(0, 80)
	return home


## Put the ball down and give it to the taker (tbl_restart_setup).
func _setup_restart() -> void:
	var type := restart_type
	var side := restart_side
	var t := teams[side]
	var taker: ISSFootballer = null
	ball.owner = null
	ball.stop()
	ball.pos = restart_pos
	ball.live = true
	ball_entered = rect.has_point(restart_pos)
	match type:
		R.GOAL_KICK:
			taker = t.players[0]
		R.KICKOFF, R.MATCH_START:
			taker = _kickoff_taker(t)
		_:
			var best := INF
			for p in t.active():
				if p.is_keeper() and type != R.FREE_KICK:
					continue
				var d := (p.pos - restart_pos).length()
				if d < best:
					best = d
					taker = p
	if taker == null:
		taker = t.players[0]
	# The wall is in place when the ball is put down.
	for p in _wall:
		if p != taker and p.state != ISSFootballer.S.SENT_OFF:
			p.pos = set_places[p]
			p.speed = 0.0
			p.facing = int(ISSFootballer.heading_to(p.pos, restart_pos)) & 63
	set_places.erase(taker)
	var d := attack_dir(side)
	var aim := 16.0 if d > 0.0 else 48.0
	match type:
		R.THROW_IN:
			# Into the pitch, half turned toward the goal the side attacks.
			aim = 32.0 - 8.0 * d if restart_pos.y < mid.y else fposmod(8.0 * d, 64.0)
		R.CORNER, R.PENALTY, R.FREE_KICK, R.OFFSIDE:
			aim = ISSFootballer.heading_to(restart_pos, goal_center(1 - side))
	taker.pos = restart_pos - ISSProjection.heading_vector(int(aim) & 63) * 8.0
	if type == R.THROW_IN:
		taker.pos = restart_pos
	taker.z = 0.0
	taker.start_set_piece(aim)
	taker.ai_wait = 50 + randi() % 50
	taker.kick_target = null
	ball.owner = taker
	ball.team = side
	ball.last_touch = taker
	ball.step()
	restart_taker = taker
	restart_phase = 1
	if type == R.PENALTY and not shootout:
		_setup_penalty(taker)
	elif type in [R.KICKOFF, R.MATCH_START]:
		emit_sound(0x47)


func _kickoff_taker(t: ISSTeam) -> ISSFootballer:
	var best: ISSFootballer = null
	var best_d := INF
	for p in t.active():
		if p.is_keeper():
			continue
		var d := (p.pos - mid).length()
		if d < best_d:
			best_d = d
			best = p
	return best


func _setup_penalty(taker: ISSFootballer) -> void:
	var defending := teams[1 - taker.team]
	var k := defending.players[0]
	k.pos = goal_center(defending.side) + Vector2(attack_dir(defending.side) * 4.0, 0)
	k.set_state(ISSFootballer.S.MOVE, ISSFootballer.A_READY)
	for t in teams:
		for p in t.active():
			if p == taker or p.is_keeper():
				continue
			p.pos = restart_place(p)


## A CPU taker (or a human team's taker while no pad drives him).
func _cpu_set_piece(p: ISSFootballer) -> void:
	p.input_dir = -1
	p.ai_wait -= 1
	if p.ai_wait > 0 or ball.owner != p:
		return
	var t := teams[p.team]
	match restart_type:
		R.PENALTY:
			var g := goal_center(1 - p.team) + Vector2(0, (randf() * 2.0 - 1.0) * 70.0)
			p.facing = int(ISSFootballer.heading_to(p.pos, g)) & 63
			p.kick_target = null
			p.kick_power = 3 + randi() % 4
			p.press = ISSFootballer.SHOOT
		R.KICKOFF, R.MATCH_START:
			var mate := t._best_mate(p, t.their_goal(), 200.0)
			p.kick_target = mate
			if mate != null:
				p.facing = int(ISSFootballer.heading_to(p.pos, mate.pos)) & 63
			p.press = ISSFootballer.PASS
		_:
			var to_goal := (goal_center(1 - p.team) - p.pos).length()
			if restart_type in [R.FREE_KICK, R.OFFSIDE] and to_goal < 420.0:
				p.facing = int(goal_heading(p)) & 63
				p.kick_power = 4
				p.press = ISSFootballer.SHOOT
				return
			var mate := t._best_mate(p, t.their_goal(), 520.0)
			if mate == null:
				p.facing = 16 if attack_dir(p.team) > 0.0 else 48
				p.kick_power = 6
				p.press = ISSFootballer.LOFT
				return
			p.kick_target = mate
			var dist := (mate.pos - p.pos).length()
			p.facing = int(ISSFootballer.heading_to(p.pos, mate.pos)) & 63
			if restart_type == R.CORNER or dist > 230.0:
				p.kick_power = t._lofted_power(dist)
				p.press = ISSFootballer.LOFT
			else:
				p.press = ISSFootballer.PASS
	p.kick_heading = p.facing


# ---------------------------------------------------------------------------
# Penalties.

## The keeper facing a penalty: a human keeper dives the way the pad points
## (up or down) at the kick, the computer guesses (shootout_keeper_ai).
func _penalty_keeper(k: ISSFootballer) -> void:
	var side := k.team
	var dir := -1
	if teams[side].pads > 0:
		var d: int = side_pad(side).get("dir", -1)
		if d >= 0:
			var v := ISSProjection.heading_vector(d)
			dir = 0 if v.y < -0.3 else (1 if v.y > 0.3 else 2)
		else:
			dir = 2
	else:
		dir = randi() % 3
	if dir < 2:
		k.start_dive(0.0 if dir == 0 else 32.0, 2.2 + 0.2 * float(teams[side].keeper_skill))


## state_shootout: five kicks each at one goal, then sudden death.
func _start_shootout() -> void:
	shootout = true
	half = 4
	pk_scores = [0, 0]
	pk_taken = [0, 0]
	pk_next = [10, 10]
	pk_side = kickoff_side
	restart_type = R.NONE
	ball.live = true
	banner.emit("penalty_kick")
	_next_penalty()


func _next_penalty() -> void:
	var s := pk_side
	# Kicks go at the right-hand goal: the taker's side defends the left one.
	left_goal_team = s
	var taker_team := teams[s]
	var keeper := teams[1 - s].players[0]
	# Takers from the forwards back (squad order 10, 9, ... 1), skipping the sent off.
	var taker: ISSFootballer = null
	for i in 11:
		var idx := int(pk_next[s])
		pk_next[s] = 10 if idx <= 1 else idx - 1
		var cand := taker_team.players[idx]
		if cand.state != ISSFootballer.S.SENT_OFF:
			taker = cand
			break
	for t in teams:
		for p in t.active():
			p.set_state(ISSFootballer.S.MOVE, ISSFootballer.A_STAND)
			p.speed = 0.0
			p.z = 0.0
			# Everyone else waits in the centre circle.
			p.pos = mid + Vector2(-40.0 + 16.0 * float(p.index % 6), -40.0 + 20.0 * float(p.team * 3 + p.index / 6))
			p.facing = 16
	keeper.pos = goal_center(1 - s) + Vector2(-4.0, 0)
	keeper.facing = 48
	restart_type = R.PENALTY
	restart_side = s
	restart_pos = goal_center(1 - s) + Vector2(-256.0, 0)
	restart_phase = 0
	_setup_restart()
	if taker != null and restart_taker != taker:
		# _setup_restart took the nearest: swap in this round's taker.
		var first := restart_taker
		first.set_state(ISSFootballer.S.MOVE, ISSFootballer.A_STAND)
		first.pos = taker.pos
		taker.pos = restart_pos - Vector2(8, 0)
		taker.start_set_piece(16.0)
		taker.ai_wait = 60 + randi() % 40
		ball.owner = taker
		ball.team = s
		ball.last_touch = taker
		restart_taker = taker
	pk_phase = 0
	pk_timer = 0


func _shootout_step() -> void:
	if shootout_over:
		restart_timer -= 1
		if restart_timer <= 0:
			banner_off.emit()
			over = true
			finished.emit()
		return
	if pk_phase == 2:
		pk_timer -= 1
		if pk_timer <= 0:
			banner_off.emit()
			var w := _shootout_winner()
			if w >= 0:
				banner.emit(_result_banner())
				restart_type = R.TIME_UP
				restart_phase = 2
				restart_timer = 150
				shootout_over = true
				return
			pk_side = 1 - pk_side
			_next_penalty()
		return
	if pk_phase != 1:
		return
	pk_timer += 1
	var b := ball
	var g: Dictionary = ISSMatchData.consts["goal"]
	var goal_x := rect.end.x
	if b.pos.x > goal_x:
		var scored: bool = absf(b.pos.y - mid.y) < float(g["post_inner"]) and b.z < float(g["bar"])
		_penalty_done(scored)
	elif b.owner != null or pk_timer > 150 or (b.speed < 0.2 and b.z <= 0.0 and pk_timer > 20) \
			or b.pos.y < rect.position.y or b.pos.y > rect.end.y:
		_penalty_done(false)



func _penalty_done(scored: bool) -> void:
	var s := pk_side
	pk_taken[s] = int(pk_taken[s]) + 1
	if scored:
		pk_scores[s] = int(pk_scores[s]) + 1
		emit_sound(0x64)
		say(0x2F)
		banner.emit("   GOAL   ")
	else:
		emit_sound(0x6A)
		banner.emit("  MISSED  ")
	ball.speed = 0.0
	pk_phase = 2
	pk_timer = 120


## The winning side once it cannot be caught (5 kicks each), else -1.
func _shootout_winner() -> int:
	var a := int(pk_scores[0])
	var b := int(pk_scores[1])
	var ta := int(pk_taken[0])
	var tb := int(pk_taken[1])
	if ta <= 5 and tb <= 5:
		if a > b + (5 - tb):
			return 0
		if b > a + (5 - ta):
			return 1
		if ta == 5 and tb == 5 and a != b:
			return 0 if a > b else 1
		return -1
	# Sudden death: after each pair.
	if ta == tb and a != b:
		return 0 if a > b else 1
	return -1


# ---------------------------------------------------------------------------
# The free kick wall (restart_setup_free_kick, $013B76).

## Within wall_range of the goal line the defenders 1..n line up
## wall_distance px from the ball toward the goal centre, n by the angle
## (tbl_wall_size), wall_gap px apart; the other defenders and the
## kicking side's players 5-10 go to the places of tbl_fk_attack / _defence,
## mirrored to the ball's side of the pitch.
func _free_kick_places() -> void:
	var fk: Dictionary = ISSMatchData.consts["free_kick"]
	var side := restart_side
	var goal := goal_center(1 - side)
	if absf(goal.x - restart_pos.x) >= float(fk["wall_range"]):
		return
	var h := int(ISSFootballer.heading_to(restart_pos, goal)) & 63
	var n := int(fk["wall_size"][h >> 2])
	var centre := restart_pos + ISSProjection.heading_vector(h) * float(fk["wall_distance"])
	var across := ISSProjection.heading_vector((h + 16) & 63) * float(fk["wall_gap"])
	var start := centre - across * float(n) / 2.0
	var def := teams[1 - side]
	var att := teams[side]
	for k in range(1, n + 1):
		var p := def.players[k]
		set_places[p] = start + across * float(k)
		_wall.append(p)
	var dy := restart_pos.y - mid.y
	var flip := 1.0 if restart_pos.y >= mid.y else -1.0
	var spots: Array = fk["defence_wide"] if absf(dy) >= float(fk["wide_y"]) else fk["defence"]
	var own_line := goal.x
	for k in range(n + 1, 11):
		var at: Array = spots[k - n - 1]
		set_places[def.players[k]] = Vector2(own_line - attack_dir(side) * float(at[0]) * 16.0,
			mid.y + flip * float(at[1]) * 16.0)
	# (The ROM picks the kicking side's table on dy, not |dy|.)
	spots = fk["attack_low"] if dy >= float(fk["wide_y"]) else fk["attack"]
	for k in range(5, 11):
		var at: Array = spots[k - 5]
		set_places[att.players[k]] = Vector2(goal.x + attack_dir(side) * float(at[0]) * 16.0,
			mid.y + flip * float(at[1]) * 16.0)


# ---------------------------------------------------------------------------
# Training (mode 0: restart_setup_practice, $01418C, and the resets of
# match_rules_update in mode 0, $015E32).

## Set drill n up: 0 free (the practice team stays off, the home side kicks
## off), 1 defence (the home defenders against three attackers), 2 free
## kick (home players 5-10 against the keeper and players 1-6, with a wall),
## 3 keeper (the home keeper, on the pad, against two attackers).
func start_drill(n: int) -> void:
	var tr: Dictionary = ISSMatchData.consts["training"]
	drill = n
	drill_wait = -1
	event_counts["drills"] = int(event_counts.get("drills", 0)) + 1
	half = 0
	clock = half_frames
	left_goal_team = 0
	_clear_offside()
	restart_type = R.NONE
	restart_taker = null
	restart_phase = 0
	set_places.clear()
	_wall.clear()
	banner_off.emit()
	ball.owner = null
	ball.kicker = null
	ball.stop()
	ball.live = true
	ball_entered = true
	var home := teams[0]
	var away := teams[1]
	# tm_keeper_manual = 2: the home keeper is the pad's (the only player on).
	home.keeper_mode = 2 if n == 3 else int(options.get("keepers", [0, 0])[0])
	_reset_players()
	match n:
		0:
			for p in away.players:
				_take_off(p)
			_start_kickoff(0)
		1:
			var form: Array = tr["defence_form"]
			for p in home.players:
				if p.role != 2:
					_take_off(p)
				else:
					p.pos = Vector2(rect.position.x + float(tr["defence_x"]) + p.form.x * float(form[0]),
						mid.y + p.form.y * float(form[1]))
			_drill_attackers(tr["defence_attackers"])
		2:
			for i in 5:
				_take_off(home.players[i])
			for i in range(7, 11):
				_take_off(away.players[i])
			_drill_free_kick(randi() % 16)
		3:
			for i in range(1, 11):
				_take_off(home.players[i])
			_drill_attackers(tr["keeper_attackers"])


## Everybody back on his feet in his place, facing the goal he attacks.
func _reset_players() -> void:
	for t in teams:
		t.reset_lines()
		t.controlled = null
		t.strategy = -1
		t.strategy_run = -1
		for p in t.players:
			p.set_state(ISSFootballer.S.MOVE, ISSFootballer.A_STAND)
			p.speed = 0.0
			p.z = 0.0
			p.vz = 0.0
			p.offside = false
			p.protect = 0
			p.kick_target = null
			p.ai_mode = ISSTeam.AI.KEEPER if p.is_keeper() else ISSTeam.AI.FORMATION
			p.facing = 16 if t.side == 0 else 48
			p.pos = t.home_position(p) if not p.is_keeper() else goal_center(t.side) + Vector2(attack_dir(t.side) * 32.0, 0)


func _take_off(p: ISSFootballer) -> void:
	p.set_state(ISSFootballer.S.SENT_OFF, ISSFootballer.A_STAND)
	p.pos = Vector2(mid.x, rect.position.y - 300.0)


## The practice team's players 10, 9, ... at the drill's places (x16 px from
## the left line and from the middle); the last one placed has the ball and
## the rest are off.
func _drill_attackers(spots: Array) -> void:
	var away := teams[1]
	var first := 11 - spots.size()
	for i in 11:
		var p := away.players[i]
		if i < first:
			_take_off(p)
			continue
		var at: Array = spots[10 - i]
		p.pos = Vector2(rect.position.x + float(at[0]) * 16.0, mid.y + float(at[1]) * 16.0)
		p.facing = 48
	var c := away.players[first]
	ball.pos = c.pos + ISSProjection.heading_vector(c.facing) * 6.0
	ball.owner = c
	ball.team = 1
	ball.last_touch = c
	c.protect = 30
	ball.step()


## restart_resume_practice: the kick is taken from one of 16 places round the
## area (misc_data_038120, x16 px from the right line and the middle).
func _drill_free_kick(i: int) -> void:
	var at: Array = ISSMatchData.consts["free_kick_spots"][i]
	var spot := Vector2(rect.end.x + float(at[0]) * 16.0, mid.y + float(at[1]) * 16.0)
	restart_type = R.FREE_KICK
	restart_side = 0
	restart_pos = spot
	_free_kick_places()
	for t in teams:
		for p in t.active():
			p.pos = restart_place(p)
	_setup_restart()


## match_rules_update, mode 0: the defence and keeper drills end when the
## home side has the ball, the free kick drill when the other side has it;
## out of play (and goals) end drills 1-3 too (_check_out, _goal).
func _drill_step() -> void:
	if drill_wait >= 0:
		_ball_in_net()
		drill_wait -= 1
		if drill_wait < 0:
			start_drill(drill)
		return
	var o := ball.owner
	if o == null or restart_type != R.NONE:
		return
	if (drill in [1, 3] and o.team == 0) or (drill == 2 and o.team == 1):
		_drill_over()


## Out of play (and goals) in a drill or a challenge.
func _practice_out() -> void:
	if challenge >= 0:
		_challenge_end(false)
	else:
		_drill_over()


func _drill_over() -> void:
	drill_wait = int(ISSMatchData.consts["training"]["reset_frames"])
	ball.live = false
	restart_type = R.NONE
	restart_taker = null
	set_places.clear()
	_wall.clear()


## The team whose half the ball is in (g_ball_zone_team).
func ball_zone_team() -> int:
	return left_goal_team if ball.pos.x < mid.x else 1 - left_goal_team


# ---------------------------------------------------------------------------
# Challenges (mode 1: restart_setup_practice_target, $014364;
# restart_resume_practice_target; match_rules_update in mode 1, $015ED0).

## Set event ev at level lv up: both sides are the practice team, only the
## event's players are on (match.json "challenge"), against 30 seconds.
func start_challenge(ev: int, lv: int) -> void:
	var ch: Dictionary = ISSMatchData.consts["challenge"]
	var e: Dictionary = ch["events"][ev]
	challenge = ev
	challenge_level = lv
	half = 0
	left_goal_team = 0
	ch_time = (ch["time"] as Array).map(func(v): return int(v))
	ch_bonus = ch_time.duplicate()
	ch_count = 0
	ch_done = false
	ch_bonus_on = false
	ch_end = -1
	ch_touched.clear()
	ch_flags.clear()
	ch_target_y = NAN
	restart_type = R.NONE
	restart_taker = null
	restart_phase = 0
	set_places.clear()
	_wall.clear()
	ball.owner = null
	ball.kicker = null
	ball.stop()
	ball.live = true
	ball_entered = true
	_reset_players()
	var home := teams[0]
	var away := teams[1]
	for t in teams:
		for p in t.players:
			_take_off(p)
	for k in int(e["home_counts"][lv]):
		var p: ISSFootballer = home.players[int(e["home_first"]) + k] if e.has("home_first") \
			else home.players[int(e["home_last"]) - k]
		_challenge_on(p, e.get("home_places", []), k)
	if e.has("home_middle"):
		var p := home.players[int(e["home_middle"])]
		_challenge_on(p, [], 0)
		p.pos = mid
	for k in int(e["away_counts"][lv]):
		_challenge_on(away.players[int(e["away_first"]) + k], e.get("away_places", []), k)
	if e.has("keeper_level") and lv >= int(e["keeper_level"]):
		_challenge_on(away.players[0], [], 0)
	if ev == 0:
		for f: Array in ch["flags"]:
			ch_flags.append(mid + Vector2(float(f[0]), float(f[1])) * 16.0)
	if bool(e.get("target", false)):
		# goal_target_init: over one half of the right goal, at random.
		ch_target_y = mid.y + (float(ch["target_y"]) if randi() % 2 == 0 else -float(ch["target_y"]))
	match str(e.get("restart", "")):
		"corner":
			var c: Array = ch["corner"]
			_challenge_restart(R.CORNER, Vector2(rect.end.x + float(c[0]), rect.end.y + float(c[1])))
		"free_kick":
			var at: Array = ISSMatchData.consts["free_kick_spots"][int(e["spot_by_level"][lv])]
			_challenge_restart(R.FREE_KICK, Vector2(rect.end.x + float(at[0]) * 16.0, mid.y + float(at[1]) * 16.0))
		_:
			var cr: Array = e["carrier"]
			var c := teams[int(cr[0])].players[int(cr[1])]
			ball.pos = c.pos + ISSProjection.heading_vector(c.facing) * 6.0
			ball.owner = c
			ball.team = c.team
			ball.last_touch = c
			ball.step()
	clock = _challenge_frames()


func _challenge_on(p: ISSFootballer, places: Array, k: int) -> void:
	p.set_state(ISSFootballer.S.MOVE, ISSFootballer.A_STAND)
	p.pos = teams[p.team].home_position(p) if not p.is_keeper() else goal_center(p.team) + Vector2(attack_dir(p.team) * 32.0, 0)
	if k < places.size():
		var at: Array = places[k]
		p.pos = mid + Vector2(float(at[0]), float(at[1])) * 16.0


## The corner (restart_setup_corner) and free kick (restart_setup_free_kick)
## of events 4 and 5, for the home side.
func _challenge_restart(type: int, at: Vector2) -> void:
	restart_type = type
	restart_side = 0
	restart_pos = at
	if type == R.FREE_KICK:
		_free_kick_places()
	for t in teams:
		for p in t.active():
			p.pos = restart_place(p)
	_setup_restart()


## Frames the HUD clock shows: the time left, then the bonus counting down.
func _challenge_frames() -> int:
	var t: Array = ch_time
	if ch_done and not ch_bonus_on and challenge in [0, 1, 3]:
		var b: Array = ch_bonus
		return (int(b[0]) * 1000 + int(b[1]) * 100 + int(b[2]) * 10 + int(b[3])) * 60 / 100
	return int(t[0]) * 600 + int(t[1]) * 60 + int(t[2]) * 10 + int(t[3])


func _challenge_step() -> void:
	var ch: Dictionary = ISSMatchData.consts["challenge"]
	if ch_end >= 0:
		_ball_in_net()
		ch_end -= 1
		if ch_end == 0:
			banner_off.emit()
			over = true
			finished.emit()
		return
	# restart_setup_practice_target_1: the dribbler (home player 1) takes a
	# flag within flag_reach px (|dx| + |dy|).
	if challenge == 0 and restart_type == R.NONE:
		var d := teams[0].players[1]
		for f in ch_flags.duplicate():
			if absf(f.x - d.pos.x) + absf(f.y - d.pos.y) < float(ch["flag_reach"]):
				ch_flags.erase(f)
				ch_count += 1
				emit_sound(0x60)
	if not ch_done:
		if challenge == 0 and ch_count == 5:
			_challenge_success()
			return
		if challenge == 1 and ball.last_touch != null and ball.last_touch.team == 0 and not ch_touched.has(ball.last_touch):
			ch_touched[ball.last_touch] = true
			ch_count += 1
			if ch_count == 10:
				_challenge_success()
				return
	var o := ball.owner
	if o != null:
		if challenge == 3:
			# Defence: winning the ball is the task; losing it again ends it.
			if not ch_done:
				if o.team == 0:
					_challenge_success()
					return
			elif o.team != 0:
				_challenge_end(false)
				return
		elif o.team != 0:
			_challenge_end(false)
			return
	if ch_done:
		if not ch_bonus_on and challenge in [0, 1, 3]:
			if _bonus_tick(int(ch["bonus_step"])):
				_challenge_end(false)
				return
	elif _time_tick(int(ch["sixths"])):
		_challenge_end(false)
		return
	if challenge in [2, 4, 5]:
		ch_bonus = ch_time.duplicate()
	clock = _challenge_frames()


## One frame off the time; true when it is up.
func _time_tick(sixths: int) -> bool:
	var t := ch_time
	t[3] -= 1
	if t[3] < 0:
		t[3] = 9
		t[2] -= 1
		if t[2] < 0:
			t[2] = sixths
			t[1] -= 1
			if t[1] < 0:
				t[1] = 9
				t[0] -= 1
	return t == [0, 0, 0, 0]


## step off the bonus (plain decimal digits); true when it is gone.
func _bonus_tick(step: int) -> bool:
	var b := ch_bonus
	b[3] -= step
	if b[3] < 0:
		b[3] += 10
		b[2] -= 1
		if b[2] < 0:
			b[2] = 9
			b[1] -= 1
			if b[1] < 0:
				b[1] = 9
				b[0] -= 1
	return b == [0, 0, 0, 0]


## The task is done ($13CC = $B, match_rules_update_5): CLEAR in the banner.
func _challenge_success() -> void:
	ch_done = true
	ch_count = 11
	emit_sound(0x61)
	banner.emit(str(ISSMatchData.consts["challenge"]["banners"][0]))


## The attempt is over (match_rules_update_7): a goal is the task in events
## 2, 4 and 5 and keeps the bonus in 0, 1 and 3; a goal by the panel
## (goal_target_update) keeps the bonus too. CLEAR or MISS, then the end.
func _challenge_end(goal: bool) -> void:
	var ch: Dictionary = ISSMatchData.consts["challenge"]
	if goal:
		if challenge in [0, 1, 3]:
			ch_bonus_on = true
		else:
			ch_done = true
		if not is_nan(ch_target_y) and absf(ball.pos.y - ch_target_y) < float(ch["target_reach"]):
			ch_bonus_on = true
	ball.live = false
	restart_type = R.NONE
	restart_taker = null
	set_places.clear()
	_wall.clear()
	clock = _challenge_frames()
	banner.emit(str(ch["banners"][0 if ch_done else 1]))
	music.emit(16 if ch_done else 17)
	ch_end = 180


func challenge_result() -> Dictionary:
	return {"event": challenge, "level": challenge_level, "done": ch_done, "bonus_on": ch_bonus_on,
		"time": ch_time.duplicate(), "bonus": ch_bonus.duplicate()}


# ---------------------------------------------------------------------------
# Officials: the referee trails the ball, the linesman runs the touchline.

func _officials() -> void:
	var target := ball.pos + Vector2(-64.0 * attack_dir(ball.team if ball.team >= 0 else 0), 72.0)
	referee_pos += (target - referee_pos).limit_length(2.0)
	var lx := clampf(ball.pos.x, rect.position.x, rect.end.x)
	linesman_pos.x += clampf(lx - linesman_pos.x, -2.2, 2.2)
	linesman_pos.y = rect.position.y - 20.0
