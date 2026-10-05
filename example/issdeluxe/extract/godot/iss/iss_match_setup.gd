class_name ISSMatchSetup
extends RefCounted
## The bridge from the front end to the match: the menus leave the match
## set up in the game's RAM as the cartridge does (teams, stadium, weather,
## time of day, the teams' state with formation, strategies and handicap,
## the 20 player objects a side with their records, energy and places,
## the controllers), and the match engine takes it as options.

const S := preload("res://iss/iss_sym.gd")
const POSITIONS := ["forward", "midfielder", "defender", "goalkeeper", "attacking type 4", "defensive type 5"]
const ROLES := ["attack", "midfield", "defence", "goalkeeper"]
const ATTRIBUTES := ["speed", "dash", "shot_power", "curl", "intelligence", "balance", "jump", "dribble", "stamina"]


static func _w(a: int) -> int:
	return ISSRam.w(a)


## {"home", "away", "options"} for ISSMatch.start.
static func from_ram() -> Dictionary:
	var home := _w(S.g_team_home)
	var away := _w(S.g_team_away)
	var info := [S.g_team_home_info, S.g_team_away_info]
	var opts := {}
	opts["stadium"] = _w(S.g_stadium)
	opts["weather"] = _w(S.g_weather)
	opts["time_of_day"] = _w(0x1630)
	opts["level"] = _w(S.g_game_level)
	opts["time"] = _w(S.g_game_time)
	opts["referee"] = _w(S.g_officials_kit)
	opts["fouls"] = _w(S.g_opt_fouls_off) == 0
	opts["cards"] = _w(S.g_opt_cards_off) == 0
	opts["offside"] = _w(S.g_opt_offside_off) == 0
	opts["vgoal"] = _w(S.g_opt_vgoal)
	opts["knockout"] = _w(S.g_knockout) != 0
	# Mode $B: the attract demo (a minute of play, Start leaves).
	opts["demo"] = _w(S.g_game_mode) == 0xB
	opts["pads"] = [_w(S.g_pads_home), _w(S.g_pads_away)]
	opts["kits"] = [_w(S.g_kit_home), _w(S.g_kit_away)]
	var formations := []
	var conditions := []
	var players := []
	var keepers := []
	var skills := []
	var strategies := []
	for side in 2:
		var t: int = info[side]
		formations.append(_w(t + ISSModes.TM_FORMATION))
		conditions.append(_w(t + ISSModes.TM_CONDITION))
		players.append(_w(t + ISSModes.TM_PLAYERS) + 7)
		keepers.append(_w(t + ISSModes.TM_KEEPER_MANUAL))
		skills.append(_w(t + ISSModes.TM_KEEPER_SKILL))
		var slots := []
		for i in 4:
			slots.append(ISSRam.sw(t + ISSModes.TM_STRATEGY_SLOTS + 2 * i))
		strategies.append(slots)
	opts["formations"] = formations
	opts["conditions"] = conditions
	opts["players"] = players
	opts["keepers"] = keepers
	opts["keeper_skills"] = skills
	opts["strategies_by_side"] = strategies
	opts["squads"] = [squad(0), squad(1)]
	opts["controllers"] = controllers()
	# The match so far (state_match plays one half and starts it from here).
	opts["half"] = _w(S.g_half)
	opts["left_goal_team"] = _w(S.g_left_goal_team)
	opts["kickoff_team"] = _w(0x1634)
	opts["clock"] = clock_frames()
	opts["scores"] = [_w(S.g_score_home), _w(S.g_score_away)]
	var stats := []
	for base in [S.g_stats_home, S.g_stats_away]:
		var words := []
		for i in 8:
			words.append(_w(base + 2 * i))
		stats.append(words)
	opts["stats"] = stats
	opts["scorers"] = scorers()
	opts["restart"] = {"type": ISSRam.sw(S.g_restart_type), "team": ISSRam.sw(S.g_restart_team),
		"x": ISSRam.sw(S.g_restart_x), "y": ISSRam.sw(S.g_restart_y)}
	# Training (restart $C) plays the drill g_training_drill; the
	# challenges (restart $D) the event g_training_drill at g_challenge_level.
	match ISSRam.sw(S.g_restart_type):
		0xC:
			opts["training"] = _w(S.g_training_drill)
		0xD:
			opts["challenge"] = {"event": _w(S.g_training_drill), "level": _w(S.g_challenge_level)}
		ISSMatchEngine.R.PENALTY_SPOT:
			# Back from the shoot-out's view: the kicker (the first in the
			# side's order), the kick's aim ($14F2) and power ($14F4), the
			# keeper's direction ($14F6) and buttons ($14F8).
			var side := ISSRam.sw(S.g_restart_team)
			opts["penalty"] = {"order0": _w(0x14FE if side == 0 else 0x1512), "aim": ISSRam.sw(0x14F2),
				"power": _w(0x14F4), "dive_dir": _w(0x14F6), "dive_input": _w(0x14F8)}
	return {"home": home, "away": away, "options": opts}


