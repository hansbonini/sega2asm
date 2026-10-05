class_name ISSScreensWorldSeries
extends ISSScreens
## The World Series (mode 9): today's games ($2F, six pages of three, the
## human's first), the day's results ($30), the table ($31, six pages of
## six) and the series' own menu from the pre-match menu ($32). Left /
## right turn the pages.
##
## RAM: $126C the series (0 first, 1 second), $1270 the days played (of
## 35), $129C each team's wins, $1776 the page, $1778 / $177C the team
## pictures and flags kept in the unpack buffer, $1384 the day's games,
## results or table (ISSModes), $126A the menu open, $127A after a
## password, $1272 0 when the human's team won the series.

func register(h: Dictionary) -> void:
	h[0x2F] = screen_ws_todays_game
	h[0x30] = screen_ws_results
	h[0x31] = screen_ws_table
	h[0x32] = screen_ws_menu


## The pictures (group 6 entry 1) at $1778 and the flags (entry 2) at
## $177C, both kept in the unpack buffer.
func _team_tiles() -> void:
	var buf := l(S.g_unpack_buffer)
	set_l(0x1778, buf)
	buf = m.unpack(6, 1, buf)
	set_l(0x177C, buf)
	set_l(S.g_unpack_buffer, m.unpack(6, 2, buf))


## Team t's picture to VRAM at pictures and its flag at flags (offsets
## from g_stadium_vram).
func _team(t: int, pictures: int, flags: int) -> void:
	var vram := w(S.g_stadium_vram)
	m.vram_dma(vram + pictures, l(0x1778) + t * 0x200, 0x200)
	m.vram_dma(vram + flags, l(0x177C) + t * 0xC0, 0xC0)


## The day (units at x, tens before them when any; digits: "0".."9" then
## a blank, two bytes each), the suffix while it is below last (from
## suffix + (day + back) * 4) and the series' name at (sx, sy).
func _day(digits: int, day: int, x: int, y: int, suffix: int, last: int, back: int, sx: int, sy: int,
		series: int) -> void:
	m.text_draw_large(x, y, digits + (day % 10) * 2)
	if day / 10 != 0:
		m.text_draw_large(x - 8, y, digits + (day / 10) * 2)
	if w(0x1270) < last:
		m.text_draw_large(x + 8, y, suffix + (w(0x1270) + back) * 4)
	m.text_draw_large(sx, sy, series + w(0x126C) * 4)


## A number of up to two digits right-aligned: units at x, the tens (or a
## blank) before.
func _number(small: bool, digits: int, x: int, y: int, v: int) -> void:
	var tens := v / 10
	_text(small, x, y, digits + (v % 10) * 2)
	_text(small, x - 8, y, digits + (tens if tens != 0 else 10) * 2)


## A number of up to two digits left-aligned at x (a blank after one
## digit).
func _number_left(small: bool, digits: int, x: int, y: int, v: int) -> void:
	var tens := v / 10
	if tens != 0:
		_text(small, x, y, digits + tens * 2)
		_text(small, x + 8, y, digits + (v % 10) * 2)
	else:
		_text(small, x + 8, y, digits + 20)
		_text(small, x, y, digits + (v % 10) * 2)


func _text(small: bool, x: int, y: int, a: int) -> void:
	if small:
		m.text_draw_small(x, y, a)
	else:
		m.text_draw_large(x, y, a)


## Right / left: the next / previous page (0-5) drawn by redraw.
func _pages(o: ISSMenu.Obj, redraw: Callable) -> void:
	if pressed(PAD_RIGHT) and w(0x1776) != 5:
		add_w(0x1776, 1)
		o.update = redraw
		m.play_sfx(77)
	if pressed(PAD_LEFT) and w(0x1776) != 0:
		add_w(0x1776, -1)
		o.update = redraw
		m.play_sfx(77)


## The arrows to the other pages at y.
func _arrows(o: ISSMenu.Obj, y: int) -> void:
	o.add_w(T, 1)
	if w(0x1776) != 0:
		m.pad_icon_draw(0, 0x08, y)
	if w(0x1776) != 5:
		m.pad_icon_draw(1, 0xF0, y)


func _leave() -> void:
	set_l(S.g_next_state, ISSMenu.STATE_MENU)
	m.fade_out_start()
	m.play_sfx(95)


# --------------------------------------------------------------------------
# Screen $2F: today's games (the human's set up), three a page.

