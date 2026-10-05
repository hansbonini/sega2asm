class_name ISSModes
extends RefCounted
## The game modes' RAM set-up as the main menu starts them (mode_start_*).
## g_game_mode: 0 training, 1 challenge, 2 PK, 3 open game, 4 short league,
## 5 short tournament, 6-8 International Cup rounds, 9 World Series,
## $A Championship, $B demo, $C scenario.

const S := preload("res://iss/iss_sym.gd")


static func _w(a: int, v: int) -> void:
	ISSRam.set_w(a, v)


static func _clear_status(n: int) -> void:
	ISSRam.clear(S.g_player_status, n)


## mode_start_pk: penalty shoot-out, England (0) against team 6 by default.
static func start_pk() -> void:
	_w(S.g_game_mode, 2)
	_w(S.g_knockout, 1)
	_w(0x1276, 0)
	_w(0x126A, 0)
	_w(0x1268, 0)
	_w(0x1264, 2)
	_w(0x1266, 2)
	_w(S.g_game_level, ISSRam.w(S.g_settings))
	_w(0x127C, 0)
	_w(0x127E, 6)
	_clear_status(0x28)
	_w(S.g_shootout_kicks, 0)
	_w(0x14FA, 0)
	_w(0x14FC, 0)
	for i in 10:
		_w(0x1526 + 2 * i, 0xFFFF)
	_w(0x153A, 0)
	_w(0x153C, 0)
	for i in 10:
		_w(0x14FE + 2 * i, 10 - i)
		_w(0x1512 + 2 * i, 10 - i)
	_w(0x153E, 1)
	_w(S.g_pads_home, 1)
	_w(S.g_pads_away, 0)
	_w(S.g_restart_team, 0)


## mode_start_international: the International Cup's elimination round.
static func start_international() -> void:
	_w(S.g_game_mode, 6)
	_w(S.g_knockout, 0)
	_w(0x1276, 1)
	_w(0x1268, 1)
	_w(0x1264, 1)
	_w(0x127C, 0)
	_w(S.g_game_level, ISSRam.w(S.g_settings))
	_w(0x1270, 0)
	_w(0x1272, 0xFFFF)
	_w(0x126A, 0)
	_w(0x127A, 0)
	_w(0x1266, 1)
	_clear_status(0x3C)
	_w(0x153E, 1)
	_w(S.g_pads_home, 1)
	_w(S.g_pads_away, 0)


## mode_start_world_series: season 1 of the World Series.
static func start_world_series() -> void:
	_w(S.g_game_mode, 9)
	_w(S.g_knockout, 1)
	_w(0x1276, 1)
	_w(0x1268, 1)
	_w(0x1264, 1)
	_w(0x127C, 0)
	_w(0x127E, 0)
	_w(0x1280, 0)
	_w(0x1266, 1)
	_w(S.g_game_level, ISSRam.w(S.g_settings))
	_w(0x1270, 0)
	_w(0x1272, 0xFFFF)
	_w(0x126A, 0)
	_w(0x127A, 0)
	_clear_status(0x28)
	_w(0x153E, 1)
	_w(S.g_pads_home, 1)
	_w(S.g_pads_away, 0)
	ISSRam.clear(0x129C, 0x48)
	_w(0x126C, 0)
	# The VDP's HV counter & 7: a random 0-7.
	_w(0x126E, randi() & 7)


## mode_start_scenario.
static func start_scenario() -> void:
	_w(S.g_game_mode, 0xC)
	_w(S.g_knockout, 0)
	_w(0x126A, 0)
	_w(0x1276, 1)
	_w(0x1268, 1)
	_w(0x1264, 1)
	_w(0x1266, 1)
	_w(S.g_game_level, ISSRam.w(S.g_settings))
	_w(0x1272, 0xFFFF)
	_clear_status(0x28)
	_w(0x1270, 0)
	ISSRam.clear(0x129C, 0x18)


## mode_start_training: the training mode (0) with the chosen team.
static func mode_start_training() -> void:
	_w(S.g_game_mode, 0)
	_w(0x1276, 0)
	_w(0x126A, 0)
	_w(0x1264, 1)
	_w(0x1266, 1)
	_w(S.g_game_level, 4)
	_w(0x127C, 0)
	_clear_status(0x28)
	_w(0x153E, 1)
	_w(S.g_pads_home, 1)
	_w(S.g_pads_away, 0)


## mode_start_challenge: the challenges (1), the practice team ($2A).
static func mode_start_challenge() -> void:
	_w(S.g_game_mode, 1)
	_w(0x1276, 0)
	_w(0x126A, 0)
	_w(0x1264, 1)
	_w(0x1266, 1)
	_w(S.g_game_level, 4)
	_w(0x127C, 0x2A)
	_w(0x127E, 0x2A)
	_clear_status(0x28)
	_w(0x153E, 1)
	_w(S.g_pads_home, 1)
	_w(S.g_pads_away, 0)


## training_challenge_menu_4: the challenges' match, the practice team on
## both sides in stadium 2 (restart $D), no restarts and practice rules.
static func challenge_setup() -> void:
	_w(S.g_training_drill, 0)
	_w(0x1638, 0)
	_w(0x1634, 0)
	_w(S.g_left_goal_team, 0)
	_w(S.g_restart_type, 0xD)
	_w(S.g_team_home, 0x2A)
	_w(S.g_team_away, 0x2A)
	_w(0x1642, 0)
	_w(S.g_stadium, 2)
	_w(S.g_weather, 1)
	_w(S.g_game_time, 0)
	_w(S.g_training, 1)
	_w(S.g_no_restarts, 1)
	team_info_init()


## mode_start_open_game: open game, England against team 6 by default.
static func start_open_game() -> void:
	_w(S.g_game_mode, 3)
	_w(0x1268, 0)
	_w(0x1276, 0)
	_w(S.g_knockout, 1)
	_w(0x1264, 2)
	_w(0x1266, 2)
	_w(0x127C, 0)
	_w(0x127E, 6)
	_w(S.g_game_level, ISSRam.w(S.g_settings))
	_w(0x1270, 0)
	_w(0x1272, 0xFFFF)
	_w(0x126A, 0)
	_w(0x127A, 0)
	_clear_status(0x28)
	_w(0x153E, 1)
	_w(S.g_pads_home, 1)
	_w(S.g_pads_away, 0)


## mode_start_short_league: six teams.
static func start_short_league() -> void:
	_w(S.g_game_mode, 4)
	_w(S.g_knockout, 0)
	_w(0x1276, 1)
	_w(0x1268, 1)
	_w(0x1264, 6)
	_w(0x127C, 0)
	_w(S.g_game_level, ISSRam.w(S.g_settings))
	_w(0x1270, 0)
	_w(0x1272, 0xFFFF)
	_w(0x126A, 0)
	_w(0x127A, 0)
	_clear_status(0x78)
	_w(0x153E, 0)
	_w(S.g_pads_home, 0)
	_w(S.g_pads_away, 0)


