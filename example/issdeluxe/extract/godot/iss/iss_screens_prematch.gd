class_name ISSScreensPrematch
extends ISSScreens
## The screens before a match: match type (1), player select (2), team
## select (3), stadium (4), handicap (5), the pre-match menu (6) and today's
## game ($10).

const RET_SCREENS := [6, 8, 9, 0xA, 0xB, 0xC, 0xD, 2, 0xE, 0xF]


func register(h: Dictionary) -> void:
	h[0x01] = screen_match_type
	h[0x02] = screen_player_select
	h[0x03] = screen_team_select
	h[0x04] = screen_stadium_select
	h[0x05] = screen_handicap
	h[0x06] = screen_prematch_menu
	h[0x10] = screen_todays_game


# --------------------------------------------------------------------------
# Screen 1: open game / short league / short tournament.

func screen_match_type() -> void:
	set_w(0x153E, 0)
	set_w(S.g_pads_home, 0)
	set_w(S.g_pads_away, 0)
	spawn(screen_match_type_1)
	var o := spawn(Callable())
	menu_state_03D64C(o)


func screen_match_type_1(o: ISSMenu.Obj) -> void:
	o.update = screen_match_type_2
	o.set_w(T, 0)
	screen_match_type_2(o)


## B goes back to the main menu; the boxes.
func screen_match_type_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_B):
		goto_screen(0)
	m.boxes_draw_sprites(rom("tbl_match_type_boxes"))


## One item of the match type menu: its two lines of description, C starts
## the mode, up / down move (wrapping), the box highlighted and the cursor.
func _match_item(o: ISSMenu.Obj, text: String, enter: Callable, idle: Callable) -> void:
	o.update = idle
	o.set_w(T, 0)
	var a := m.text_draw_large(0x38, 0x88, rom(text))
	m.text_draw_large(0x38, 0xA0, a)
	idle.call(o)


func _match_item_1(o: ISSMenu.Obj, start: Callable, screen: int, up: Callable, down: Callable,
		box: Array, cursor_x1: int, cursor_y: int, me: Callable) -> void:
	if pressed(PAD_C):
		start.call()
		goto_screen(screen)
		m.play_sfx(95)
	if pressed(PAD_UP):
		o.update = up
		m.play_sfx(77)
	if pressed(PAD_DOWN):
		o.update = down
		m.play_sfx(77)
	if o.update == me:
		m.rect_highlight(box[0], box[1], box[2], box[3])
	else:
		m.rect_unhighlight(box[0], box[1], box[2], box[3])
	o.add_w(T, 1)
	m.cursor_draw_large(0, 0x40, cursor_x1, cursor_y)


func menu_state_03D64C(o: ISSMenu.Obj) -> void:
	_match_item(o, "str_open_game_info", menu_state_03D64C, menu_state_03D64C_1)


func menu_state_03D64C_1(o: ISSMenu.Obj) -> void:
	_match_item_1(o, ISSModes.start_open_game, 0x02, menu_state_03D838, menu_state_03D742,
		[0x40, 0x88, 0x28, 0x38], 0x88, 0x29, menu_state_03D64C_1)


func menu_state_03D742(o: ISSMenu.Obj) -> void:
	_match_item(o, "str_league_info", menu_state_03D742, menu_state_03D742_1)


func menu_state_03D742_1(o: ISSMenu.Obj) -> void:
	_match_item_1(o, ISSModes.start_short_league, 0x34, menu_state_03D64C, menu_state_03D838,
		[0x40, 0xA0, 0x40, 0x50], 0xA0, 0x41, menu_state_03D742_1)


func menu_state_03D838(o: ISSMenu.Obj) -> void:
	_match_item(o, "str_tournament_info", menu_state_03D838, menu_state_03D838_1)


func menu_state_03D838_1(o: ISSMenu.Obj) -> void:
	_match_item_1(o, ISSModes.start_short_tournament, 0x35, menu_state_03D742, menu_state_03D64C,
		[0x40, 0xC0, 0x58, 0x68], 0xC0, 0x59, menu_state_03D838_1)


# --------------------------------------------------------------------------
# Screen 2: player select. $1776 = humans (0-8), $1778 = how many of them
# play for the home side, $1780 = controllers connected; the backups
# $177A-$177E restore the old choice on B. In a competition ($1268) a row
# that would move the humans to the other side is greyed and refused.

## Per number of humans: the home count's range, the cursor's y for the
## top row and whether the rows step from home_max (y = base + 24 *
## (home_max - home)). From the menu_state_03DC14 ... 03E3AE family.
const PLAYERS := [
	{"lo": 0, "hi": 1, "base": 0x58, "data": "tbl_player_rows_1"},
	{"lo": 0, "hi": 1, "base": 0x58, "data": "tbl_player_rows_1"},
	{"lo": 1, "hi": 2, "base": 0x58, "data": "tbl_player_rows_2"},
	{"lo": 2, "hi": 3, "base": 0x58, "data": "tbl_player_rows_3"},
	{"lo": 2, "hi": 4, "base": 0x50, "data": "tbl_player_rows_4"},
	{"lo": 3, "hi": 4, "base": 0x58, "data": "tbl_player_rows_5"},
	{"lo": 3, "hi": 4, "base": 0x58, "data": "tbl_player_rows_6"},
	{"lo": 4, "hi": 4, "base": 0x68, "data": "tbl_player_rows_7"},
	{"lo": 4, "hi": 4, "base": 0x68, "data": "tbl_player_rows_8"},
]


func screen_player_select() -> void:
	# A quieter cursor sound while song 25 (silence) is on.
	set_w(0x1782, 0x7B if w(S.g_sound_disabled) == 0x19 else 0x4D)
	spawn(screen_player_select_1)
	set_w(0x1780, w(0x153E))
	set_w(0x1776, w(0x153E))
	set_w(0x1778, w(S.g_pads_home))
	set_w(0x177A, w(0x153E))
	set_w(0x177C, w(S.g_pads_home))
	set_w(0x177E, w(S.g_pads_away))
	set_w(0x153E, 0)
	set_w(S.g_pads_home, 0)
	set_w(S.g_pads_away, 0)
	var o := spawn(Callable())
	_players_state(o, w(0x1776))


func screen_player_select_1(o: ISSMenu.Obj) -> void:
	o.update = screen_player_select_2
	screen_player_select_2(o)