## The challenge's result where screen_challenge_record reads it: the time
## left and the bonus as four decimal digits, $B in g_challenge_count when
## the task was done and in g_challenge_bonus_on when the bonus counted.
static func challenge_to_ram(e: ISSMatchEngine) -> void:
	for i in 4:
		ISSRam.set_b(S.g_challenge_time + i, int(e.ch_time[i]))
		ISSRam.set_b(S.g_challenge_bonus + i, int(e.ch_bonus[i]))
	ISSRam.set_w(S.g_challenge_count, 0xB if e.ch_done else e.ch_count)
	ISSRam.set_w(S.g_challenge_bonus_on, 0xB if e.ch_bonus_on else 0)


## g_match_clock (minutes, tens of seconds, seconds, frames) in frames.
static func clock_frames() -> int:
	var c := S.g_match_clock
	return ((ISSRam.b(c) * 60 + ISSRam.b(c + 1) * 10 + ISSRam.b(c + 2)) * 60) + ISSRam.b(c + 3)


static func _set_clock(frames: int) -> void:
	var f := maxi(0, frames)
	var secs := f / 60
	ISSRam.set_b(S.g_match_clock, secs / 60)
	ISSRam.set_b(S.g_match_clock + 1, (secs % 60) / 10)
	ISSRam.set_b(S.g_match_clock + 2, secs % 10)
	ISSRam.set_b(S.g_match_clock + 3, f % 60)


## g_scorers: one 6-byte entry per goal so far (up to 32).
static func scorers() -> Array:
	var out := []
	var n := mini(32, _w(S.g_score_home) + _w(S.g_score_away))
	for i in n:
		var a := S.g_scorers + i * 6
		out.append({"seconds": _w(a), "half": ISSRam.b(a + 2), "side": ISSRam.b(a + 3),
			"team": ISSRam.b(a + 4), "record": ISSRam.b(a + 5), "name": "", "minute": _w(a) / 60,
			"own_goal": ISSRam.b(a + 3) != ISSRam.b(a + 4)})
	return out