## mode_start_short_tournament: eight teams.
static func start_short_tournament() -> void:
	_w(S.g_game_mode, 5)
	_w(S.g_knockout, 1)
	_w(0x1276, 1)
	_w(0x1268, 1)
	_w(0x1264, 8)
	_w(0x127C, 0)
	_w(S.g_game_level, ISSRam.w(S.g_settings))
	_w(0x1270, 0)
	_w(0x1272, 0xFFFF)
	_w(0x126A, 0)
	_w(0x127A, 0)
	_clear_status(0xA0)
	_w(0x153E, 0)
	_w(S.g_pads_home, 0)
	_w(S.g_pads_away, 0)


# --------------------------------------------------------------------------
# Match set-up in RAM (what the pre-match screens then change).

const TM_KEEPER_MANUAL := 0x10
const TM_AI_LEVEL := 0x12
const TM_RATINGS := 0x1E
const TM_STRATEGY_ON := 0x2A
const TM_STRATEGY_LABEL := 0x2C
const TM_STRATEGY_SLOTS := 0x2E
const TM_FORMATION := 0x5C
const TM_CONDITION := 0x5E
const TM_PLAYERS := 0x60
const TM_KEEPER_SKILL := 0x62
## Player objects (20 a side, $8E bytes): +$4A side, +$51 role (6 = bench),
## +$52 / $53 formation x / y, +$54, +$55-$65 the block the squad screen
## swaps (+$56 squad index, +$57 energy, +$58 stamina drain, +$5A-$65 the
## 12-byte record of tbl_player_data: attributes, ..., position).
const PLAYER_SIZE := 0x8E


## The game's random step: g_random rotated left one bit (rol.w #1), and
## when the bit rotated out is set, exclusive-or $37E8.
static func _rand() -> int:
	var v := ISSRam.w(S.g_random)
	var carry := v & 0x8000
	v = ((v << 1) | (v >> 15)) & 0xFFFF
	if carry:
		v ^= 0x37E8
	ISSRam.set_w(S.g_random, v)
	return v


## rules_input_01487E: both teams' match state (struct team) and their 20
## player objects from g_team_home / g_team_away: handicap defaults,
## strategies cleared, ratings, kits (the second when they clash), kit
## palettes, player records, suspended starters replaced from the bench,
## the teams' own formations, edit points and energy.
static func team_info_init() -> void:
	ISSRam.set_l(0x1814, 0x0001E000)
	ISSRam.set_l(0x1818, ISSRom.addr("misc_data_024000"))
	_w(0x182A, 0)
	_w(0x18B2, 0)
	_w(0x182C, 0)
	_w(0x18B4, 0)
	ISSRam.set_l(0x1896, 0xFF20F6)
	ISSRam.set_l(0x189A, 0xFF20F6)
	ISSRam.set_l(0x189E, 0xFF1FDA)
	ISSRam.set_l(0x18A2, 0xFF2068)
	ISSRam.set_l(0x191E, 0xFF2C0E)
	ISSRam.set_l(0x1922, 0xFF2C0E)
	ISSRam.set_l(0x1926, 0xFF2AF2)
	ISSRam.set_l(0x192A, 0xFF2B80)
	_w(0x1836, 3)
	_w(0x18BE, 3)
	_w(0x1838, 1)
	_w(0x18C0, 1)
	var home := S.g_team_home_info
	var away := S.g_team_away_info
	for t in [home, away]:
		_w(t + TM_KEEPER_MANUAL, 0)
		_w(t + TM_CONDITION, 5)
		_w(t + TM_PLAYERS, 4)
		_w(t + TM_AI_LEVEL, 2)
		_w(t + TM_KEEPER_SKILL, 2)
	var level := ISSRam.w(S.g_game_level)
	if ISSRam.w(S.g_pads_home) == 0:
		_w(home + TM_AI_LEVEL, level)
		_w(home + TM_KEEPER_SKILL, level)
	if ISSRam.w(S.g_pads_away) == 0:
		_w(away + TM_AI_LEVEL, level)
		_w(away + TM_KEEPER_SKILL, level)
	for t in [home, away]:
		_w(t + TM_STRATEGY_ON, 1)
		_w(t + TM_STRATEGY_LABEL, 2)
		for i in 4:
			_w(t + TM_STRATEGY_SLOTS + 2 * i, 0xFFFF)
	var teams := [ISSRam.w(S.g_team_home), ISSRam.w(S.g_team_away)]
	for side in 2:
		var t: int = [home, away][side]
		for i in 5:
			ISSRam.set_b(t + TM_RATINGS + i, ISSRom.u8(ISSRom.addr("tbl_team_ratings") + teams[side] * 5 + i))
	var clash := ISSRom.addr("tbl_kit_clash")
	_w(S.g_kit_home, 0)
	_w(S.g_kit_away, 1 if ISSRom.u16(clash + teams[0] * 2) == ISSRom.u16(clash + teams[1] * 2) else 0)
	var pals := ISSRom.res(6, 12)
	for side in 2:
		var dst: int = [0x185A, 0x18E2][side]
		for i in 32:
			ISSRam.set_b(dst + i, pals[teams[side] * 32 + i])
	for side in 2:
		var rec := ISSRom.u32(ISSRom.addr("tbl_player_data") + teams[side] * 4)
		var status: int = S.g_player_status + ISSRam.w([0x1642, 0x1644][side]) * 20
		var obj: int = [S.g_team_home_players, S.g_team_away_players][side]
		for k in 20:
			for i in 12:
				ISSRam.set_b(obj + 0x5A + i, ISSRom.u8(rec + i))
			rec += 12
			_w(obj + 0x4A, side)
			ISSRam.set_b(obj + 0x56, k)
			var st := ISSRam.b(status + k)
			if st & 0x80 == 0:
				if st == 4:
					ISSRam.set_b(status + k, 0)
			elif st & 7 >= 3:
				ISSRam.set_b(status + k, 4)
			else:
				ISSRam.set_b(status + k, st & 7)
			_w(obj + 0x58, ISSRom.u16(ISSRom.addr("tbl_stamina_drain") + ISSRam.b(obj + 0x62) * 2))
			ISSRam.set_b(obj + 0x55, 0)
			ISSRam.set_b(obj + 0x0F, 0)
			ISSRam.set_b(obj + 0x54, 0xFF)
			obj += PLAYER_SIZE
	for side in 2:
		_replace_suspended(side)
	for side in 2:
		_team_formation(side)
	for side in 2:
		edit_points_reset(side)
	_energy()
	_w(0x1544, 0)
	_w(0x1546, 0)


## rules_func_014D3E / 014D64: the side's points for the edit player screen
## (tbl_edit_points, 999 with code 3), all (tm +$14) and left (+$16).
static func edit_points_reset(side: int) -> void:
	var team := ISSRam.w([S.g_team_home, S.g_team_away][side])
	var v := 999 if ISSRam.w(0x125C) != 0 else ISSRom.u16(ISSRom.addr("tbl_edit_points") + team * 2)
	var t: int = [S.g_team_home_info, S.g_team_away_info][side]
	_w(t + 0x14, v)
	_w(t + 0x16, v)