func screen_player_select_2(o: ISSMenu.Obj) -> void:
	var n := 0
	while n < 8 and w(S.g_pad_type + 2 * n) != 0xF:
		n += 1
	set_w(0x1780, n)
	if pressed(PAD_B):
		set_w(0x153E, w(0x177A))
		set_w(S.g_pads_home, w(0x177C))
		set_w(S.g_pads_away, w(0x177E))
		set_w(S.g_next_screen, 0 if w(S.g_game_mode) == 2 else 1)
		_back_to_prematch()
		set_l(S.g_next_state, ISSMenu.STATE_MENU)
		m.fade_out_start()
	if pressed(PAD_C):
		if w(0x1268) != 0 and not _players_row_ok(w(0x1778), w(0x1776) - w(0x1778)):
			m.play_sfx(94)
		else:
			set_w(0x153E, w(0x1776))
			set_w(S.g_pads_home, w(0x1778))
			set_w(S.g_pads_away, w(0x1776) - w(0x1778))
			set_w(S.g_next_screen, 3)
			_back_to_prematch()
			set_l(S.g_next_state, ISSMenu.STATE_MENU)
			m.fade_out_start()
			m.play_sfx(95)
	if w(0x1780) > 1:
		o.add_w(T, 1)
		m.pad_icon_draw(0, 0x18, 0x68)
		m.pad_icon_draw(1, 0xE0, 0x68)
	m.boxes_draw_sprites(rom("tbl_player_select_boxes"))


## From the pre-match menu's screens (6-$10) the choice returns there
## (menu_input_040F5E; its "player select" answer means the menu itself).
func _back_to_prematch() -> void:
	var prev := w(0x175A)
	if prev >= 6 and prev <= 0x10:
		menu_input_040F5E()
		if w(S.g_next_screen) == 2:
			set_w(S.g_next_screen, 6)


## In a competition the humans must stay on the sides they had.
func _players_row_ok(home: int, away: int) -> bool:
	return (w(0x177C) != 0) == (home != 0) and (w(0x177E) != 0) == (away != 0)


## Enter the state for n humans (the menu_state_03DC14 ... family).
func _players_state(o: ISSMenu.Obj, n: int) -> void:
	o.update = func(ob: ISSMenu.Obj) -> void: _players_frame(ob, n)
	o.set_w(T, 0)
	_players_draw(rom(PLAYERS[n]["data"]))
	_players_frame(o, n)


## menu_func_03DC08 ... 03E3A2: n humans, home count min(n, 4).
func _players_enter(o: ISSMenu.Obj, n: int) -> void:
	set_w(0x1778, mini(n, 4))
	set_w(0x1776, n)
	_players_state(o, n)


func _players_frame(o: ISSMenu.Obj, n: int) -> void:
	var p: Dictionary = PLAYERS[n]
	var lo: int = p["lo"]
	var hi: int = p["hi"]
	var sfx := w(0x1782)
	var pads := w(0x1780)
	if lo != hi:
		if pressed(PAD_UP):
			var h := w(0x1778) + 1
			set_w(0x1778, lo if h > hi else h)
			if n <= 1:
				set_w(0x1776, w(0x1778))
			m.play_sfx(sfx)
		if pressed(PAD_DOWN):
			var h := w(0x1778) - 1
			set_w(0x1778, hi if h < lo else h)
			if n <= 1:
				set_w(0x1776, w(0x1778))
			m.play_sfx(sfx)
	# Left / right pick the state the next frame enters (the ROM sets the
	# object's update to its menu_func); from 0 or 1 human left wraps to
	# every controller playing and right goes to 2.
	if pressed(PAD_LEFT) and (n > 1 or pads > 1):
		_players_next(o, pads if n <= 1 else n - 1)
		m.play_sfx(sfx)
	if pressed(PAD_RIGHT) and (n > 1 or pads > 1):
		if n <= 1:
			_players_next(o, 2)
		else:
			_players_next(o, n + 1 if pads > n and n < 8 else 1)
		m.play_sfx(sfx)
	if n >= 2 and pads < n:
		_players_next(o, 1)
	o.add_w(T, 1)
	var y: int = p["base"] + 0x18 * (hi - w(0x1778)) if lo != hi else p["base"]
	m.cursor_draw_large(0, 0x74, 0x8C, y)


## The next frame enters the state for n humans (the ROM switches the
## object's update to the menu_func, which runs from the next frame).
func _players_next(o: ISSMenu.Obj, n: int) -> void:
	o.update = func(ob: ISSMenu.Obj) -> void: _players_enter(ob, maxi(n, 1))


## menu_input_03E440: the rows of the table at a (y, home, away; -1 ends):
## "VS" between the sides, a controller icon per human (the 3-button pad's
## when that controller is one) under the player numbers, or the CPU.
func _players_draw(a: int) -> void:
	var base := w(S.g_stadium_vram) >> 5
	m.rect_fill(0x30, 0xD0, 0x40, 0xA0, base | 0x4000)
	while ISSRom.s16(a) >= 0:
		var pad := 0
		var y := ISSRom.u16(a)
		var home := ISSRom.u16(a + 2)
		var away := ISSRom.u16(a + 4)
		m.rect_fill_tiles(0x78, 0x88, y, y + 0x10, (base | 0xA000) + 0x1C8)
		if home > 0:
			for k in range(home - 1, -1, -1):
				var t := (base | 0xA000) + 0x1CC + (2 if w(S.g_pad_type + 2 * pad) == 0 else 0)
				pad += 1
				var x := 0x60 - k * 0x10
				m.rect_fill_tiles(x, x + 0x10, y + 8, y + 0x10, t)
			m.rect_fill_tiles(0x70 - home * 0x10, 0x70, y, y + 8, (base | 0xA000) + 0x1D0)
		else:
			m.rect_fill_tiles(0x60, 0x70, y, y + 0x10, (base | 0xA000) + 0x1A0)
		if away > 0:
			for k in away:
				var t := (base | 0xA000) + 0x1CC + (2 if w(S.g_pad_type + 2 * pad) == 0 else 0)
				pad += 1
				var x := 0x90 + k * 0x10
				m.rect_fill_tiles(x, x + 0x10, y + 8, y + 0x10, t)
			m.rect_fill_tiles(0x90, 0x90 + away * 0x10, y, y + 8, (base | 0xA000) + 0x1D0 + home * 2)
		else:
			m.rect_fill_tiles(0x90, 0xA0, y, y + 0x10, (base | 0xA000) + 0x1C4)
		if w(0x1268) != 0 and not _players_row_ok(home, away):
			m.rect_unhighlight(0x30, 0xD0, y, y + 0x10)
		a += 6


# --------------------------------------------------------------------------
# Screen 3: team select. $1786 = the team shown for side $1768 (written to
# $127C + 2 * side on C); the region's six flags, the team's flag, name,
# formation, photo and its GK / DF / MF / FW averages. Resource group 6:
# entry 1 the 16-tile name plates ($1776), 0 the regions' small plates
# ($177A), 2 the flags (VRAM $177E), 7 the photo bodies (VRAM $1780), 8 the
# photo heads ($1782), 11 / 12 the flag and photo palettes (raw).

