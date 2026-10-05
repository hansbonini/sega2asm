class_name ISSScreensControls
extends ISSScreens
## Key configuration ($C) and change control ($D): one panel per human
## controller (four a row), each driven by its own pad through the edges
## in g_control_slots (+4 pressed, +6 consumed). Key configuration orders
## the four buttons (dash, pass, high ball, shot: slot +$10-$16, the
## permutation's index * 16 in +$18) and the goalkeeper mode
## (tm_keeper_manual: auto, semi-auto, manual); change control sets the
## player switch type (+$A), the area (+$C) and the cursor change (+$E).
## When every controller has chosen OK the screen returns. A / Z and Y page
## through the help text.

const O_OWNER := 0x08
const O_INDEX := 0x0C
const O_SIDE := 0x4A
const O_ROW := 0x7A
const O_PICK := 0x8C


func register(h: Dictionary) -> void:
	h[0x0C] = screen_key_config
	h[0x0D] = screen_change_control


## The controllers' panels: one object per human, its slot and index.
func _panels(state: Callable) -> void:
	set_w(0x1788, 0x7B if w(S.g_sound_disabled) == 0x19 else 0x4D)
	ISSRam.clear(0x1776, 16)
	set_w(0x1786, 0xFFFF)
	var slot := S.g_control_slots
	var k := 0
	while k < w(S.g_pads_home):
		_panel(state, slot, k, 0)
		slot += 0x1A
		k += 1
	slot = 0x15C4
	while k < w(0x153E):
		_panel(state, slot, k, 1)
		slot += 0x1A
		k += 1


func _panel(state: Callable, slot: int, k: int, side: int) -> void:
	var o := m.obj_alloc()
	o.set_l(O_OWNER, 0xFF0000 | slot)
	o.set_b(O_INDEX, k)
	o.set_w(O_SIDE, side)
	o.set_w(O_ROW, 0)
	o.set_w(O_PICK, 0xFFFF)
	state.call(o)


func _slot(o: ISSMenu.Obj) -> int:
	return o.l(O_OWNER) & 0xFFFF


## A panel's origin: four across ($30 apart from $38), two rows.
func _dx(o: ISSMenu.Obj) -> int:
	return (o.b(O_INDEX) & 3) * 0x30 + 0x38


func _dy(o: ISSMenu.Obj, row_step: int) -> int:
	return (o.b(O_INDEX) & 4) * row_step + 0x18


func _fill(o: ISSMenu.Obj, rect: int, step: int, t: int) -> void:
	var dx := _dx(o)
	var dy := _dy(o, step)
	m.rect_fill_tiles(ISSRom.u16(rect) + dx, ISSRom.u16(rect + 2) + dx, ISSRom.u16(rect + 4) + dy,
		ISSRom.u16(rect + 6) + dy, t)


## The pad of a panel: the 3-button one's picture when it is one.
func _pad_icon(o: ISSMenu.Obj, rect: int, step: int) -> void:
	var t := ((w(S.g_stadium_vram) >> 5) | 0xC000) + 0x1CC
	if ISSRam.w(_slot(o) + 8) == 0:
		t += 2
	_fill(o, rect, step, t)


## This controller's edges: pressed (+4) bits, which it then consumes (+6).
func _take(o: ISSMenu.Obj, bits: int) -> bool:
	var a := _slot(o)
	if ISSRam.w(a + 4) & bits:
		ISSRam.or_w(a + 6, bits)
		return true
	return false


func _done(o: ISSMenu.Obj) -> bool:
	return w(0x1776 + o.b(O_INDEX) * 2) != 0


func _set_done(o: ISSMenu.Obj, v: int) -> void:
	set_w(0x1776 + o.b(O_INDEX) * 2, v)


func _cursor(o: ISSMenu.Obj, table: String, step: int) -> void:
	var a := rom(table) + o.w(O_ROW) * 8
	m.cursor_draw(o.w(O_SIDE), ISSRom.u16(a) + _dx(o), ISSRom.u16(a + 2) + _dx(o), ISSRom.u16(a + 4) + _dy(o, step))


## The help object: every controller done -> return (the screen's own
## number means the pre-match menu); A / Z next page, Y previous.
func _help(o: ISSMenu.Obj, own: int, pages: int, redraw: Callable, boxes: String) -> void:
	var n := 0
	for i in 8:
		if w(0x1776 + 2 * i) != 0:
			n += 1
	if n == w(0x153E):
		ISSModes.prematch_return()
		if w(S.g_next_screen) == own:
			set_w(S.g_next_screen, 6)
		set_l(S.g_next_state, ISSMenu.STATE_MENU)
		m.fade_out_start()
	if pressed(PAD_A | 0x100):
		add_w(0x1786, 1)
		if w(0x1786) > pages - 1:
			set_w(0x1786, 0)
		o.update = redraw
		m.play_sfx(w(0x1788))
	if pressed(0x200):
		add_w(0x1786, -1)
		if sw(0x1786) < 0:
			set_w(0x1786, pages - 1)
		o.update = redraw
		m.play_sfx(w(0x1788))
	m.boxes_draw_sprites(rom(boxes))