## rules_input_01487E_1 / _2: a suspended starter (status 4) changes
## places with the first available substitute of his position (or the last
## available one).
static func _replace_suspended(side: int) -> void:
	var status: int = S.g_player_status + ISSRam.w([0x1642, 0x1644][side]) * 20
	var base: int = [S.g_team_home_players, S.g_team_away_players][side]
	for k in range(1, 11):
		var a4 := base + k * PLAYER_SIZE
		if ISSRam.b(status + k) != 4:
			continue
		var a0 := -1
		var a3 := base + 12 * PLAYER_SIZE
		for i in 8:
			if ISSRam.b(status + ISSRam.b(a3 + 0x56)) != 4:
				a0 = a3
				if ISSRam.b(a0 + 0x65) == ISSRam.b(a4 + 0x65):
					break
			a3 += PLAYER_SIZE
		if a0 < 0:
			continue
		for i in 0x11:
			var t := ISSRam.b(a4 + 0x55 + i)
			ISSRam.set_b(a4 + 0x55 + i, ISSRam.b(a0 + 0x55 + i))
			ISSRam.set_b(a0 + 0x55 + i, t)


## rules_func_014C9A / 014CEC: the team's own formation (tbl_team_formations)
## and the starters' places in it; the bench has role 6.
static func _team_formation(side: int) -> void:
	var team := ISSRam.w([S.g_team_home, S.g_team_away][side])
	var a := ISSRom.u32(ISSRom.addr("tbl_team_formations") + team * 4)
	_w([S.g_team_home_info, S.g_team_away_info][side] + TM_FORMATION, ISSRom.s8(a))
	a += 1
	var obj: int = [S.g_team_home_players, S.g_team_away_players][side]
	for k in 20:
		if k < 11:
			ISSRam.set_b(obj + 0x52, ISSRom.u8(a))
			ISSRam.set_b(obj + 0x53, ISSRom.u8(a + 1))
			ISSRam.set_b(obj + 0x51, ISSRom.u8(a + 2))
			a += 3
		else:
			ISSRam.set_b(obj + 0x52, 0)
			ISSRam.set_b(obj + 0x53, 0)
			ISSRam.set_b(obj + 0x51, 6)
		obj += PLAYER_SIZE


## rules_func_014D8A: each player's energy from the team's condition, or
## at random from [1, 2, 2, 3, 3, 3, 4, 4] for condition 5.
static func _energy() -> void:
	var tbl := ISSRom.addr("tbl_random_condition")
	for side in 2:
		var cond := ISSRam.w([S.g_team_home_info, S.g_team_away_info][side] + TM_CONDITION)
		var obj: int = [S.g_team_home_players, S.g_team_away_players][side]
		for k in 20:
			if cond != 5:
				ISSRam.set_b(obj + 0x57, cond)
			else:
				ISSRam.set_b(obj + 0x57, ISSRom.u8(tbl + (_rand() & 7)))
			obj += PLAYER_SIZE


## match_stats_clear.
static func match_stats_clear() -> void:
	_w(S.g_training, 0)
	_w(S.g_no_restarts, 0)
	for a in [S.g_stats_home, 0x1650, 0x1652, 0x1654, 0x1656, 0x1658, 0x165A, S.g_score_home,
			S.g_stats_away, 0x1660, 0x1662, 0x1664, 0x1666, 0x1668, 0x166A, S.g_score_away]:
		_w(a, 0)


## The clock at the start of the first half: 2 * g_game_time + 1 minutes.
static func _clock_start() -> void:
	_w(S.g_half, 0)
	_w(S.g_restart_timer, 0)
	ISSRam.set_l(S.g_match_clock, 0)
	ISSRam.set_b(S.g_match_clock, ISSRam.w(S.g_game_time) * 2 + 1)


## menu_func_05AEAC: an open game (and the scenarios, the PK code ...):
## kick-off sides at random, stadium 0 in fine weather, the referee (3 =
## any of the three), a random time of day ($1630), the game time from
## the options, then the teams.
static func open_game_setup() -> void:
	_w(0x1638, 0)
	_w(0x1634, randi() & 1)
	_w(S.g_left_goal_team, 0)
	_w(S.g_restart_type, 4)
	_w(S.g_stadium, 0)
	_w(S.g_weather, 1)
	var ref := ISSRam.w(S.g_opt_referee)
	_w(S.g_officials_kit, randi() % 3 if ref == 3 else ref)
	_w(0x1630, randi() % 3)
	_w(S.g_game_time, ISSRam.w(S.g_opt_time))
	_clock_start()
	match_stats_clear()
	_w(S.g_team_home, ISSRam.w(0x127C))
	_w(S.g_team_away, ISSRam.w(0x127E))
	_w(0x1642, 0)
	_w(0x1644, 1)
	team_info_init()


## menu_state_03E8F0_2: training, the chosen team against the practice team
## ($2A, second kit) in stadium 0, restart 12 (the drill).
static func training_setup() -> void:
	_w(S.g_training_drill, 0)
	_w(0x1638, 0)
	_w(0x1634, 0)
	_w(S.g_left_goal_team, 0)
	_w(S.g_restart_type, 0xC)
	_w(S.g_team_home, ISSRam.w(0x127C))
	_w(S.g_team_away, 0x2A)
	_w(0x1642, 0)
	_w(S.g_stadium, 0)
	_w(S.g_weather, 1)
	_w(S.g_game_time, 0)
	_w(S.g_training, 1)
	team_info_init()
	_w(S.g_kit_away, 1)


## menu_state_03E8F0_3: PK, the two chosen teams in stadium 0.
static func pk_setup() -> void:
	_w(S.g_team_home, ISSRam.w(0x127C))
	_w(S.g_team_away, ISSRam.w(0x127E))
	_w(0x1642, 0)
	_w(0x1644, 1)
	_w(S.g_stadium, 0)
	_w(S.g_weather, 1)
	_w(0x1638, 0)
	_w(0x17D8, 0)
	team_info_init()


# --------------------------------------------------------------------------
# After the match.

## Where the game goes when the match is over (screen_match_stats_2 at the end,
## shootout_decided_1 after a shoot-out): the main menu, or the game
## mode's own screen once its tables have the result (the league's
## fixtures, the tournament's bracket, the cup's rounds, the World Series,
## the championship). Leagues and group rounds have no shoot-outs.
static func after_match(shootout: bool) -> void:
	ISSRam.set_l(S.g_next_state, ISSMenu.STATE_MENU)
	_w(S.g_next_screen, 0)
	match ISSRam.w(S.g_game_mode):
		4:
			if not shootout:
				league_result()
				_w(S.g_next_screen, 0x1D)
		5:
			tournament_result()
			_w(S.g_next_screen, 0x22)
		6:
			if not shootout:
				intl_elimination_result()
				_w(S.g_next_screen, 0x29)
		7:
			if not shootout:
				intl_group_result()
				_w(S.g_next_screen, 0x2B)
		8:
			intl_finals_result()
			_w(S.g_next_screen, 0x2D)
		9:
			_w(S.g_next_screen, 0x30)
		0xA:
			championship_result()
			championship_end()
			_w(S.g_next_screen, 0x33 if ISSRam.w(0x1272) == 0 else 0x27)