func screen_team_select() -> void:
	set_l(0x1776, l(S.g_unpack_buffer))
	set_l(S.g_unpack_buffer, m.unpack(6, 1, l(S.g_unpack_buffer)))
	set_l(0x177A, l(S.g_unpack_buffer))
	set_l(S.g_unpack_buffer, m.unpack(6, 0, l(S.g_unpack_buffer)))
	set_w(0x177E, m.load_tiles(6, 2))
	set_w(0x1780, m.load_tiles(6, 7))
	add_w(S.g_unpack_vram, 0x300)
	set_l(0x1782, l(S.g_unpack_buffer))
	set_l(S.g_unpack_buffer, m.unpack(6, 8, l(S.g_unpack_buffer)))
	set_w(0x1768, 0)
	spawn(screen_team_select_1)
	var o := spawn(Callable())
	menu_func_03E8E0(o)


func screen_team_select_1(o: ISSMenu.Obj) -> void:
	o.update = screen_team_select_2
	screen_team_select_2(o)


## The controller icons, the team photo (ten heads from the players'
## records, then the bodies of the photo's layout) and the boxes.
func screen_team_select_2(o: ISSMenu.Obj) -> void:
	o.add_w(T, 1)
	m.pad_icon_draw(0, 0x10, 0xA8)
	m.pad_icon_draw(1, 0xE8, 0xA8)
	var team := w(0x1786)
	var rec := ISSRom.u32(rom("tbl_player_data") + team * 4) + 0x16
	var a := ISSRom.u32(rom("tbl_team_photos") + team * 4)
	var base := w(0x1780) >> 5
	for k in 10:
		m.sprite(ISSRom.u16(a), ISSRom.u16(a + 2), base + ISSRom.u8(rec) + ISSRom.u16(a + 4), ISSRom.u16(a + 6))
		rec += 12
		a += 8
	var n := ISSRom.u16(a)
	a += 2
	for k in n + 1:
		m.sprite(ISSRom.u16(a), ISSRom.u16(a + 2), base + ISSRom.u16(a + 4), ISSRom.u16(a + 6))
		a += 8
	m.boxes_draw_sprites(rom("tbl_team_select_boxes"))


## menu_func_03E8E0: show the team side $1768 has.
func menu_func_03E8E0(o: ISSMenu.Obj) -> void:
	set_w(0x1786, w(0x127C + w(0x1768) * 2))
	menu_state_03E8F0(o)


## A line's average of the nine attributes over the players whose record
## matches, as the bar's 0-7 steps (* 56 / players / 90).
func _line_average(team: int, roles: Array, fw_quirk: bool) -> int:
	var a := ISSRom.u32(rom("tbl_player_data") + team * 4)
	var n := 0
	var sum := 0
	for k in 20:
		var pos := ISSRom.u8(a + 0xB)
		# The forwards' test reads the next record's first byte instead of
		# this one's position (cmpi.b #4,$C(a3)).
		if pos in roles or (fw_quirk and ISSRom.u8(a + 0xC) == 4):
			n += 1
			for i in 9:
				sum += ISSRom.u8(a + i)
		a += 12
	if n == 0:
		return 0
	return (sum * 0x38 / n) / 0x5A


## menu_state_03E8F0: draw the team: name plates and photo heads to VRAM,
## flag colours, the four line averages, the region's name, the formation,
## the flags, the side's icon, the photo palette and the side's colours;
## then the pads that drive it ($1548).
func menu_state_03E8F0(o: ISSMenu.Obj) -> void:
	o.update = menu_state_03E8F0_1
	o.set_w(T, 0)
	var team := w(0x1786)
	var side := w(0x1768)
	m.vram_dma(w(S.g_overlay_vram) + 0x6A00, l(0x1776) + team * 0x200, 0x200)
	m.vram_dma(w(S.g_overlay_vram) + 0x6C00, l(0x177A) + (team / 6) * 0x1E * 32, 0x3C0)
	m.vram_dma(w(0x1780) + 0xD60, l(0x1782) + ISSRom.u16(rom("tbl_team_photo_heads") + team * 2), 0x300)
	var flag_pal := ISSRom.res(6, 11)
	for i in 8:
		ISSRam.set_b(0x778 + i, flag_pal[team * 8 + i])
	if w(S.g_fade_step) == 0x18:
		m.cram_dma(0x22, 0x778, 8)
	m.bar_draw_wide(0xA8, 0x40, 0, _line_average(team, [3], false))
	m.bar_draw_wide(0xA8, 0x48, 1, _line_average(team, [2, 5], false))
	m.bar_draw_wide(0xA8, 0x50, 2, _line_average(team, [1, 4, 5], false))
	m.bar_draw_wide(0xA8, 0x58, 3, _line_average(team, [0], true))
	m.text_draw_large(0x20, 0x80, rom("str_region_names") + (team / 6) * 12)
	var formation := ISSRom.u8(ISSRom.u32(rom("tbl_team_formations") + team * 4))
	m.text_draw_small(0xB8, 0x30, rom("str_formation_names") + formation * 6)
	var flags := (w(0x177E) >> 5) | 0xC000
	m.rect_fill_tiles(0x88, 0xA0, 0x20, 0x30, flags + team * 6)
	var v := flags + (team / 6) * 0x24
	for r: Array in [[0x40, 0x58, 0x98, 0xA8], [0x78, 0x90, 0x98, 0xA8], [0xB0, 0xC8, 0x98, 0xA8],
			[0x40, 0x58, 0xB8, 0xC8], [0x78, 0x90, 0xB8, 0xC8], [0xB0, 0xC8, 0xB8, 0xC8]]:
		v = m.rect_fill_tiles(r[0], r[1], r[2], r[3], v)
	var icon := ((w(S.g_stadium_vram) >> 5) | 0xC000) + (0x180 if side & 1 == 0 else 0x1A4)
	icon += side * 4 if w(0x1266) > side else 0x20
	m.rect_fill_tiles(8, 0x18, 8, 0x18, icon)
	if w(0x1264) > 2:
		m.text_draw_large(0x38, 8, rom("str_team_slots") + side * 0x12)
	var pal := ISSRom.res(6, 12)
	for i in 32:
		ISSRam.set_b(S.g_palette_target + i, pal[team * 32 + i])
	var cols := rom("tbl_home_side_colours") if side & 1 == 0 else rom("tbl_away_side_colours")
	for i in 5:
		set_w(0x7C6 + 2 * i, ISSRom.u16(cols + 2 * i))
	if w(S.g_fade_step) == 0x18:
		m.cram_dma(0, S.g_palette_target, 0x80)
	if w(0x1264) >= 3:
		set_w(0x1548, 2)
	else:
		set_w(0x1548, side & 1)
		if w(S.g_pads_home if side & 1 == 0 else S.g_pads_away) == 0:
			set_w(0x1548, 2)
	menu_state_03E8F0_1(o)


