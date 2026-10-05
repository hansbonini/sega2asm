class_name ISSScreensStrategy
extends ISSScreens
## Adjust strategy (screen $A): the number of strategies (one, or four on
## the A / B / C / Z buttons, tm_strategy_on), the strategy on each button
## (tm_strategy_slots, -1 none), how the match shows them (tm_strategy_label)
## and, on the mini pitch, a little demonstration of the strategy under the
## cursor. $1768 is the side being set.
##
## RAM: $177A the button under the cursor, $177C the strategy under it,
## $177E the demonstration running (-1 none: the eleven's numbers instead),
## $1778 its figures' animation clock (0-23), $1784 its time, $1782 its
## figures, $1774 / $1776 the number / figure tiles, $1788 the settings on
## entry (for CANCEL and B), $1786 the move sound.

const SLOTS_HOME := 0x184C
const SLOTS_AWAY := 0x18D4

## tbl_strategy_demos as data: each demonstration places its figures
## (player objects 0.. used as figures: kind in +$7A, x +$10, y +$14) and
## then, while lo < time < hi, moves `count` figures from `first` by
## (dx, dy) a frame; at `loop` it starts again. Kinds 0 / 1 are the big
## arrows, 2 the ball, 3 (running) the side's players, 6 the opponents.
const DEMOS := [
	{"figs": [], "moves": [], "loop": -1},
	{"figs": [[3, 0x2C, 0x28], [3, 0x3C, 0x38], [3, 0x3C, 0x58], [3, 0x2C, 0x68], [0, 0x54, 0x48]],
		"moves": [[0x30, 0x44, 0, 5, 1, 0]], "loop": 0x74},
	{"figs": [[3, 0x2C, 0x48], [3, 0x54, 0x38], [3, 0x54, 0x48], [3, 0x54, 0x58], [6, 0x3E, 0x48], [2, 0x38, 0x45]],
		"moves": [[0x30, 0x44, 1, 3, 1, 0], [0x20, 0x26, 4, 2, -1, 0], [0x38, 0x4E, 5, 1, 3, 0]], "loop": 0x74},
	{"figs": [[3, 0x2C, 0x48], [3, 0x54, 0x2C], [3, 0x54, 0x64], [6, 0x3E, 0x48], [2, 0x38, 0x45]],
		"moves": [[0x30, 0x44, 1, 2, 1, 0], [0x20, 0x26, 3, 2, -1, 0], [0x38, 0x4E, 4, 1, 3, -1]], "loop": 0x74},
	{"figs": [[3, 0x2C, 0x48], [3, 0x54, 0x2C], [3, 0x54, 0x48], [3, 0x54, 0x64], [6, 0x3E, 0x48], [2, 0x38, 0x45]],
		"moves": [[0x30, 0x44, 1, 3, 1, 0], [0x20, 0x26, 4, 2, -1, 0], [0x38, 0x4E, 5, 1, 3, 1]], "loop": 0x74},
	{"figs": [[3, 0x74, 0x28], [3, 0x64, 0x38], [3, 0x64, 0x58], [3, 0x74, 0x68], [1, 0x4C, 0x48]],
		"moves": [[0x30, 0x44, 0, 5, -1, 0]], "loop": 0x74},
	{"figs": [[3, 0x28, 0x28], [3, 0x28, 0x38], [3, 0x28, 0x58], [3, 0x28, 0x68],
		[6, 0x38, 0x28], [6, 0x38, 0x38], [6, 0x38, 0x58], [6, 0x38, 0x68]],
		"moves": [[0x30, 0x44, 0, 4, 1, 0], [0x38, 0x4C, 4, 4, 1, 0]], "loop": 0x74},
	{"figs": [[3, 0x2C, 0x30], [3, 0x24, 0x48], [3, 0x2C, 0x60], [6, 0x50, 0x48], [2, 0x4A, 0x45]],
		"moves": [[0x30, 0x37, 0, 1, 2, 2], [0x30, 0x37, 1, 1, 2, 0], [0x30, 0x37, 2, 1, 2, -2],
			[0x20, 0x34, 3, 2, -1, 0]], "loop": 0x70},
	{"figs": [[3, 0x2C, 0x28], [3, 0x2C, 0x38], [3, 0x2C, 0x58], [3, 0x2C, 0x68], [0, 0x4C, 0x2C],
		[0, 0x4C, 0x64], [6, 0x4C, 0x48], [6, 0x60, 0x48], [2, 0x5A, 0x45]],
		"moves": [[0x30, 0x4C, 0, 6, 1, 0], [0x20, 0x3C, 6, 1, -1, 0], [0x40, 0x51, 8, 1, -3, 0]], "loop": 0x7C},
]
const RUNNING := 0x100


