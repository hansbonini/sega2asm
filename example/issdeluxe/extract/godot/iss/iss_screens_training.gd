class_name ISSScreensTraining
extends ISSScreens
## Training and the challenges: the choice between them (screen $13), the
## challenge's name entry ($14), its event and level with the records
## ($15), its menu ($16) and the result against the records ($17); the
## training drill ($18) and the training menu ($19).
##
## RAM: g_training_drill the drill or event, g_challenge_level, the name
## (g_challenge_name, three letters), the records g_best_times /
## g_best_scores (6 events x 4 levels x 6 bytes: the word, then the
## holder's three letters and $FF); the name entry's cursor $1776 (and
## $1778 the cell it was on) and letters entered $177A; the menus' item
## $182C and chosen mark $182A; the record screen's time $1776, score
## $1778 and new-record mark $177A.

const DIGITS := "menu_data_04EE16"


func register(h: Dictionary) -> void:
	h[0x13] = screen_training_challenge
	h[0x14] = screen_input_name
	h[0x15] = screen_challenge_select
	h[0x16] = screen_challenge_menu
	h[0x17] = screen_challenge_record
	h[0x18] = screen_training_select
	h[0x19] = screen_training_menu


func _ram(a: int) -> int:
	return 0xFF0000 | a


## Four $FF-terminated lines of small text from src at (x, y), 8 apart.
func _lines(x: int, y: int, src: int, n: int) -> void:
	for i in n:
		src = m.text_draw_small(x, y + i * 8, src)


## The box (x0, x1, y0, y1) at table address a: highlighted or not.
func _box(a: int, on: bool) -> void:
	var x0 := ISSRom.u16(a)
	var x1 := ISSRom.u16(a + 2)
	var y0 := ISSRom.u16(a + 4)
	var y1 := ISSRom.u16(a + 6)
	if on:
		m.rect_highlight(x0, x1, y0, y1)
	else:
		m.rect_unhighlight(x0, x1, y0, y1)


## The large cursor beside the box at table address a.
func _box_cursor(a: int) -> void:
	m.cursor_draw_large(0, ISSRom.u16(a), ISSRom.u16(a + 2), ISSRom.u16(a + 4) + 1)


## text_draw_time4: v as four large digits at x, x + 8, x + $18, x + $20
## (a gap for the colon); returns what is left in d3 (v / 1000).
func text_draw_time4(v: int, x: int, y: int) -> int:
	m.text_draw_large(x + 0x20, y, rom(DIGITS) + (v % 10) * 2)
	v /= 10
	m.text_draw_large(x + 0x18, y, rom(DIGITS) + (v % 10) * 2)
	v /= 10
	m.text_draw_large(x + 8, y, rom(DIGITS) + (v % 10) * 2)
	v /= 10
	m.text_draw_large(x, y, rom(DIGITS) + v * 2)
	return v


## text_draw_digits3: v as three large digits at x, x + 8, x + $10.
func text_draw_digits3(v: int, x: int, y: int) -> void:
	m.text_draw_large(x + 0x10, y, rom(DIGITS) + (v % 10) * 2)
	v /= 10
	m.text_draw_large(x + 8, y, rom(DIGITS) + (v % 10) * 2)
	v /= 10
	m.text_draw_large(x, y, rom(DIGITS) + v * 2)


# --------------------------------------------------------------------------
# Screen $13: training or challenge.

func screen_training_challenge() -> void:
	set_w(0x153E, 0)
	set_w(S.g_pads_home, 0)
	set_w(S.g_pads_away, 0)
	m.menu_music(0x0E)
	spawn(screen_training_challenge_1)
	training_challenge_menu(spawn(Callable()))


func screen_training_challenge_1(o: ISSMenu.Obj) -> void:
	o.update = screen_training_challenge_2
	o.set_w(T, 0)
	screen_training_challenge_2(o)


func screen_training_challenge_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_B):
		goto_screen(0)
	m.boxes_draw_sprites(rom("screen_training_challenge_2_data"))


## Training, with its description (tbl_mode_texts).
func training_challenge_menu(o: ISSMenu.Obj) -> void:
	o.update = training_challenge_menu_1
	o.set_w(T, 0)
	_lines(0x28, 0x88, rom("tbl_mode_texts"), 4)
	training_challenge_menu_1(o)