## penalty_view_start: a match's penalty goes to the shoot-out's view: in a
## match ($1638), no kicks yet, both orders 10, 9 ... 1 from the start (the
## order screen puts a human side's kicker first).
static func penalty_view_start() -> void:
	_w(0x1638, 1)
	_w(S.g_shootout_kicks, 0)
	_w(0x14FA, 0)
	_w(0x14FC, 0)
	for i in 10:
		_w(0x14FE + 2 * i, 10 - i)
		_w(0x1512 + 2 * i, 10 - i)


## shootout_start: the shoot-out after extra time: out of the match ($1638),
## no kicks yet, the takers' places ($1526) free, nought each, both orders
## 10, 9 ... 1, the home side first.
static func shootout_start() -> void:
	_w(0x1638, 0)
	_w(S.g_shootout_kicks, 0)
	_w(0x14FA, 0)
	_w(0x14FC, 0)
	for i in 10:
		_w(0x1526 + 2 * i, 0xFFFF)
	_w(0x153A, 0)
	_w(0x153C, 0)
	for i in 10:
		_w(0x14FE + 2 * i, 10 - i)
		_w(0x1512 + 2 * i, 10 - i)
	_w(S.g_restart_team, 0)


# --------------------------------------------------------------------------
# Matches between computer teams, the weather, the short league.

## The VDP's HV counter, read as a random number.
static func _hv() -> int:
	return randi() & 0xFFFF


## match_simulate: a match between computer teams. d = tbl_team_strength
## of the home team less the away team's, clamped to 0-63 each way; the
## goals of each side are tbl_sim_goals[(d & ~7) + random 0-7]; the
## penalties (for a knockout) 3 + another draw each, the home side one more
## when level.
static func match_simulate() -> void:
	var st := ISSRom.addr("tbl_team_strength")
	var goals := ISSRom.addr("tbl_sim_goals")
	var d := ISSRom.u8(st + ISSRam.w(S.g_team_home)) - ISSRom.u8(st + ISSRam.w(S.g_team_away))
	var dh := clampi(d, 0, 63) & ~7
	var da := clampi(-d, 0, 63) & ~7
	var h := dh + (_rand() & 7)
	var a := da + (_rand() & 7)
	ISSRam.set_b(S.g_score_home + 1, ISSRom.u8(goals + h))
	ISSRam.set_b(S.g_score_away + 1, ISSRom.u8(goals + a))
	h = (h & ~7) + (_rand() & 7)
	a = (a & ~7) + (_rand() & 7)
	var ph := ISSRom.u8(goals + h) + 3
	var pa := ISSRom.u8(goals + a) + 3
	if ph == pa:
		ph += 1
	_w(0x153A, ph)
	_w(0x153C, pa)


## weather_random: fine most often (HV counter & $FF from $28), rain from
## 8, below that the stadium's own (weather_random_data, 8 per stadium).
static func weather_random() -> void:
	var v := _hv() & 0xFF
	if v >= 0x28:
		_w(S.g_weather, 1)
	elif v >= 8:
		_w(S.g_weather, 2)
	else:
		_w(S.g_weather, ISSRom.u8(ISSRom.addr("weather_random_data") + ISSRam.w(S.g_stadium) * 8 + v))


## The match's conditions as a competition sets them up: a kick-off side
## at random, the ends, the stadium (at random 0-7), its weather, the
## referee, the time of day, the game time and clock, the statistics; no
## pads until the sides are known. The International Cup's elimination
## round passes its region's stadium; the World Series keeps its pads.
static func _competition_match(stadium: int = -1, clear_pads: bool = true) -> void:
	_w(0x1638, 0)
	_w(0x1634, _hv() & 1)
	_w(S.g_left_goal_team, 0)
	_w(S.g_restart_type, 4)
	_w(S.g_stadium, _hv() & 7 if stadium < 0 else stadium)
	weather_random()
	var ref := ISSRam.w(S.g_opt_referee)
	_w(S.g_officials_kit, (_hv() % 3) if ref == 3 else ref)
	_w(0x1630, _hv() % 3)
	_w(S.g_game_time, ISSRam.w(S.g_opt_time))
	_clock_start()
	match_stats_clear()
	if clear_pads:
		_w(0x153E, 0)
		_w(S.g_pads_home, 0)
		_w(S.g_pads_away, 0)


## The two sides of a fixture: their slots ($1642 / $1644, which also
## pick the status blocks), the teams in them ($127C + 2 * slot) and a pad
## for each human slot (below $1266).
static func _fixture(home_slot: int, away_slot: int) -> void:
	_w(0x1642, home_slot)
	if home_slot < ISSRam.w(0x1266):
		ISSRam.add_w(0x153E, 1)
		ISSRam.add_w(S.g_pads_home, 1)
	_w(S.g_team_home, ISSRam.w(0x127C + home_slot * 2))
	_w(0x1644, away_slot)
	if away_slot < ISSRam.w(0x1266):
		ISSRam.add_w(0x153E, 1)
		ISSRam.add_w(S.g_pads_away, 1)
	_w(S.g_team_away, ISSRam.w(0x127C + away_slot * 2))


## league_next_game: the league's next game (tbl_league_fixtures,
## game $1270 of 15); computer teams' games are simulated and recorded until
## one with a human side or the end.
static func league_next_game() -> void:
	while true:
		_competition_match()
		var f := ISSRom.addr("tbl_league_fixtures") + ISSRam.w(0x1270) * 2
		_fixture(ISSRom.u8(f), ISSRom.u8(f + 1))
		team_info_init()
		if ISSRam.w(0x153E) != 0:
			return
		match_simulate()
		league_result()
		if ISSRam.w(0x1270) >= 15:
			return


## league_result: the league game's result ($129C + 2 * game: 0 home
## win, 1 away win, 2 draw), on to the next game.
static func league_result() -> void:
	var a := 0x129C + ISSRam.w(0x1270) * 2
	var h := ISSRam.w(S.g_score_home)
	var aw := ISSRam.w(S.g_score_away)
	_w(a, 2 if h == aw else (0 if h > aw else 1))
	ISSRam.add_w(0x1270, 1)