func register(h: Dictionary) -> void:
	h[0x0A] = screen_strategy


func _side() -> int:
	return w(0x1768)


func _info() -> int:
	return S.g_team_home_info if _side() == 0 else S.g_team_away_info


func _on() -> int:
	return _info() + ISSModes.TM_STRATEGY_ON


func _label() -> int:
	return _info() + ISSModes.TM_STRATEGY_LABEL


## The strategy on button i (-1 none).
func _slot(i: int) -> int:
	return _info() + ISSModes.TM_STRATEGY_SLOTS + 2 * i


func _sfx() -> void:
	m.play_sfx(w(0x1786))


## A box of a table of four words (x0, x1, y0, y1).
func _box(table: String, i: int) -> Array:
	var a := rom(table) + i * 8
	return [ISSRom.u16(a), ISSRom.u16(a + 2), ISSRom.u16(a + 4), ISSRom.u16(a + 6)]


func screen_strategy() -> void:
	set_w(0x1786, 0x7B if w(S.g_sound_disabled) == 0x19 else 0x4D)
	var side := _side()
	if side != 0:
		for i in 5:
			set_w(0x7C6 + 2 * i, ISSRom.u16(rom("tbl_away_side_colours") + 2 * i))
		set_w(0x1548, 1)
	if side != w(S.g_left_goal_team):
		m.rect_mirror(0x28, 0x78, 0x18, 0x78)
	var team := w(S.g_team_home if side == 0 else S.g_team_away)
	var buf := l(S.g_unpack_buffer)
	m.unpack(6, 2, buf)
	m.vram_dma(w(S.g_stadium_vram) + 0x6400, buf + team * 0xC0, 0xC0)
	m.unpack(6, 1, buf)
	m.vram_dma(w(S.g_stadium_vram) + 0x64C0, buf + team * 0x200, 0x200)
	side_icon(side, 0x10, 0x20, 8, 0x18)
	set_w(0x1774, m.load_tiles(4, 33))
	set_w(0x1776, m.load_tiles(4, 34))
	set_l(0x177E, 0xFFFFFFFF)
	set_l(0x1788, l(S.g_unpack_buffer))
	set_l(S.g_unpack_buffer, l(S.g_unpack_buffer) + 10)
	screen_strategy_1(spawn(Callable()))
	menu_state_0452B8(spawn(Callable()))


# --------------------------------------------------------------------------
# The mini pitch: the eleven's numbers, or the demonstration; the lights of
# palette line 1 (colours 1-8) turning every 8 frames.

func screen_strategy_1(o: ISSMenu.Obj) -> void:
	o.update = screen_strategy_2
	screen_strategy_2(o)


func screen_strategy_2(_o: ISSMenu.Obj) -> void:
	if w(S.g_fade_step) == 0x18 and w(S.g_frame_counter) & 7 == 0:
		var first := w(0x778)
		for i in 7:
			set_w(0x778 + 2 * i, w(0x77A + 2 * i))
		set_w(0x786, first)
		m.cram_dma(0x20, 0x776, 0x20)
	if l(0x177E) & 0x80000000:
		m.pitch_draw(_side())
	else:
		set_w(0x1778, 0 if w(0x1778) + 1 >= 0x18 else w(0x1778) + 1)
		_demo()
		add_w(0x1784, 1)
		var table := rom("tbl_strategy_figures_home" if _side() == 0 else "tbl_strategy_figures_away")
		var flip := w(S.g_left_goal_team) != _side()
		for k in w(0x1782):
			var p := player(_side(), k)
			var kind := ISSRam.w(p + 0x7A)
			if kind > 2:
				kind += w(0x1778) >> 3
			var a := table + kind * 8
			var attr := (w(0x1776) >> 5) + ISSRom.u16(a + 4)
			var x := ISSRam.sw(p + 0x10)
			if flip:
				attr ^= 0x0800
				x = 0xA0 - x
			m.sprite(ISSRam.sw(p + 0x14) + ISSRom.s16(a), ISSRom.u16(a + 2), attr,
				x - sw(S.g_plane_b_hscroll) + ISSRom.s16(a + 6))
	m.boxes_draw_sprites(rom("tbl_strategy_screen_boxes"))