func training_challenge_menu_1(o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		ISSModes.mode_start_training()
		goto_screen(3)
		m.play_sfx(95)
	if pressed(PAD_UP | PAD_DOWN):
		o.update = training_challenge_menu_2
		m.play_sfx(77)
	if o.update == training_challenge_menu_1:
		m.rect_highlight(0x40, 0xA8, 0x30, 0x40)
	else:
		m.rect_unhighlight(0x40, 0xA8, 0x30, 0x40)
	o.add_w(T, 1)
	m.cursor_draw_large(0, 0x40, 0xA8, 0x31)


## The challenge, with its description.
func training_challenge_menu_2(o: ISSMenu.Obj) -> void:
	o.update = training_challenge_menu_3
	o.set_w(T, 0)
	_lines(0x28, 0x88, rom("training_challenge_menu_2_data"), 4)
	training_challenge_menu_3(o)


func training_challenge_menu_3(o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		ISSModes.mode_start_challenge()
		ISSModes.challenge_setup()
		goto_screen(0x14)
		m.play_sfx(95)
	if pressed(PAD_UP | PAD_DOWN):
		o.update = training_challenge_menu
		m.play_sfx(77)
	if o.update == training_challenge_menu_3:
		m.rect_highlight(0x40, 0xB0, 0x48, 0x58)
	else:
		m.rect_unhighlight(0x40, 0xB0, 0x48, 0x58)
	o.add_w(T, 1)
	m.cursor_draw_large(0, 0x40, 0xB0, 0x49)


# --------------------------------------------------------------------------
# Screen $14: the name for the records, three of 40 characters (10 a row).

func screen_input_name() -> void:
	for i in 3:
		ISSRam.set_b(S.g_challenge_name + i, 0x40)
	ISSRam.set_b(S.g_challenge_name + 3, 0xFF)
	set_w(0x1776, 0)
	set_w(0x177A, 0)
	spawn(screen_input_name_1)
	input_name_grid(spawn(Callable()))


func screen_input_name_1(o: ISSMenu.Obj) -> void:
	o.update = screen_input_name_2
	o.set_w(T, 0)
	screen_input_name_2(o)


func screen_input_name_2(_o: ISSMenu.Obj) -> void:
	m.boxes_draw_sprites(rom("screen_input_name_2_data"))


## B: the last letter rubbed out (its place shows "_").
func _rub_out() -> void:
	var x := w(0x177A) * 8 + 0x70
	m.rect_unhighlight(x, x + 8, 0x88, 0x90)
	add_w(0x177A, -1)
	ISSRam.set_b(S.g_challenge_name + w(0x177A), 0x40)
	m.text_draw_small(w(0x177A) * 8 + 0x70, 0x88, rom("menu_data_04E2E0"))


## The cursor on OK: C goes on, B rubs out (or with no letters goes back),
## up / down return to the grid's bottom / top row.
func input_name_grid_1(o: ISSMenu.Obj) -> void:
	o.update = input_name_grid_2
	o.set_w(T, 0)
	input_name_grid_2(o)


func input_name_grid_2(o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		goto_screen(0x15)
		m.play_sfx(95)
	if pressed(PAD_B):
		if w(0x177A) == 0:
			goto_screen(0x13)
		else:
			_rub_out()
	if w(0x177A) < 3:
		if pressed(PAD_UP):
			set_w(0x1776, w(0x1776) % 10 + 30)
			o.update = input_name_grid
			m.play_sfx(77)
		if pressed(PAD_DOWN):
			set_w(0x1776, w(0x1776) % 10)
			o.update = input_name_grid
			m.play_sfx(77)
	o.add_w(T, 1)
	m.cursor_draw(0, 0x98, 0xA8, 0x88)


func input_name_grid(o: ISSMenu.Obj) -> void:
	o.update = input_name_grid_3
	o.set_w(T, 0)
	input_name_grid_3(o)


func input_name_grid_3(o: ISSMenu.Obj) -> void:
	set_w(0x1778, w(0x1776))
	if pressed(PAD_B):
		if w(0x177A) == 0:
			o.update = input_name_grid_1
		else:
			_rub_out()
	if pressed(PAD_RIGHT):
		add_w(0x1776, 1)
		if w(0x1776) >= 40:
			set_w(0x1776, 0)
		o.update = input_name_grid
		m.play_sfx(77)
	if pressed(PAD_LEFT):
		add_w(0x1776, -1)
		if sw(0x1776) < 0:
			set_w(0x1776, 39)
		o.update = input_name_grid
		m.play_sfx(77)
	if pressed(PAD_DOWN):
		if w(0x1776) >= 30:
			o.update = input_name_grid_1
		else:
			add_w(0x1776, 10)
			o.update = input_name_grid
		m.play_sfx(77)
	if pressed(PAD_UP):
		if w(0x1776) < 10:
			o.update = input_name_grid_1
		else:
			add_w(0x1776, -10)
			o.update = input_name_grid
		m.play_sfx(77)
	if pressed(PAD_C):
		var ch := rom("tbl_name_chars") + w(0x1776) * 2
		ISSRam.set_b(S.g_challenge_name + w(0x177A), ISSRom.u8(ch))
		m.text_draw_small(w(0x177A) * 8 + 0x70, 0x88, ch)
		add_w(0x177A, 1)
		if w(0x177A) > 2:
			o.update = input_name_grid_1
		m.play_sfx(95)
	o.add_w(T, 1)
	var cell := w(0x1778)
	var cx := (cell % 10) * 8 + 0x58
	var cy := (cell / 10) * 16 + 0x48
	m.cursor_draw(0, cx, cx + 8, cy)
	if o.update == input_name_grid_3:
		m.rect_highlight(cx, cx + 8, cy, cy + 8)
	else:
		m.rect_unhighlight(cx, cx + 8, cy, cy + 8)
	var nx := w(0x177A) * 8 + 0x70
	if o.update == input_name_grid_3:
		m.rect_flash(nx, nx + 8, 0x88, 0x90)
	else:
		m.rect_unhighlight(nx, nx + 8, 0x88, 0x90)


# --------------------------------------------------------------------------
# Screen $15: the event and its level, with the records.

func screen_challenge_select() -> void:
	for base in [S.g_team_home_players, S.g_team_away_players]:
		for k in 11:
			var a: int = base + k * ISSModes.PLAYER_SIZE
			ISSRam.set_b(a + 0x0F, 0)
			ISSRam.set_b(a + 0x55, 1)
	spawn(screen_challenge_select_1)
	challenge_select_event(spawn(Callable()))


func screen_challenge_select_1(o: ISSMenu.Obj) -> void:
	o.update = screen_challenge_select_2
	o.set_w(T, 0)
	screen_challenge_select_2(o)


func screen_challenge_select_2(_o: ISSMenu.Obj) -> void:
	m.boxes_draw_sprites(rom("screen_challenge_select_2_data"))


## The cursor on the way back (top right): C returns to screen $13, up /
## down go to the last / first event.
func challenge_select_event_1(o: ISSMenu.Obj) -> void:
	o.update = challenge_select_event_2
	o.set_w(T, 0)
	challenge_select_event_2(o)


func challenge_select_event_2(o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		goto_screen(0x13)
		m.play_sfx(95)
	if pressed(PAD_UP):
		set_w(S.g_training_drill, 5)
		o.update = challenge_select_event
		m.play_sfx(77)
	if pressed(PAD_DOWN):
		set_w(S.g_training_drill, 0)
		o.update = challenge_select_event
		m.play_sfx(77)
	o.add_w(T, 1)
	m.cursor_draw(0, 0xE0, 0xF8, 8)


## The event's best time and best score over its four levels (the level
## and the holder beside them), the boxes and the event's description.
func challenge_select_event(o: ISSMenu.Obj) -> void:
	o.update = challenge_select_event_3
	o.set_w(T, 0)
	var drill := w(S.g_training_drill)
	var a3 := S.g_best_times + drill * 0x18
	var d3 := 0
	for lv in range(1, 4):
		var a0 := S.g_best_times + drill * 0x18 + lv * 6
		if w(a3) >= w(a0):
			a3 = a0
			d3 = lv
	m.text_draw_small(0x98, 0x40, rom("challenge_select_event_data") + d3 * 5)
	m.text_draw_small(0xC0, 0x40, _ram(a3 + 2))
	# text_draw_time4 leaves the thousands in d3, the level the scores'
	# loop starts from when the first level has the best score.
	d3 = text_draw_time4(w(a3), 0xB0, 0x30)
	a3 = S.g_best_scores + drill * 0x18
	for lv in range(1, 4):
		var a0 := S.g_best_scores + drill * 0x18 + lv * 6
		if w(a3) <= w(a0):
			a3 = a0
			d3 = lv
	m.text_draw_small(0x98, 0x70, rom("challenge_select_event_data") + d3 * 5)
	m.text_draw_small(0xC0, 0x70, _ram(a3 + 2))
	text_draw_digits3(w(a3), 0xC0, 0x60)
	_box(rom("tbl_challenge_level_boxes") + w(S.g_challenge_level) * 8, false)
	for i in 6:
		_box(rom("tbl_challenge_event_boxes") + i * 8, i == drill)
	_lines(0x10, 0x90, ISSRom.u32(rom("tbl_challenge_texts") + drill * 4), 7)
	challenge_select_event_3(o)


func challenge_select_event_3(o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		o.update = challenge_select_level
		m.play_sfx(95)
	if pressed(PAD_B):
		o.update = challenge_select_event_1
	if pressed(PAD_DOWN):
		if w(S.g_training_drill) == 5:
			o.update = challenge_select_event_1
		else:
			add_w(S.g_training_drill, 1)
			o.update = challenge_select_event
		m.play_sfx(77)
	if pressed(PAD_UP):
		if w(S.g_training_drill) == 0:
			o.update = challenge_select_event_1
		else:
			add_w(S.g_training_drill, -1)
			o.update = challenge_select_event
		m.play_sfx(77)
	o.add_w(T, 1)
	if o.update == challenge_select_event_3:
		m.rect_flash(0, 0x50, 0x10, 0x88)
	else:
		m.rect_unhighlight(0, 0x50, 0x10, 0x88)
	_box_cursor(rom("tbl_challenge_event_boxes") + w(S.g_training_drill) * 8)


## The level's own best time and score; C starts the attempt (restart $D,
## screen $16), B goes back to the events.
func challenge_select_level(o: ISSMenu.Obj) -> void:
	o.update = challenge_select_level_1
	o.set_w(T, 0)
	var at := w(S.g_training_drill) * 0x18 + w(S.g_challenge_level) * 6
	m.text_draw_small(0x98, 0x40, rom("challenge_select_level_data"))
	m.text_draw_small(0xC0, 0x40, _ram(S.g_best_times + at + 2))
	text_draw_time4(w(S.g_best_times + at), 0xB0, 0x30)
	m.text_draw_small(0x98, 0x70, rom("challenge_select_level_data"))
	m.text_draw_small(0xC0, 0x70, _ram(S.g_best_scores + at + 2))
	text_draw_digits3(w(S.g_best_scores + at), 0xC0, 0x60)
	for i in 4:
		_box(rom("tbl_challenge_level_boxes") + i * 8, i == w(S.g_challenge_level))
	challenge_select_level_1(o)


func challenge_select_level_1(o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		set_w(S.g_restart_type, 0xD)
		goto_screen(0x16)
		m.play_sfx(95)
	if pressed(PAD_B):
		o.update = challenge_select_event
	if pressed(PAD_DOWN):
		add_w(S.g_challenge_level, 1)
		if w(S.g_challenge_level) > 3:
			set_w(S.g_challenge_level, 0)
		o.update = challenge_select_level
		m.play_sfx(77)
	if pressed(PAD_UP):
		add_w(S.g_challenge_level, -1)
		if sw(S.g_challenge_level) < 0:
			set_w(S.g_challenge_level, 3)
		o.update = challenge_select_level
		m.play_sfx(77)
	o.add_w(T, 1)
	if o.update == challenge_select_level_1:
		m.rect_flash(0x50, 0x80, 0x10, 0x88)
	else:
		m.rect_unhighlight(0x50, 0x80, 0x10, 0x88)
	_box_cursor(rom("tbl_challenge_level_boxes") + w(S.g_challenge_level) * 8)


# --------------------------------------------------------------------------
# Screens $16 and $19: the challenge's and the training's menus (start,
# then key configuration and change control; the training's also select
# squad and formation change). One pad; $182C the item, $182A chosen.

## The menus' shared part: B (nothing chosen, on the first item) goes back;
## once chosen, the first item plays, any other opens its screen.
func _menu_2(back: int, items: String, y0: int, y1: int, boxes: String) -> void:
	if pressed_home(PAD_B) and w(0x182A) == 0 and w(0x182C) == 0:
		goto_screen(back)
	if w(0x182A) != 0:
		if w(0x182C) == 0:
			set_l(S.g_next_state, ISSMenu.STATE_MATCH)
		else:
			set_w(0x176A, 0)
			set_w(S.g_next_screen, ISSRom.u16(rom(items) + w(0x182C) * 2))
			set_l(S.g_next_state, ISSMenu.STATE_MENU)
		m.fade_out_start()
	m.rect_unhighlight_all(0x38, 0xC8, y0, y1)
	var y := w(0x182C) * 16 + y0
	m.rect_highlight(0x38, 0xC8, y, y + 16)
	m.boxes_draw_sprites(rom(boxes))


## The cursor: up / down over the items (last), C chooses, B on a later
## item returns to the first; once chosen B takes it back.
func _menu_4(o: ISSMenu.Obj, last: int, y0: int) -> void:
	if w(0x182A) == 0:
		if pressed_home(PAD_DOWN):
			add_w(0x182C, 1)
			if w(0x182C) > last:
				set_w(0x182C, 0)
			m.play_sfx(77)
		if pressed_home(PAD_UP):
			add_w(0x182C, -1)
			if sw(0x182C) < 0:
				set_w(0x182C, last)
			m.play_sfx(77)
		if pressed_home(PAD_C):
			set_w(0x182A, 1)
			m.play_sfx(95)
		if pressed_home(PAD_B) and w(0x182C) != 0:
			set_w(0x182C, 0)
			set_w(S.g_pad_pressed_home, 0)
		o.add_w(T, 1)
	else:
		if pressed_home(PAD_B):
			set_w(S.g_pad_pressed_home, 0)
			set_w(0x182A, 0)
		o.set_w(T, 0)
	m.pad_icon_draw(3, 0x34, w(0x182C) * 16 + y0)


func screen_challenge_menu() -> void:
	set_w(0x182A, 0)
	spawn(screen_challenge_menu_1)
	screen_challenge_menu_3(spawn(Callable()))


func screen_challenge_menu_1(o: ISSMenu.Obj) -> void:
	o.update = screen_challenge_menu_2
	o.set_w(T, 0)
	screen_challenge_menu_2(o)


func screen_challenge_menu_2(_o: ISSMenu.Obj) -> void:
	_menu_2(0x15, "screen_challenge_menu_2_data2", 0x48, 0x78, "screen_challenge_menu_2_data")


func screen_challenge_menu_3(o: ISSMenu.Obj) -> void:
	o.update = screen_challenge_menu_4
	screen_challenge_menu_4(o)


func screen_challenge_menu_4(o: ISSMenu.Obj) -> void:
	_menu_4(o, 2, 0x48)


func screen_training_menu() -> void:
	set_w(0x182A, 0)
	spawn(screen_training_menu_1)
	screen_training_menu_3(spawn(Callable()))


func screen_training_menu_1(o: ISSMenu.Obj) -> void:
	o.update = screen_training_menu_2
	o.set_w(T, 0)
	screen_training_menu_2(o)


func screen_training_menu_2(_o: ISSMenu.Obj) -> void:
	_menu_2(0x18, "screen_training_menu_2_data2", 0x38, 0x88, "screen_training_menu_2_data")


func screen_training_menu_3(o: ISSMenu.Obj) -> void:
	o.update = screen_training_menu_4
	screen_training_menu_4(o)


func screen_training_menu_4(o: ISSMenu.Obj) -> void:
	_menu_4(o, 4, 0x38)


# --------------------------------------------------------------------------
# Screen $17: the attempt's time (30.00 less what was left), bonus and
# score against the level's records; a better one takes the name.

## g_challenge_time / g_challenge_bonus: n decimal digits as a number.
func _digits(a: int, n: int) -> int:
	var v := 0
	for i in n:
		v = v * 10 + ISSRam.b(a + i)
	return v


func screen_challenge_record() -> void:
	m.menu_music(0x0E)
	set_w(0x177A, 0)
	if w(S.g_challenge_count) != 0xB:
		ISSRam.set_l(S.g_challenge_time, 0)
		ISSRam.set_l(S.g_challenge_bonus, 0)
	if w(S.g_challenge_bonus_on) != 0xB:
		ISSRam.set_l(S.g_challenge_bonus, 0)
	m.text_draw_large(0x30, 0x28, rom("tbl_challenge_event_names") + w(S.g_training_drill) * 0xC)
	m.text_draw_large(0xB0, 0x28, rom("str_levels") + w(S.g_challenge_level) * 5)
	m.text_draw_small(0x90, 0x30, _ram(S.g_challenge_name))
	var time := (3000 - _digits(S.g_challenge_time, 4)) & 0xFFFF
	set_w(0x1776, time)
	text_draw_time4(time, 0xA8, 0x38)
	set_w(0x1778, _digits(S.g_challenge_time, 3))
	text_draw_digits3(w(0x1778), 0xB8, 0x48)
	text_draw_time4(_digits(S.g_challenge_bonus, 4), 0xA8, 0x58)
	var bonus := _digits(S.g_challenge_bonus, 3)
	add_w(0x1778, bonus)
	text_draw_digits3(bonus, 0xB8, 0x68)
	text_draw_digits3(w(0x1778), 0xB8, 0x78)
	var at := w(S.g_training_drill) * 0x18 + w(S.g_challenge_level) * 6
	if sw(0x1778) > ISSRam.sw(S.g_best_scores + at):
		_new_record(S.g_best_scores + at, w(0x1778))
		m.rect_highlight(0x30, 0xD0, 0x78, 0x88)
	if sw(0x1776) < ISSRam.sw(S.g_best_times + at):
		_new_record(S.g_best_times + at, w(0x1776))
		m.rect_highlight(0x30, 0xD0, 0x38, 0x48)
	var text := rom("str_record_fail")
	if w(S.g_challenge_count) == 0xB:
		text = rom("str_record_new") if w(0x177A) != 0 else rom("str_record_average")
	_lines(0x30, 0x98, text, 3)
	spawn(screen_challenge_record_1)


func _new_record(a: int, v: int) -> void:
	set_w(a, v)
	for i in 3:
		ISSRam.set_b(a + 2 + i, ISSRam.b(S.g_challenge_name + i))
	set_w(0x177A, 1)


func screen_challenge_record_1(o: ISSMenu.Obj) -> void:
	o.update = screen_challenge_record_2
	o.set_w(T, 0)
	screen_challenge_record_2(o)


func screen_challenge_record_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		goto_screen(0x15)
		m.play_sfx(95)
	m.boxes_draw_sprites(rom("screen_challenge_record_2_data"))


# --------------------------------------------------------------------------
# Screen $18: the training drill (free play, defence, free kick, keeper)
# with its description; C plays it (restart $C) by way of the training
# menu, B returns to the stadium.

func screen_training_select() -> void:
	m.menu_music(0x0E)
	set_w(0x1638, 0)
	for base in [S.g_team_home_players, S.g_team_away_players]:
		for k in 11:
			ISSRam.set_b(base + k * ISSModes.PLAYER_SIZE + 0x55, 0)
	spawn(screen_training_select_1)
	screen_training_select_menu(spawn(Callable()))


func screen_training_select_1(o: ISSMenu.Obj) -> void:
	o.update = screen_training_select_2
	o.set_w(T, 0)
	screen_training_select_2(o)


func screen_training_select_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_B):
		goto_screen(4)
	if pressed(PAD_C):
		set_w(S.g_restart_type, 0xC)
		goto_screen(0x19)
		m.play_sfx(95)
	m.boxes_draw_sprites(rom("screen_training_select_2_data"))


func screen_training_select_menu(o: ISSMenu.Obj) -> void:
	o.update = screen_training_select_menu_1
	m.rect_fill(0x20, 0xE0, 0x98, 0xB8, (w(S.g_stadium_vram) >> 5) | 0x4000)
	_lines(0x20, 0x98, ISSRom.u32(rom("tbl_drill_texts") + w(S.g_training_drill) * 4), 4)
	for i in 4:
		_box(rom("tbl_drill_boxes") + i * 8, i == w(S.g_training_drill))
	screen_training_select_menu_1(o)


func screen_training_select_menu_1(o: ISSMenu.Obj) -> void:
	if pressed(PAD_DOWN):
		set_w(S.g_training_drill, 0 if w(S.g_training_drill) == 3 else w(S.g_training_drill) + 1)
		o.update = screen_training_select_menu
		m.play_sfx(77)
	if pressed(PAD_UP):
		set_w(S.g_training_drill, 3 if w(S.g_training_drill) == 0 else w(S.g_training_drill) - 1)
		o.update = screen_training_select_menu
		m.play_sfx(77)
	o.add_w(T, 1)
	_box_cursor(rom("tbl_drill_boxes") + w(S.g_training_drill) * 8)
