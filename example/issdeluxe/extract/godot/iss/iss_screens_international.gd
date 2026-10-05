class_name ISSScreensInternational
extends ISSScreens
## The International Cup (modes 6-8): the elimination round's fixtures
## ($29) and table ($2A), the group round's fixtures ($2B) and table ($2C),
## and the finals' bracket ($2D). Each fixtures screen sets up the next
## game (simulating the computer teams' ones) unless the competition's menu
## is open ($126A, which also sends B and C back to it).
##
## RAM: $126C the region / the group letter, $127C the slots' teams (slot 0
## the human's), $1270 the games played, $129C their results, $127A set
## after a password, $1272 0 still in, 1 out (ISSModes).

func register(h: Dictionary) -> void:
	h[0x29] = screen_intl_elimination
	h[0x2A] = screen_intl_elimination_table
	h[0x2B] = screen_intl_group
	h[0x2C] = screen_intl_group_table
	h[0x2D] = screen_intl_finals


## The first n slots' team pictures (group 6 entry 1, $200 bytes a team)
## to VRAM from pictures on and their flags (entry 2, $C0) from flags on;
## the game's two flags at match_flags and $C0 after it.
func _slot_tiles(n: int, pictures: int, flags: int, match_flags: int) -> void:
	var buf := l(S.g_unpack_buffer)
	var vram := w(S.g_stadium_vram)
	m.unpack(6, 1, buf)
	for k in n:
		m.vram_dma(vram + pictures + k * 0x200, buf + w(0x127C + 2 * k) * 0x200, 0x200)
	m.unpack(6, 2, buf)
	for k in n:
		m.vram_dma(vram + flags + k * 0xC0, buf + w(0x127C + 2 * k) * 0xC0, 0xC0)
	if match_flags != 0:
		m.vram_dma(vram + match_flags, buf + w(S.g_team_home) * 0xC0, 0xC0)
		m.vram_dma(vram + match_flags + 0xC0, buf + w(S.g_team_away) * 0xC0, 0xC0)


## The waving flags' frames (group 4 entry 30) at $1770.
func _wave_frames() -> void:
	var buf := l(S.g_unpack_buffer)
	set_l(0x1770, buf)
	set_l(S.g_unpack_buffer, m.unpack(4, 30, buf))


## The results so far as marks: per game two cells (bytes x, y in cells)
## of marks, the home side's result and the away side's.
func _marks(marks: int) -> void:
	for g in w(0x1270):
		var r := w(0x129C + g * 2)
		var a := marks + g * 4
		m.result_mark_draw(ISSRom.u8(a) * 8, ISSRom.u8(a + 1) * 8, r)
		m.result_mark_draw(ISSRom.u8(a + 2) * 8, ISSRom.u8(a + 3) * 8, r if r == 2 else r ^ 1)


## A table's rows (ISSModes.intl_table at t, n rows from y $60, $18
## apart): the place, the slot's picture ($6C80 + row * $200) and flag
## (flags + row * $C0), won, lost, drawn and points.
func _table_rows(t: int, n: int, flags: int) -> void:
	var digits := rom("screen_intl_elimination_table_data2" if n == 3 else "screen_intl_group_table_data2")
	var pictures := l(0x1776)
	var flag_tiles := l(0x177A)
	var vram := w(S.g_stadium_vram)
	for row in n:
		var r := t + row * 6
		var y := row * 0x18 + 0x60
		m.text_draw_large(0x18, y, digits + ISSRam.b(r) * 2)
		var team := w(0x127C + ISSRam.b(r + 1) * 2)
		m.vram_dma(vram + 0x6C80 + row * 0x200, pictures + team * 0x200, 0x200)
		m.vram_dma(vram + flags + row * 0xC0, flag_tiles + team * 0xC0, 0xC0)
		for i in 4:
			m.text_draw_large(0xA0 + i * 0x18, y, digits + ISSRam.b(r + 2 + i) * 2)


