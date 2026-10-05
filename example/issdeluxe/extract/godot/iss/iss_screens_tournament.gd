class_name ISSScreensTournament
extends ISSScreens
## The short tournament (mode 5): how many of the eight teams humans play
## ($20), the eight teams ($21), the bracket ($22) and the tournament's own
## menu from the pre-match menu ($23).
##
## RAM as the league's: $1264 the teams (8), $1266 the human ones, $127C
## the slots' teams, $1270 the games played (of 7), $129C each game's
## winning slot, $126A the menu open, $127A after a password, $1272 the
## champion's slot.

func register(h: Dictionary) -> void:
	h[0x20] = screen_tournament_humans
	h[0x21] = screen_tournament_teams
	h[0x22] = screen_tournament_bracket
	h[0x23] = screen_tournament_menu


## The eight slots' pictures and flags to VRAM.
func _slot_tiles(pictures: int, flags: int) -> void:
	var buf := l(S.g_unpack_buffer)
	m.unpack(6, 1, buf)
	for k in 8:
		m.vram_dma(w(S.g_stadium_vram) + pictures + k * 0x200, buf + w(0x127C + 2 * k) * 0x200, 0x200)
	m.unpack(6, 2, buf)
	for k in 8:
		m.vram_dma(w(S.g_stadium_vram) + flags + k * 0xC0, buf + w(0x127C + 2 * k) * 0xC0, 0xC0)


# --------------------------------------------------------------------------
# Screen $20: the human teams, 1-8 (two columns of four).

func screen_tournament_humans() -> void:
	set_w(0x1264, 8)
	spawn(screen_tournament_humans_1)
	menu_state_0517B4(spawn(Callable()))


func screen_tournament_humans_1(o: ISSMenu.Obj) -> void:
	o.update = screen_tournament_humans_2
	o.set_w(T, 0)
	screen_tournament_humans_2(o)


func screen_tournament_humans_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_B):
		goto_screen(0)
	if pressed(PAD_C):
		goto_screen(3)
		m.play_sfx(95)
	m.boxes_draw_sprites(rom("screen_tournament_humans_2_data"))


func menu_state_0517B4(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0517B4_1
	o.set_w(T, 0)
	menu_state_0517B4_1(o)


func menu_state_0517B4_1(o: ISSMenu.Obj) -> void:
	humans_item(o, 1, menu_state_0517B4_1, menu_state_051AD4, menu_state_05187C, menu_state_051A0C,
		[0x58, 0x70, 0x51], [0x58, 0x70, 0x50, 0x60])


func menu_state_05187C(o: ISSMenu.Obj) -> void:
	o.update = menu_state_05187C_1
	o.set_w(T, 0)
	menu_state_05187C_1(o)


func menu_state_05187C_1(o: ISSMenu.Obj) -> void:
	humans_item(o, 2, menu_state_05187C_1, menu_state_051B9C, menu_state_051944, menu_state_0517B4,
		[0x58, 0x70, 0x69], [0x58, 0x70, 0x68, 0x78])


func menu_state_051944(o: ISSMenu.Obj) -> void:
	o.update = menu_state_051944_1
	o.set_w(T, 0)
	menu_state_051944_1(o)


func menu_state_051944_1(o: ISSMenu.Obj) -> void:
	humans_item(o, 3, menu_state_051944_1, menu_state_051C64, menu_state_051A0C, menu_state_05187C,
		[0x50, 0x78, 0x81], [0x50, 0x78, 0x80, 0x90])


func menu_state_051A0C(o: ISSMenu.Obj) -> void:
	o.update = menu_state_051A0C_1
	o.set_w(T, 0)
	menu_state_051A0C_1(o)


func menu_state_051A0C_1(o: ISSMenu.Obj) -> void:
	humans_item(o, 4, menu_state_051A0C_1, menu_state_051D2C, menu_state_0517B4, menu_state_051944,
		[0x50, 0x70, 0x99], [0x48, 0x70, 0x98, 0xA8])


func menu_state_051AD4(o: ISSMenu.Obj) -> void:
	o.update = menu_state_051AD4_1
	o.set_w(T, 0)
	menu_state_051AD4_1(o)


func menu_state_051AD4_1(o: ISSMenu.Obj) -> void:
	humans_item(o, 5, menu_state_051AD4_1, menu_state_0517B4, menu_state_051B9C, menu_state_051D2C,
		[0x90, 0xB0, 0x51], [0x90, 0xB0, 0x50, 0x60])


func menu_state_051B9C(o: ISSMenu.Obj) -> void:
	o.update = menu_state_051B9C_1
	o.set_w(T, 0)
	menu_state_051B9C_1(o)


func menu_state_051B9C_1(o: ISSMenu.Obj) -> void:
	humans_item(o, 6, menu_state_051B9C_1, menu_state_05187C, menu_state_051C64, menu_state_051AD4,
		[0x90, 0xA8, 0x69], [0x90, 0xA8, 0x68, 0x78])


func menu_state_051C64(o: ISSMenu.Obj) -> void:
	o.update = menu_state_051C64_1
	o.set_w(T, 0)
	menu_state_051C64_1(o)


func menu_state_051C64_1(o: ISSMenu.Obj) -> void:
	humans_item(o, 7, menu_state_051C64_1, menu_state_051944, menu_state_051D2C, menu_state_051B9C,
		[0x88, 0xB0, 0x81], [0x88, 0xB0, 0x80, 0x90])


func menu_state_051D2C(o: ISSMenu.Obj) -> void:
	o.update = menu_state_051D2C_1
	o.set_w(T, 0)
	menu_state_051D2C_1(o)


func menu_state_051D2C_1(o: ISSMenu.Obj) -> void:
	humans_item(o, 8, menu_state_051D2C_1, menu_state_051A0C, menu_state_051AD4, menu_state_051C64,
		[0x88, 0xB0, 0x99], [0x88, 0xB0, 0x98, 0xA8])


# --------------------------------------------------------------------------
# Screen $21: the eight teams with their controller icons.

func screen_tournament_teams() -> void:
	_slot_tiles(0x6400, 0x7400)
	for k in 8:
		m.rect_fill_tiles(0x50, 0x60, k * 16 + 0x28, k * 16 + 0x38, slot_icon(k))
	spawn(screen_tournament_teams_1)


func screen_tournament_teams_1(o: ISSMenu.Obj) -> void:
	o.update = screen_tournament_teams_2
	o.set_w(T, 0)
	screen_tournament_teams_2(o)


func screen_tournament_teams_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_B):
		goto_screen(3)
	if pressed(PAD_C):
		goto_screen(0x22)
		m.play_sfx(95)
	m.boxes_draw_sprites(rom("screen_tournament_teams_2_data"))