## screen_league_table_3: the standings at buf (6 bytes a slot: place,
## slot, won, lost, drawn, points), sorted by points (a selection sort
## that keeps the first of equals; equal points share the place above);
## after the 15th game $1272 = the winner's slot. Returns buf ($1384).
static func league_standings(buf: int) -> int:
	_w(0x1384, (buf >> 16) & 0xFFFF)
	_w(0x1386, buf & 0xFFFF)
	var t := buf & 0xFFFF
	for k in 6:
		ISSRam.set_b(t + k * 6, k + 1)
		ISSRam.set_b(t + k * 6 + 1, k)
		for i in range(2, 6):
			ISSRam.set_b(t + k * 6 + i, 0)
	var fx := ISSRom.addr("tbl_league_fixtures")
	for g in ISSRam.w(0x1270):
		var r := ISSRam.w(0x129C + g * 2)
		var hs := t + ISSRom.u8(fx + g * 2) * 6
		var aws := t + ISSRom.u8(fx + g * 2 + 1) * 6
		match r:
			2:
				for e in [hs, aws]:
					ISSRam.set_b(e + 4, ISSRam.b(e + 4) + 1)
					ISSRam.set_b(e + 5, ISSRam.b(e + 5) + 1)
			0:
				ISSRam.set_b(hs + 2, ISSRam.b(hs + 2) + 1)
				ISSRam.set_b(hs + 5, ISSRam.b(hs + 5) + 3)
				ISSRam.set_b(aws + 3, ISSRam.b(aws + 3) + 1)
			_:
				ISSRam.set_b(aws + 2, ISSRam.b(aws + 2) + 1)
				ISSRam.set_b(aws + 5, ISSRam.b(aws + 5) + 3)
				ISSRam.set_b(hs + 3, ISSRam.b(hs + 3) + 1)
	for k in 6:
		var a2 := t + k * 6
		var a1 := a2
		for j in range(k, 6):
			if ISSRam.b(a1 + 5) < ISSRam.b(t + j * 6 + 5):
				a1 = t + j * 6
		for i in range(1, 6):
			var v := ISSRam.b(a1 + i)
			ISSRam.set_b(a1 + i, ISSRam.b(a2 + i))
			ISSRam.set_b(a2 + i, v)
		if k != 0 and ISSRam.b(a2 - 1) == ISSRam.b(a2 + 5):
			ISSRam.set_b(a2, ISSRam.b(a2 - 6))
	if ISSRam.w(0x1270) == 15:
		_w(0x1272, ISSRam.b(t + 1))
	return buf


## tournament_next_game: the tournament's next game ($1270 of 7):
## the quarter-finals pair slots 0-4, 2-6, 1-5, 3-7
## (tbl_tournament_first_round), the semi-finals and the final the
## winners ($129C) of the games before, a human side at home; computer
## teams' games are simulated and recorded until one with a human side or
## the end.
static func tournament_next_game() -> void:
	while true:
		_competition_match()
		var g := ISSRam.w(0x1270)
		var h: int
		var a: int
		if g < 4:
			var p := ISSRom.addr("tbl_tournament_first_round") + g * 2
			h = ISSRom.u8(p)
			a = ISSRom.u8(p + 1)
		else:
			var r := 0x129C + (g - 4) * 4
			h = ISSRam.w(r)
			a = ISSRam.w(r + 2)
			if h >= ISSRam.w(0x1266):
				h = ISSRam.w(r + 2)
				a = ISSRam.w(r)
		_fixture(h, a)
		team_info_init()
		if ISSRam.w(0x153E) != 0:
			return
		match_simulate()
		tournament_result()
		if ISSRam.w(0x1270) >= 7:
			return


## tournament_result: the tournament game's winner ($129C + 2 * game, its
## slot): the score, or when level the penalties; on to the next game.
static func tournament_result() -> void:
	var d := ISSRam.sw(S.g_score_home) - ISSRam.sw(S.g_score_away)
	if d == 0:
		d = ISSRam.sw(0x153A) - ISSRam.sw(0x153C)
	_w(0x129C + ISSRam.w(0x1270) * 2, ISSRam.w(0x1642) if d > 0 else ISSRam.w(0x1644))
	ISSRam.add_w(0x1270, 1)


# --------------------------------------------------------------------------
# The International Cup (modes 6-8): the human's team (slot 0, $127C) plays
# two others of its region ($126C = team / 3: 0-7 Europe, then Asia,
# Africa, South and North/Central America) once each, the first two going
# on to a group of four ($126C the group letter), the first two of that to
# the sixteen-team finals (slot 15 the group's other qualifier). $1270 the
# games played, $129C each game's result (0 home win, 1 away win, 2 a
# draw; in the finals the winner's slot), $1272 0 still in, 1 out.

## The random 0..n-1 the cup draws teams with: g_random's step mod n, less
## one (wrapping), stepped down again while next is false.
static func _draw(n: int, ok: Callable) -> int:
	var d := _rand() % n
	while true:
		d -= 1
		if d < 0:
			d = n - 1
		if ok.call(d):
			return d
	return 0


## intl_elimination_next_game: before the first game the region and the two
## opponents (any other European team for Europe, the region's other two
## elsewhere); the next game ($1270 of 3, menu_data_05B994) at one of the
## region's stadiums (tbl_intl_region_stadiums); computer teams'
## games are simulated and recorded.
static func intl_elimination_next_game() -> void:
	while true:
		var me := ISSRam.w(0x127C)
		if ISSRam.w(0x1270) == 0:
			var region := me / 3
			_w(0x126C, region)
			if region < 8:
				_w(0x127E, _draw(24, func(t: int) -> bool: return t != me))
				var t1 := ISSRam.w(0x127E)
				_w(0x1280, _draw(24, func(t: int) -> bool: return t != me and t != t1))
			else:
				_w(0x127E, region * 3 + _draw(3, func(t: int) -> bool: return region * 3 + t != me))
				var t1 := ISSRam.w(0x127E)
				_w(0x1280, region * 3 + _draw(3,
					func(t: int) -> bool: return region * 3 + t != me and region * 3 + t != t1))
		var st := ISSRom.u8(ISSRom.addr("tbl_intl_region_stadiums")
			+ ISSRam.w(0x126C) * 4 + (_rand() & 3))
		_competition_match(st)
		var f := ISSRom.addr("tbl_intl_elimination_games") + ISSRam.w(0x1270) * 2
		_fixture(ISSRom.u8(f), ISSRom.u8(f + 1))
		team_info_init()
		if ISSRam.w(0x153E) != 0:
			return
		match_simulate()
		intl_elimination_result()
		if ISSRam.w(0x1270) >= 3:
			return


## intl_elimination_result: a round-robin game's result ($129C + 2 *
## game: 0 home win, 1 away win, 2 draw); on to the next game.
static func intl_elimination_result() -> void:
	var d := ISSRam.sw(S.g_score_home) - ISSRam.sw(S.g_score_away)
	_w(0x129C + ISSRam.w(0x1270) * 2, 2 if d == 0 else (0 if d > 0 else 1))
	ISSRam.add_w(0x1270, 1)


## intl_group_result: the same for the group round.
static func intl_group_result() -> void:
	intl_elimination_result()