## The pictures at $1776 and the flags at $177A (both kept in the unpack
## buffer), the game's two flags at match_flags and $C0 after it.
func _table_tiles(match_flags: int) -> void:
	var buf := l(S.g_unpack_buffer)
	set_l(0x1776, buf)
	buf = m.unpack(6, 1, buf)
	set_l(0x177A, buf)
	set_l(S.g_unpack_buffer, m.unpack(6, 2, buf))
	var vram := w(S.g_stadium_vram)
	m.vram_dma(vram + match_flags, l(0x177A) + w(S.g_team_home) * 0xC0, 0xC0)
	m.vram_dma(vram + match_flags + 0xC0, l(0x177A) + w(S.g_team_away) * 0xC0, 0xC0)


## C after a table or a bracket between games: the competition's menu,
## else the password (none just after one was entered), then the
## pre-match menu.
func _between_games() -> void:
	if w(0x126A) != 0:
		set_w(S.g_next_screen, 0x1E)
	else:
		set_w(S.g_next_screen, 0x3B if w(0x127A) == 0 else 6)
		set_w(0x127A, 0)


func _leave() -> void:
	set_l(S.g_next_state, ISSMenu.STATE_MENU)
	m.fade_out_start()
	m.play_sfx(95)


# --------------------------------------------------------------------------
# Screen $29: the elimination round (three teams of the region, each
# playing the other two once): the region's name, the results as marks;
# after the third game the next game's place blanked.

func screen_intl_elimination() -> void:
	m.menu_music(0x0C)
	if w(0x126A) == 0 and w(0x1270) < 3:
		ISSModes.intl_elimination_next_game()
	if w(0x1270) == 3:
		m.rect_fill(0x30, 0xC0, 0xB0, 0xC8, tiles())
	_slot_tiles(3, 0x6C80, 0x7280, 0x74C0)
	_wave_frames()
	m.text_draw_large(0x18, 0x30, rom("screen_intl_elimination_data") + w(0x126C) * 13)
	_marks(rom("screen_intl_elimination_data2"))
	spawn(screen_intl_elimination_1)


func screen_intl_elimination_1(o: ISSMenu.Obj) -> void:
	o.update = screen_intl_elimination_2
	o.set_w(T, 0)
	screen_intl_elimination_2(o)


## B: back to the competition's menu, or before the first game to the team
## select; C: the menu, the pre-match menu before the first game, else the
## table.
func screen_intl_elimination_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_B):
		if w(0x126A) != 0:
			goto_screen(0x1E)
		elif w(0x1270) == 0:
			goto_screen(3)
	if pressed(PAD_C):
		if w(0x126A) != 0:
			set_w(S.g_next_screen, 0x1E)
		elif w(0x1270) == 0:
			set_w(S.g_next_screen, 6)
		else:
			set_w(S.g_next_screen, 0x2A)
		_leave()
	m.flags_wave()
	m.boxes_draw_sprites(rom("screen_intl_elimination_2_data"))


# --------------------------------------------------------------------------
# Screen $2A: the elimination round's table: place, team, won, lost, drawn,
# points. After the third game C goes on to the group round (the first two
# through) or to game over.

func screen_intl_elimination_table() -> void:
	if w(0x1270) == 3:
		m.rect_fill(0x30, 0xC0, 0xB0, 0xC8, tiles())
	_table_tiles(0x74C0)
	_table_rows(ISSModes.intl_elimination_table(), 3, 0x7280)
	m.text_draw_large(0x18, 0x30, rom("screen_intl_elimination_table_data") + w(0x126C) * 13)
	spawn(screen_intl_elimination_table_1)


func screen_intl_elimination_table_1(o: ISSMenu.Obj) -> void:
	o.update = screen_intl_elimination_table_2
	o.set_w(T, 0)
	screen_intl_elimination_table_2(o)