# --------------------------------------------------------------------------
# Screen $22: the bracket. The next game is set up (the computer teams'
# games before it simulated); each slot's controller icon and name plate
# stand where it has got to (its starting place, then the place of each
# game it won); the plane scrolls to the round being played, left / right
# move it.

func screen_tournament_bracket() -> void:
	m.menu_music(0x0D)
	if w(0x126A) == 0 and w(0x1270) < 7:
		ISSModes.tournament_next_game()
	_slot_tiles(0x66C0, 0x76C0)
	screen_tournament_bracket_4()
	var start := rom("screen_tournament_bracket_data2")
	var won := rom("screen_tournament_bracket_data")
	for k in 8:
		var at := start + k * 2
		for g in w(0x1270):
			if w(0x129C + g * 2) == k:
				at = won + g * 2
		var x := ISSRom.u8(at) * 8
		var y := ISSRom.u8(at + 1) * 8
		var ix := x if x >= 0x100 else x + 0x18
		m.rect_fill_tiles(ix, ix + 16, y, y + 16, slot_icon(k))
		var px := x + 0x10 if x > 0x100 else x
		m.rect_fill_tiles(px, px + 0x18, y, y + 16, tiles() + 0x3B6 + k * 6)
	set_w(S.g_plane_b_hscroll, ISSRom.u16(rom("screen_tournament_bracket_data3") + w(0x1270) * 2))
	spawn(screen_tournament_bracket_1)
	menu_state_0522FA(spawn(Callable()))


## After the final: the champion's slot.
func screen_tournament_bracket_4() -> void:
	if w(0x1270) == 7:
		set_w(0x1272, w(0x12A8))


func screen_tournament_bracket_1(o: ISSMenu.Obj) -> void:
	o.update = screen_tournament_bracket_2
	o.set_w(T, 0)
	screen_tournament_bracket_2(o)