## Team select input (the side's own pads): B back (side 0: the mode's
## previous screen), C takes the team (the next side, or on to the mode),
## left / right along the region's three columns into the next region,
## up / down between its two rows; the cursor on the team's flag.
func menu_state_03E8F0_1(o: ISSMenu.Obj) -> void:
	var p := w(S.g_pad_pressed_home)
	var side := w(0x1768)
	var mode := w(S.g_game_mode)
	if p & PAD_B:
		if side == 0:
			var back := {3: 2, 4: 0x1B, 5: 0x20, 6: 0, 9: 0, 2: 0, 0: 0x13}
			if back.has(mode):
				set_w(S.g_next_screen, back[mode])
			set_l(S.g_next_state, ISSMenu.STATE_MENU)
			m.fade_out_start()
		else:
			set_w(0x1768, side - 1)
			o.update = menu_func_03E8E0
	if p & PAD_C:
		var a := 0x127C + w(0x1768) * 2
		set_w(a, w(0x1786))
		if w(0x1264) - 1 > w(0x1768):
			add_w(0x1768, 1)
			o.update = menu_func_03E8E0
			if w(0x1264) > 2:
				set_w(a + 2, w(a))
		else:
			set_l(S.g_next_state, ISSMenu.STATE_MENU)
			var nxt := {4: 0x1C, 5: 0x21, 6: 0x29, 9: 0x2F}
			if nxt.has(mode):
				set_w(S.g_next_screen, nxt[mode])
			if mode == 3:
				ISSModes.open_game_setup()
				set_w(S.g_next_screen, 4)
			if mode == 2:
				ISSModes.pk_setup()
				set_w(S.g_next_screen, 4)
			if mode == 0:
				ISSModes.training_setup()
				set_w(S.g_next_screen, 4)
			m.fade_out_start()
		m.play_sfx(95)
	# The number of teams: 36, or 42 with code 1 outside the competitions.
	var count := 0x2A if w(0x125A) != 0 and w(0x1276) == 0 else 0x24
	if p & PAD_RIGHT:
		var t := w(0x1786)
		if t % 3 != 2:
			t += 1
		else:
			t += 4
			if t >= count:
				t -= count
		set_w(0x1786, t)
		o.update = menu_state_03E8F0
		m.play_sfx(77)
	if p & PAD_LEFT:
		var t := w(0x1786)
		if t % 3 != 0:
			t -= 1
		else:
			t -= 4
			if t < 0:
				t += count
		set_w(0x1786, t)
		o.update = menu_state_03E8F0
		m.play_sfx(77)
	if p & (PAD_UP | PAD_DOWN):
		var t := w(0x1786)
		set_w(0x1786, t + 3 if t % 6 <= 2 else t - 3)
		o.update = menu_state_03E8F0
		m.play_sfx(77)
	o.add_w(T, 1)
	var c := rom("tbl_team_flag_cursor") + (w(0x1786) % 6) * 8
	m.cursor_draw_large(0, ISSRom.u16(c), ISSRom.u16(c + 2), ISSRom.u16(c + 4))


# --------------------------------------------------------------------------
# Screen 4: stadium and weather. The stadiums' pictures (group 4 entry 15,
# $177A) and their countries' name plates (group 6 entry 1, eight plates
# copied to $1776 and recoloured), animated crowd tiles (group 4 entries 7
# and 8, raw), the weather boxes (menu_data_03FC5E).

## The plate of each stadium's country, by its offset in the unpacked
## plates at buffer + $1000.
const STADIUM_PLATES := [0x5400, 0x2200, 0x1400, 0x1000, 0x1200, 0x4C00, 0x4600, 0x4000]


func screen_stadium_select() -> void:
	set_l(0x177A, l(S.g_unpack_buffer))
	set_l(S.g_unpack_buffer, m.unpack(4, 15, l(S.g_unpack_buffer)))
	var buf := l(S.g_unpack_buffer)
	m.unpack(6, 1, buf + 0x1000)
	set_l(0x1776, buf)
	var a := buf
	for off: int in STADIUM_PLATES:
		ISSRam.copy(a, buf + off, 0x200)
		a += 0x200
	set_l(S.g_unpack_buffer, a)
	m.recolour(buf & 0xFFFF, 0x1000, 0xA, 0xD)
	m.recolour(buf & 0xFFFF, 0x1000, 0xB, 0xE)
	m.recolour(buf & 0xFFFF, 0x1000, 0xC, 0xF)
	spawn(screen_stadium_select_1)
	var o := spawn(Callable())
	menu_state_03FB56(o)
	menu_state_03FA38(o)


func screen_stadium_select_1(o: ISSMenu.Obj) -> void:
	o.update = screen_stadium_select_2
	screen_stadium_select_2(o)


## B back to team select; C on (training select, PK order or the
## shoot-out when no human plays, handicap); the animated crowd tiles, the
## stadium's sprites, the controller icons and the boxes.
func screen_stadium_select_2(o: ISSMenu.Obj) -> void:
	if pressed(PAD_B):
		goto_screen(3)
	if pressed(PAD_C):
		set_l(S.g_next_state, ISSMenu.STATE_MENU)
		var mode := w(S.g_game_mode)
		if mode == 0:
			set_w(S.g_next_screen, 0x18)
		if mode == 2:
			if w(S.g_pads_home) == 0:
				set_l(S.g_next_state, ISSMenu.STATE_SHOOTOUT)
				m.fade_out_start()
			else:
				set_w(0x176A, 0)
				set_w(S.g_next_screen, 0x1A)
		if mode == 3:
			set_w(S.g_next_screen, 5)
		m.fade_out_start()
		m.play_sfx(95)
	var fc := w(S.g_frame_counter)
	var ov := w(S.g_overlay_vram)
	if fc & 7 == 0:
		if fc & 8 == 0:
			m.vdp.dma(ov + 0x6D80, ISSRom.res(4, 7), (fc & 0xF0) << 2, 0x40)
		else:
			m.vdp.dma(ov + 0x6DC0, ISSRom.res(4, 7), ((fc + 0x80) & 0xF0) << 2, 0x40)
	if fc & 1 == 0:
		m.vdp.dma(ov + 0x6F80, ISSRom.res(4, 8), (fc & 0xE) << 5, 0x40)
	else:
		m.vdp.dma(ov + 0x6FC0, ISSRom.res(4, 8), ((fc + 8) & 0xE) << 5, 0x40)
	var a := rom("tbl_stadium_sprites")
	var n := ISSRom.u16(a)
	a += 2
	var base := w(S.g_stadium_vram) >> 5
	for k in n + 1:
		m.sprite(ISSRom.u16(a), ISSRom.u16(a + 2), base + ISSRom.u16(a + 4), ISSRom.u16(a + 6))
		a += 8
	o.add_w(T, 1)
	m.pad_icon_draw(0, 0x20, 0x40)
	m.pad_icon_draw(1, 0xD8, 0x40)
	m.boxes_draw_sprites(rom("tbl_stadium_boxes"))