## The table of a round robin of n teams after the games so far (pairs:
## the games' slot pairs, two bytes each) as six-byte rows at the unpack
## buffer ($1384): place, slot, won, lost, drawn, points; sorted on points
## (the first of equals first), equal points sharing a place. Returns its
## address.
static func intl_table(n: int, pairs: int) -> int:
	var t := ISSRam.l(S.g_unpack_buffer)
	ISSRam.set_l(0x1384, t)
	for k in n:
		ISSRam.set_b(t + k * 6, k + 1)
		ISSRam.set_b(t + k * 6 + 1, k)
		for i in range(2, 6):
			ISSRam.set_b(t + k * 6 + i, 0)
	ISSRam.set_l(S.g_unpack_buffer, t + n * 6)
	var add := func(slot: int, i: int, v: int) -> void:
		ISSRam.set_b(t + slot * 6 + i, ISSRam.b(t + slot * 6 + i) + v)
	for g in ISSRam.w(0x1270):
		var h := ISSRom.u8(pairs + g * 2)
		var a := ISSRom.u8(pairs + g * 2 + 1)
		match ISSRam.w(0x129C + g * 2):
			2:
				add.call(h, 4, 1)
				add.call(h, 5, 1)
				add.call(a, 4, 1)
				add.call(a, 5, 1)
			0:
				add.call(h, 2, 1)
				add.call(h, 5, 3)
				add.call(a, 3, 1)
			_:
				add.call(a, 2, 1)
				add.call(a, 5, 3)
				add.call(h, 3, 1)
	for k in n:
		var best := t + k * 6
		for j in range(k, n):
			var r := t + j * 6
			if ISSRam.sb(best + 5) < ISSRam.sb(r + 5):
				best = r
		var here := t + k * 6
		for i in range(1, 6):
			var v := ISSRam.b(best + i)
			ISSRam.set_b(best + i, ISSRam.b(here + i))
			ISSRam.set_b(here + i, v)
		if k > 0 and ISSRam.b(here - 1) == ISSRam.b(here + 5):
			ISSRam.set_b(here, ISSRam.b(here - 6))
	return t


## intl_elimination_table: the elimination table; after the
## third game $1272 is 0 when the human's side (slot 0) is first or
## second, and $1284 the team that came third.
static func intl_elimination_table() -> int:
	var t := intl_table(3, ISSRom.addr("tbl_intl_elimination_games"))
	if ISSRam.w(0x1270) == 3:
		_w(0x1272, 0 if ISSRam.b(t + 1) == 0 or ISSRam.b(t + 7) == 0 else 1)
		_w(0x1284, ISSRam.w(0x127C + ISSRam.b(t + 13) * 2))
	return t


## mode_international_group: the group round (mode 7): three opponents
## at random (not the human's team nor the two of the elimination round),
## a random group letter; the opponents' status blocks cleared.
static func intl_group_start() -> void:
	_w(S.g_game_mode, 7)
	_w(S.g_knockout, 0)
	_w(0x1276, 1)
	_w(0x1268, 1)
	_w(0x1264, 1)
	_w(0x1270, 0)
	_w(0x1272, 0xFFFF)
	_w(0x126A, 0)
	_w(0x127A, 0)
	_w(0x1266, 1)
	ISSRam.clear(S.g_player_status + 20, 0x3C)
	_w(0x153E, 1)
	_w(S.g_pads_home, 1)
	_w(S.g_pads_away, 0)
	_intl_teams(3, [ISSRam.w(0x127E), ISSRam.w(0x1280)])
	_w(0x126C, _hv() % 6)


## Slots 1..n: teams at random (the HV counter mod 36, stepped down by two
## while taken), none already in the slots before nor in not.
static func _intl_teams(n: int, not_these: Array) -> void:
	var taken := not_these.duplicate()
	for k in n:
		var d := _hv() % 36
		while true:
			d -= 2
			if d < 0:
				d += 36
			var used := d in taken
			for j in k + 1:
				if ISSRam.w(0x127C + j * 2) == d:
					used = true
			if not used:
				break
		_w(0x127E + k * 2, d)


## intl_group_next_game: the group's next game ($1270 of 6,
## menu_data_05BE40); computer teams' games are simulated and recorded.
static func intl_group_next_game() -> void:
	while true:
		_competition_match()
		var f := ISSRom.addr("tbl_intl_group_games") + ISSRam.w(0x1270) * 2
		_fixture(ISSRom.u8(f), ISSRom.u8(f + 1))
		team_info_init()
		if ISSRam.w(0x153E) != 0:
			return
		match_simulate()
		intl_group_result()
		if ISSRam.w(0x1270) >= 6:
			return


## intl_group_table: the group's table; after the sixth game
## $1272 is 0 when the human's side is first or second, and $129A (slot
## 15 of the finals) the other of the two.
static func intl_group_table() -> int:
	var t := intl_table(4, ISSRom.addr("tbl_intl_group_games"))
	if ISSRam.w(0x1270) == 6:
		_w(0x1272, 1)
		var other := 0
		if ISSRam.b(t + 1) == 0:
			_w(0x1272, 0)
			other = ISSRam.b(t + 7)
		if ISSRam.b(t + 7) == 0:
			_w(0x1272, 0)
			other = ISSRam.b(t + 1)
		_w(0x129A, ISSRam.w(0x127C + other * 2))
	return t


## mode_international_finals: the finals (mode 8, a knockout): fourteen
## teams at random in slots 1-14 (none of the group's nor the third of the
## elimination round), the group's other qualifier already in slot 15; the
## opponent's status block cleared.
static func international_finals() -> void:
	_w(S.g_game_mode, 8)
	_w(S.g_knockout, 1)
	_w(0x1276, 1)
	_w(0x1268, 1)
	_w(0x1270, 0)
	_w(0x1272, 0xFFFF)
	_w(0x126A, 0)
	_w(0x127A, 0)
	_w(0x1266, 1)
	ISSRam.clear(S.g_player_status + 20, 20)
	_w(0x153E, 1)
	_w(S.g_pads_home, 1)
	_w(S.g_pads_away, 0)
	_intl_teams(14, [ISSRam.w(0x127E), ISSRam.w(0x1280), ISSRam.w(0x1282), ISSRam.w(0x1284)])


## The finals' game g: the first eight pair slots 0-1, 2-3 ...
## (tbl_intl_finals_games), the rest the winners ($129C) of two games before.
static func _intl_finals_slots(g: int) -> Array:
	if g < 8:
		var p := ISSRom.addr("tbl_intl_finals_games") + g * 2
		return [ISSRom.u8(p), ISSRom.u8(p + 1)]
	var r := 0x129C + (g - 8) * 4
	return [ISSRam.w(r), ISSRam.w(r + 2)]


## intl_finals_next_game: the finals' next game ($1270 of 15): the opponent's
## status block (always slot 1's) cleared; computer teams' games are
## simulated and recorded.
static func intl_finals_next_game() -> void:
	while true:
		_competition_match()
		ISSRam.clear(S.g_player_status + 20, 20)
		var s := _intl_finals_slots(ISSRam.w(0x1270))
		var h: int = s[0]
		var a: int = s[1]
		_w(0x1642, 0)
		if h < ISSRam.w(0x1266):
			ISSRam.add_w(0x153E, 1)
			ISSRam.add_w(S.g_pads_home, 1)
		_w(S.g_team_home, ISSRam.w(0x127C + h * 2))
		_w(0x1644, 1)
		if a < ISSRam.w(0x1266):
			ISSRam.add_w(0x153E, 1)
			ISSRam.add_w(S.g_pads_away, 1)
		_w(S.g_team_away, ISSRam.w(0x127C + a * 2))
		team_info_init()
		if ISSRam.w(0x153E) != 0:
			return
		match_simulate()
		intl_finals_result()
		if ISSRam.w(0x1270) >= 15:
			return


