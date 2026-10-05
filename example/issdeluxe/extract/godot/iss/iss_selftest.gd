extends SceneTree
## Headless check of the extracted ISS Deluxe assets and scripts:
##
##   godot --headless --path out/godot --import
##   godot --headless --path out/godot -s res://iss/iss_selftest.gd
##
## Exits with status 1 if anything is missing or behaves unexpectedly.

var _failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", what)


func _json(path: String) -> Variant:
	var doc = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(doc != null, "parse " + path)
	return doc


func _init() -> void:
	var players = _json("res://assets/iss/players/animations.json")
	var ball = _json("res://assets/iss/ball/animations.json")
	var npc = _json("res://assets/iss/npc/animations.json")
	var weather = _json("res://assets/iss/weather/weather.json")
	var stadiums = _json("res://assets/iss/stadiums/stadiums.json")
	var teams = _json("res://assets/iss/teams.json")
	var flags = _json("res://assets/iss/flags/flags.json")
	var hud = _json("res://assets/iss/hud/hud.json")
	var sound = _json("res://assets/iss/sound/sound.json")
	var misc = _json("res://assets/iss/misc/misc.json")
	if _failures > 0:
		quit(1)
		return
	_check(players["actions"].size() == 54, "54 player actions")
	var keepers = _json("res://assets/iss/keeper/animations.json")
	_check(keepers["actions"].size() == 37 and keepers["actions"][0]["directions"].size() == 16, "37 keeper actions, 16 directions")
	var kf: Dictionary = keepers["frames"][keepers["actions"][22]["directions"][4][0]]
	_check(ResourceLoader.exists(kf["right"]["png"]) and ResourceLoader.exists(kf["left"]["png"]), "keeper frames")
	_check(ball["actions"].size() == 5, "5 ball actions")
	_check(npc["actions"].size() == 21 and npc["action_names"].size() == 21, "21 named NPC actions")
	_check(stadiums["stadiums"].size() == 8, "8 stadiums")
	_check(stadiums["stadiums"][0]["pitch_bounds"]["right"] == 1920, "stadium 0 pitch bounds")
	_check(flags["actions"].size() == 2 and flags["actions"][0].size() == 4, "flag frames")
	_check(teams != null and teams["teams"][0]["name"] == "England", "team names")
	_check(teams["teams"][0]["players"][9]["attributes"]["speed"] == 7 \
		and teams["teams"][0]["players"][0]["position"] == "goalkeeper", "player records")
	var formations = _json("res://assets/iss/formations.json")
	_check(formations["formations"].size() == 16 and formations["formations"][1]["name"] == "4-4-2", "formations")
	_check(hud["radar"]["mapping"].size() == 8, "radar mapping per stadium")
	_check(hud["banner_messages"]["throw_in"]["text"] == "  THROW IN  " \
		and ResourceLoader.exists("res://assets/iss/hud/banner_font.png"), "banner font and messages")
	_check(ResourceLoader.exists("res://assets/iss/hud/flags/flag_41.png"), "team flags")
	_check(hud["strategy_names"].size() == 8 \
		and ResourceLoader.exists("res://assets/iss/hud/strategies/strategy_7.png"), "strategy labels")
	_check(misc["particles"]["rain"]["actions"]["1"].size() == 3 and misc["goal_target"].size() == 2, "small sprites")
	_check(sound["samples"].size() == 65 and sound["sfx"].size() == 126, "65 PCM samples, 126 effects")
	for s: Dictionary in sound["samples"]:
		_check(ResourceLoader.exists(s["wav"]), "sample " + s["wav"])
	for id in [0x01, 0x2F, 0x4D]:
		_check(sound["sfx"][id].has("wav") and ResourceLoader.exists(sound["sfx"][id]["wav"]), "effect %X" % id)
	var crowd: AudioStreamWAV = load(sound["sfx"][0x62]["wav"])
	_check(crowd != null and crowd.loop_mode == AudioStreamWAV.LOOP_FORWARD \
		and crowd.loop_end == sound["sfx"][0x62]["loop"][1] - 1, "crowd loop points")
	var counts := [32, 0, 16]
	for w in 3:
		_check(weather["weathers"][w]["frames"].size() == counts[w], "weather %d frame count" % w)
	for doc in [players, ball, npc]:
		for f: Dictionary in doc["frames"].values():
			for side in ["right", "left", "shadow"]:
				if f.has(side):
					_check(ResourceLoader.exists(f[side]["png"]), "frame " + f[side]["png"])

	# Run the demo for two seconds of game time.
	var demo: Node = load("res://iss/iss_demo.tscn").instantiate()
	root.add_child(demo)
	for i in 120:
		await process_frame
	var b := ISSBallSprite.new()
	root.add_child(b)
	for h: int in [0, 0x3F, 0x40, 0x5F, 0x60, 0xC8]:
		b.height = h
		_check(b.action() == clampi((h - 0x20) >> 5, 0, 2), "ball action at height %d" % h)
	_check(ISSProjection.heading_vector(16).is_equal_approx(Vector2(1, 0)), "heading 16 = right")
	_check(ISSProjection.heading_vector(0).is_equal_approx(Vector2(0, -1)), "heading 0 = up")
	_check(ISSProjection.direction(60) == 0 and ISSProjection.direction(20) == 3, "direction index")
	var snd := ISSSound.new()
	root.add_child(snd)
	var rendered := FileAccess.file_exists("res://assets/iss/sound/rendered/rendered.json")
	_check(snd.play_sfx(0x2F), "commentary plays")
	_check(not snd.has_sfx(0x10), "commentary whose sample is missing")
	_check(snd.has_sfx(0x5F) == rendered, "PSG effect only with the rendered sound")
	_check(snd.play_music(5) == rendered, "music only with the rendered sound")
	if rendered:
		var ogg: AudioStreamOggVorbis = load("res://assets/iss/sound/rendered/song_12.ogg")
		_check(ogg != null and ogg.get_length() > 10.0, "rendered song")
	_check(snd.speech_context(0x2F) == "goal", "speech context")
	snd.stop_music()
	snd.stop_sfx()
	snd.queue_free()
	demo.queue_free()
	await process_frame
	_check_match_engine()
	_check_human_control()
	_check_knockout()
	_check_ram_halves()
	_check_passwords()
	_check_international()
	_check_world_series()
	_check_presentations()
	_check_goal_presentation()
	_check_shootout()
	_check_penalty_view()
	_check_boot()
	_check_pause_replay()
	_check_competitions()
	_check_strategies_and_subs()
	_check_long_modes()
	await _check_game()
	print("iss_selftest: ", "OK" if _failures == 0 else "%d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)


## A whole CPU v CPU match with 1-minute halves: kick-offs, half time, time up,
## restarts; the ball stays on or around the pitch and never dies for long.
func _check_match_engine() -> void:
	seed(7)
	var match_json = _json("res://assets/iss/match.json")
	_check(match_json["pitch_bounds"].size() == 8 and is_equal_approx(match_json["run_speed"], 1.875), "match constants")
	var e := ISSMatchEngine.new()
	e.setup(0, 1, {"stadium": 0, "weather": 1, "time": 1, "level": 2, "pads": [0, 0], "half_seconds": 60})
	var frames := 0
	var still := 0
	var worst := 0
	var outside := 0
	while not e.over and frames < 60 * 60 * 10:
		e.step([])
		frames += 1
		if e.restart_type == ISSMatchEngine.R.NONE and e.ball.live and e.ball.speed == 0.0 and e.ball.owner == null:
			still += 1
			worst = maxi(worst, still)
		else:
			still = 0
		if not e.rect.grow(96.0).has_point(e.ball.pos):
			outside += 1
	_check(e.over, "match finishes (%d frames)" % frames)
	_check(frames < 60 * 60 * 6, "match length %d frames" % frames)
	_check(int(e.event_counts.get(ISSMatchEngine.R.HALF_TIME, 0)) == 1 \
		and int(e.event_counts.get(ISSMatchEngine.R.TIME_UP, 0)) == 1, "half time and time up")
	_check(int(e.event_counts.get(ISSMatchEngine.R.KICKOFF, 0)) >= 1, "kick-offs")
	_check(worst < 60 * 20, "ball never left dead in play (%d frames)" % worst)
	_check(outside < 60 * 3, "ball stays near the pitch (%d frames outside)" % outside)
	var total := 0
	for k in e.event_counts:
		if k is int and k in [ISSMatchEngine.R.THROW_IN, ISSMatchEngine.R.GOAL_KICK, ISSMatchEngine.R.CORNER,
				ISSMatchEngine.R.FREE_KICK, ISSMatchEngine.R.GOAL, ISSMatchEngine.R.OWN_GOAL]:
			total += int(e.event_counts[k])
	_check(total > 0, "restarts happen")
	_check(e.scorers.size() == e.teams[0].score + e.teams[1].score, "every goal recorded")
	print("iss_selftest: match ", e.teams[0].name, " ", e.teams[0].score, "-", e.teams[1].score, " ", e.teams[1].name,
		" in ", frames, " frames, events ", e.event_counts)
	e.dispose()


## Player 1's pad drives the controlled player: run right with dash, then
## pass; the kick-off taker is the human's when the home side kicks off.
func _check_human_control() -> void:
	seed(3)
	var e := ISSMatchEngine.new()
	e.setup(0, 1, {"stadium": 0, "weather": 1, "time": 1, "level": 2, "pads": [1, 0], "half_seconds": 60})
	var idle := {"dir": -1, "press": 0, "held": 0}
	var frames := 0
	# Wait for the kick-off to be ready (the CPU may kick off).
	while e.restart_type != ISSMatchEngine.R.NONE and frames < 600:
		if e.restart_taker != null and e.restart_taker.team == 0 and e.restart_phase == 1:
			e.step([{"dir": 16, "press": ISSFootballer.PASS, "held": 0}, null])
		else:
			e.step([idle, null])
		frames += 1
	_check(e.restart_type == ISSMatchEngine.R.NONE, "kick-off taken")
	var c := e.teams[0].controlled
	_check(c != null, "a controlled player")
	if c == null:
		e.dispose()
		return
	var x0 := c.pos.x
	for i in 60:
		e.step([{"dir": 16, "press": 0, "held": ISSFootballer.DASH}, null])
	c = e.teams[0].controlled
	_check(c != null and c.human, "human flag on the controlled player")
	# Get the ball to a home player and pass it.
	e.ball.owner = null
	e.ball.stop()
	var p := e.teams[0].players[6]
	e.ball.pos = p.pos + Vector2(4, 0)
	e.slots[0].player = p
	for i in 4:
		e.step([idle, null])
	_check(e.ball.owner == p, "the controlled player picks up the ball")
	var kicked := false
	for i in 40:
		e.step([{"dir": 16, "press": ISSFootballer.PASS if i == 0 else 0, "held": 0}, null])
		if e.ball.owner == null and e.ball.kicker == p:
			kicked = true
	_check(kicked, "the pad's pass button kicks the ball")
	_check(absf(x0) > 0.0, "controlled player moved")
	e.dispose()


## The game: the main menu first; an open game's first half played from
## RAM ends on the statistics (screen $39), which go on by themselves
## without human pads to the match menu (screen 6) for the second half
## with the ends changed.
func _check_game() -> void:
	var game: ISSGame = load("res://iss/iss_game.tscn").instantiate()
	root.add_child(game)
	for i in 5:
		await process_frame
	_check(game._screen is ISSMenu and ISSRam.w(ISSSym.g_screen) == 0, "the game starts on the main menu")
	ISSModes.start_open_game()
	ISSModes.open_game_setup()
	ISSRam.set_w(0x153E, 0)
	ISSRam.set_w(ISSSym.g_pads_home, 0)
	_short_clock(8)
	var left := ISSRam.w(ISSSym.g_left_goal_team)
	Engine.time_scale = 8.0
	Engine.max_physics_steps_per_frame = 64
	game._state(ISSMenu.STATE_MATCH)
	for i in 30:
		await physics_frame
	var m := game._screen as ISSMatch
	_check(m != null and m.engine.half_only and m.engine.frame > 10, "a half runs on screen")
	var seen := false
	for i in 60 * 30:
		await physics_frame
		if game._screen is ISSMenu and ISSRam.w(ISSSym.g_screen) == 0x39:
			seen = true
		if seen and ISSRam.w(ISSSym.g_screen) == 6:
			break
	_check(seen, "the half ends on the match statistics")
	_check(ISSRam.w(ISSSym.g_screen) == 6 and ISSRam.w(ISSSym.g_half) == 1 and ISSRam.w(0x1638) == 1 \
		and ISSRam.w(ISSSym.g_left_goal_team) == left ^ 1 and ISSRam.w(ISSSym.g_restart_type) == 4,
		"then the match menu for the second half, ends changed")
	Engine.time_scale = 1.0
	game.queue_free()
	await process_frame


## Passwords: one the cartridge showed for a short league (level 2, one
## human team, five games played) decodes to its RAM; every mode's
## password round-trips through encode, seal, check and resume.
func _check_passwords() -> void:
	ISSMenu.power_on()
	var hex := "03bcf9fca47c68c4ddbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbc"
	for i in hex.length() / 2:
		ISSRam.set_b(ISSSym.g_password + i, hex.substr(i * 2, 2).hex_to_int())
	ISSRam.set_w(ISSSym.g_password_length, 96)
	var ok := ISSPassword.check() and ISSPassword.resume(ISSPassword.mode_of_length(96)) == 0x1D
	var teams := []
	for i in 6:
		teams.append(ISSRam.w(0x127C + 2 * i))
	_check(ok and ISSRam.w(ISSSym.g_game_level) == 2 and ISSRam.w(0x1270) == 5 and teams == [0, 6, 12, 3, 20, 30]
		and ISSRam.w(0x12A0) == 2, "the cartridge's league password decodes")
	var all := true
	for mode: int in ISSPassword.FIELDS:
		ISSMenu.power_on()
		for i in 0x30:
			ISSRam.set_w(0x127C + 2 * i, 0)
		ISSRam.set_w(ISSSym.g_game_level, 3)
		ISSRam.set_w(0x1270, 2)
		ISSRam.set_w(0x127C, 17)
		ISSRam.set_w(0x129C, 1)
		ISSPassword.encode(mode)
		ISSPassword.seal()
		ISSRam.set_w(0x127C, 0)
		ISSRam.set_w(0x129C, 0)
		if not ISSPassword.check() or ISSPassword.mode_of_length(ISSRam.w(ISSSym.g_password_length)) != mode:
			all = false
			continue
		ISSPassword.resume(mode)
		if ISSRam.w(ISSSym.g_game_level) != 3 or ISSRam.w(ISSSym.g_game_mode) != mode:
			all = false
		if mode != 0xC and ISSRam.w(0x127C) != 17:
			all = false
	_check(all, "every mode's password round-trips")


## The International Cup's bookkeeping with no human side (every game
## simulated): the draws, the tables and the finals' bracket.
func _check_international() -> void:
	ISSMenu.power_on()
	ISSRam.set_l(ISSSym.g_unpack_buffer, 0xFF3E18)
	ISSModes.start_international()
	ISSRam.set_w(0x127C, 31)
	ISSRam.set_w(0x1266, 0)
	ISSModes.intl_elimination_next_game()
	var o1 := ISSRam.w(0x127E)
	var o2 := ISSRam.w(0x1280)
	_check(ISSRam.w(0x1270) == 3 and ISSRam.w(0x126C) == 10 and [o1, o2] in [[30, 32], [32, 30]],
		"International Cup: the region's other two teams, three games")
	ISSMenu.power_on()
	ISSModes.start_international()
	ISSRam.set_w(0x127C, 7)
	ISSRam.set_w(0x1266, 0)
	ISSModes.intl_elimination_next_game()
	o1 = ISSRam.w(0x127E)
	o2 = ISSRam.w(0x1280)
	ISSRam.set_l(ISSSym.g_unpack_buffer, 0xFF3E18)
	var t := ISSModes.intl_elimination_table()
	var points := 0
	for k in 3:
		points += ISSRam.b(t + k * 6 + 5)
	_check(o1 < 24 and o2 < 24 and o1 != o2 and 7 not in [o1, o2] and points >= 6 and points <= 9
		and ISSRam.b(t + 5) >= ISSRam.b(t + 11) and ISSRam.w(0x1272) in [0, 1],
		"International Cup: European opponents, the table")
	ISSModes.intl_group_start()
	ISSRam.set_w(0x1266, 0)
	var group := [ISSRam.w(0x127C), ISSRam.w(0x127E), ISSRam.w(0x1280), ISSRam.w(0x1282)]
	ISSModes.intl_group_next_game()
	ISSRam.set_l(ISSSym.g_unpack_buffer, 0xFF3E18)
	t = ISSModes.intl_group_table()
	var first := ISSRam.b(t + 1)
	var second := ISSRam.b(t + 7)
	var other := ISSRam.w(0x129A)
	_check(ISSRam.w(0x1270) == 6 and o1 not in group and o2 not in group and group.size() == 4
		and (ISSRam.w(0x1272) == 1 or (other in group and other != group[0]))
		and (ISSRam.w(0x1272) == 0) == (first == 0 or second == 0),
		"International Cup: the group round")
	ISSModes.international_finals()
	ISSRam.set_w(0x1266, 0)
	var slots := []
	for k in 16:
		slots.append(ISSRam.w(0x127C + k * 2))
	var distinct := true
	for k in 15:
		if slots.count(slots[k]) != 1:
			distinct = false
	ISSModes.intl_finals_next_game()
	var bracket := ISSRam.w(0x1270) == 15
	for g in 15:
		var win := ISSRam.w(0x129C + g * 2)
		var pair := [g * 2, g * 2 + 1] if g < 8 else [ISSRam.w(0x129C + (g - 8) * 4), ISSRam.w(0x129E + (g - 8) * 4)]
		if win not in pair:
			bracket = false
	_check(distinct and bracket and ISSRam.w(ISSSym.g_game_mode) == 8, "International Cup: the finals")


## A World Series season: every pair of the 36 teams meets once in the 35
## days, 18 wins a day; the table's leader is the series' winner.
## state_screen's presentations run to where they lead: the toss (C
## pressed now and then on both pads; the coin falls heads, the call):
## home takes the kick-off, away picks the right-hand end, then the match;
## a goal's big screen back to the match after 320 frames; the trophy on to
## the World Series' second series ($37).
func _check_presentations() -> void:
	var results := []
	for kind in 3:
		ISSMenu.power_on()
		ISSModes.team_info_init()
		ISSRam.set_w(ISSSym.g_pads_home, 1)
		ISSRam.set_w(ISSSym.g_pads_away, 1)
		ISSRam.set_w(0x1730, kind)
		ISSRam.set_w(0x1734, 1)
		var menu := ISSMenu.new()
		root.add_child(menu)
		menu.set_physics_process(false)
		ISSRam.set_l(ISSSym.g_current_state, ISSMenu.STATE_MENU)
		menu.enter(ISSMenu.STATE_SCREEN)
		menu.hv_counter = func() -> int: return 0
		var frames := 0
		while frames < 2000 and ISSRam.l(ISSSym.g_current_state) == ISSMenu.STATE_SCREEN:
			frames += 1
			var press := kind == 0 and frames % 30 < 2
			for pad in 2:
				if press:
					Input.action_press(ISSInput.action(pad, "c"))
				else:
					Input.action_release(ISSInput.action(pad, "c"))
			menu._physics_process(1.0 / 60.0)
		for pad in 2:
			Input.action_release(ISSInput.action(pad, "c"))
		results.append([frames, ISSRam.l(ISSSym.g_current_state), ISSRam.w(0x1634), ISSRam.w(ISSSym.g_left_goal_team),
			ISSRam.w(ISSSym.g_screen)])
		menu.free()
	var toss: Array = results[0]
	var goal: Array = results[1]
	var cup: Array = results[2]
	_check(toss[1] == ISSMenu.STATE_MATCH and toss[2] == 0 and toss[3] == 1, "presentation: the toss %s" % [toss])
	_check(goal[1] == ISSMenu.STATE_MATCH and goal[0] > 320 and goal[0] < 400, "presentation: a goal %s" % [goal])
	_check(cup[1] == ISSMenu.STATE_MENU and cup[4] == 0x37, "presentation: the trophy %s" % [cup])


## A PK-mode shoot-out between two CPU sides, kick after kick seen from
## behind the taker (the HUD on the window plane, the taker, the keeper and
## the ball as sprites): it is decided (five each, or sudden death), every
## kick ticks or crosses its taker's mark, and it ends in the main menu.
func _check_shootout() -> void:
	ISSMenu.power_on()
	ISSModes.start_pk()
	ISSModes.pk_setup()
	ISSRam.set_w(ISSSym.g_pads_home, 0)
	ISSRam.set_w(ISSSym.g_pads_away, 0)
	var menu := ISSMenu.new()
	root.add_child(menu)
	menu.set_physics_process(false)
	var reads := [0]
	menu.hv_counter = func() -> int:
		var k: int = reads[0]
		reads[0] = k + 1
		return ((k * 2654435761) >> 7) & 0xFFFF
	ISSRam.set_l(ISSSym.g_current_state, ISSMenu.STATE_MENU)
	menu.enter(ISSMenu.STATE_SHOOTOUT)
	var kicks := 0
	var last: ISSShootout = null
	var sprites := 0
	var marks := 0
	var window := 0
	var frames := 0
	while frames < 12000 and ISSRam.l(ISSSym.g_current_state) == ISSMenu.STATE_SHOOTOUT:
		frames += 1
		menu._physics_process(1.0 / 60.0)
		if menu.shootout != last:
			last = menu.shootout
			kicks += 1
		if ISSRam.w(ISSSym.g_frame_state) == 2:
			sprites = maxi(sprites, menu.vdp.sprite_count)
			window = menu.vdp.window_h
		var m := 0
		for i in 10:
			if ISSRam.w(0x1526 + 2 * i) != 0xFFFF:
				m += 1
		marks = maxi(marks, m)
	var home := ISSRam.w(0x153A)
	var away := ISSRam.w(0x153C)
	var ok := ISSRam.l(ISSSym.g_current_state) == ISSMenu.STATE_MENU and ISSRam.w(ISSSym.g_next_screen) == 0 \
		and home != away and kicks >= 6 and marks >= 6 and sprites >= 10 and window == 0x80
	_check(ok, "shoot-out: %d kicks, %d-%d in %d frames, %d marks, %d sprites" % [kicks, home, away, frames, marks,
		sprites])
	menu.free()


## A penalty in a front-end match: the match leaves for the shoot-out's
## view, which runs one kick (CPU v CPU here) and comes back with restart
## 7; the match then puts everyone in place, the kicker walks up and takes
## the kick the view decided, and play goes on.
## The title screen (ISSBoot on ISSMenu, warm_start's screen alone): with
## no press it hands over to the attract demo (mode $B: two computer teams,
## state_match), whose match the engine ends after a minute of play, or at
## Start; with Start on the title, to the main menu.
func _check_boot() -> void:
	for pressed in [false, true]:
		ISSMenu.power_on()
		ISSBoot.screens_override = [1]
		var menu := ISSMenu.new()
		root.add_child(menu)
		menu.set_physics_process(false)
		var states := []
		menu.next_state.connect(func(st: int) -> void: states.append(st))
		menu.enter(ISSMenu.STATE_WARM)
		var frames := 0
		while states.is_empty() and frames < 3000:
			frames += 1
			# A press counts only 24 frames into a wait (boot_vblank_pressed), so
			# hold Start through the title's loading waits.
			if pressed and frames == 150:
				Input.action_press(ISSInput.action(0, "start"))
			elif pressed and frames == 400:
				Input.action_release(ISSInput.action(0, "start"))
			menu._physics_process(1.0 / 60.0)
		ISSBoot.screens_override = []
		var want := ISSMenu.STATE_MENU if pressed else ISSMenu.STATE_MATCH
		var ok: bool = states.size() == 1 and states[0] == want
		if pressed:
			ok = ok and ISSRam.w(ISSSym.g_next_screen) == 0 and frames < 1400
		else:
			ok = ok and ISSRam.w(ISSSym.g_game_mode) == 0xB and ISSRam.w(ISSSym.g_pads_home) == 0 \
				and ISSRam.w(ISSSym.g_team_home) != ISSRam.w(ISSSym.g_team_away) and frames > 1400
		_check(ok, "title %s: state $%X after %d frames" % ["with Start" if pressed else "unpressed", states[0] if not states.is_empty() else 0, frames])
		menu.queue_free()
		if pressed:
			continue
		# The demo's match: CPU against CPU, over once the clock's minutes drop
		# below 4; a second one leaves at Start.
		var setup := ISSMatchSetup.from_ram()
		var e := ISSMatchEngine.new()
		e.setup(int(setup["home"]), int(setup["away"]), setup["options"])
		var steps := 0
		while not e.over and steps < 6000:
			e.step([])
			steps += 1
		var demo_ok := e.demo and e.over and e.end_reason == "demo_over" and steps > 3600 and e.slots.is_empty()
		e.dispose()
		e = ISSMatchEngine.new()
		e.setup(int(setup["home"]), int(setup["away"]), setup["options"])
		for i in 30:
			e.step([])
		e.demo_start()
		_check(demo_ok and e.over and e.end_reason == "demo_title",
			"the attract demo: over after %d steps (%s), Start leaves for the title" % [steps, e.end_reason])
		e.dispose()


## n frames of match m, pad 1's button `press` held for the first `hold`
## (a release needs a frame of its own before the next press has an edge).
func _match_frames(m: ISSMatch, n: int, press := "", hold := 1) -> void:
	for i in n:
		if press != "" and i == 0:
			Input.action_press(ISSInput.action(0, press))
		m._physics_process(1.0 / 60.0)
		if press != "" and i == hold - 1:
			Input.action_release(ISSInput.action(0, press))


## The pause menu and the replay: Start freezes the game and opens the
## band to its menu's height (two items on a 6-button pad, four on a
## 3-button one); the replay ring holds the last six seconds; REPLAY fades
## to a replay that plays by itself (A / B / C take it over), Start brings
## the menu back and RESUME closes it with the game where it was.
func _check_pause_replay() -> void:
	for six in [true, false]:
		var m := ISSMatch.new()
		root.add_child(m)
		m.set_physics_process(false)
		m.start(0, 6, {"pads": [1, 0], "controllers": [{"side": 0, "six": six}], "level": 1})
		_match_frames(m, 200)
		var frame0: int = m.engine.frame
		var ring_ok: bool = m._rec_frame == 200 and m._rec_start == 0 and m._ring[24] != null \
			and m._ring[24]["anim"][1] != null and m._ring[25] == null
		_match_frames(m, 2, "start")
		var kind := "six_button" if six else "three_button"
		var opened: bool = m.paused and m._pause["kind"] == kind and int(m._pause["band"]) == 2
		_match_frames(m, 20)
		var band := 20 if six else 36
		var full: bool = int(m._pause["band"]) == band and m.engine.frame == frame0 and m._hud.pause["band"] == band
		_match_frames(m, 2, "down")
		var cursor: bool = int(m._pause["cursor"]) == 1
		if not six:
			# STRATEGY takes the first slot, EDIT SCREEN asks for the match
			# menu; the cursor wraps both ways.
			_match_frames(m, 2, "down")
			_match_frames(m, 2, "c")
			var slot0 := int(m.engine.teams[0].strategy_slots[0])
			cursor = cursor and int(m._pause["cursor"]) == 2 and m.engine.teams[0].strategy == slot0
			_match_frames(m, 2, "down")
			_match_frames(m, 2, "c")
			cursor = cursor and int(m._pause["cursor"]) == 3 and m.engine.menu_request[0] == 1
			_match_frames(m, 2, "down")
			cursor = cursor and int(m._pause["cursor"]) == 0
			_match_frames(m, 2, "up")
			cursor = cursor and int(m._pause["cursor"]) == 3
			_match_frames(m, 2, "down")
			_match_frames(m, 2, "down")
		else:
			_match_frames(m, 2, "up")
			cursor = cursor and int(m._pause["cursor"]) == 0
			_match_frames(m, 2, "down")
		cursor = cursor and int(m._pause["cursor"]) == 1
		_match_frames(m, 1, "c")
		var fading: bool = m._fade_dir == 1 and m.paused
		_match_frames(m, ISSMatch.FADE)
		var started: bool = not m._replay.is_empty() and int(m._replay["frame"]) == 0 and int(m._replay["end"]) == 200 \
			and m._fade_dir == -1 and not m._referee.visible
		_match_frames(m, ISSMatch.FADE + 10)
		var auto: bool = not m._replay.is_empty() and int(m._replay["frame"]) == 10 and int(m._replay["auto"]) == 2 \
			and not m._hud.replay.get("manual", false)
		# B: slow motion and manual; C held 8 frames moves 4; A held 8 moves
		# back 4; B again and it plays backwards by itself; C forwards.
		_match_frames(m, 2, "b")
		_match_frames(m, 8, "c", 8)
		var slow: bool = int(m._replay["frame"]) == 14 and int(m._replay["slow"]) != 0 and m._hud.replay["manual"] \
			and m._hud.replay["slow"] and not m._hud.replay["back"]
		_match_frames(m, 1)
		_match_frames(m, 8, "a", 8)
		var back: bool = int(m._replay["frame"]) == 10 and m._replay["back"] and m._hud.replay["back"]
		_match_frames(m, 1)
		_match_frames(m, 1, "b")
		_match_frames(m, 4)
		var plays: bool = int(m._replay["frame"]) == 5 and int(m._replay["slow"]) == 0
		_match_frames(m, 1, "c")
		_match_frames(m, 1)
		plays = plays and int(m._replay["frame"]) == 7 and not m._replay["back"]
		_match_frames(m, 1, "start")
		_match_frames(m, ISSMatch.FADE)
		var menu_back: bool = m._replay.is_empty() and m.paused and int(m._pause["cursor"]) == 0 \
			and int(m._pause["band"]) == band and m._hud.replay.is_empty() and m._referee.visible and m._fade_dir == -1
		_match_frames(m, ISSMatch.FADE)
		_match_frames(m, 1, "start")
		_match_frames(m, band / 2)
		var closed: bool = not m.paused and m.engine.frame == frame0
		_match_frames(m, 5)
		closed = closed and m.engine.frame == frame0 + 5 and m._rec_frame == 205
		_check(ring_ok and opened and full and cursor and fading and started and auto and slow and back and plays \
			and menu_back and closed,
			"%s pause and replay: ring %s open %s band %s cursor %s fade %s replay %s auto %s slow %s back %s plays %s menu %s close %s" % [
			kind, ring_ok, opened, full, cursor, fading, started, auto, slow, back, plays, menu_back, closed])
		m.queue_free()


func _check_penalty_view() -> void:
	ISSMenu.power_on()
	ISSModes.start_open_game()
	ISSModes.open_game_setup()
	ISSRam.set_w(ISSSym.g_pads_home, 0)
	ISSRam.set_w(ISSSym.g_pads_away, 0)
	_short_clock(50)
	var setup := ISSMatchSetup.from_ram()
	var e := ISSMatchEngine.new()
	e.setup(int(setup["home"]), int(setup["away"]), setup["options"])
	e.ball.live = true
	e.start_restart(ISSMatchEngine.R.PENALTY, 0, e.goal_center(1) - Vector2(e.attack_dir(0) * 256.0, 0))
	var frames := 0
	while not e.over and frames < 600:
		e.step([])
		frames += 1
	var left := e.end_reason
	ISSMatchSetup.to_ram(e)
	e.dispose()
	_check(left == "penalty" and ISSRam.sw(ISSSym.g_restart_type) == ISSMatchEngine.R.PENALTY,
		"penalty: the match leaves for the view (%s, restart %d)" % [left, ISSRam.sw(ISSSym.g_restart_type)])
	ISSModes.penalty_view_start()
	var menu := ISSMenu.new()
	root.add_child(menu)
	menu.set_physics_process(false)
	var reads := [0]
	menu.hv_counter = func() -> int:
		var k: int = reads[0]
		reads[0] = k + 1
		return ((k * 2654435761) >> 7) & 0xFFFF
	ISSRam.set_l(ISSSym.g_current_state, ISSMenu.STATE_MATCH)
	var next := [0]
	menu.next_state.connect(func(st: int) -> void: next[0] = st)
	menu.enter(ISSMenu.STATE_SHOOTOUT)
	frames = 0
	while frames < 2000 and next[0] == 0:
		frames += 1
		menu._physics_process(1.0 / 60.0)
	menu.free()
	_check(next[0] == ISSMenu.STATE_MATCH and ISSRam.sw(ISSSym.g_restart_type) == ISSMatchEngine.R.PENALTY_SPOT,
		"penalty: the view comes back to the match (state %X, restart %d, %d frames)" % [next[0],
		ISSRam.sw(ISSSym.g_restart_type), frames])
	var order0 := ISSRam.w(0x14FE)
	setup = ISSMatchSetup.from_ram()
	e = ISSMatchEngine.new()
	e.setup(int(setup["home"]), int(setup["away"]), setup["options"])
	var scripted := e.restart_type == ISSMatchEngine.R.PENALTY_SPOT and e.restart_phase == 4 \
		and e.pk_spot_taker == e.teams[0].players[order0]
	frames = 0
	while frames < 900 and e.restart_type != ISSMatchEngine.R.NONE:
		e.step([])
		frames += 1
	var kicker := e.ball.kicker
	for i in 120:
		e.step([])
	# The kick is taken, the keeper has made the view's save, and play went
	# on (a goal or a goal kick are restarts of their own by now).
	var outcome := "goal" if e.restart_type in [ISSMatchEngine.R.GOAL, ISSMatchEngine.R.KICKOFF] else \
		("play on" if e.restart_type == ISSMatchEngine.R.NONE else "restart %d" % e.restart_type)
	_check(scripted and kicker == e.teams[0].players[order0] and int(e.teams[0].stats["shots"]) >= 1
		and e.scripted_keeper == null and e.pk_spot_wait == 0 and e.restart_type != ISSMatchEngine.R.PENALTY_SPOT,
		"penalty: taken from the spot by player %d in %d frames (dive %X, kicker %s, %s)" % [order0, frames,
		int(setup["options"].get("penalty", {}).get("dive_input", -1)), kicker.index if kicker != null else -1, outcome])
	e.dispose()


## A front-end match leaves for the big screen after a goal that puts a
## human side one up, and after an own goal (the side that conceded), then
## takes the kick-off up again from RAM.
func _check_goal_presentation() -> void:
	var got := []
	for own in [false, true]:
		ISSMenu.power_on()
		ISSModes.start_open_game()
		ISSModes.open_game_setup()
		ISSRam.set_w(ISSSym.g_pads_home, 1)
		ISSRam.set_w(ISSSym.g_pads_away, 0)
		_short_clock(50)
		var setup := ISSMatchSetup.from_ram()
		var e := ISSMatchEngine.new()
		e.setup(int(setup["home"]), int(setup["away"]), setup["options"])
		e.ball.live = true
		e.ball.last_touch = e.teams[1 if own else 0].players[5]
		e._goal(1)
		var frames := 0
		while not e.over and frames < 60 * 20:
			e.step([])
			frames += 1
		ISSMatchSetup.to_ram(e)
		var p := e.presentation.duplicate()
		var reason := e.end_reason
		e.dispose()
		setup = ISSMatchSetup.from_ram()
		e = ISSMatchEngine.new()
		e.setup(int(setup["home"]), int(setup["away"]), setup["options"])
		got.append([reason, p, e.restart_type, e.restart_side, e.teams[0].score])
		e.dispose()
	_check(got[0][0] == "presentation" and got[0][1] == {"side": 0, "kind": 1} and got[0][3] == 1 and got[0][4] == 1,
		"a goal: the big screen, then the other side's kick-off %s" % [got[0]])
	_check(got[1][0] == "presentation" and got[1][1] == {"side": 1, "kind": 0} and got[1][3] == 1,
		"an own goal: the big screen in the conceding side's kit %s" % [got[1]])


func _check_world_series() -> void:
	ISSMenu.power_on()
	ISSModes.start_world_series()
	ISSRam.set_w(0x127C, 0)
	var met := {}
	var ok := true
	for day in 35:
		ISSRam.set_l(ISSSym.g_unpack_buffer, 0xFF3E18)
		ISSModes.ws_next_game()
		var t := ISSRam.l(0x1384)
		var seen := {}
		for k in 18:
			var a := ISSRam.b(t + k * 2)
			var b := ISSRam.b(t + k * 2 + 1)
			met[mini(a, b) * 64 + maxi(a, b)] = true
			seen[a] = true
			seen[b] = true
		if seen.size() != 36 or ISSRam.b(t) != 0 or ISSRam.w(ISSSym.g_team_home) != 0:
			ok = false
		ISSRam.set_w(ISSSym.g_score_home, 1)
		ISSRam.set_w(ISSSym.g_score_away, 0)
		ISSRam.set_l(ISSSym.g_unpack_buffer, 0xFF3E18)
		ISSModes.ws_record_day()
	var wins := 0
	for team in 36:
		wins += ISSRam.w(0x129C + team * 2)
	ISSRam.set_l(ISSSym.g_unpack_buffer, 0xFF3E18)
	var t := ISSModes.ws_standings()
	_check(ok and met.size() == 36 * 35 / 2 and wins == 35 * 18 and ISSRam.w(0x1270) == 35
		and ISSRam.w(0x129C) == 35 and ISSRam.b(t + 1) == 0 and ISSRam.w(0x127E) == 0 and ISSRam.w(0x1272) == 0,
		"World Series: a season of 35 days, the human's team winning every game")
	ISSModes.ws_second_series()
	_check(ISSRam.w(0x126C) == 1 and ISSRam.w(0x1270) == 0 and ISSRam.w(0x129C) == 0, "World Series: the second series")
	ISSRam.set_w(0x1280, 5)
	ISSModes.start_championship()
	ISSModes.match_setup_random()
	_check(ISSRam.w(ISSSym.g_game_mode) == 0xA and ISSRam.w(ISSSym.g_team_away) == 5, "championship: the other series' winner")


## A short half on g_match_clock (seconds).
func _short_clock(seconds: int) -> void:
	ISSRam.set_l(ISSSym.g_match_clock, 0)
	ISSRam.set_b(ISSSym.g_match_clock + 1, seconds / 10)
	ISSRam.set_b(ISSSym.g_match_clock + 2, seconds % 10)


## state_match from RAM: one half that stops at half time, the match
## written back; a side asking for the match menu leaves at the next
## restart, which the next start takes up again; V-goal extra time ends on
## a goal.
func _check_ram_halves() -> void:
	seed(5)
	ISSMenu.power_on()
	ISSModes.start_open_game()
	ISSModes.open_game_setup()
	ISSRam.set_w(ISSSym.g_pads_home, 0)
	_short_clock(20)
	var setup := ISSMatchSetup.from_ram()
	var e := ISSMatchEngine.new()
	e.setup(int(setup["home"]), int(setup["away"]), setup["options"])
	var frames := 0
	while not e.over and frames < 60 * 60:
		e.step([])
		frames += 1
	_check(e.over and e.end_reason == "half" and e.half == 0, "a half from RAM stops at half time")
	e.teams[0].stats["corners"] = 3
	e.teams[1].players[4].energy = 1
	ISSMatchSetup.to_ram(e)
	var away4: int = ISSSym.g_team_away_players + e.teams[1].players[4].ram_slot * ISSModes.PLAYER_SIZE
	_check(ISSRam.w(ISSSym.g_score_home) == e.teams[0].score and ISSRam.w(ISSSym.g_stats_home + 4) == 3 \
		and ISSRam.b(away4 + 0x57) == 1 and ISSMatchSetup.clock_frames() == 0, "the half written back to RAM")
	e.dispose()
	_short_clock(50)
	ISSRam.set_w(ISSSym.g_restart_type, 4)
	setup = ISSMatchSetup.from_ram()
	e = ISSMatchEngine.new()
	e.setup(int(setup["home"]), int(setup["away"]), setup["options"])
	e.menu_request[0] = 1
	frames = 0
	while not e.over and frames < 60 * 60:
		e.step([])
		frames += 1
	var waiting := e.restart_type
	_check(e.end_reason == "menu" and waiting in [0, 1, 2, 5, 6, 20], "the match menu at the next restart (%s, %d)" % [e.end_reason, waiting])
	ISSMatchSetup.to_ram(e)
	_check(ISSRam.w(0x182A) == 0 and ISSMatchSetup.clock_frames() > 0, "the request taken, the clock kept")
	e.dispose()
	setup = ISSMatchSetup.from_ram()
	e = ISSMatchEngine.new()
	e.setup(int(setup["home"]), int(setup["away"]), setup["options"])
	_check(e.restart_type == (5 if waiting == 20 else waiting), "the restart taken up again")
	e.dispose()
	var g := ISSMatchEngine.new()
	g.setup(0, 1, {"pads": [0, 0], "half_seconds": 20, "knockout": true, "vgoal": 0})
	g.half = 2
	g.ball.live = true
	g._goal(1)
	frames = 0
	while not g.over and frames < 60 * 20:
		g.step([])
		frames += 1
	_check(g.over and not g.shootout and g.half == 2, "V-goal: a goal in extra time ends the match")
	g.dispose()


## A level knockout match goes through extra time to a shoot-out that ends
## with a winner; PK mode is a shoot-out on its own.
func _check_knockout() -> void:
	seed(21)
	var e := ISSMatchEngine.new()
	e.setup(0, 1, {"pads": [0, 0], "half_seconds": 20, "knockout": true, "vgoal": 1})
	var halves := {}
	var frames := 0
	while not e.over and frames < 60 * 60 * 20:
		if not e.shootout:
			e.teams[1].score = e.teams[0].score
		e.step([])
		halves[e.half] = true
		frames += 1
	_check(e.over and e.shootout and halves.size() == 5, "extra time then penalties")
	_check(e.pk_scores[0] != e.pk_scores[1] and e.pk_taken[0] >= 3, "the shoot-out has a winner")
	e.dispose()
	var p := ISSMatchEngine.new()
	p.setup(2, 3, {"pads": [0, 0], "pk_only": true})
	frames = 0
	while not p.over and frames < 60 * 60 * 10:
		p.step([])
		frames += 1
	_check(p.over and p.half == 4, "PK mode")
	p.dispose()


## Short league and tournament between computer teams, and a league that
## stops at the human team's games.
func _check_competitions() -> void:
	seed(4)
	var lg := ISSCompetition.league([0, 1, 2, 3, 4, 5], 0)
	lg.simulate_until_human()
	_check(lg.finished() and lg.games.size() == 15, "league: 15 games")
	var w := 0
	var l := 0
	for r: Dictionary in lg.table():
		_check(r["w"] + r["d"] + r["l"] == 5, "league: 5 games each")
		w += r["w"]
		l += r["l"]
	_check(w == l, "league: wins match losses")
	var t := lg.table()
	_check(t[0]["p"] >= t[5]["p"], "league: sorted by points")
	var cup := ISSCompetition.tournament([6, 7, 8, 9, 10, 11, 12, 13], 0)
	cup.simulate_until_human()
	_check(cup.finished() and cup.games.size() == 7 and cup.champion() >= 0, "tournament: 7 games, a champion")
	for r: Dictionary in cup.games:
		_check(r["hg"] != r["ag"] or not r["pk"].is_empty(), "tournament: every game has a winner")
	var mine := ISSCompetition.league([0, 1, 2, 3, 4, 5], 1)
	mine.simulate_until_human()
	_check(mine.games.is_empty() and mine.next_game() == [0, 2], "league: the human's first game comes first")
	mine.record(2, 1)
	mine.simulate_until_human()
	_check(mine.games.size() == 3 and mine.next_game() == [0, 4], "league: computer games played in between")


## Strategy button + dash picks the strategy on the dash slot; the offside
## trap puts the lines round the halfway line; three substitutions.
func _check_strategies_and_subs() -> void:
	seed(8)
	var e := ISSMatchEngine.new()
	e.setup(0, 1, {"pads": [1, 0], "half_seconds": 60, "strategies": [7, 1, 4, 0]})
	var idle := {"dir": -1, "press": 0, "held": 0}
	for i in 200:
		e.step([idle, null])
	var t := e.teams[0]
	e.step([{"dir": -1, "press": ISSFootballer.STRATEGY, "held": ISSFootballer.STRATEGY}, null])
	e.step([{"dir": -1, "press": ISSFootballer.DASH, "held": ISSFootballer.STRATEGY | ISSFootballer.DASH}, null])
	_check(t.strategy == 7, "strategy button + dash picks slot 0")
	# Give the ball to the opponents: the trap moves the lines up.
	e.restart_type = ISSMatchEngine.R.NONE
	e.ball.live = true
	e.ball.owner = e.teams[1].players[5]
	e.ball.team = 1
	t.apply_strategy()
	var mx := e.rect.get_center().x
	var d := e.attack_dir(0)
	_check(is_equal_approx(t.lines[1], mx) and is_equal_approx(t.lines[2], mx - 192.0 * d), "offside trap lines")
	e.step([{"dir": -1, "press": ISSFootballer.STRATEGY, "held": ISSFootballer.STRATEGY}, null])
	_check(t.strategy == -1, "strategy button alone switches it off")
	e.ball.owner = null
	var before := t.players[6].name
	_check(t.substitute(6, 0) and t.players[6].name != before and t.subs_left == 2, "substitution")
	_check(t.substitute(7, 0) and t.substitute(8, 0) and not t.substitute(9, 0), "three substitutions at most")
	e.dispose()


## The International Cup through to the final when the human side wins every
## game, out in the first round when it loses; the World Series; a scenario
## start; the training drills and the free kick wall.
func _check_long_modes() -> void:
	seed(12)
	var cup := ISSCompetition.international_cup(0)
	var played := 0
	while not cup.finished() and played < 100:
		cup.simulate_until_human()
		var g := cup.next_game()
		if g.is_empty():
			break
		cup.record(3 if cup.is_human(g[0]) else 0, 0 if cup.is_human(g[0]) else 3)
		played += 1
	_check(cup.finished() and cup.stage == 2 and cup.champion() == 0 and played == 2 + 3 + 4,
		"International Cup: 2 + 3 + 4 games to win it (%d)" % played)
	var out := ISSCompetition.international_cup(1)
	out.simulate_until_human()
	var g2 := out.next_game()
	out.record(0 if out.is_human(g2[0]) else 5, 5 if out.is_human(g2[0]) else 0)
	out.simulate_until_human()
	g2 = out.next_game()
	if not g2.is_empty():
		out.record(0 if out.is_human(g2[0]) else 5, 5 if out.is_human(g2[0]) else 0)
		out.simulate_until_human()
	_check(out.finished() and out.champion() == -1, "International Cup: knocked out")
	var ws := ISSCompetition.world_series(4)
	var mine := 0
	while not ws.finished():
		ws.simulate_until_human()
		var g := ws.next_game()
		if g.is_empty():
			break
		ws.record(2 if ws.is_human(g[0]) else 0, 0 if ws.is_human(g[0]) else 2)
		mine += 1
	_check(mine == 70 and ws.season_winners == [4, 4] and ws.champion() == 4, "World Series: two seasons of 35 games won")
	# Won the first season only: the Championship against the second's winner.
	var ws2 := ISSCompetition.world_series(4)
	while not ws2.finished():
		ws2.simulate_until_human()
		var g := ws2.next_game()
		if g.is_empty():
			break
		var win := ws2.season == 0 or ws2.in_championship()
		var human_home := ws2.is_human(g[0])
		ws2.record(2 if human_home == win else 0, 0 if human_home == win else 2)
	_check(ws2.season_winners.size() == 2 and ws2.season_winners[0] == 4 and ws2.season_winners[1] != 4 \
		and ws2.games.size() == 1 and ws2.champion() == 4, "World Series: the Championship")
	var e := ISSMatchEngine.new()
	var sc: Dictionary = ISSMatchData.consts["scenarios"][0]
	e.setup(int(sc["home"]), int(sc["away"]), {"pads": [0, 0], "scenario": sc})
	_check(e.teams[0].score == 1 and e.teams[1].score == 2 and e.half == 1 \
		and e.restart_type == ISSMatchEngine.R.CORNER and e.clock == 74 * 60, "scenario 1: Italy 1-2 Croatia, 1:14, corner")
	e.dispose()
	_check_training()
	_check_wall()
	_check_challenges()
	_check_controls()
	_check_man_marking()


## The four drills of restart_setup_practice: who is on, who has the ball,
## and that each one starts again once it is over.
func _check_training() -> void:
	seed(21)
	var practice := int(ISSMatchData.consts["training"]["team"])
	var expect := {0: [11, 0], 1: [-1, 3], 2: [6, 7], 3: [1, 2]}
	for d in 4:
		var t := ISSMatchEngine.new()
		t.setup(0, practice, {"pads": [0, 0], "training": d, "level": 4})
		var home := t.teams[0].active().size()
		var away := t.teams[1].active().size()
		var defenders := 0
		for p in t.teams[0].players:
			if p.role == 2:
				defenders += 1
		var want_home: int = expect[d][0] if expect[d][0] >= 0 else defenders
		_check(home == want_home and away == expect[d][1], "training %d: %d v %d players" % [d, home, away])
		match d:
			0:
				_check(t.restart_type == ISSMatchEngine.R.KICKOFF and t.restart_side == 0, "free training: home kick-off")
			1:
				_check(t.ball.owner == t.teams[1].players[8], "defence drill: attacker 8 has the ball")
			2:
				_check(t.restart_type == ISSMatchEngine.R.FREE_KICK and t.restart_side == 0 and t._wall.size() >= 3,
					"free kick drill: a free kick with a wall of %d" % t._wall.size())
			3:
				_check(t.ball.owner == t.teams[1].players[9] and t.teams[0].keeper_mode == 2,
					"keeper drill: attacker 9 has the ball, the pad has the keeper")
		if d == 0:
			t.dispose()
			continue
		var resets := 0
		var last: int = t.event_counts.get("drills", 0)
		for f in 60 * 90:
			t.step([{}, {}])
			if t.event_counts.get("drills", 0) != last:
				last = t.event_counts["drills"]
				resets += 1
				if resets == 2:
					break
		_check(resets == 2 and t.teams[1].active().size() == expect[d][1], "drill %d starts again (%d)" % [d, resets])
		t.dispose()
	# A human keeper: lofted with a direction dives that way.
	var k := ISSMatchEngine.new()
	k.setup(0, practice, {"pads": [1, 0], "training": 3})
	var keeper := k.teams[0].players[0]
	k.step([{"dir": 0, "press": ISSFootballer.LOFT, "held": ISSFootballer.LOFT}, {}])
	# keeper_side_dive keeps his facing and dives to that side of it.
	_check(keeper.state == ISSFootballer.S.KEEPER_DIVE and int(keeper.kick_heading) == 0 and keeper.action in [23, 24],
		"keeper drill: lofted + up dives up")
	k.dispose()


## restart_setup_free_kick: a wall of 6 for a free kick straight in front
## of the goal from 400 px, none from 700 px.
func _check_wall() -> void:
	var e := ISSMatchEngine.new()
	e.setup(0, 1, {"pads": [0, 0], "half_seconds": 60})
	var g := e.goal_center(1)
	e.start_restart(ISSMatchEngine.R.FREE_KICK, 0, Vector2(g.x - 400.0, g.y))
	_check(e._wall.size() == 6, "free kick: wall of 6 (%d)" % e._wall.size())
	for f in 200:
		e.step([{}, {}])
		if e.restart_phase == 1:
			break
	var at := true
	for p in e._wall:
		if p.state != ISSFootballer.S.SENT_OFF and absf(p.pos.distance_to(e.restart_pos) - 192.0) > 24.0:
			at = false
	_check(e.restart_phase == 1 and at, "free kick: the wall stands 192 px from the ball")
	e.start_restart(ISSMatchEngine.R.FREE_KICK, 0, Vector2(g.x - 700.0, g.y))
	_check(e._wall.is_empty(), "free kick: no wall from 700 px")
	e.dispose()


## The challenges: each event's players and ball, a CPU attempt to its end,
## the dribble cleared by taking the flags, the timer and the scores.
func _check_challenges() -> void:
	seed(5)
	var practice := int(ISSMatchData.consts["training"]["team"])
	var events: Array = ISSMatchData.consts["challenge"]["events"]
	for ev in 6:
		var e := ISSMatchEngine.new()
		e.setup(practice, practice, {"pads": [0, 0], "challenge": {"event": ev, "level": 3}, "level": 4, "stadium": 2})
		var spec: Dictionary = events[ev]
		var want_home := int(spec["home_counts"][3]) + (1 if spec.has("home_middle") else 0)
		var want_away := int(spec["away_counts"][3]) + (1 if spec.has("keeper_level") else 0)
		_check(e.teams[0].active().size() == want_home and e.teams[1].active().size() == want_away
			and e.ball.owner != null, "challenge %d: %d v %d, the ball held" % [ev, want_home, want_away])
		var frames := 0
		while not e.over and frames < 60 * 70:
			e.step([{}, {}])
			frames += 1
		_check(e.over, "challenge %d: the attempt ends (%d frames, %s)" % [ev, frames, "cleared" if e.ch_done else "missed"])
		e.dispose()
	# Dribble: the five flags clear it; a goal then keeps the bonus.
	var d := ISSMatchEngine.new()
	d.setup(practice, practice, {"pads": [1, 0], "challenge": {"event": 0, "level": 0}, "stadium": 2})
	var dribbler := d.teams[0].players[1]
	for f in d.ch_flags.duplicate():
		dribbler.pos = f
		d.step([{}, {}])
	d.step([{}, {}])
	_check(d.ch_done and d.ch_flags.is_empty(), "dribble: the five flags clear it")
	for f in 60:
		d.step([{}, {}])
	d._challenge_end(true)
	var r := d.challenge_result()
	var sc := ISSChallenge.score(r)
	_check(r["bonus_on"] and int(sc["bonus_score"]) > 0 and int(sc["total"]) == int(sc["time_score"]) + int(sc["bonus_score"]),
		"dribble: a goal keeps the bonus (%s)" % str(sc))
	d.dispose()
	# The timer: 60 frames are one second (29.00 after 30.00).
	var t := ISSMatchEngine.new()
	t.setup(practice, practice, {"pads": [1, 0], "challenge": {"event": 1, "level": 0}, "stadium": 2})
	for f in 60:
		t._time_tick(5)
	_check(t.ch_time == [2, 9, 0, 0], "challenge timer: one second in 60 frames (%s)" % str(t.ch_time))
	t.dispose()
	var s := ISSChallenge.score({"done": true, "bonus_on": false, "time": [2, 0, 3, 2], "bonus": [1, 0, 0, 0]})
	_check(s["time_taken"] == 968 and s["time_score"] == 203 and s["total"] == 203, "challenge scores: %s" % str(s))


## The controls: the button layouts, TYPE A switching, Mode + Y and the
## goalkeeper modes (match_players_update, ai_func_00F91A_8).
func _check_controls() -> void:
	_check(ISSInput.logical(ISSInput.B, 0) == ISSFootballer.PASS and ISSInput.logical(ISSInput.C, 0) == ISSFootballer.LOFT
		and ISSInput.logical(ISSInput.A, 0) == ISSFootballer.DASH and ISSInput.logical(ISSInput.Z, 0) == ISSFootballer.SHOOT,
		"layout 0: B pass, C high ball, A dash, Z shoot")
	_check(ISSInput.logical(ISSInput.C, 1) == ISSFootballer.SHOOT, "layout 1: C shoots")
	var e := ISSMatchEngine.new()
	e.setup(0, 1, {"pads": [1, 0], "half_seconds": 60, "keepers": [1, 0]})
	var idle := {"dir": -1, "press": 0, "held": 0}
	while e.restart_type != ISSMatchEngine.R.NONE:
		e.step([{"dir": 16, "press": ISSFootballer.PASS, "held": 0} if e.restart_taker != null and e.restart_taker.team == 0 else idle])
	e.ball.owner = null
	e.ball.stop()
	e.ball.team = 0
	e.ball.pos = e.teams[0].players[8].pos + Vector2(30, 0)
	e.slots[0].player = e.teams[0].players[2]
	e.step([{"dir": -1, "press": ISSFootballer.SWITCH, "held": ISSFootballer.SWITCH}])
	_check(e.slots[0].player != e.teams[0].players[2] and e.slots[0].player.index != 0,
		"TYPE A: Y passes control on (%d)" % e.slots[0].player.index)
	e.step([idle])
	# With the ball dead nobody takes it (kicker_claim would hand him over).
	e.ball.live = false
	e.slots[0].manual = 1
	e.step([{"dir": -1, "press": ISSFootballer.SWITCH, "held": ISSFootballer.SWITCH | ISSFootballer.STRATEGY}])
	_check(e.slots[0].player == e.teams[0].players[0], "SEMI-AUTO keeper: Mode + Y takes him")
	for i in 20:
		e.step([idle])
	_check(e.slots[0].player == e.teams[0].players[0], "SEMI-AUTO keeper: kept")
	e.teams[0].keeper_mode = 0
	for i in 20:
		e.step([idle])
	_check(e.slots[0].player != e.teams[0].players[0], "AUTO keeper: given back to the computer")
	e.dispose()


## Man-marking (obj_mark from screen_man_marking): a defender told to mark
## the opponents' number 9 keeps goal side of him while either team has the
## ball; the bridge takes +$54 from the player objects.
func _check_man_marking() -> void:
	seed(11)
	var dist := [0.0, 0.0]
	for run in 2:
		var e := ISSMatchEngine.new()
		e.setup(0, 1, {"stadium": 0, "weather": 1, "time": 1, "level": 2, "pads": [0, 0], "half_seconds": 60})
		var marker := e.teams[0].players[2]
		var target := e.teams[1].players[9]
		if run == 1:
			marker.mark = 9
		var n := 0
		var goal_side := 0
		for f in 60 * 40:
			e.step([])
			if e.ball.owner != null and e.ball.owner != marker and e.restart_type == ISSMatchEngine.R.NONE:
				dist[run] += marker.pos.distance_to(target.pos)
				n += 1
				if (target.pos.x - marker.pos.x) * e.attack_dir(0) >= 0.0:
					goal_side += 1
		dist[run] /= maxi(n, 1)
		if run == 1:
			_check(marker.ai_mode == ISSTeam.AI.MARK or e.ball.owner == null or e.restart_type != ISSMatchEngine.R.NONE \
				or marker.ai_mode == ISSTeam.AI.CHASE or marker.ai_mode == ISSTeam.AI.CARRY, "marker in mark mode")
			_check(goal_side * 3 > n * 2, "marker goal side of his man (%d of %d frames)" % [goal_side, n])
		e.dispose()
	# The marker walks to 24 px goal side of his man, re-aimed every 16
	# frames, so he trails a running opponent.
	_check(dist[1] < 120.0 and dist[1] * 2.0 < dist[0], "man-marking keeps close (%.0f px, %.0f unmarked)" % [dist[1], dist[0]])
	ISSRam.ensure()
	var obj: int = ISSSym.g_team_home_players + 2 * ISSModes.PLAYER_SIZE
	ISSRam.set_b(obj + 0x54, 9)
	_check(int(ISSMatchSetup.squad(0)[2]["mark"]) == 9, "bridge: obj_mark")
	ISSRam.set_b(obj + 0x54, 0xFF)
	_check(int(ISSMatchSetup.squad(0)[2]["mark"]) == -1, "bridge: no marking")
