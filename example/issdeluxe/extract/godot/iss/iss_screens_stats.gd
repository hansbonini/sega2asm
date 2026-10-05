class_name ISSScreensStats
extends ISSScreens
## The match statistics (screen $39), shown when a half ends: the score,
## seven figures a side from g_stats_home / g_stats_away (shots, free
## kicks, corners, penalties, yellow cards, red cards, offsides) beside the
## teams' flags and name plates, and with goals the scorers (g_scorers) in
## a window two rows high that up / down scroll. C (or, with no human
## pads, $100 frames without a button) goes on: to the next half (screen 6
## with the ends changed), into extra time, to the shoot-out, or when the
## match is over to where the game mode goes after it.
##
## RAM: $1776 the list's scroll in thirds of a row, $1778 its direction,
## $177A / $177C the goals of each side so far down the list, $177E the
## goals of the match.

const DISTANCE := 0x8A


func register(h: Dictionary) -> void:
	h[0x39] = screen_match_stats


func _digit(d: int) -> int:
	return rom("str_digit_strings") + 2 * d


## A number in large digits, the tens only when there are any: at x (the
## home side's column: tens at x, units at x + 8) or, from x on, packed
## (the away side's: units at x without tens).
func _large(v: int, x: int, y: int, packed: bool) -> void:
	var tens := v / 10
	if tens != 0:
		m.text_draw_large(x, y, _digit(tens))
		if packed:
			x += 8
	if not packed:
		x += 8
	m.text_draw_large(x, y, _digit(v % 10))


func screen_match_stats() -> void:
	set_w(0x1776, 0)
	m.menu_music(0x19)
	if w(0x17D8) != 1:
		m.play_sfx(102)
		set_w(0x17D8, 1)
	# The flags (group 6 entry 2, 6 tiles a team) and name plates (entry 0,
	# 5 tiles) of both teams.
	var buf := l(S.g_unpack_buffer)
	var ov := w(S.g_overlay_vram)
	m.unpack(6, 2, buf)
	m.vram_dma(ov + 0x6480, buf + w(S.g_team_home) * 0xC0, 0xC0)
	m.vram_dma(ov + 0x6540, buf + w(S.g_team_away) * 0xC0, 0xC0)
	m.unpack(6, 0, buf)
	m.vram_dma(ov + 0x6600, buf + w(S.g_team_home) * 0xA0, 0xA0)
	m.vram_dma(ov + 0x66A0, buf + w(S.g_team_away) * 0xA0, 0xA0)
	_large(w(S.g_score_home), 0x68, 8, false)
	for i in 7:
		_large(w(S.g_stats_home + 2 * i), 0x40, i * 16 + 0x20, false)
	_large(w(S.g_score_away), 0x88, 8, true)
	for i in 7:
		_large(w(S.g_stats_away + 2 * i), 0xB0, i * 16 + 0x20, true)
	spawn(screen_match_stats_1)
	var goals := w(S.g_score_home) + w(S.g_score_away)
	if goals != 0:
		stats_scorers(spawn(Callable()))
	set_w(0x177E, goals)


func screen_match_stats_1(o: ISSMenu.Obj) -> void:
	o.update = screen_match_stats_2
	o.set_w(T, 0)
	o.set_w(DISTANCE, 0x100)
	screen_match_stats_2(o)


func screen_match_stats_2(o: ISSMenu.Obj) -> void:
	m.boxes_draw_sprites(rom("tbl_stats_boxes_goals" if w(0x177E) != 0 else "tbl_stats_boxes"))
	if w(S.g_frame_state) != 2:
		return
	var go := false
	if w(0x153E) == 0:
		# No human pads: on by itself after $100 frames without a button.
		if w(S.g_pad_pressed_any) != 0:
			o.set_w(DISTANCE, 0x100)
		else:
			o.add_w(DISTANCE, -1)
			go = o.sw(DISTANCE) < 0
	if not go and w(S.g_pad_pressed_any) & PAD_C == 0:
		return
	var level := w(S.g_score_home) == w(S.g_score_away)
	var half := w(S.g_half)
	if half > 1 and not level and w(S.g_opt_vgoal) == 0:
		ISSModes.after_match(false)
		m.fade_out_start()
		return
	if half & 1 == 0:
		_next_half()
		return
	if w(S.g_knockout) == 0 or not level:
		ISSModes.after_match(false)
		m.fade_out_start()
		return
	if half != 3:
		# Level after the second half: extra time, one g_game_time shorter.
		add_w(S.g_game_time, -1)
		_next_half()
		return
	# Level after extra time: the shoot-out, with the order chosen first
	# when humans play (screen $1A, the home side first if it has pads).
	ISSModes.shootout_start()
	if w(0x153E) == 0:
		set_l(S.g_next_state, ISSMenu.STATE_SHOOTOUT)
	else:
		set_w(S.g_next_screen, 0x1A)
		set_w(0x176A, 0 if w(S.g_pads_home) != 0 else 1)
	m.fade_out_start()