## The demonstration in $177E: its first frame places the figures, then
## each frame moves them (strategy_demo_none ... strategy_demo_offside_trap).
func _demo() -> void:
	var v := l(0x177E)
	var d: Dictionary = DEMOS[v & 0xFF]
	if v & RUNNING == 0:
		set_l(0x177E, v | RUNNING)
		set_w(0x1784, 0)
		set_w(0x1782, d["figs"].size())
		for k in d["figs"].size():
			var f: Array = d["figs"][k]
			var p := player(_side(), k)
			ISSRam.set_w(p + 0x7A, f[0])
			ISSRam.set_w(p + 0x10, f[1])
			ISSRam.set_w(p + 0x14, f[2])
	var t := w(0x1784)
	for mv: Array in d["moves"]:
		if t > mv[0] and t < mv[1]:
			for k in range(mv[2], mv[2] + mv[3]):
				var p := player(_side(), k)
				ISSRam.set_w(p + 0x10, ISSRam.sw(p + 0x10) + mv[4])
				ISSRam.set_w(p + 0x14, ISSRam.sw(p + 0x14) + mv[5])
	if t == d["loop"]:
		set_l(0x177E, v & 0xFF)


## The demonstration of strategy s (-1 none).
func _show(s: int) -> void:
	set_l(0x177E, s + 1)


# --------------------------------------------------------------------------
# The marks above: RESET ($C8) and EXIT ($E0).