## The match back into RAM where state_match leaves it: scores, statistics,
## scorers, the clock and the restart waiting, the match menu requests,
## and each player's energy (+$57), status (g_player_status) and whether he
## is off the pitch (+$55: sent off).
static func to_ram(e: ISSMatchEngine) -> void:
	for s in 2:
		var t: ISSTeam = e.teams[s]
		var base: int = S.g_stats_home if s == 0 else S.g_stats_away
		for i in ISSMatchEngine.STAT_KEYS.size():
			ISSRam.set_w(base + 2 * i, int(t.stats.get(ISSMatchEngine.STAT_KEYS[i], 0)))
		ISSRam.set_w(S.g_score_home if s == 0 else S.g_score_away, t.score)
	for i in mini(32, e.scorers.size()):
		var g: Dictionary = e.scorers[i]
		var a := S.g_scorers + i * 6
		ISSRam.set_w(a, int(g.get("seconds", 0)))
		ISSRam.set_b(a + 2, int(g.get("half", e.half)))
		ISSRam.set_b(a + 3, int(g.get("side", 0)))
		ISSRam.set_b(a + 4, int(g.get("team", g.get("side", 0))))
		ISSRam.set_b(a + 5, int(g.get("record", 0)))
	_set_clock(e.clock)
	var type := e.restart_type
	if type == ISSMatchEngine.R.OFFSIDE:
		type = ISSMatchEngine.R.FREE_KICK
	ISSRam.set_w(S.g_restart_type, type & 0xFFFF)
	ISSRam.set_w(S.g_restart_team, e.restart_side)
	ISSRam.set_w(S.g_restart_x, int(e.restart_pos.x) & 0xFFFF)
	ISSRam.set_w(S.g_restart_y, int(e.restart_pos.y) & 0xFFFF)
	ISSRam.set_w(0x182A, int(e.menu_request[0]))
	ISSRam.set_w(0x18B2, int(e.menu_request[1]))
	for s in 2:
		var t: ISSTeam = e.teams[s]
		var obj: int = S.g_team_home_players if s == 0 else S.g_team_away_players
		var status: int = S.g_player_status + _w(0x1642 if s == 0 else 0x1644) * 20
		for p in t.players:
			if p.ram_slot < 0:
				continue
			var a := obj + p.ram_slot * ISSModes.PLAYER_SIZE
			ISSRam.set_b(a + 0x57, clampi(p.energy, 0, 255))
			if p.state == ISSFootballer.S.SENT_OFF:
				ISSRam.set_b(a + 0x55, 1)
			ISSRam.set_b(status + p.record, p.status)


## One side's 20 player objects in their order: the squad index (+$56),
## the record (+$5A: nine attributes, number, hair, position), energy
## (+$57) and, for the eleven, the place in the formation (+$51 role, +$52
## / $53 x / y).
static func squad(side: int) -> Array:
	var out := []
	var obj: int = S.g_team_home_players if side == 0 else S.g_team_away_players
	var status: int = S.g_player_status + _w(0x1642 if side == 0 else 0x1644) * 20
	for k in 20:
		var attrs := {}
		for i in ATTRIBUTES.size():
			attrs[ATTRIBUTES[i]] = ISSRam.b(obj + 0x5A + i)
		var e := {
			"index": ISSRam.b(obj + 0x56),
			"attributes": attrs,
			"number": ISSRam.b(obj + 0x63),
			"hair": ISSRam.b(obj + 0x64),
			"position": POSITIONS[clampi(ISSRam.b(obj + 0x65), 0, 5)],
			"energy": ISSRam.b(obj + 0x57),
			"mark": ISSRam.b(obj + 0x54) if ISSRam.b(obj + 0x54) < 0x80 else -1,
			"ram": k,
			"status": ISSRam.b(status + ISSRam.b(obj + 0x56)),
			"off": ISSRam.b(obj + 0x55) != 0,
		}
		var role := ISSRam.b(obj + 0x51)
		if k < 11 and role < ROLES.size():
			e["slot"] = {"role": ROLES[role], "form_x": ISSRam.b(obj + 0x52), "form_y": ISSRam.b(obj + 0x53)}
		out.append(e)
		obj += ISSModes.PLAYER_SIZE
	return out


## The controllers in pad order: the home side's slots (g_control_slots),
## then the away side's ($15C4): pad type (+8, 0 = a 3-button pad, whose
## pause menu offers the strategies and the match menu), player switch type
## (+$A), area (+$C), cursor change (+$E) and button layout (+$18). The
## layouts go to ISSInput.
static func controllers() -> Array:
	var out := []
	var pad := 0
	for side in 2:
		var base: int = S.g_control_slots if side == 0 else 0x15C4
		for i in _w(S.g_pads_home if side == 0 else S.g_pads_away):
			var a := base + i * 0x1A
			out.append({"side": side, "six": _w(a + 8) != 0, "type": _w(a + 0xA), "area": _w(a + 0xC), "manual": _w(a + 0xE)})
			if pad < ISSInput.layouts.size():
				ISSInput.layouts[pad] = clampi(_w(a + 0x18) / 16, 0, 23)
			pad += 1
	return out