func screen_intl_elimination_table_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_B) and w(0x126A) != 0:
		goto_screen(0x1E)
	if pressed(PAD_C):
		if w(0x1270) != 3:
			_between_games()
		elif w(0x1272) == 0:
			ISSModes.intl_group_start()
			set_w(S.g_next_screen, 0x2B)
		else:
			set_w(S.g_next_screen, 0x27)
		_leave()
	m.boxes_draw_sprites(rom("screen_intl_elimination_table_2_data"))


# --------------------------------------------------------------------------
# Screen $2B: the group round (four teams, each playing the others once):
# the group's letter, the results as marks.

func screen_intl_group() -> void:
	m.menu_music(0x0C)
	if w(0x126A) == 0 and w(0x1270) < 6:
		ISSModes.intl_group_next_game()
	if w(0x1270) == 6:
		m.rect_fill(0x30, 0xC0, 0xC0, 0xD0, tiles())
	_slot_tiles(4, 0x6C80, 0x7480, 0x7780)
	_wave_frames()
	m.text_draw_large(0x18, 0x30, rom("screen_intl_group_data") + w(0x126C) * 2)
	_marks(rom("screen_intl_group_data2"))
	spawn(screen_intl_group_1)


func screen_intl_group_1(o: ISSMenu.Obj) -> void:
	o.update = screen_intl_group_2
	o.set_w(T, 0)
	screen_intl_group_2(o)


## B: back to the competition's menu; C: the menu, before the group's
## first game the password (then the pre-match menu), else the table.
func screen_intl_group_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_B) and w(0x126A) != 0:
		goto_screen(0x1E)
	if pressed(PAD_C):
		if w(0x126A) != 0:
			set_w(S.g_next_screen, 0x1E)
		elif w(0x1270) == 0:
			_between_games()
		else:
			set_w(S.g_next_screen, 0x2C)
		_leave()
	m.flags_wave()
	m.boxes_draw_sprites(rom("screen_intl_group_2_data"))


# --------------------------------------------------------------------------
# Screen $2C: the group's table. After the sixth game C goes on to the
# finals (the first two through) or to game over.

func screen_intl_group_table() -> void:
	if w(0x1270) == 6:
		m.rect_fill(0x30, 0xC0, 0xC0, 0xD0, tiles())
	_table_tiles(0x7780)
	_table_rows(ISSModes.intl_group_table(), 4, 0x7480)
	m.text_draw_large(0x28, 0x30, rom("screen_intl_group_table_data") + w(0x126C) * 2)
	spawn(screen_intl_group_table_1)


func screen_intl_group_table_1(o: ISSMenu.Obj) -> void:
	o.update = screen_intl_group_table_2
	o.set_w(T, 0)
	screen_intl_group_table_2(o)


func screen_intl_group_table_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_B) and w(0x126A) != 0:
		goto_screen(0x1E)
	if pressed(PAD_C):
		if w(0x1270) < 6:
			_between_games()
		elif w(0x1272) == 0:
			ISSModes.international_finals()
			set_w(S.g_next_screen, 0x2D)
		else:
			set_w(S.g_next_screen, 0x27)
		_leave()
	m.boxes_draw_sprites(rom("screen_intl_group_table_2_data"))


# --------------------------------------------------------------------------
# Screen $2D: the finals' bracket of sixteen: each slot's flag where it has
# got to (its starting place, then the place of each game it won); plane B
# scrolls to the round being played, left / right move it. Winning the
# final goes to the trophy (state_screen 2).