func menu_state_0450D4(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0450D4_1
	menu_state_0450D4_1(o)


func menu_state_0450D4_1(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_C):
		ISSModes.prematch_return()
		set_l(S.g_next_state, ISSMenu.STATE_MENU)
		m.fade_out_start()
		m.play_sfx(95)
	if pressed_home(PAD_LEFT | PAD_RIGHT):
		o.update = menu_state_0450D4_2
		_sfx()
	if pressed_home(PAD_UP):
		o.update = menu_state_045432
		_sfx()
	if pressed_home(PAD_DOWN):
		o.update = menu_state_0452B8
		_sfx()
	o.add_w(T, 1)
	m.cursor_draw(_side(), 0xE0, 0xF8, 8)


## RESET: four strategies, their own labels, none chosen.
func menu_state_0450D4_2(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0450D4_3
	menu_state_0450D4_3(o)


func menu_state_0450D4_3(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_C):
		set_w(_on(), 1)
		set_w(_label(), 2)
		for i in 4:
			set_w(_slot(i), 0xFFFF)
		m.play_sfx(95)
	if pressed_home(PAD_B | PAD_LEFT | PAD_RIGHT):
		o.update = menu_state_0450D4
		_sfx()
	if pressed_home(PAD_UP):
		o.update = menu_state_045432
		_sfx()
	if pressed_home(PAD_DOWN):
		o.update = menu_state_0452B8
		_sfx()
	o.add_w(T, 1)
	m.cursor_draw(_side(), 0xC8, 0xE0, 8)


# --------------------------------------------------------------------------
# The two items: ADJUST STRATEGY and ADJUST DISPLAY.

func _menu_text() -> void:
	m.rect_fill(0x98, 0xF0, 0x18, 0x70, tiles())
	var a := rom("str_strategy_menu")
	for y in [0x30, 0x38, 0x50, 0x58]:
		a = m.text_draw_small(0xA0, y, a)


func _item(o: ISSMenu.Obj, me: Callable, y: int) -> void:
	if o.update == me:
		m.rect_highlight(0xA0, 0xE8, y, y + 0x10)
	else:
		m.rect_unhighlight(0xA0, 0xE8, y, y + 0x10)
	o.add_w(T, 1)
	m.cursor_draw_large(_side(), 0xA0, 0xE8, y)


func _save() -> void:
	var a := l(0x1788)
	ISSRam.set_w(a, w(_on()))
	for i in 4:
		ISSRam.set_w(a + 2 + 2 * i, w(_slot(i)))


func _restore() -> void:
	var a := l(0x1788)
	set_w(_on(), ISSRam.w(a))
	for i in 4:
		set_w(_slot(i), ISSRam.w(a + 2 + 2 * i))


func menu_state_0452B8(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0452B8_1
	_menu_text()
	m.pitch_place(0x10, 0x18, _side())
	set_l(0x177E, 0xFFFFFFFF)
	menu_state_0452B8_1(o)


func menu_state_0452B8_1(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_C):
		_save()
		# The ROM clears $177A(a5), the object's address + $177A, meaning
		# the button cursor; menu_state_045770 sets it before it is used.
		o.update = menu_state_045770
		m.play_sfx(95)
	if pressed_home(PAD_B | PAD_UP):
		o.update = menu_state_0450D4
		_sfx()
	if pressed_home(PAD_DOWN):
		o.update = menu_state_045432
		_sfx()
	_item(o, menu_state_0452B8_1, 0x30)


func menu_state_045432(o: ISSMenu.Obj) -> void:
	o.update = menu_state_045432_1
	_menu_text()
	menu_state_045432_1(o)


func menu_state_045432_1(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_C):
		ISSRam.set_w(l(0x1788), w(_label()))
		o.update = menu_state_04556E
		m.play_sfx(95)
	if pressed_home(PAD_B | PAD_DOWN):
		o.update = menu_state_0450D4
		_sfx()
	if pressed_home(PAD_UP):
		o.update = menu_state_0452B8
		_sfx()
	_item(o, menu_state_045432_1, 0x50)


# --------------------------------------------------------------------------
# Adjust display: the strategy's own label, none, or only the display.

func menu_state_04556E(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04556E_1
	m.rect_fill(0x98, 0xF0, 0x18, 0x70, tiles())
	var a := rom("str_strategy_display")
	for y in [0x20, 0x28, 0x38, 0x48, 0x50, 0x58, 0x60]:
		a = m.text_draw_small(0x98, y, a)
	for i in 3:
		var b := _box("tbl_strategy_display_boxes", i)
		if i == w(_label()):
			m.rect_highlight(b[0], b[1], b[2], b[3])
		else:
			m.rect_unhighlight(b[0], b[1], b[2], b[3])
	menu_state_04556E_1(o)


func menu_state_04556E_1(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_C):
		o.update = menu_state_045432
		m.play_sfx(95)
	if pressed_home(PAD_B):
		set_w(_label(), ISSRam.w(l(0x1788)))
		o.update = menu_state_045432
	if pressed_home(PAD_DOWN):
		set_w(_label(), 0 if w(_label()) >= 2 else w(_label()) + 1)
		o.update = menu_state_04556E
		_sfx()
	if pressed_home(PAD_UP):
		set_w(_label(), 2 if w(_label()) == 0 else w(_label()) - 1)
		o.update = menu_state_04556E
		_sfx()
	o.add_w(T, 1)
	var b := _box("tbl_strategy_display_boxes", w(_label()))
	m.cursor_draw_large(_side(), b[0], b[1], b[2])


# --------------------------------------------------------------------------
# Number of strategies: ONE / FOUR.

func menu_state_045770(o: ISSMenu.Obj) -> void:
	o.update = menu_state_045770_1
	m.rect_fill(0x98, 0xF0, 0x18, 0x70, tiles())
	var a := rom("str_strategy_count")
	a = m.text_draw_small(0x98, 0x20, a)
	a = m.text_draw_small(0x98, 0x28, a)
	a = m.text_draw_large(0xB8, 0x40, a)
	m.text_draw_large(0xB8, 0x58, a)
	for i in 2:
		var b := _box("tbl_strategy_count_boxes", i)
		if i == w(_on()):
			m.rect_highlight(b[0], b[1], b[2], b[3])
		else:
			m.rect_unhighlight(b[0], b[1], b[2], b[3])
	menu_state_045770_1(o)


func menu_state_045770_1(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_B):
		_restore()
		o.update = menu_state_0452B8
	if pressed_home(PAD_C):
		set_w(0x177A, 0)
		o.update = menu_state_04590A
		m.play_sfx(95)
	if pressed_home(PAD_UP | PAD_DOWN):
		set_w(_on(), w(_on()) ^ 1)
		o.update = menu_state_045770
		_sfx()
	o.add_w(T, 1)
	var b := _box("tbl_strategy_count_boxes", w(_on()))
	m.cursor_draw_large(_side(), b[0], b[1], b[2] + 1)


# --------------------------------------------------------------------------
# The buttons (A, B, C, Z; just one with ONE) and the strategy on each; OK /
# CANCEL below.

func menu_state_04590A(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04590A_1
	m.rect_fill(0x98, 0xF0, 0x18, 0x70, tiles())
	m.rect_fill_tiles(0xC0, 0xF0, 0x68, 0x70, tiles() + 0x2BA)
	var n := 1
	if w(_on()) != 0:
		var a := rom("str_strategy_buttons")
		for y in [0x28, 0x38, 0x48, 0x58]:
			a = m.text_draw_large(0x98, y, a)
		n = 4
	for i in n:
		var b := _box("tbl_strategy_slot_boxes", i)
		var a := rom("str_strategy_names") + (sw(_slot(i)) + 1) * 0x16
		a = m.text_draw_small(b[0], b[2], a)
		m.text_draw_small(b[0], b[2] + 8, a)
		if i == w(0x177A):
			m.rect_highlight(b[0], b[1], b[2], b[3])
		else:
			m.rect_unhighlight(b[0], b[1], b[2], b[3])
	for i in 8:
		var b := _box("tbl_strategy_boxes", i)
		m.rect_unhighlight(b[0], b[1], b[2], b[3])
	_show(sw(_slot(w(0x177A))))
	menu_state_04590A_1(o)


func menu_state_04590A_1(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_B):
		if sw(_slot(w(0x177A))) >= 0:
			set_w(_slot(w(0x177A)), 0xFFFF)
			o.update = menu_state_04590A
		else:
			o.update = menu_state_045DDC
	if pressed_home(PAD_C):
		set_w(0x177C, maxi(sw(_slot(w(0x177A))), 0))
		o.update = menu_state_045BE6
		m.play_sfx(95)
	if w(_on()) == 0:
		if pressed_home(PAD_UP | PAD_DOWN):
			o.update = menu_state_045DDC
	else:
		if pressed_home(PAD_DOWN):
			if w(0x177A) == 3:
				o.update = menu_state_045DDC
			else:
				add_w(0x177A, 1)
				o.update = menu_state_04590A
			_sfx()
		if pressed_home(PAD_UP):
			if w(0x177A) == 0:
				o.update = menu_state_045DDC
			else:
				add_w(0x177A, -1)
				o.update = menu_state_04590A
			_sfx()
	o.add_w(T, 1)
	var b := _box("tbl_strategy_slot_boxes", w(0x177A))
	m.cursor_draw_large(_side(), b[0], b[1], b[2])


## The eight strategies (two columns of four): C puts the one under the
## cursor on the button.
func menu_state_045BE6(o: ISSMenu.Obj) -> void:
	o.update = menu_state_045BE6_1
	for i in 8:
		var b := _box("tbl_strategy_boxes", i)
		if i == w(0x177C):
			m.rect_highlight(b[0], b[1], b[2], b[3])
		else:
			m.rect_unhighlight(b[0], b[1], b[2], b[3])
	_show(w(0x177C))
	menu_state_045BE6_1(o)


func menu_state_045BE6_1(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_B):
		o.update = menu_state_04590A
	if pressed_home(PAD_C):
		set_w(_slot(w(0x177A)), w(0x177C))
		o.update = menu_state_04590A
		m.play_sfx(95)
	var s := w(0x177C)
	if pressed_home(PAD_DOWN):
		s = s + 1 if (s + 1) & 3 != 0 else s - 3
		_moved(o, s)
	s = w(0x177C)
	if pressed_home(PAD_UP):
		s = s + 3 if s & 3 == 0 else s - 1
		_moved(o, s)
	s = w(0x177C)
	if pressed_home(PAD_RIGHT):
		s = s + 4 if s + 4 <= 7 else s - 4
		_moved(o, s)
	s = w(0x177C)
	if pressed_home(PAD_LEFT):
		s = s - 4 if s - 4 >= 0 else s + 4
		_moved(o, s)
	o.add_w(T, 1)
	var b := _box("tbl_strategy_boxes", w(0x177C))
	m.cursor_draw_large(_side(), b[0], b[1], b[2])


func _moved(o: ISSMenu.Obj, s: int) -> void:
	set_w(0x177C, s)
	o.update = menu_state_045BE6
	_sfx()


## OK ($C0) and CANCEL ($D0) under the buttons.
func _to_buttons(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_DOWN):
		set_w(0x177A, 0)
		o.update = menu_state_04590A
		_sfx()
	if pressed_home(PAD_UP):
		set_w(0x177A, 3 if w(_on()) != 0 else 0)
		o.update = menu_state_04590A
		_sfx()


func menu_state_045DDC(o: ISSMenu.Obj) -> void:
	o.update = menu_state_045DDC_1
	menu_state_045DDC_1(o)


func menu_state_045DDC_1(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_C):
		o.update = menu_state_0452B8
		m.play_sfx(95)
	_to_buttons(o)
	if pressed_home(PAD_LEFT | PAD_RIGHT):
		o.update = menu_state_045DDC_2
		_sfx()
	o.add_w(T, 1)
	m.cursor_draw(_side(), 0xC0, 0xD0, 0x68)


func menu_state_045DDC_2(o: ISSMenu.Obj) -> void:
	o.update = menu_state_045DDC_3
	menu_state_045DDC_3(o)


func menu_state_045DDC_3(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_C):
		_restore()
		o.update = menu_state_0452B8
		m.play_sfx(95)
	_to_buttons(o)
	if pressed_home(PAD_LEFT | PAD_RIGHT):
		o.update = menu_state_045DDC
		_sfx()
	o.add_w(T, 1)
	m.cursor_draw(_side(), 0xD0, 0xF0, 0x68)
