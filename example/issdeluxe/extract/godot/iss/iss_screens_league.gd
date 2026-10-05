class_name ISSScreensLeague
extends ISSScreens
## The short league (mode 4): how many of the six teams humans play ($1B),
## the six teams ($1C), the fixtures with the results so far ($1D), the
## league's own menu from the pre-match menu ($1E) and the table ($1F).
##
## RAM: $1264 the teams (6), $1266 the human ones (the first slots),
## $127C the six slots' teams, $1270 the games played (of 15,
## tbl_league_fixtures), $129C their results, $126A set while the league's
## menu is open, $127A set after a password, $1272 the winner's slot.

func register(h: Dictionary) -> void:
	h[0x1B] = screen_league_humans
	h[0x1C] = screen_league_teams
	h[0x1D] = screen_league_fixtures
	h[0x1E] = screen_league_menu
	h[0x1F] = screen_league_table


## The slots' team pictures (group 6 entry 1, $200 bytes a team) and flags
## (entry 2, $C0) to VRAM from pictures / flags on.
func _slot_tiles(pictures: int, flags: int) -> void:
	var buf := l(S.g_unpack_buffer)
	m.unpack(6, 1, buf)
	for k in 6:
		m.vram_dma(w(S.g_stadium_vram) + pictures + k * 0x200, buf + w(0x127C + 2 * k) * 0x200, 0x200)
	m.unpack(6, 2, buf)
	for k in 6:
		m.vram_dma(w(S.g_stadium_vram) + flags + k * 0xC0, buf + w(0x127C + 2 * k) * 0xC0, 0xC0)


## The flags of the game's two teams at $7D00 / $7DC0, from the flags
## unpacked at buf.
func _match_flags(buf: int) -> void:
	m.vram_dma(w(S.g_stadium_vram) + 0x7D00, buf + w(S.g_team_home) * 0xC0, 0xC0)
	m.vram_dma(w(S.g_stadium_vram) + 0x7DC0, buf + w(S.g_team_away) * 0xC0, 0xC0)


## The round ("1st" .. "5th", game / 3) at the top, or after the last game
## the round and the next game's place blanked.
func _round() -> void:
	if w(0x1270) == 15:
		m.rect_fill(0x30, 0xC0, 0xC0, 0xD0, tiles())
		m.rect_fill(0x18, 0x78, 0x18, 0x28, tiles())
	else:
		m.text_draw_large(0x38, 0x18, rom("screen_league_fixtures_data") + (w(0x1270) / 3) * 4)


# --------------------------------------------------------------------------
# Screen $1B: the human teams, 1-6 (two columns of three).

func screen_league_humans() -> void:
	set_w(0x1264, 6)
	spawn(screen_league_humans_1)
	menu_state_050480(spawn(Callable()))


func screen_league_humans_1(o: ISSMenu.Obj) -> void:
	o.update = screen_league_humans_2
	o.set_w(T, 0)
	screen_league_humans_2(o)


func screen_league_humans_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_B):
		goto_screen(0)
	if pressed(PAD_C):
		goto_screen(3)
		m.play_sfx(95)
	m.boxes_draw_sprites(rom("screen_league_humans_2_data"))


func menu_state_050480(o: ISSMenu.Obj) -> void:
	o.update = menu_state_050480_1
	o.set_w(T, 0)
	menu_state_050480_1(o)


func menu_state_050480_1(o: ISSMenu.Obj) -> void:
	humans_item(o, 1, menu_state_050480_1, menu_state_0506D8, menu_state_050548, menu_state_050610, [0x58, 0x70, 0x51], [0x58, 0x70, 0x50, 0x60])


func menu_state_050548(o: ISSMenu.Obj) -> void:
	o.update = menu_state_050548_1
	o.set_w(T, 0)
	menu_state_050548_1(o)


func menu_state_050548_1(o: ISSMenu.Obj) -> void:
	humans_item(o, 2, menu_state_050548_1, menu_state_0507A0, menu_state_050610, menu_state_050480, [0x58, 0x70, 0x69], [0x58, 0x70, 0x68, 0x78])