## The stadium: its picture and name plate to VRAM; left / right step
## through the eight (wrapping), up / down go to the weather; the box
## flashes while it is chosen.
func menu_state_03FA38(o: ISSMenu.Obj) -> void:
	o.update = menu_state_03FA38_1
	o.set_w(T, 0)
	m.vram_dma(w(S.g_overlay_vram) + 0x7200, l(0x177A) + w(S.g_stadium) * 0x200, 0x200)
	m.vram_dma(w(S.g_overlay_vram) + 0x7000, l(0x1776) + w(S.g_stadium) * 0x200, 0x200)
	menu_state_03FA38_1(o)


func menu_state_03FA38_1(o: ISSMenu.Obj) -> void:
	if pressed(PAD_UP | PAD_DOWN):
		o.update = menu_state_03FB56
		m.play_sfx(77)
	if pressed(PAD_RIGHT):
		set_w(S.g_stadium, 0 if w(S.g_stadium) >= 7 else w(S.g_stadium) + 1)
		o.update = menu_state_03FA38
		m.play_sfx(77)
	if pressed(PAD_LEFT):
		set_w(S.g_stadium, 7 if w(S.g_stadium) <= 0 else w(S.g_stadium) - 1)
		o.update = menu_state_03FA38
		m.play_sfx(77)
	o.add_w(T, 1)
	if o.update == menu_state_03FA38_1:
		m.rect_flash(0x28, 0xD8, 0x18, 0x78)
	else:
		m.rect_unhighlight(0x28, 0xD8, 0x18, 0x78)


## The weather: snow, fine, rain boxes (the chosen one highlighted, or
## flashing while the weather is being chosen).
func menu_state_03FB56(o: ISSMenu.Obj) -> void:
	o.update = menu_state_03FB56_1
	o.set_w(T, 0)
	var a := rom("tbl_weather_boxes")
	for k in 3:
		var r := [ISSRom.u16(a), ISSRom.u16(a + 2), ISSRom.u16(a + 4), ISSRom.u16(a + 6)]
		if k == w(S.g_weather):
			m.rect_highlight(r[0], r[1], r[2], r[3])
		else:
			m.rect_unhighlight(r[0], r[1], r[2], r[3])
		a += 8
	menu_state_03FB56_1(o)


func menu_state_03FB56_1(o: ISSMenu.Obj) -> void:
	if pressed(PAD_UP | PAD_DOWN):
		o.update = menu_state_03FA38
		m.play_sfx(77)
	if pressed(PAD_RIGHT):
		set_w(S.g_weather, 0 if w(S.g_weather) >= 2 else w(S.g_weather) + 1)
		o.update = menu_state_03FB56
		m.play_sfx(77)
	if pressed(PAD_LEFT):
		set_w(S.g_weather, 2 if w(S.g_weather) <= 0 else w(S.g_weather) - 1)
		o.update = menu_state_03FB56
		m.play_sfx(77)
	o.add_w(T, 1)
	var a := rom("tbl_weather_boxes") + w(S.g_weather) * 8
	if o.update == menu_state_03FB56_1:
		m.rect_flash(ISSRom.u16(a), ISSRom.u16(a + 2), ISSRom.u16(a + 4), ISSRom.u16(a + 6))
	else:
		m.rect_highlight(ISSRom.u16(a), ISSRom.u16(a + 2), ISSRom.u16(a + 4), ISSRom.u16(a + 6))


# --------------------------------------------------------------------------
# Screen 5: handicap. Per side: condition 0-5 (5 = random), players on the
# pitch 7-11 (tm_players 0-4) and the goalkeeper's skill 0-4; each side's
# own pads drive its column (the away column mirrors left / right). With no
# human, or only home ones, A switches which side the pad sets ($1548).

func screen_handicap() -> void:
	var buf := l(S.g_unpack_buffer)
	var ov := w(S.g_overlay_vram)
	m.unpack(6, 2, buf)
	m.vram_dma(ov + 0x6940, buf + w(S.g_team_home) * 0xC0, 0xC0)
	m.vram_dma(ov + 0x6A00, buf + w(S.g_team_away) * 0xC0, 0xC0)
	m.unpack(6, 0, buf)
	m.vram_dma(ov + 0x6AC0, buf + w(S.g_team_home) * 0xA0, 0xA0)
	m.vram_dma(ov + 0x6B60, buf + w(S.g_team_away) * 0xA0, 0xA0)
	set_l(0x1770, buf)
	set_l(S.g_unpack_buffer, m.unpack(4, 35, buf))
	var base := (w(S.g_stadium_vram) >> 5) | 0xC000
	var t := base + 0x180 + (w(0x1642) * 4 if w(S.g_pads_home) != 0 else 0x20)
	m.rect_fill_tiles(0x48, 0x58, 0x20, 0x30, t)
	t = base + 0x1A4 + (w(0x1644) * 4 if w(S.g_pads_away) != 0 else 0x20)
	m.rect_fill_tiles(0xA8, 0xB8, 0x20, 0x30, t)
	if w(0x153E) == 0 or w(S.g_pads_away) == 0:
		if w(0x153E) == 0:
			set_w(0x1548, 2)
		var a := m.text_draw_large(0x18, 0xB0, rom("str_handicap_help"))
		m.text_draw_large(0x18, 0xC0, a)
	spawn(menu_state_03FF24)
	var o := spawn(Callable())
	menu_state_04045A(o)
	menu_state_04032E(o)
	menu_state_040208(o)
	o = spawn(Callable())
	menu_state_0407E4(o)
	menu_state_0406CC(o)
	menu_state_0405A6(o)


## Which side the pad sets (2 = each its own): the pad mark over it.
func menu_state_03FF24(o: ISSMenu.Obj) -> void:
	o.update = menu_state_03FF24_1
	var d5 := 2
	if w(0x153E) == 0 or w(S.g_pads_away) == 0:
		d5 = w(0x1548) & 1
	var base := (w(S.g_stadium_vram) >> 5) | 0xC000
	if d5 == 0:
		m.rect_fill_tiles(0x30, 0x40, 0x20, 0x30, base + 0x8C)
	else:
		m.rect_fill(0x30, 0x40, 0x20, 0x30, base)
	if d5 == 1:
		m.rect_fill_tiles(0xC0, 0xD0, 0x20, 0x30, base + 0x8C)
	else:
		m.rect_fill(0xC0, 0xD0, 0x20, 0x30, base)
	menu_state_03FF24_1(o)