## The next half: ends and kick-off changed, the match starting again
## (restart 4) with a full clock, by way of the match menu.
func _next_half() -> void:
	add_w(S.g_half, 1)
	set_w(S.g_left_goal_team, w(S.g_left_goal_team) ^ 1)
	set_w(0x1634, w(0x1634) ^ 1)
	set_w(S.g_restart_type, 4)
	set_w(S.g_restart_timer, 0)
	ISSRam.set_l(S.g_match_clock, 0)
	ISSRam.set_b(S.g_match_clock, w(S.g_game_time) * 2 + 1)
	set_l(S.g_next_state, ISSMenu.STATE_MENU)
	set_w(S.g_next_screen, 6)
	m.fade_out_start()


# --------------------------------------------------------------------------
# The scorers: name (or OWN GOAL) under the scoring side, the half and the
# time into it, and the score after the goal.

func stats_scorers(o: ISSMenu.Obj) -> void:
	o.update = stats_scorers_1
	o.set_w(T, 0)
	var sv := w(S.g_stadium_vram) >> 5
	m.rect_fill(0x20, 0xE0, 0xA0, 0xD0, sv | 0x4000)
	set_w(0x177A, 0)
	set_w(0x177C, 0)
	var a4 := S.g_scorers
	var scroll := w(0x1776)
	var y := 0xA0 - (scroll % 3) * 8
	for i in scroll / 3:
		add_w(0x177A if ISSRam.b(a4 + 3) == 0 else 0x177C, 1)
		a4 += 6
	var rows := mini(3, w(S.g_score_home) + w(S.g_score_away))
	for k in rows:
		var x := 0x20 if ISSRam.b(a4 + 4) == 0 else 0xA0
		var credited := ISSRam.b(a4 + 3)
		add_w(0x177A if credited == 0 else 0x177C, 1)
		var name := rom("str_own_goal")
		if credited == ISSRam.b(a4 + 4):
			var team := w(S.g_team_home if credited == 0 else S.g_team_away)
			name = ISSRom.u32(rom("tbl_player_names") + team * 4) + ISSRam.b(a4 + 5) * 8
		m.text_draw_field(x, x + 0x40, y, name)
		m.text_draw_small(x, y + 0x10, rom("str_scorer_halves") + (ISSRam.b(a4 + 2) & 3) * 4)
		var secs := w(a4)
		m.text_draw_small(x + 0x38, y + 0x10, _digit(secs % 10))
		m.text_draw_small(x + 0x30, y + 0x10, _digit((secs / 10) % 6))
		m.text_draw_small(x + 0x20, y + 0x10, _digit(secs / 60))
		m.text_draw_small(x + 0x28, y + 0x10, rom("str_colon"))
		_large(w(0x177A), 0x68, y, false)
		_large(w(0x177C), 0x88, y, true)
		m.rect_fill_tiles(0x78, 0x88, y + 8, y + 0x10, (sv | 0xC000) + 0x320)
		y += 0x18
		a4 += 6
	# The window's edges, and the arrows when it scrolls.
	m.rect_fill(0x20, 0xE0, 0x98, 0xA0, sv | 0x4000)
	m.rect_fill(0x20, 0xE0, 0x90, 0x98, sv | 0xC000)
	m.rect_fill(0x20, 0xE0, 0xD0, 0xD8, sv | 0x4000)
	m.rect_fill(0x20, 0xE0, 0xD8, 0xE0, sv | 0xC000)
	if scroll != 0:
		m.rect_fill_tiles(0x78, 0x88, 0x98, 0xA0, (sv | 0xC000) + 0x322)
	if _last_scroll() > scroll:
		m.rect_fill_tiles(0x78, 0x88, 0xD0, 0xD8, (sv | 0xD000) + 0x322)
	stats_scorers_1(o)


## The furthest the list scrolls: two rows from the end.
func _last_scroll() -> int:
	return (w(S.g_score_home) + w(S.g_score_away)) * 3 - 6


func stats_scorers_1(o: ISSMenu.Obj) -> void:
	if w(0x1776) % 3 != 0:
		# Between rows: a third of a row every other frame.
		if w(S.g_frame_counter) & 1 == 0:
			add_w(0x1776, 1 if w(0x1778) != 0 else -1)
			o.update = stats_scorers
		set_w(0x154E, 2)
		return
	if w(S.g_pad_pressed_any) & PAD_UP and w(0x1776) != 0:
		add_w(0x1776, -1)
		set_w(0x1778, 0)
		o.update = stats_scorers
	if w(S.g_pad_pressed_any) & PAD_DOWN and _last_scroll() > w(0x1776):
		add_w(0x1776, 1)
		set_w(0x1778, 1)
		o.update = stats_scorers