func screen_ws_todays_game() -> void:
	m.menu_music(9)
	ISSModes.ws_next_game()
	set_w(0x1776, 0)
	_team_tiles()
	_day(rom("screen_ws_todays_game_data2"), w(0x1270) + 1, 0x90, 0x20, rom("screen_ws_todays_game_data3"),
		3, 0, 0x20, 0x20, rom("screen_ws_todays_game_data"))
	menu_state_05579A(spawn(Callable()))


## The page's six teams' pictures ($6400 on) and flags ($7000 on).
func menu_state_05579A(o: ISSMenu.Obj) -> void:
	o.update = menu_state_05579A_1
	var a := l(0x1384) + w(0x1776) * 6
	for k in 6:
		_team(ISSRam.b(a + k), 0x6400 + k * 0x200, 0x7000 + k * 0xC0)
	menu_state_05579A_1(o)


## B: before the first game of the first series back to the team select;
## C: the pre-match menu (after the first day by way of the password).
func menu_state_05579A_1(o: ISSMenu.Obj) -> void:
	_pages(o, menu_state_05579A)
	if pressed(PAD_B) and w(0x126C) == 0 and w(0x1270) == 0:
		goto_screen(3)
	if pressed(PAD_C):
		if w(0x1270) == 0:
			set_w(S.g_next_screen, 6)
		else:
			set_w(S.g_next_screen, 0x3B if w(0x127A) == 0 else 6)
			set_w(0x127A, 0)
		_leave()
	_arrows(o, 0xC0)


# --------------------------------------------------------------------------
# Screen $30: the day's results (recorded here), three a page: the scores
# (the penalties under a level one), the winner's highlighted.

func screen_ws_results() -> void:
	m.menu_music(9)
	ISSModes.ws_record_day()
	set_w(0x1776, 0)
	_team_tiles()
	_day(rom("menu_data_055E74"), w(0x1270), 0x90, 0x20, rom("screen_ws_results_data2"), 2, -1, 0x20, 0x20,
		rom("screen_ws_results_data"))
	menu_state_055ABA(spawn(Callable()))


func menu_state_055ABA(o: ISSMenu.Obj) -> void:
	o.update = menu_state_055ABA_1
	var digits := rom("menu_data_055E74")
	var a := l(0x1384) + w(0x1776) * 18
	for k in 3:
		var r := a + k * 6
		_team(ISSRam.b(r), 0x6420 + k * 0x400, 0x7020 + k * 0x180)
		_team(ISSRam.b(r + 1), 0x6620 + k * 0x400, 0x70E0 + k * 0x180)
		var y := k * 0x30 + 0x50
		_number(false, digits, 0x70, y, ISSRam.b(r + 2))
		_number_left(false, digits, 0x88, y, ISSRam.b(r + 3))
		var first := ISSRam.sb(r + 2)
		var second := ISSRam.sb(r + 3)
		if first != second:
			m.text_draw_small(0x60, y + 0x10, rom("menu_state_055ABA_data"))
		else:
			m.text_draw_small(0x60, y + 0x10, rom("menu_state_055ABA_data2"))
			_number(true, digits, 0x88, y + 0x10, ISSRam.b(r + 4))
			_number_left(true, digits, 0x98, y + 0x10, ISSRam.b(r + 5))
			first = ISSRam.sb(r + 4)
			second = ISSRam.sb(r + 5)
		if first > second:
			m.rect_highlight(0x68, 0x78, y, y + 0x10)
		else:
			m.rect_highlight(0x88, 0x98, y, y + 0x10)
	menu_state_055ABA_1(o)


## C: the table.
func menu_state_055ABA_1(o: ISSMenu.Obj) -> void:
	_pages(o, menu_state_055ABA)
	if pressed(PAD_C):
		set_w(S.g_next_screen, 0x31)
		_leave()
	_arrows(o, 0xC0)


# --------------------------------------------------------------------------
# Screen $31: the table (place, team, won, lost), six a page; after the
# last day the next game's box and the day blanked.

func screen_ws_table() -> void:
	set_w(0x1776, 0)
	if w(0x1270) == 35:
		m.rect_fill(0x30, 0xC0, 0xC8, 0xD8, tiles())
		m.rect_fill(0x10, 0x78, 0x20, 0x30, tiles())
		m.text_draw_large(0x10, 0x10, rom("screen_ws_table_data") + w(0x126C) * 4)
	else:
		_day(rom("menu_data_0563C4"), w(0x1270), 0x28, 0x20, rom("screen_ws_table_data2"), 2, -1, 0x10, 0x10,
			rom("screen_ws_table_data"))
	ISSModes.ws_standings()
	_team_tiles()
	var vram := w(S.g_stadium_vram)
	m.vram_dma(vram + 0x7D00, l(0x177C) + w(S.g_team_home) * 0xC0, 0xC0)
	m.vram_dma(vram + 0x7DC0, l(0x177C) + w(S.g_team_away) * 0xC0, 0xC0)
	menu_state_05604A(spawn(Callable()))