func screen_intl_finals() -> void:
	m.menu_music(0x0C)
	if w(0x126A) == 0 and w(0x1270) < 15:
		ISSModes.intl_finals_next_game()
	_slot_tiles(16, 0x70C0, 0x90C0, 0)
	screen_intl_finals_3()
	var start := rom("screen_intl_finals_data2")
	var won := rom("screen_intl_finals_data")
	for k in 16:
		var at := start + k * 2
		for g in w(0x1270):
			if w(0x129C + g * 2) == k:
				at = won + g * 2
		var x := ISSRom.u8(at) * 8
		var y := ISSRom.u8(at + 1) * 8
		m.rect_fill_tiles(x, x + 0x18, y, y + 0x10, tiles() + 0x486 + k * 6)
	set_w(S.g_plane_b_hscroll, ISSRom.u16(rom("screen_intl_finals_data3") + w(0x1270) * 2))
	spawn(screen_intl_finals_1)
	spawn(menu_state_05551C)


## After the final: the champion's slot.
func screen_intl_finals_3() -> void:
	if w(0x1270) == 15:
		set_w(0x1272, w(0x12B8))


func screen_intl_finals_1(o: ISSMenu.Obj) -> void:
	o.update = screen_intl_finals_2
	o.set_w(T, 0)
	screen_intl_finals_2(o)


## B: back to the competition's menu (the tournament's, $23); C: the menu,
## the pre-match menu by way of the password, or after the final the
## trophy or game over.
func screen_intl_finals_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_B) and w(0x126A) != 0:
		goto_screen(0x23)
	if pressed(PAD_C):
		set_l(S.g_next_state, ISSMenu.STATE_MENU)
		if w(0x126A) != 0:
			set_w(S.g_next_screen, 0x23)
		elif w(0x1270) < 15:
			set_w(S.g_next_screen, 0x3B if w(0x127A) == 0 else 6)
			set_w(0x127A, 0)
		elif w(0x1272) == 0:
			set_l(S.g_next_state, ISSMenu.STATE_SCREEN)
			set_w(0x1730, 2)
			set_w(S.g_weather, 1)
			set_w(0x1630, 0)
		else:
			set_w(S.g_next_screen, 0x27)
		m.fade_out_start()
		m.play_sfx(95)
	m.boxes_draw_sprites(rom("screen_intl_finals_2_data"))


## Right scrolls plane B 8 a frame to $80 (or on to $100 while held), left
## back to $80 or 0 (the tournament's menu_state_0522FA again).
func menu_state_05551C(o: ISSMenu.Obj) -> void:
	o.update = menu_state_05551C_1
	o.set_w(T, 0)
	menu_state_05551C_1(o)


func menu_state_05551C_1(o: ISSMenu.Obj) -> void:
	if pressed(PAD_RIGHT):
		o.update = menu_state_05551C_2
	if pressed(PAD_LEFT):
		o.update = menu_state_05551C_4


func menu_state_05551C_2(o: ISSMenu.Obj) -> void:
	o.update = menu_state_05551C_3
	o.set_w(T, 0)
	menu_state_05551C_3(o)


func menu_state_05551C_3(o: ISSMenu.Obj) -> void:
	set_w(S.g_pad_held_any, w(S.g_pad_held_any) & ~PAD_RIGHT)
	add_w(S.g_plane_b_hscroll, 8)
	if sw(S.g_plane_b_hscroll) > 0x100:
		set_w(S.g_plane_b_hscroll, 0x100)
		o.update = menu_state_05551C
		return
	if w(S.g_plane_b_hscroll) == 0x80 and not pressed(PAD_RIGHT):
		o.update = menu_state_05551C


func menu_state_05551C_4(o: ISSMenu.Obj) -> void:
	o.update = menu_state_05551C_5
	o.set_w(T, 0)
	menu_state_05551C_5(o)


func menu_state_05551C_5(o: ISSMenu.Obj) -> void:
	set_w(S.g_pad_held_any, w(S.g_pad_held_any) & ~PAD_LEFT)
	add_w(S.g_plane_b_hscroll, -8)
	if sw(S.g_plane_b_hscroll) < 0:
		set_w(S.g_plane_b_hscroll, 0)
		o.update = menu_state_05551C
		return
	if w(S.g_plane_b_hscroll) == 0x80 and not pressed(PAD_LEFT):
		o.update = menu_state_05551C