func menu_state_050610(o: ISSMenu.Obj) -> void:
	o.update = menu_state_050610_1
	o.set_w(T, 0)
	menu_state_050610_1(o)


func menu_state_050610_1(o: ISSMenu.Obj) -> void:
	humans_item(o, 3, menu_state_050610_1, menu_state_050868, menu_state_050480, menu_state_050548, [0x50, 0x78, 0x81], [0x50, 0x78, 0x80, 0x90])


func menu_state_0506D8(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0506D8_1
	o.set_w(T, 0)
	menu_state_0506D8_1(o)


func menu_state_0506D8_1(o: ISSMenu.Obj) -> void:
	humans_item(o, 4, menu_state_0506D8_1, menu_state_050480, menu_state_0507A0, menu_state_050868, [0x90, 0xB0, 0x51], [0x90, 0xB0, 0x50, 0x60])


func menu_state_0507A0(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0507A0_1
	o.set_w(T, 0)
	menu_state_0507A0_1(o)


func menu_state_0507A0_1(o: ISSMenu.Obj) -> void:
	humans_item(o, 5, menu_state_0507A0_1, menu_state_050548, menu_state_050868, menu_state_0506D8, [0x90, 0xB0, 0x69], [0x90, 0xB0, 0x68, 0x78])


func menu_state_050868(o: ISSMenu.Obj) -> void:
	o.update = menu_state_050868_1
	o.set_w(T, 0)
	menu_state_050868_1(o)


func menu_state_050868_1(o: ISSMenu.Obj) -> void:
	humans_item(o, 6, menu_state_050868_1, menu_state_050610, menu_state_0506D8, menu_state_0507A0, [0x90, 0xA8, 0x81], [0x90, 0xA8, 0x80, 0x90])


# --------------------------------------------------------------------------
# Screen $1C: the six teams, each with its controller icon.

func screen_league_teams() -> void:
	_slot_tiles(0x6400, 0x7000)
	for k in 6:
		m.rect_fill_tiles(0x50, 0x60, k * 16 + 0x38, k * 16 + 0x48, slot_icon(k))
	spawn(screen_league_teams_1)


func screen_league_teams_1(o: ISSMenu.Obj) -> void:
	o.update = screen_league_teams_2
	o.set_w(T, 0)
	screen_league_teams_2(o)


func screen_league_teams_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_B):
		goto_screen(3)
	if pressed(PAD_C):
		goto_screen(0x1D)
		m.play_sfx(95)
	m.boxes_draw_sprites(rom("screen_league_teams_2_data"))


# --------------------------------------------------------------------------
# Screen $1D: the fixtures. The next game is set up (the computer teams'
# games before it simulated); the teams down the left, the results so far
# as marks in the grid on the right (plane B scrolls to it with right).

func screen_league_fixtures() -> void:
	m.menu_music(0x0D)
	if w(0x126A) == 0 and w(0x1270) < 15:
		ISSModes.league_next_game()
	_round()
	_slot_tiles(0x6C80, 0x7880)
	_match_flags(l(S.g_unpack_buffer))
	var rows := rom("screen_league_fixtures_data2")
	for k in 6:
		var y := ISSRom.u16(rows + k * 2)
		m.rect_fill_tiles(0x80, 0x90, y, y + 16, slot_icon(k))
	# The waving flags' frames (group 4 entry 30) at $1770.
	var buf := l(S.g_unpack_buffer)
	set_l(0x1770, buf)
	set_l(S.g_unpack_buffer, m.unpack(4, 30, buf))
	var marks := rom("screen_league_fixtures_data3")
	for g in w(0x1270):
		var r := w(0x129C + g * 2)
		var a := marks + g * 4
		m.result_mark_draw(ISSRom.u8(a) * 8, ISSRom.u8(a + 1) * 8, r)
		m.result_mark_draw(ISSRom.u8(a + 2) * 8, ISSRom.u8(a + 3) * 8, r if r == 2 else r ^ 1)
	spawn(screen_league_fixtures_1)
	menu_state_050F60(spawn(Callable()))


func screen_league_fixtures_1(o: ISSMenu.Obj) -> void:
	o.update = screen_league_fixtures_2
	o.set_w(T, 0)
	screen_league_fixtures_2(o)


## B: back to the league's menu, or before the first game to the teams;
## C: the league's menu, the pre-match menu before the first game, else
## the table.
func screen_league_fixtures_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_B):
		if w(0x126A) != 0:
			goto_screen(0x1E)
		elif w(0x1270) == 0:
			goto_screen(0x1C)
	if pressed(PAD_C):
		if w(0x126A) != 0:
			goto_screen(0x1E)
		elif w(0x1270) == 0:
			goto_screen(6)
		else:
			goto_screen(0x1F)
		m.play_sfx(95)
	m.flags_wave()
	m.boxes_draw_sprites(rom("screen_league_fixtures_2_data"))