func _help_text(table: String, y: int, lines: int) -> void:
	var a := ISSRom.u32(rom(table) + w(0x1786) * 4)
	for i in lines:
		a = m.text_draw_small(0x10, y + i * 8, a)


# --------------------------------------------------------------------------
# Key configuration. Rows: the four buttons (0-3), the goalkeeper (4), OK
# (5), RESET (6). C on a button picks it and C on another swaps them.

func screen_key_config() -> void:
	spawn(menu_sound_047C7C)
	_panels(menu_state_047DA0)


func menu_sound_047C7C_1(o: ISSMenu.Obj) -> void:
	o.update = menu_sound_047C7C
	_help_text("menu_sound_047C7C_1_data", 0xA0, 6)
	menu_sound_047C7C(o)


func menu_sound_047C7C(o: ISSMenu.Obj) -> void:
	_help(o, 0x0C, 5, menu_sound_047C7C_1, "menu_sound_047C7C_data")


## Draw the panel: pad, the four buttons' letters (a 3-button pad shows Z
## as none), the goalkeeper mode.
func menu_state_047DA0(o: ISSMenu.Obj) -> void:
	o.update = menu_state_047DA0_1
	o.set_w(T, 0)
	var a := _slot(o)
	var base := (w(S.g_stadium_vram) >> 5) | 0xC000
	var rect := rom("menu_data_048290")
	_pad_icon(o, rect, 0x12)
	for i in 4:
		rect += 8
		var v := ISSRam.w(a + 0x10 + 2 * i)
		if ISSRam.w(a + 8) == 0 and v == 3:
			v = 4
		_fill(o, rect, 0x12, base + 0x337 + v)
	rect += 8
	var info: int = S.g_team_home_info if o.w(O_SIDE) == 0 else S.g_team_away_info
	_fill(o, rect, 0x12, base + 0x32E + w(info + ISSModes.TM_KEEPER_MANUAL) * 3)
	menu_state_047DA0_1(o)


func _key_rect(o: ISSMenu.Obj, row: int) -> Array:
	var a := rom("menu_state_047DA0_1_data") + row * 8
	var dx := _dx(o)
	var dy := _dy(o, 0x12)
	return [ISSRom.u16(a) + dx, ISSRom.u16(a + 2) + dx, ISSRom.u16(a + 4) + dy, ISSRom.u16(a + 6) + dy]


func menu_state_047DA0_1(o: ISSMenu.Obj) -> void:
	var a := _slot(o)
	if _done(o):
		if _take(o, PAD_B):
			_set_done(o, 0)
		o.set_w(T, 4)
	else:
		var row := o.w(O_ROW)
		var pick := o.sw(O_PICK)
		if _take(o, PAD_DOWN):
			if pick < 0:
				row = 0 if row >= 5 else row + 1
			else:
				row = 0 if row + 1 > 3 else row + 1
			o.set_w(O_ROW, row)
			m.play_sfx(w(0x1788))
		if _take(o, PAD_UP):
			if pick < 0:
				if row == 0:
					row = 5
				elif row > 4:
					row = 4
				else:
					row -= 1
			else:
				row = 3 if row - 1 < 0 else row - 1
			o.set_w(O_ROW, row)
			m.play_sfx(w(0x1788))
		if _take(o, PAD_LEFT | PAD_RIGHT) and row > 4:
			row = 6 if row == 5 else 5
			o.set_w(O_ROW, row)
			m.play_sfx(w(0x1788))
		if _take(o, PAD_B):
			if pick < 0:
				o.set_w(O_ROW, 5)
			else:
				o.set_w(O_ROW, pick)
				var r := _key_rect(o, pick)
				m.rect_unhighlight(r[0], r[1], r[2], r[3])
				o.set_w(O_PICK, 0xFFFF)
		if _take(o, PAD_C):
			row = o.w(O_ROW)
			if o.sw(O_PICK) < 0:
				if row == 4:
					var info: int = S.g_team_home_info if o.w(O_SIDE) == 0 else S.g_team_away_info
					var k := w(info + ISSModes.TM_KEEPER_MANUAL) + 1
					set_w(info + ISSModes.TM_KEEPER_MANUAL, 0 if k > 2 else k)
					o.update = menu_state_047DA0
					m.play_sfx(95)
				if row == 5:
					_set_done(o, 1)
					m.play_sfx(95)
				if row == 6:
					ISSRam.set_w(a + 0x10, 2)
					ISSRam.set_w(a + 0x12, 0)
					ISSRam.set_w(a + 0x14, 1)
					ISSRam.set_w(a + 0x16, 3)
					ISSRam.set_w(a + 0x18, 0)
					var info: int = S.g_team_home_info if o.w(O_SIDE) == 0 else S.g_team_away_info
					set_w(info + ISSModes.TM_KEEPER_MANUAL, 0)
					o.update = menu_state_047DA0
					m.play_sfx(95)
				if row < 4:
					o.set_w(O_PICK, row)
					var r := _key_rect(o, row)
					m.rect_highlight(r[0], r[1], r[2], r[3])
					o.set_w(O_ROW, 0 if row + 1 > 3 else row + 1)
					m.play_sfx(95)
			else:
				# Swap the two buttons, then find the layout's index.
				var p := o.w(O_PICK)
				var t := ISSRam.w(a + 0x10 + row * 2)
				ISSRam.set_w(a + 0x10 + row * 2, ISSRam.w(a + 0x10 + p * 2))
				ISSRam.set_w(a + 0x10 + p * 2, t)
				var perms := rom("menu_state_047DA0_1_data2")
				var found := 0
				for i in 24:
					var ok := true
					for j in 4:
						if ISSRam.w(a + 0x10 + j * 2) != ISSRom.u8(perms + i * 4 + j):
							ok = false
					if ok:
						found = i
						break
				ISSRam.set_w(a + 0x18, found * 16)
				o.set_w(O_PICK, 0xFFFF)
				o.update = menu_state_047DA0
				m.play_sfx(95)
		o.add_w(T, 1)
	_cursor(o, "menu_state_047DA0_1_data", 0x12)