## A switches the side, B back to the stadium, C: the players' energy from
## the conditions (rules_func_014D8A), the handicap players marked off
## (+$55 = 1 for the first 4 - tm_players outfield players) and on to the
## pre-match menu. Then the faces, the condition marks and the arrows.
func menu_state_03FF24_1(o: ISSMenu.Obj) -> void:
	if pressed(PAD_A) and (w(0x153E) == 0 or w(S.g_pads_away) == 0):
		set_w(0x1548, w(0x1548) ^ 1)
		set_w(S.g_pad_held_home, 0xFFFF)
		set_w(S.g_pad_held_away, 0xFFFF)
		o.update = menu_state_03FF24
		m.play_sfx(77)
	if pressed(PAD_B):
		goto_screen(4)
	if pressed(PAD_C):
		ISSModes._energy()
		for side in 2:
			var off := 4 - w([S.g_team_home_info, S.g_team_away_info][side] + ISSModes.TM_PLAYERS)
			var a: int = [S.g_team_home_players, S.g_team_away_players][side] + ISSModes.PLAYER_SIZE
			for k in range(1, 11):
				ISSRam.set_b(a + 0x55, 1 if k <= off else 0)
				a += ISSModes.PLAYER_SIZE
		goto_screen(6)
		m.play_sfx(95)
	m.anim_tiles()
	o.add_w(T, 1)
	var c := rom("tbl_handicap_condition_home") + w(S.g_team_home_info + ISSModes.TM_CONDITION) * 8
	m.icon_draw_small(0, ISSRom.u16(c) + 4, ISSRom.u16(c + 4) + 0x11)
	c = rom("tbl_handicap_condition_away") + w(S.g_team_away_info + ISSModes.TM_CONDITION) * 8
	m.icon_draw_small(0, ISSRom.u16(c) + 4, ISSRom.u16(c + 4) + 0x11)
	m.icon_draw_small(1, 0x40, 0x74)
	m.icon_draw_small(2, 0x58, 0x74)
	m.icon_draw_small(1, 0xA0, 0x74)
	m.icon_draw_small(2, 0xB8, 0x74)
	m.boxes_draw_sprites(rom("tbl_handicap_boxes"))


## One handicap setting of one side: value at addr wraps 0..hi with
## left / right (mirrored for the away side), up / down go to the other
## settings; the cursor on its box.
func _handicap(o: ISSMenu.Obj, side: int, addr: int, hi: int, me: Callable, up: Callable,
		down: Callable) -> void:
	var p := w(S.g_pad_pressed_home if side == 0 else S.g_pad_pressed_away)
	var dec := PAD_LEFT if side == 0 else PAD_RIGHT
	var inc := PAD_RIGHT if side == 0 else PAD_LEFT
	if p & dec:
		set_w(addr, hi if sw(addr) - 1 < 0 else w(addr) - 1)
		o.update = me
		m.play_sfx(77)
	if p & inc:
		set_w(addr, 0 if w(addr) + 1 > hi else w(addr) + 1)
		o.update = me
		m.play_sfx(77)
	if p & PAD_UP:
		o.update = up
		m.play_sfx(77)
	if p & PAD_DOWN:
		o.update = down
		m.play_sfx(77)
	o.add_w(T, 1)


func _box_cursor(set: int, table: String, index: int) -> void:
	var a := rom(table) + index * 8
	m.cursor_draw_large(set, ISSRom.u16(a), ISSRom.u16(a + 2), ISSRom.u16(a + 4) + 1)


## Condition (home: menu_state_040208, away: menu_state_0405A6).
func menu_state_040208(o: ISSMenu.Obj) -> void:
	o.update = menu_state_040208_1
	o.set_w(T, 0)
	menu_state_040208_1(o)


func menu_state_040208_1(o: ISSMenu.Obj) -> void:
	_handicap(o, 0, S.g_team_home_info + ISSModes.TM_CONDITION, 5, menu_state_040208,
		menu_state_04045A, menu_state_04032E)
	_box_cursor(0, "tbl_handicap_condition_home", w(S.g_team_home_info + ISSModes.TM_CONDITION))