## Plane B back to 0 (4 a frame); right scrolls to $60.
func menu_state_050F60(o: ISSMenu.Obj) -> void:
	o.update = menu_state_050F60_1
	o.set_w(T, 0)
	menu_state_050F60_1(o)


func menu_state_050F60_1(o: ISSMenu.Obj) -> void:
	if w(S.g_plane_b_hscroll) != 0:
		add_w(S.g_plane_b_hscroll, -4)
	elif pressed(PAD_RIGHT):
		o.update = menu_state_050F60_2


func menu_state_050F60_2(o: ISSMenu.Obj) -> void:
	o.update = menu_state_050F60_3
	o.set_w(T, 0)
	menu_state_050F60_3(o)


func menu_state_050F60_3(o: ISSMenu.Obj) -> void:
	if sw(S.g_plane_b_hscroll) < 0x60:
		add_w(S.g_plane_b_hscroll, 4)
	elif pressed(PAD_LEFT):
		o.update = menu_state_050F60


# --------------------------------------------------------------------------
# Screen $1E: the league's menu (the pre-match menu's eleventh item): the
# next game's fixtures, the table, or back (the cursor at the top right).

func screen_league_menu() -> void:
	set_w(0x126A, 1)
	spawn(screen_league_menu_1)
	menu_state_05113E(spawn(Callable()))


func screen_league_menu_1(o: ISSMenu.Obj) -> void:
	o.update = screen_league_menu_2
	o.set_w(T, 0)
	screen_league_menu_2(o)


func screen_league_menu_2(_o: ISSMenu.Obj) -> void:
	m.boxes_draw_sprites(rom("screen_league_menu_2_data"))


## Back: to where the pre-match menu's sub-screens return.
func menu_state_05108A(o: ISSMenu.Obj) -> void:
	o.update = menu_state_05108A_1
	menu_state_05108A_1(o)