func menu_state_05604A(o: ISSMenu.Obj) -> void:
	o.update = menu_state_05604A_1
	var digits := rom("menu_data_0563C4")
	var a := l(0x1384) + w(0x1776) * 24
	for k in 6:
		var r := a + k * 4
		var y := k * 0x18 + 0x38
		_number(false, digits, 0x18, y, ISSRam.b(r))
		_team(ISSRam.b(r + 1), 0x6C80 + k * 0x200, 0x7880 + k * 0xC0)
		_number(false, digits, 0xB8, y, ISSRam.b(r + 2))
		_number(false, digits, 0xE8, y, ISSRam.b(r + 3))
	menu_state_05604A_1(o)


## B: back to the series' menu; C: the menu or the next day, after the
## last the trophy (the human's team won), the second series, the
## championship (the human's team won the first) or game over.
func menu_state_05604A_1(o: ISSMenu.Obj) -> void:
	_pages(o, menu_state_05604A)
	if pressed(PAD_B) and w(0x126A) != 0:
		goto_screen(0x32)
	if pressed(PAD_C):
		set_l(S.g_next_state, ISSMenu.STATE_MENU)
		if w(0x1270) < 35:
			set_w(S.g_next_screen, 0x32 if w(0x126A) != 0 else 0x2F)
		elif w(0x1272) == 0:
			set_l(S.g_next_state, ISSMenu.STATE_SCREEN)
			set_w(S.g_weather, 1)
			set_w(0x1630, 0)
			set_w(0x1730, 2)
		elif w(0x126C) == 0:
			ISSModes.ws_second_series()
			set_w(S.g_next_screen, 0x37)
		elif w(0x127E) == w(0x127C):
			ISSModes.start_championship()
			ISSModes.match_setup_random()
			set_w(S.g_next_screen, 0x38)
		else:
			set_w(S.g_next_screen, 0x27)
		m.fade_out_start()
		m.play_sfx(95)
	_arrows(o, 0xC8)
	m.boxes_draw_sprites(rom("menu_state_05604A_1_data"))


# --------------------------------------------------------------------------
# Screen $32: the series' menu (the pre-match menu's eleventh item): the
# table, or back.

func screen_ws_menu() -> void:
	set_w(0x126A, 1)
	spawn(screen_ws_menu_1)
	spawn(menu_state_0564DC)


func screen_ws_menu_1(o: ISSMenu.Obj) -> void:
	o.update = screen_ws_menu_2
	o.set_w(T, 0)
	screen_ws_menu_2(o)


func screen_ws_menu_2(_o: ISSMenu.Obj) -> void:
	m.boxes_draw_sprites(rom("screen_ws_menu_2_data"))


## Back (the cursor at the top right): C returns where the pre-match menu
## would.
func menu_state_0564DC_1(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0564DC_2
	menu_state_0564DC_2(o)


func menu_state_0564DC_2(o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		set_w(0x126A, 0)
		ISSModes.prematch_return()
		if w(S.g_next_screen) == 0x32:
			set_w(S.g_next_screen, 6)
		set_l(S.g_next_state, ISSMenu.STATE_MENU)
		m.fade_out_start()
		m.play_sfx(95)
	if pressed(PAD_UP | PAD_DOWN):
		o.update = menu_state_0564DC
		m.play_sfx(77)
	o.add_w(T, 1)
	m.cursor_draw(w(0x1768), 0xE0, 0xF8, 8)


## The table.
func menu_state_0564DC(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0564DC_3
	menu_state_0564DC_3(o)


func menu_state_0564DC_3(o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		goto_screen(0x31)
		m.play_sfx(95)
	if pressed(PAD_B | PAD_UP | PAD_DOWN):
		o.update = menu_state_0564DC_1
	o.add_w(T, 1)
	m.cursor_draw_large(w(0x1768), 0x40, 0xC0, 0x50)
	if o.update == menu_state_0564DC_3:
		m.rect_highlight(0x40, 0xC0, 0x50, 0x60)
	else:
		m.rect_unhighlight(0x40, 0xC0, 0x50, 0x60)