## B: back to the tournament's menu, or before the first game to the
## teams; C: the menu, the pre-match menu (by way of the password after a
## game unless one was just entered), or after the final congratulations or
## game over.
func screen_tournament_bracket_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_B):
		if w(0x126A) != 0:
			goto_screen(0x23)
		elif w(0x1270) == 0:
			goto_screen(0x21)
	if pressed(PAD_C):
		if w(0x126A) != 0:
			set_w(S.g_next_screen, 0x23)
		elif w(0x1270) < 7:
			if w(0x1270) == 0:
				set_w(S.g_next_screen, 6)
			else:
				set_w(S.g_next_screen, 0x3B if w(0x127A) == 0 else 6)
				set_w(0x127A, 0)
		else:
			set_w(S.g_next_screen, 0x28 if sw(0x1272) < w(0x1266) else 0x27)
		set_l(S.g_next_state, ISSMenu.STATE_MENU)
		m.fade_out_start()
		m.play_sfx(95)
	m.boxes_draw_sprites(rom("screen_tournament_bracket_2_data"))


## Right scrolls plane B 8 a frame to $80 (or on to $100 while held), left
## back to $80 or 0.
func menu_state_0522FA(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0522FA_1
	o.set_w(T, 0)
	menu_state_0522FA_1(o)


func menu_state_0522FA_1(o: ISSMenu.Obj) -> void:
	if pressed(PAD_RIGHT):
		o.update = menu_state_0522FA_2
	if pressed(PAD_LEFT):
		o.update = menu_state_0522FA_4


func menu_state_0522FA_2(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0522FA_3
	o.set_w(T, 0)
	menu_state_0522FA_3(o)


func menu_state_0522FA_3(o: ISSMenu.Obj) -> void:
	set_w(S.g_pad_held_any, w(S.g_pad_held_any) & ~PAD_RIGHT)
	add_w(S.g_plane_b_hscroll, 8)
	if sw(S.g_plane_b_hscroll) > 0x100:
		set_w(S.g_plane_b_hscroll, 0x100)
		o.update = menu_state_0522FA
		return
	if w(S.g_plane_b_hscroll) == 0x80 and not pressed(PAD_RIGHT):
		o.update = menu_state_0522FA


func menu_state_0522FA_4(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0522FA_5
	o.set_w(T, 0)
	menu_state_0522FA_5(o)


func menu_state_0522FA_5(o: ISSMenu.Obj) -> void:
	set_w(S.g_pad_held_any, w(S.g_pad_held_any) & ~PAD_LEFT)
	add_w(S.g_plane_b_hscroll, -8)
	if sw(S.g_plane_b_hscroll) < 0:
		set_w(S.g_plane_b_hscroll, 0)
		o.update = menu_state_0522FA
		return
	if w(S.g_plane_b_hscroll) == 0x80 and not pressed(PAD_LEFT):
		o.update = menu_state_0522FA


# --------------------------------------------------------------------------
# Screen $23: the tournament's menu: the bracket, or back.

func screen_tournament_menu() -> void:
	set_w(0x126A, 1)
	spawn(screen_tournament_menu_1)
	menu_state_0524EC(spawn(Callable()))


func screen_tournament_menu_1(o: ISSMenu.Obj) -> void:
	o.update = screen_tournament_menu_2
	o.set_w(T, 0)
	screen_tournament_menu_2(o)


func screen_tournament_menu_2(_o: ISSMenu.Obj) -> void:
	m.boxes_draw_sprites(rom("screen_tournament_menu_2_data"))


func menu_state_0524EC_1(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0524EC_2
	menu_state_0524EC_2(o)


func menu_state_0524EC_2(o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		set_w(0x126A, 0)
		ISSModes.prematch_return()
		if w(S.g_next_screen) == 0x23:
			set_w(S.g_next_screen, 6)
		set_l(S.g_next_state, ISSMenu.STATE_MENU)
		m.fade_out_start()
		m.play_sfx(95)
	if pressed(PAD_UP | PAD_DOWN):
		o.update = menu_state_0524EC
		m.play_sfx(77)
	o.add_w(T, 1)
	m.cursor_draw(w(0x1768), 0xE0, 0xF8, 8)


## The bracket (the International Cup's finals share this menu: screen
## $2D).
func menu_state_0524EC(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0524EC_3
	menu_state_0524EC_3(o)


func menu_state_0524EC_3(o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		goto_screen(0x2D if w(S.g_game_mode) == 8 else 0x22)
		m.play_sfx(95)
	if pressed(PAD_B | PAD_UP | PAD_DOWN):
		o.update = menu_state_0524EC_1
	o.add_w(T, 1)
	m.cursor_draw_large(w(0x1768), 0x40, 0xC0, 0x58)
	if o.update == menu_state_0524EC_3:
		m.rect_highlight(0x38, 0xC8, 0x58, 0x68)
	else:
		m.rect_unhighlight(0x38, 0xC8, 0x58, 0x68)