func menu_state_05108A_1(o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		set_w(0x126A, 0)
		ISSModes.prematch_return()
		if w(S.g_next_screen) == 0x1E:
			set_w(S.g_next_screen, 6)
		set_l(S.g_next_state, ISSMenu.STATE_MENU)
		m.fade_out_start()
		m.play_sfx(95)
	if pressed(PAD_UP):
		o.update = menu_state_051218
		m.play_sfx(77)
	if pressed(PAD_DOWN):
		o.update = menu_state_05113E
		m.play_sfx(77)
	o.add_w(T, 1)
	m.cursor_draw(w(0x1768), 0xE0, 0xF8, 8)


## The fixtures (of the league, or the cup's rounds that share this menu).
func menu_state_05113E(o: ISSMenu.Obj) -> void:
	o.update = menu_state_05113E_1
	menu_state_05113E_1(o)


func menu_state_05113E_1(o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		set_l(S.g_next_state, ISSMenu.STATE_MENU)
		var to := {4: 0x1D, 6: 0x29, 7: 0x2B}
		if to.has(w(S.g_game_mode)):
			set_w(S.g_next_screen, to[w(S.g_game_mode)])
		m.fade_out_start()
		m.play_sfx(95)
	if pressed(PAD_B | PAD_UP):
		o.update = menu_state_05108A
	if pressed(PAD_DOWN):
		o.update = menu_state_051218
		m.play_sfx(77)
	o.add_w(T, 1)
	m.cursor_draw_large(w(0x1768), 0x40, 0xC0, 0x50)
	if o.update == menu_state_05113E_1:
		m.rect_highlight(0x40, 0xC0, 0x50, 0x60)
	else:
		m.rect_unhighlight(0x40, 0xC0, 0x50, 0x60)


## The table.
func menu_state_051218(o: ISSMenu.Obj) -> void:
	o.update = menu_state_051218_1
	menu_state_051218_1(o)


func menu_state_051218_1(o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		set_l(S.g_next_state, ISSMenu.STATE_MENU)
		var to := {4: 0x1F, 6: 0x2A, 7: 0x2C}
		if to.has(w(S.g_game_mode)):
			set_w(S.g_next_screen, to[w(S.g_game_mode)])
		m.fade_out_start()
		m.play_sfx(95)
	if pressed(PAD_B | PAD_DOWN):
		o.update = menu_state_05108A
	if pressed(PAD_UP):
		o.update = menu_state_05113E
		m.play_sfx(77)
	o.add_w(T, 1)
	m.cursor_draw_large(w(0x1768), 0x40, 0xC0, 0x68)
	if o.update == menu_state_051218_1:
		m.rect_highlight(0x40, 0xC0, 0x68, 0x78)
	else:
		m.rect_unhighlight(0x40, 0xC0, 0x68, 0x78)


# --------------------------------------------------------------------------
# Screen $1F: the table: place, picture, controller, won, lost, drawn and
# points of each slot by points.

func screen_league_table() -> void:
	_round()
	var buf := l(S.g_unpack_buffer)
	var pictures := buf
	buf = m.unpack(6, 1, buf)
	var flags := buf
	buf = m.unpack(6, 2, buf)
	set_l(S.g_unpack_buffer, buf)
	_match_flags(flags)
	var t := ISSModes.league_standings(buf) & 0xFFFF
	set_l(S.g_unpack_buffer, 0xFF0000 | (t + 36))
	var digits := rom("screen_league_table_data2")
	for k in 6:
		var e := t + k * 6
		var y := k * 0x18 + 0x30
		var slot := ISSRam.b(e + 1)
		var team := w(0x127C + slot * 2)
		m.text_draw_large(0x18, y, digits + ISSRam.b(e) * 2)
		m.vram_dma(w(S.g_stadium_vram) + 0x6C80 + k * 0x200, pictures + team * 0x200, 0x200)
		m.vram_dma(w(S.g_stadium_vram) + 0x7880 + k * 0xC0, flags + team * 0xC0, 0xC0)
		m.rect_fill_tiles(0x80, 0x90, y, y + 16, slot_icon(slot))
		m.text_draw_large(0xA0, y, digits + ISSRam.b(e + 2) * 2)
		m.text_draw_large(0xB8, y, digits + ISSRam.b(e + 3) * 2)
		m.text_draw_large(0xD0, y, digits + ISSRam.b(e + 4) * 2)
		var p := ISSRam.b(e + 5)
		m.text_draw_large(0xE8, y, digits + (p % 10) * 2)
		if p / 10 != 0:
			m.text_draw_large(0xE0, y, digits + (p / 10) * 2)
	spawn(screen_league_table_1)


func screen_league_table_1(o: ISSMenu.Obj) -> void:
	o.update = screen_league_table_2
	o.set_w(T, 0)
	screen_league_table_2(o)


## B: back to the league's menu (when it was opened from there); C: the
## league's menu, the password (unless one was just entered) then the
## pre-match menu, or after the last game the end: congratulations when a
## human slot won, else game over.
func screen_league_table_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_B) and w(0x126A) != 0:
		goto_screen(0x1E)
	if pressed(PAD_C):
		if w(0x1270) < 15:
			if w(0x126A) != 0:
				set_w(S.g_next_screen, 0x1E)
			else:
				set_w(S.g_next_screen, 0x3B if w(0x127A) == 0 else 6)
				set_w(0x127A, 0)
		else:
			set_w(S.g_next_screen, 0x28 if sw(0x1272) < w(0x1266) else 0x27)
		set_l(S.g_next_state, ISSMenu.STATE_MENU)
		m.fade_out_start()
		m.play_sfx(95)
	m.boxes_draw_sprites(rom("screen_league_table_2_data"))