# --------------------------------------------------------------------------
# Change control. Rows: type (0), area (1), cursor change (2), OK (3),
# RESET (4).

func screen_change_control() -> void:
	spawn(menu_sound_048808)
	_panels(menu_state_04891C)


func menu_sound_048808_1(o: ISSMenu.Obj) -> void:
	o.update = menu_sound_048808
	_help_text("menu_sound_048808_1_data", 0x90, 7)
	menu_sound_048808(o)


func menu_sound_048808(o: ISSMenu.Obj) -> void:
	_help(o, 0x0D, 9, menu_sound_048808_1, "menu_sound_048808_data")


func menu_state_04891C(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04891C_1
	o.set_w(T, 0)
	var a := _slot(o)
	var base := (w(S.g_stadium_vram) >> 5) | 0xC000
	var rect := rom("menu_data_048C44")
	_pad_icon(o, rect, 0x10)
	_fill(o, rect + 8, 0x10, base + 0x144 + ISSRam.w(a + 0xA))
	_fill(o, rect + 16, 0x10, base + 0x144 + ISSRam.w(a + 0xC))
	_fill(o, rect + 24, 0x10, base + 0x328 + ISSRam.w(a + 0xE) * 3)
	menu_state_04891C_1(o)


func menu_state_04891C_1(o: ISSMenu.Obj) -> void:
	var a := _slot(o)
	if _done(o):
		if _take(o, PAD_B):
			_set_done(o, 0)
		o.set_w(T, 4)
	else:
		var row := o.w(O_ROW)
		if _take(o, PAD_DOWN):
			row = row + 1 if row < 3 else 0
			o.set_w(O_ROW, row)
			m.play_sfx(w(0x1788))
		if _take(o, PAD_UP):
			if row == 0:
				row = 3
			elif row > 3:
				row = 2
			else:
				row -= 1
			o.set_w(O_ROW, row)
			m.play_sfx(w(0x1788))
		if _take(o, PAD_LEFT | PAD_RIGHT) and row > 2:
			row = 4 if row == 3 else 3
			o.set_w(O_ROW, row)
			m.play_sfx(w(0x1788))
		if _take(o, PAD_B):
			o.set_w(O_ROW, 3)
		if _take(o, PAD_C):
			match o.w(O_ROW):
				0:
					var v := ISSRam.w(a + 0xA) + 1
					ISSRam.set_w(a + 0xA, 0 if v > 3 else v)
					o.update = menu_state_04891C
				1:
					ISSRam.set_w(a + 0xC, ISSRam.w(a + 0xC) ^ 1)
					o.update = menu_state_04891C
				2:
					ISSRam.set_w(a + 0xE, ISSRam.w(a + 0xE) ^ 1)
					o.update = menu_state_04891C
				3:
					_set_done(o, 1)
				4:
					ISSRam.set_w(a + 0xA, 0)
					ISSRam.set_w(a + 0xC, 0)
					ISSRam.set_w(a + 0xE, 0)
					o.update = menu_state_04891C
			m.play_sfx(95)
		o.add_w(T, 1)
	_cursor(o, "menu_state_04891C_1_data", 0x10)