## intl_finals_result: the finals game's winner ($129C + 2 * game, its
## slot): the score, or when level the penalties; on to the next game.
static func intl_finals_result() -> void:
	var s := _intl_finals_slots(ISSRam.w(0x1270))
	var d := ISSRam.sw(S.g_score_home) - ISSRam.sw(S.g_score_away)
	if d == 0:
		d = ISSRam.sw(0x153A) - ISSRam.sw(0x153C)
	_w(0x129C + ISSRam.w(0x1270) * 2, s[0] if d > 0 else s[1])
	ISSRam.add_w(0x1270, 1)


# --------------------------------------------------------------------------
# The World Series (mode 9): the 36 teams play a 35-day season, 18 games a
# day (tbl_ws_rounds: 35 rounds of 18 pairs, in the order of one of eight
# schedules, tbl_ws_schedules, $126E); the human's team plays at home
# every day. $126C the series (0 first, 1 second), $1270 the days played,
# $129C + 2 * team each team's wins, $127E / $1280 the two series'
# winners. Winning a series goes to the trophy; after both, the
# championship (mode $A) against the other series' winner.

## The round of day $1270 in the season's schedule.
static func _ws_round() -> int:
	var day := ISSRom.u8(ISSRom.addr("tbl_ws_schedules") + ISSRam.w(0x126E) * 35 + ISSRam.w(0x1270))
	return ISSRom.addr("tbl_ws_rounds") + day * 36


## The human's pair in the round at r: its index (18 when absent).
static func _ws_pair(r: int) -> int:
	var me := ISSRam.w(0x127C)
	for k in 18:
		if ISSRom.u8(r + k * 2) == me or ISSRom.u8(r + k * 2 + 1) == me:
			return k
	return 18


## ws_second_series: the second series: statuses and wins cleared, the
## next schedule.
static func ws_second_series() -> void:
	_w(S.g_game_mode, 9)
	_clear_status(0x28)
	ISSRam.clear(0x129C, 0x48)
	_w(0x1270, 0)
	_w(0x126C, 1)
	_w(0x126E, (ISSRam.w(0x126E) + 1) & 7)


## ws_next_game: today's game, the human's team at home against today's
## opponent (whose status block, slot 1's, is cleared), and the day's 18
## pairs at the unpack buffer ($1384): the human's first, then the others
## in the round's order from it.
static func ws_next_game() -> void:
	_competition_match(-1, false)
	ISSRam.clear(S.g_player_status + 20, 20)
	_w(S.g_team_home, 0)
	_w(S.g_team_away, 0)
	var t := ISSRam.l(S.g_unpack_buffer)
	ISSRam.set_l(0x1384, t)
	var r := _ws_round()
	var k := _ws_pair(r)
	var a := t
	if k < 18:
		var me := ISSRam.w(0x127C)
		var other := ISSRom.u8(r + k * 2 + 1) if ISSRom.u8(r + k * 2) == me else ISSRom.u8(r + k * 2)
		_w(S.g_team_home, me)
		_w(S.g_team_away, other)
		ISSRam.set_b(a, me)
		ISSRam.set_b(a + 1, other)
		a += 2
	_w(0x1642, 0)
	_w(0x1644, 1)
	for i in 17:
		k = (k + 1) % 18
		ISSRam.set_b(a, ISSRom.u8(r + k * 2))
		ISSRam.set_b(a + 1, ISSRom.u8(r + k * 2 + 1))
		a += 2
	ISSRam.set_l(S.g_unpack_buffer, a)
	team_info_init()


## One game of the day's results at a: the teams, the score and (level)
## the penalties; a win for the first team when its score (or penalties)
## is higher, else for the second.
static func _ws_result(a: int, first: int, second: int) -> void:
	var h := ISSRam.w(S.g_score_home)
	var v := ISSRam.w(S.g_score_away)
	ISSRam.set_b(a, first)
	ISSRam.set_b(a + 1, second)
	ISSRam.set_b(a + 2, h)
	ISSRam.set_b(a + 3, v)
	ISSRam.set_b(a + 4, 0)
	ISSRam.set_b(a + 5, 0)
	if h & 0xFF == v & 0xFF:
		h = ISSRam.w(0x153A)
		v = ISSRam.w(0x153C)
		ISSRam.set_b(a + 4, h)
		ISSRam.set_b(a + 5, v)
	var winner := first if h > v else second
	ISSRam.add_w(0x129C + winner * 2, 1)


## ws_record_day: the day's results as six-byte entries at the unpack
## buffer ($1384): the human's game first (from the match's score), then
## the other 17 simulated; the wins counted, on to the next day.
static func ws_record_day() -> void:
	var t := ISSRam.l(S.g_unpack_buffer)
	ISSRam.set_l(0x1384, t)
	var r := _ws_round()
	var k := _ws_pair(r)
	var a := t
	if k < 18:
		var me := ISSRam.w(0x127C)
		var x := ISSRom.u8(r + k * 2)
		var y := ISSRom.u8(r + k * 2 + 1)
		_ws_result(a, me, y if x == me else x)
		a += 6
	for i in 17:
		k = (k + 1) % 18
		var x := ISSRom.u8(r + k * 2)
		var y := ISSRom.u8(r + k * 2 + 1)
		_w(S.g_team_home, x)
		_w(S.g_team_away, y)
		match_simulate()
		_ws_result(a, x, y)
		a += 6
	ISSRam.set_l(S.g_unpack_buffer, a)
	ISSRam.add_w(0x1270, 1)


## ws_standings: the table at the unpack buffer ($1384), four bytes a
## team from the human's on: place, team, won, lost; sorted on wins (the
## first of equals first), equal wins sharing a place. After the last day
## the leader is the series' winner ($127E / $1280) and $1272 0 when it is
## the human's team; before it g_team_home / away the human's next game.
## Returns the table's address.
static func ws_standings() -> int:
	var t := ISSRam.l(S.g_unpack_buffer)
	ISSRam.set_l(0x1384, t)
	var team := ISSRam.w(0x127C)
	var days := ISSRam.w(0x1270)
	for i in 36:
		var wins := ISSRam.w(0x129C + team * 2)
		ISSRam.set_b(t + i * 4, i + 1)
		ISSRam.set_b(t + i * 4 + 1, team)
		ISSRam.set_b(t + i * 4 + 2, wins)
		ISSRam.set_b(t + i * 4 + 3, days - wins)
		team = (team + 1) % 36
	ISSRam.set_l(S.g_unpack_buffer, t + 36 * 4)
	for k in 36:
		var best := t + k * 4
		for j in range(k, 36):
			if ISSRam.sb(best + 2) < ISSRam.sb(t + j * 4 + 2):
				best = t + j * 4
		var here := t + k * 4
		for i in range(1, 4):
			var v := ISSRam.b(best + i)
			ISSRam.set_b(best + i, ISSRam.b(here + i))
			ISSRam.set_b(here + i, v)
		if k > 0 and ISSRam.b(here - 2) == ISSRam.b(here + 2):
			ISSRam.set_b(here, ISSRam.b(here - 4))
	if days == 35:
		var leader := ISSRam.b(t + 1)
		_w(0x127E if ISSRam.w(0x126C) == 0 else 0x1280, leader)
		_w(0x1272, 0 if leader == ISSRam.w(0x127C) else 1)
		return t
	_w(S.g_team_home, 0)
	_w(S.g_team_away, 0)
	var r := _ws_round()
	var k := _ws_pair(r)
	if k < 18:
		var me := ISSRam.w(0x127C)
		var x := ISSRom.u8(r + k * 2)
		_w(S.g_team_home, me)
		_w(S.g_team_away, ISSRom.u8(r + k * 2 + 1) if x == me else x)
	return t