func menu_state_0405A6(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0405A6_1
	o.set_w(T, 0)
	menu_state_0405A6_1(o)


func menu_state_0405A6_1(o: ISSMenu.Obj) -> void:
	_handicap(o, 1, S.g_team_away_info + ISSModes.TM_CONDITION, 5, menu_state_0405A6,
		menu_state_0407E4, menu_state_0406CC)
	_box_cursor(1, "tbl_handicap_condition_away", w(S.g_team_away_info + ISSModes.TM_CONDITION))


## Players on the pitch: the number (menu_data_040446) and its box.
func menu_state_04032E(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04032E_1
	o.set_w(T, 0)
	m.text_draw_large(0x40, 0x70, rom("str_player_counts") + w(S.g_team_home_info + ISSModes.TM_PLAYERS) * 4)
	m.rect_highlight(0x40, 0x60, 0x70, 0x80)
	menu_state_04032E_1(o)


func menu_state_04032E_1(o: ISSMenu.Obj) -> void:
	_handicap(o, 0, S.g_team_home_info + ISSModes.TM_PLAYERS, 4, menu_state_04032E,
		menu_state_040208, menu_state_04045A)
	m.cursor_draw_large(0, 0x40, 0x60, 0x71)


func menu_state_0406CC(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0406CC_1
	o.set_w(T, 0)
	m.text_draw_large(0xA0, 0x70, rom("str_player_counts") + w(S.g_team_away_info + ISSModes.TM_PLAYERS) * 4)
	m.rect_highlight(0xA0, 0xC0, 0x70, 0x80)
	menu_state_0406CC_1(o)


func menu_state_0406CC_1(o: ISSMenu.Obj) -> void:
	_handicap(o, 1, S.g_team_away_info + ISSModes.TM_PLAYERS, 4, menu_state_0406CC,
		menu_state_0405A6, menu_state_0407E4)
	m.cursor_draw_large(1, 0xA0, 0xC0, 0x71)


## Goalkeeper skill: five boxes, the chosen one highlighted.
func _keeper_boxes(table: String, value: int) -> void:
	var a := rom(table)
	for k in 5:
		var r := [ISSRom.u16(a), ISSRom.u16(a + 2), ISSRom.u16(a + 4), ISSRom.u16(a + 6)]
		if k == value:
			m.rect_highlight(r[0], r[1], r[2], r[3])
		else:
			m.rect_unhighlight(r[0], r[1], r[2], r[3])
		a += 8


func menu_state_04045A(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04045A_1
	o.set_w(T, 0)
	_keeper_boxes("tbl_handicap_keeper_home", w(S.g_team_home_info + ISSModes.TM_KEEPER_SKILL))
	menu_state_04045A_1(o)


func menu_state_04045A_1(o: ISSMenu.Obj) -> void:
	_handicap(o, 0, S.g_team_home_info + ISSModes.TM_KEEPER_SKILL, 4, menu_state_04045A,
		menu_state_04032E, menu_state_040208)
	_box_cursor(0, "tbl_handicap_keeper_home", w(S.g_team_home_info + ISSModes.TM_KEEPER_SKILL))


func menu_state_0407E4(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0407E4_1
	o.set_w(T, 0)
	_keeper_boxes("tbl_handicap_keeper_away", w(S.g_team_away_info + ISSModes.TM_KEEPER_SKILL))
	menu_state_0407E4_1(o)


func menu_state_0407E4_1(o: ISSMenu.Obj) -> void:
	_handicap(o, 1, S.g_team_away_info + ISSModes.TM_KEEPER_SKILL, 4, menu_state_0407E4,
		menu_state_0406CC, menu_state_0405A6)
	_box_cursor(1, "tbl_handicap_keeper_away", w(S.g_team_away_info + ISSModes.TM_KEEPER_SKILL))


# --------------------------------------------------------------------------
# Screen 6: the pre-match menu, one cursor per side: home $182C (chosen:
# $182A), away $18B4 ($18B2). Items: game start, select squad, formation
# change, adjust strategy, man to man marking, key configuration, change
# control, number of players, edit player skills, team colours (and in a
# competition ($1270) an eleventh, the competition's own menu). During a
# match ($1638, the pause) the menu has eight items and resumes the match.

## The last item: the menu has 10 items, 11 in a competition, 8 in a match.
func _prematch_last() -> int:
	if w(0x1638) != 0:
		return 7
	return 10 if w(0x1270) != 0 else 9


func screen_prematch_menu() -> void:
	if w(0x1638) != 0:
		set_w(0x1776, 0x7B)
		m.menu_music(0x19)
		if w(0x17D8) != 1:
			m.play_sfx(102)
			set_w(0x17D8, 1)
	else:
		set_w(0x1776, 0x4D)
	# The menu's rows: the competitions' layout moves rows 28-31 up to
	# 24-27 and blanks row 2; the match's moves 24-27 to 20-23 and blanks
	# rows 24 and 2.
	var tn := l(S.g_text_nametable) & 0xFFFF
	if w(0x1638) == 0:
		if w(0x1270) != 0:
			ISSRam.copy(tn + 0xC00, tn + 0xE00, 0x200)
			ISSRam.copy(tn + 0x100, tn, 0x80)
	else:
		ISSRam.copy(tn + 0xA00, tn + 0xC00, 0x200)
		ISSRam.copy(tn + 0xC00, tn, 0x80)
		ISSRam.copy(tn + 0x100, tn, 0x80)
	if w(0x182C) != 0:
		set_w(0x182A, 0)
	if w(0x18B4) != 0:
		set_w(0x18B2, 0)
	spawn(screen_prematch_menu_1)
	spawn(screen_prematch_menu_3)
	spawn(screen_prematch_menu_5)


func screen_prematch_menu_1(o: ISSMenu.Obj) -> void:
	o.update = screen_prematch_menu_2
	screen_prematch_menu_2(o)


## B on game start (not chosen) goes back; once both sides have chosen,
## both on game start leads to today's game (or back to the match), any
## other item to its screen for the side that chose it (home first).
func screen_prematch_menu_2(_o: ISSMenu.Obj) -> void:
	var mode := w(S.g_game_mode)
	if w(0x1270) == 0 and w(0x1638) == 0:
		var back := false
		if w(S.g_pad_pressed_home) & PAD_B and w(0x182A) == 0 and w(0x182C) == 0:
			back = true
		elif w(S.g_pad_pressed_away) & PAD_B and w(0x18B2) == 0 and w(0x18B4) == 0:
			back = true
		if back:
			set_w(0x182A, 0)
			set_w(0x18B2, 0)
			var to := {4: 0x1C, 5: 0x21, 6: 3, 9: 0x2F, 3: 5}
			if to.has(mode):
				set_w(S.g_next_screen, to[mode])
			if w(S.g_next_screen) != 6:
				set_l(S.g_next_state, ISSMenu.STATE_MENU)
				m.fade_out_start()
	if w(0x182A) != 0 and w(0x18B2) != 0:
		if w(0x182C) | w(0x18B4) == 0:
			if w(0x1638) == 0:
				set_w(S.g_next_screen, 0x10)
				set_l(S.g_next_state, ISSMenu.STATE_MENU)
			else:
				set_l(S.g_next_state, ISSMenu.STATE_MATCH)
		else:
			set_w(0x176A, 0)
			var item := w(0x182C)
			if item == 0:
				set_w(0x176A, 1)
				item = w(0x18B4)
			if item < 10:
				set_w(S.g_next_screen, ISSRom.u16(rom("tbl_prematch_screens") + item * 2))
			else:
				var to := {4: 0x1E, 5: 0x23, 6: 0x1E, 7: 0x1E, 8: 0x23, 9: 0x32}
				if to.has(mode):
					set_w(S.g_next_screen, to[mode])
			set_l(S.g_next_state, ISSMenu.STATE_MENU)
		m.fade_out_start()
	m.rect_unhighlight_all(0x38, 0xC8, 0x20, 0xD0)
	for item in [w(0x182C), w(0x18B4)]:
		m.rect_highlight(0x38, 0xC8, item * 16 + 0x20, item * 16 + 0x30)
	var boxes := "tbl_prematch_boxes_pause"
	if w(0x1638) == 0:
		boxes = "tbl_prematch_boxes_comp" if w(0x1270) != 0 else "tbl_prematch_boxes"
	m.boxes_draw_sprites(rom(boxes))


func screen_prematch_menu_3(o: ISSMenu.Obj) -> void:
	o.update = screen_prematch_menu_4
	screen_prematch_menu_4(o)


func screen_prematch_menu_5(o: ISSMenu.Obj) -> void:
	o.update = screen_prematch_menu_6
	screen_prematch_menu_6(o)


## One side's cursor: up / down (wrapping), C chooses, B goes back to game
## start (or takes the choice back); a computer side chooses game start
## after 64 frames. The side's controller icon at its item.
func _prematch_side(o: ISSMenu.Obj, side: int) -> void:
	var pad: int = S.g_pad_pressed_home if side == 0 else S.g_pad_pressed_away
	var item: int = 0x182C if side == 0 else 0x18B4
	var chosen: int = 0x182A if side == 0 else 0x18B2
	if w(chosen) == 0:
		if w(pad) & PAD_DOWN:
			add_w(item, 1)
			if w(item) > _prematch_last():
				set_w(item, 0)
			m.play_sfx(w(0x1776))
		if w(pad) & PAD_UP:
			add_w(item, -1)
			if sw(item) < 0:
				set_w(item, _prematch_last())
			m.play_sfx(w(0x1776))
		if w(pad) & PAD_C:
			set_w(chosen, 1)
			m.play_sfx(95)
		if w(pad) & PAD_B and w(item) != 0:
			set_w(item, 0)
			set_w(pad, 0)
		o.add_w(T, 1)
		if w(S.g_pads_home if side == 0 else S.g_pads_away) == 0 and o.w(T) > 0x40:
			set_w(item, 0)
			set_w(chosen, 1)
			m.play_sfx(95)
	else:
		if w(pad) & PAD_B:
			set_w(pad, 0)
			set_w(chosen, 0)
		o.set_w(T, 0)
	m.pad_icon_draw(3 if side == 0 else 2, 0x2C if side == 0 else 0xCC, w(item) * 16 + 0x20)


func screen_prematch_menu_4(o: ISSMenu.Obj) -> void:
	_prematch_side(o, 0)


func screen_prematch_menu_6(o: ISSMenu.Obj) -> void:
	_prematch_side(o, 1)


# --------------------------------------------------------------------------
# Screen $10: today's game. The two flags and name plates, the stadium's
# picture and name, the time of day ($1630: 13:00, 16:00, 19:00, the last
# "tonight's game") and the weather, each side's controllers (or the CPU);
# C (or 128 frames when no human plays) goes on to the presentation
# (state_screen, $1730 = 0), B back to the pre-match menu.

const OBJ_DISTANCE := 0x8A


func screen_todays_game() -> void:
	spawn(screen_todays_game_1)
	var buf := l(S.g_unpack_buffer)
	var sv := w(S.g_stadium_vram)
	m.unpack(4, 2, buf)
	set_w(0x1776, w(S.g_unpack_vram))
	m.vram_dma(w(S.g_unpack_vram), buf, 0x800)
	add_w(S.g_unpack_vram, 0x800)
	m.unpack(6, 2, buf)
	m.vram_dma(sv + 0x6600, buf + w(S.g_team_home) * 0xC0, 0xC0)
	m.vram_dma(sv + 0x66C0, buf + w(S.g_team_away) * 0xC0, 0xC0)
	m.unpack(6, 1, buf)
	m.vram_dma(sv + 0x6780, buf + w(S.g_team_home) * 0x200, 0x200)
	m.vram_dma(sv + 0x6980, buf + w(S.g_team_away) * 0x200, 0x200)
	m.unpack(4, 15, buf)
	m.vram_dma(sv + 0x6400, buf + w(S.g_stadium) * 0x200, 0x200)
	m.text_draw_large(0x48, 0x48, rom("str_stadium_names") + w(S.g_stadium) * 8)
	m.text_draw_large(0x98, 0xA8, rom("str_weathers") + w(S.g_weather) * 8)
	m.text_draw_large(0x98, 0x90, rom("str_kickoff_times") + w(0x1630) * 8)
	if w(0x1630) == 2:
		m.text_draw_large(0x40, 8, rom("str_tonights_game"))
	var base := (sv >> 5) | 0xC000
	m.rect_fill_tiles(0x40, 0x50, 0x28, 0x38, base + 0x180 + (w(0x1642) * 4 if w(S.g_pads_home) != 0 else 0x20))
	m.rect_fill_tiles(0xB0, 0xC0, 0x28, 0x38, base + 0x1A4 + (w(0x1644) * 4 if w(S.g_pads_away) != 0 else 0x20))
	# The controllers: player number, pad (the 3-button one's when the
	# slot's pad type is 0) and the controller's label tiles.
	var labels := (w(0x1776) >> 5) | 0xA000
	var slot := S.g_control_slots
	for side in 2:
		var n := w(S.g_pads_home if side == 0 else S.g_pads_away)
		var a := rom("tbl_todays_game_home_pads" if side == 0 else "tbl_todays_game_away_pads")
		for d5 in n:
			var x0 := ISSRom.u16(a)
			var x1 := ISSRom.u16(a + 2)
			var y0 := ISSRom.u16(a + 4)
			var y1 := ISSRom.u16(a + 6)
			var num := d5 if side == 0 else d5 + w(S.g_pads_home)
			m.rect_fill_tiles(x0, x1, y0, y1, base + 0x1D0 + num * 2)
			m.rect_fill_tiles(x0, x1, y0 + 8, y1 + 8, base + 0x1CC + (2 if w(slot + 8) == 0 else 0))
			if side == 0:
				m.rect_fill_tiles(x0 + 0x10, x1 + 0x20, y0, y1 + 8, labels + d5 * 16)
			else:
				m.rect_fill_tiles(x0 - 0x20, x1 - 0x10, y0, y1 + 8, labels + 8 + d5 * 16)
			slot += 0x1A
			a += 8
	if w(S.g_pads_home) == 0:
		var a := rom("tbl_todays_game_home_pads")
		m.rect_fill_tiles(ISSRom.u16(a), ISSRom.u16(a + 2), ISSRom.u16(a + 4), ISSRom.u16(a + 6) + 8, base + 0x1A0)
	if w(S.g_pads_away) == 0:
		var a := rom("tbl_todays_game_away_pads")
		m.rect_fill_tiles(ISSRom.u16(a), ISSRom.u16(a + 2), ISSRom.u16(a + 4), ISSRom.u16(a + 6) + 8, base + 0x1C4)


func screen_todays_game_1(o: ISSMenu.Obj) -> void:
	o.update = screen_todays_game_2
	o.set_w(OBJ_DISTANCE, 0x80)
	screen_todays_game_2(o)


func screen_todays_game_2(o: ISSMenu.Obj) -> void:
	var go := false
	if w(0x153E) != 0:
		if pressed(PAD_B):
			set_w(0x182A, 0)
			set_w(0x18B2, 0)
			goto_screen(6)
	else:
		o.add_w(OBJ_DISTANCE, -1)
		go = o.w(OBJ_DISTANCE) == 0
	if go or pressed(PAD_C):
		set_w(0x1730, 0)
		set_l(S.g_next_state, ISSMenu.STATE_SCREEN)
		m.fade_out_start()
		m.play_sfx(95)
	# The lights: two colours of line 1 cycle every other frame.
	if w(S.g_fade_step) == 0x18 and w(S.g_frame_counter) & 1 == 0:
		var a := rom("tbl_light_colours") + (w(S.g_frame_counter) & 0x1E) * 2
		set_w(0x786, ISSRom.u16(a))
		set_w(0x788, ISSRom.u16(a + 2))
		m.cram_dma(0x30, 0x786, 4)
	m.boxes_draw_sprites(rom("tbl_todays_game_boxes"))


# --------------------------------------------------------------------------

## menu_input_040F5E (ISSModes.prematch_return).
func menu_input_040F5E() -> void:
	ISSModes.prematch_return()