## mode_start_championship: the championship (mode $A, one knockout game)
## after the second series.
static func start_championship() -> void:
	_w(S.g_game_mode, 0xA)
	_w(S.g_knockout, 1)
	_w(0x1276, 1)
	_w(0x1268, 1)
	_w(0x1264, 1)
	_w(0x1266, 1)
	_w(0x1270, 0)
	_w(0x1272, 0xFFFF)
	_w(0x126A, 0)
	_w(0x127A, 0)
	_clear_status(0x28)
	_w(0x153E, 1)
	_w(S.g_pads_home, 1)
	_w(S.g_pads_away, 0)


## match_setup_random: the championship's game: the human's team at home
## against the first series' winner, or the second's when that is the
## human's, or (both the human's) the All Star team (36).
static func match_setup_random() -> void:
	_competition_match(-1, false)
	var me := ISSRam.w(0x127C)
	_w(S.g_team_home, me)
	var other := ISSRam.w(0x127E)
	if other == me:
		other = ISSRam.w(0x1280)
		if other == me:
			other = 0x24
	_w(S.g_team_away, other)
	_w(0x1642, 0)
	_w(0x1644, 1)
	team_info_init()


## championship_result: $129C 0 when the human's side won, else 1.
static func championship_result() -> void:
	_w(0x129C, 0 if ISSRam.sw(S.g_score_home) > ISSRam.sw(S.g_score_away) else 1)


## championship_end: $1272 from it (0 the champions).
static func championship_end() -> void:
	_w(0x1272, 0 if ISSRam.w(0x129C) == 0 else 1)


## scenario_setup: scenario $1270 from tbl_scenarios (16-byte records:
## the clock, the teams, the score, the stadium, the referee, the restart
## and where): the second half, the human's side at home and starting with
## the restart; the team's captain and penalty taker pointers reset.
static func scenario_setup() -> void:
	_clear_status(0x28)
	match_stats_clear()
	var r := ISSRom.u32(ISSRom.addr("tbl_scenarios") + ISSRam.w(0x1270) * 4)
	for i in 4:
		ISSRam.set_b(S.g_match_clock + i, ISSRom.u8(r + i))
	ISSRam.set_b(S.g_team_home + 1, ISSRom.u8(r + 4))
	ISSRam.set_b(S.g_team_away + 1, ISSRom.u8(r + 5))
	ISSRam.set_b(S.g_score_home + 1, ISSRom.u8(r + 6))
	ISSRam.set_b(S.g_score_away + 1, ISSRom.u8(r + 7))
	_w(S.g_weather, 1)
	_w(0x1630, 0)
	_w(S.g_game_time, 2)
	_w(S.g_half, 1)
	_w(S.g_restart_timer, 0x280)
	ISSRam.set_b(S.g_stadium + 1, ISSRom.u8(r + 8))
	ISSRam.set_b(S.g_officials_kit + 1, ISSRom.u8(r + 9))
	_w(S.g_restart_type, ISSRom.u16(r + 0xA))
	_w(S.g_restart_team, 0)
	_w(S.g_restart_x, ISSRom.u16(r + 0xC))
	_w(S.g_restart_y, ISSRom.u16(r + 0xE))
	_w(0x17D8, 0)
	_w(0x1638, 0)
	_w(0x1634, 0)
	_w(S.g_left_goal_team, 0)
	_w(0x1642, 0)
	_w(0x1644, 1)
	team_info_init()
	ISSRam.set_l(0x1896, 0xFF1FDA)
	ISSRam.set_l(0x189A, 0xFF1FDA)
	_w(0x153E, 1)
	_w(S.g_pads_home, 1)
	_w(S.g_pads_away, 0)


## scenario_record_result: one more attempt at the scenario (up to 99,
## $129D + 2 * scenario), cleared when the human's side won
## ($129C + 2 * scenario); all twelve cleared ends the mode ($1272 = 0).
static func scenario_record_result() -> void:
	var a := 0x129C + ISSRam.w(0x1270) * 2
	if ISSRam.b(a) == 0:
		if ISSRam.b(a + 1) < 0x63:
			ISSRam.set_b(a + 1, ISSRam.b(a + 1) + 1)
		if ISSRam.sw(S.g_score_home) > ISSRam.sw(S.g_score_away):
			ISSRam.set_b(a, 1)
	var cleared := 0
	for k in 12:
		if ISSRam.b(0x129C + k * 2) != 0:
			cleared += 1
	if cleared == 12:
		_w(0x1272, 0)


## kit_shades: the kit's shades on palette line 0: colour 1 black,
## colour 2 colour 5 a step darker, colour 3 colour 7 two steps lighter (up
## to 7), colour 4 colour 8 a step darker (per channel).
static func kit_shades() -> void:
	var pt := S.g_palette_target
	_w(pt + 2, 0)
	var c5 := ISSRam.w(pt + 10)
	var c7 := ISSRam.w(pt + 14)
	var c8 := ISSRam.w(pt + 16)
	var dark := func(c: int) -> int:
		var v := 0
		for sh in [1, 5, 9]:
			var ch: int = (c >> sh) & 7
			v |= maxi(0, ch - 1) << sh
		return v
	var light := func(c: int) -> int:
		var v := 0
		for sh in [1, 5, 9]:
			var ch: int = (c >> sh) & 7
			v |= (ch + 2 if ch <= 5 else 7) << sh
		return v
	_w(pt + 4, dark.call(c5))
	_w(pt + 6, light.call(c7))
	_w(pt + 8, dark.call(c8))


## menu_func_05AEAC: the open game's set-up (the scenarios' and PK's code
## shortcuts use it too).
static func menu_func_05AEAC() -> void:
	open_game_setup()


## menu_input_040F5E: where a pre-match sub-screen returns. Training and
## challenges have their own menus; with humans on both sides the home
## side's choice is followed by the away side's on the same item
## ($176A = 1, the item through tbl_prematch_screens), or after the last
## item the competition's own screen; otherwise the pre-match menu.
static func prematch_return() -> void:
	var mode := ISSRam.w(S.g_game_mode)
	if mode == 0:
		_w(S.g_next_screen, 0x19)
		return
	if mode == 1:
		_w(S.g_next_screen, 0x16)
		return
	if ISSRam.w(0x1768) != 0 or ISSRam.w(S.g_pads_away) == 0:
		_w(S.g_next_screen, 6)
		return
	_w(0x176A, 1)
	var item := ISSRam.w(0x18B4)
	if item < 10:
		_w(S.g_next_screen, ISSRom.u16(ISSRom.addr("tbl_prematch_screens") + item * 2))
		return
	match mode:
		4, 6, 7:
			_w(S.g_next_screen, 0x1E)
		5, 8:
			_w(S.g_next_screen, 0x23)
		9:
			_w(S.g_next_screen, 0x32)
