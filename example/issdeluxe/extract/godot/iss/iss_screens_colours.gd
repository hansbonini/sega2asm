class_name ISSScreensColours
extends ISSScreens
## Team colours (screen $F): both sides at once, the home side on the first
## pad's half and the away side on the other's: TYPE 1 / TYPE 2 (the kits)
## or EDIT (the side's own colours at $185A / $18E2: shirt, pants, socks,
## three shades of each, two for the socks, R / G / B 0-7), a player in the
## kit on each side, and OK. With one pad, A hands it to the other side
## ($1548). The screen ends when both sides (or, with one pad, either)
## said OK.
##
## The ROM has every routine twice, once per side; here each pair calls one
## implementation with the side's constants (SIDES).

const SIDES := [
	{"pad": S.g_pad_pressed_home, "done": 0x178A, "kit": S.g_kit_home, "team": S.g_team_home,
		"part": 0x177E, "shade": 0x1782, "chan": 0x1786, "custom": 0x185A, "pal": 0x756, "cram": 0x00,
		"done_x": 0x38, "kits": "tbl_colours_kit_boxes_home", "parts": "tbl_colours_part_boxes_home",
		"chans": "tbl_colours_channel_boxes_home", "label_x": 0x38, "label_attr": 0x8000,
		"digit_x": 0x28, "bar_x": 0x38, "name_x": 0x30, "shade_x": 0x20, "ok_x": 0x50, "reset_x": 0x60},
	{"pad": S.g_pad_pressed_away, "done": 0x178C, "kit": S.g_kit_away, "team": S.g_team_away,
		"part": 0x1780, "shade": 0x1784, "chan": 0x1788, "custom": 0x18E2, "pal": 0x776, "cram": 0x20,
		"done_x": 0xB8, "kits": "tbl_colours_kit_boxes_away", "parts": "tbl_colours_part_boxes_away",
		"chans": "tbl_colours_channel_boxes_away", "label_x": 0xA0, "label_attr": 0xA000,
		"digit_x": 0x90, "bar_x": 0xA0, "name_x": 0x98, "shade_x": 0x88, "ok_x": 0xB8, "reset_x": 0xC8},
]

var _figs: Array = []


func register(h: Dictionary) -> void:
	h[0x0F] = screen_team_colors


func _sfx() -> void:
	m.play_sfx(w(0x178E))


func _c(s: int, key: String) -> Variant:
	return SIDES[s][key]


func _sym(s: int, key: String) -> int:
	return _c(s, key)


func _pad(s: int, bits: int) -> bool:
	return w(_sym(s, "pad")) & bits != 0


func _box(table: String, i: int) -> Array:
	var a := rom(table) + i * 8
	return [ISSRom.u16(a), ISSRom.u16(a + 2), ISSRom.u16(a + 4), ISSRom.u16(a + 6)]


func screen_team_colors() -> void:
	set_w(0x178E, 0x7B if w(S.g_sound_disabled) == 0x19 else 0x4D)
	var buf := l(S.g_unpack_buffer)
	m.unpack(6, 2, buf)
	m.vram_dma(w(S.g_stadium_vram) + 0x6A00, buf + w(S.g_team_home) * 0xC0, 0xC0)
	m.vram_dma(w(S.g_stadium_vram) + 0x6AC0, buf + w(S.g_team_away) * 0xC0, 0xC0)
	m.unpack(6, 1, buf)
	m.vram_dma(w(S.g_stadium_vram) + 0x6B80, buf + w(S.g_team_home) * 0x200, 0x200)
	m.vram_dma(w(S.g_stadium_vram) + 0x6D80, buf + w(S.g_team_away) * 0x200, 0x200)
	side_icon(0, 0x10, 0x20, 8, 0x18)
	side_icon(1, 0xE0, 0xF0, 8, 0x18)
	# A player of each side in the kit: the referee object and the next
	# one, at (x $58 / $A6, y $CE) facing the screen, hair style 1 (their
	# shirt number is left at 0, so the head is whatever lies before the
	# head tiles; the port shows number 1).
	_figs = []
	for s in 2:
		var f := ISSPlayerSprite.new()
		m.figures.add_child(f)
		f.position = Vector2((0x58 if s == 0 else 0xA6) + 1, 0xCE / 2)
		_figs.append(f)
	for a in [0x178A, 0x178C, 0x177E, 0x1782, 0x1780, 0x1784]:
		set_w(a, 0)
	spawn(menu_state_04B038)
	menu_state_04B28A(spawn(Callable()))
	menu_state_04BD88(spawn(Callable()))


## The figure of side s in its kit (tiles of the first or second kit), its
## palette the screen's CRAM with the side's line as the kit's.
func _figure(s: int) -> void:
	if s >= _figs.size():
		return
	var f: ISSPlayerSprite = _figs[s]
	var kit := w(_sym(s, "kit"))
	f.set_look(w(_sym(s, "team")), kit & 1 == 1, 1, 1)
	f.set_palette_cram(m.vdp.cram, s)
	f.set_pose(ISSFootballer.A_READY, 0, 0x20, false)


# --------------------------------------------------------------------------
# The screen: which side the single pad has (A swaps), the shade marks, and
# the end once the sides said OK.

func menu_state_04B038(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04B038_1
	var d5 := 2
	if w(0x153E) == 0 or w(S.g_pads_away) == 0:
		d5 = w(0x1548) & 1
	if d5 == 0:
		m.rect_fill_tiles(0, 0x10, 8, 0x18, tiles() + 0x8C)
	else:
		m.rect_fill(0, 0x10, 8, 0x18, tiles())
	if d5 == 1:
		m.rect_fill_tiles(0xF0, 0x100, 8, 0x18, tiles() + 0x8C)
	else:
		m.rect_fill(0xF0, 0x100, 8, 0x18, tiles())
	menu_state_04B038_1(o)


func menu_state_04B038_1(o: ISSMenu.Obj) -> void:
	if w(S.g_pad_pressed_any) & PAD_A and (w(0x153E) == 0 or w(S.g_pads_away) == 0):
		set_w(0x1548, w(0x1548) ^ 1)
		set_w(S.g_pad_held_home, 0xFFFF)
		set_w(S.g_pad_held_away, 0xFFFF)
		o.update = menu_state_04B038
		_sfx()
	var done := false
	if w(S.g_pads_away) == 0:
		done = (w(0x178A) | w(0x178C)) != 0
	else:
		done = w(0x178A) != 0 and w(0x178C) != 0
	if done:
		ISSModes.prematch_return()
		if w(S.g_next_screen) == 0x0F:
			set_w(S.g_next_screen, 6)
		set_l(S.g_next_state, ISSMenu.STATE_MENU)
		m.fade_out_start()
	o.add_w(T, 1)
	for s in 2:
		var a := rom("tbl_colours_shade_marks_home" if s == 0 else "tbl_colours_shade_marks_away")
		a += w(_c(s, "shade")) * 8
		m.icon_draw_small(0, ISSRom.u16(a), ISSRom.u16(a + 4) + 8)
	m.boxes_draw_sprites(rom("tbl_colours_screen_boxes"))
	for s in 2:
		if s < _figs.size():
			(_figs[s] as ISSPlayerSprite).set_palette_cram(m.vdp.cram, s)


# --------------------------------------------------------------------------
# OK (above each side): C says done, B takes it back, up / down to the kits.

func _ok(o: ISSMenu.Obj, s: int, kits: Callable) -> void:
	var done: int = _c(s, "done")
	if _pad(s, PAD_B):
		set_w(done, 0)
	if w(done) == 0:
		if _pad(s, PAD_C):
			set_w(done, 1)
			m.play_sfx(95)
		if _pad(s, PAD_UP | PAD_DOWN):
			o.update = kits
			_sfx()
		o.add_w(T, 1)
	else:
		o.set_w(T, 4)
	m.cursor_draw(s, _c(s, "done_x"), _c(s, "done_x") + 0x10, 0x20)


func menu_state_04B28A_1(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04B28A_2
	menu_state_04B28A_2(o)


func menu_state_04B28A_2(o: ISSMenu.Obj) -> void:
	_ok(o, 0, menu_state_04B28A)


func menu_state_04BD88_1(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04BD88_2
	menu_state_04BD88_2(o)


func menu_state_04BD88_2(o: ISSMenu.Obj) -> void:
	_ok(o, 1, menu_state_04BD88)


# --------------------------------------------------------------------------
# TYPE 1 / TYPE 2 / EDIT: left / right choose the kit (the side's palette
# line and the figure follow), C on EDIT edits it.

func _kits_init(o: ISSMenu.Obj, s: int) -> void:
	o.set_w(T, 0)
	var kit := w(_sym(s, "kit"))
	for i in 3:
		var b := _box(_c(s, "kits"), i)
		if i == kit:
			m.rect_highlight(b[0], b[1], b[2], b[3])
		else:
			m.rect_unhighlight(b[0], b[1], b[2], b[3])
	var team := w(_sym(s, "team"))
	var words := []
	if kit == 2:
		for i in 16:
			words.append(w(_c(s, "custom") + 2 * i))
	else:
		var pal := ISSRom.res(6, 13 if kit != 0 else 12)
		for i in 16:
			words.append((pal[team * 32 + 2 * i] << 8) | pal[team * 32 + 2 * i + 1])
	for i in 16:
		set_w(_c(s, "pal") + 2 * i, words[i])
	if w(S.g_fade_step) == 0x18:
		m.cram_dma(_c(s, "cram"), _c(s, "pal"), 0x20)
	_figure(s)


func _kits(o: ISSMenu.Obj, s: int, ok: Callable, me: Callable, edit: Callable) -> void:
	var kit: int = _sym(s, "kit")
	if _pad(s, PAD_UP | PAD_DOWN | PAD_B):
		o.update = ok
		_sfx()
	if _pad(s, PAD_C) and w(kit) == 2:
		o.update = edit
		m.play_sfx(95)
	if _pad(s, PAD_RIGHT):
		set_w(kit, 0 if w(kit) >= 2 else w(kit) + 1)
		o.update = me
		_sfx()
	if _pad(s, PAD_LEFT):
		set_w(kit, 2 if w(kit) == 0 else w(kit) - 1)
		o.update = me
		_sfx()
	o.add_w(T, 1)
	var b := _box(_c(s, "kits"), w(kit))
	m.cursor_draw(s, b[0], b[1], b[2])


func menu_state_04B28A(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04B28A_3
	_kits_init(o, 0)
	menu_state_04B28A_3(o)


func menu_state_04B28A_3(o: ISSMenu.Obj) -> void:
	_kits(o, 0, menu_state_04B28A_1, menu_state_04B28A, menu_state_04B466)


func menu_state_04BD88(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04BD88_3
	_kits_init(o, 1)
	menu_state_04BD88_3(o)


func menu_state_04BD88_3(o: ISSMenu.Obj) -> void:
	_kits(o, 1, menu_state_04BD88_1, menu_state_04BD88, menu_state_04BF64)


# --------------------------------------------------------------------------
# EDIT: shirt / pants / socks.

func _parts_init(o: ISSMenu.Obj, s: int) -> void:
	o.set_w(T, 0)
	var part := w(_c(s, "part"))
	for i in 3:
		var b := _box(_c(s, "parts"), i)
		if i == part:
			m.rect_highlight(b[0], b[1], b[2], b[3])
		else:
			m.rect_unhighlight(b[0], b[1], b[2], b[3])
	var t: int = ((w(S.g_stadium_vram) >> 5) + 0x327) | int(_c(s, "label_attr"))
	m.rect_fill_tiles(_c(s, "label_x"), _c(s, "label_x") + 0x18, 0x90, 0x98, t + part * 3)


func _parts(o: ISSMenu.Obj, s: int, kits: Callable, shades: Callable, me: Callable) -> void:
	var part: int = _c(s, "part")
	if _pad(s, PAD_B):
		o.update = kits
	if _pad(s, PAD_C):
		set_w(_c(s, "shade"), 0)
		o.update = shades
		m.play_sfx(95)
	if _pad(s, PAD_DOWN):
		set_w(part, 0 if w(part) >= 2 else w(part) + 1)
		o.update = me
		_sfx()
	if _pad(s, PAD_UP):
		set_w(part, 2 if w(part) == 0 else w(part) - 1)
		o.update = me
		_sfx()
	o.add_w(T, 1)
	var b := _box(_c(s, "parts"), w(part))
	m.cursor_draw(s, b[0], b[1], b[2])


func menu_state_04B466(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04B466_1
	_parts_init(o, 0)
	menu_state_04B466_1(o)


func menu_state_04B466_1(o: ISSMenu.Obj) -> void:
	_parts(o, 0, menu_state_04B28A, menu_state_04B5C6, menu_state_04B466)


func menu_state_04BF64(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04BF64_1
	_parts_init(o, 1)
	menu_state_04BF64_1(o)


func menu_state_04BF64_1(o: ISSMenu.Obj) -> void:
	_parts(o, 1, menu_state_04BD88, menu_state_04C0C4, menu_state_04BF64)


# --------------------------------------------------------------------------
# The shade being edited and its R / G / B.

## The address of the colour being edited (colours 8-15 of the side's
## line: three shades per part).
func _colour(s: int, base: int) -> int:
	return base + 0x10 + w(_c(s, "shade")) * 2 + w(_c(s, "part")) * 6


## The side's own colours into its palette line, and the colour's R / G / B
## as digits and bars (red 3, green 1, blue 0 bar styles).
func _show_colour(s: int) -> void:
	for i in 16:
		set_w(_c(s, "pal") + 2 * i, w(_c(s, "custom") + 2 * i))
	if w(S.g_fade_step) == 0x18:
		m.cram_dma(_c(s, "cram"), _c(s, "pal"), 0x20)
	var v := w(_colour(s, _c(s, "pal")))
	var rows := [[1, 0xA0, 3], [5, 0xB0, 1], [9, 0xC0, 0]]
	for r: Array in rows:
		var c: int = (v >> int(r[0])) & 7
		m.text_draw_small(_c(s, "digit_x"), r[1], rom("str_digits") + c * 2)
		m.bar_draw_wide(_c(s, "bar_x"), r[1], r[2], c * 8)
	_figure(s)


func _shades_init(o: ISSMenu.Obj, s: int) -> void:
	o.set_w(T, 0)
	_show_colour(s)
	m.text_draw_small(_c(s, "name_x"), 0x88, rom("str_kit_parts") + w(_c(s, "part")) * 8)


func _shades(o: ISSMenu.Obj, s: int, ok: Callable, chans: Callable, me: Callable, reset: Callable) -> void:
	var shade: int = _c(s, "shade")
	if _pad(s, PAD_B):
		o.update = ok
	if _pad(s, PAD_DOWN):
		set_w(_c(s, "chan"), 0)
		o.update = chans
		_sfx()
	if _pad(s, PAD_UP):
		set_w(_c(s, "chan"), 2)
		o.update = chans
		_sfx()
	if _pad(s, PAD_RIGHT):
		var last := 1 if w(_c(s, "part")) == 2 else 2
		if w(shade) == last:
			o.update = ok
		else:
			add_w(shade, 1)
			o.update = me
		_sfx()
	if _pad(s, PAD_LEFT):
		if w(shade) == 0:
			o.update = reset
		else:
			add_w(shade, -1)
			o.update = me
		_sfx()
	o.add_w(T, 1)
	m.cursor_draw(s, _c(s, "shade_x"), _c(s, "shade_x") + 0x18, 0x90)


func menu_state_04B5C6(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04B5C6_1
	_shades_init(o, 0)
	menu_state_04B5C6_1(o)


func menu_state_04B5C6_1(o: ISSMenu.Obj) -> void:
	_shades(o, 0, menu_state_04BB44, menu_state_04B870, menu_state_04B5C6, menu_state_04BBF8)


func menu_state_04C0C4(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04C0C4_1
	_shades_init(o, 1)
	menu_state_04C0C4_1(o)


func menu_state_04C0C4_1(o: ISSMenu.Obj) -> void:
	_shades(o, 1, menu_state_04C646, menu_state_04C372, menu_state_04C0C4, menu_state_04C6FA)


func _chans(o: ISSMenu.Obj, s: int, ok: Callable, shades: Callable, me: Callable) -> void:
	var chan: int = _c(s, "chan")
	if _pad(s, PAD_B):
		o.update = ok
	if _pad(s, PAD_DOWN):
		if w(chan) == 2:
			o.update = shades
		else:
			add_w(chan, 1)
		_sfx()
	if _pad(s, PAD_UP):
		if w(chan) == 0:
			o.update = shades
		else:
			add_w(chan, -1)
		_sfx()
	var a := _colour(s, _c(s, "custom"))
	var sh := w(chan) * 4 + 1
	var v := (w(a) >> sh) & 7
	if _pad(s, PAD_RIGHT) and v < 7:
		set_w(a, (w(a) & ~(7 << sh)) | ((v + 1) << sh))
		o.update = me
		_sfx()
	v = (w(a) >> sh) & 7
	if _pad(s, PAD_LEFT) and v > 0:
		set_w(a, (w(a) & ~(7 << sh)) | ((v - 1) << sh))
		o.update = me
		_sfx()
	o.add_w(T, 1)
	var b := _box(_c(s, "chans"), w(chan))
	m.cursor_draw(s, b[0], b[1], b[2])


func menu_state_04B870(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04B870_1
	_show_colour(0)
	menu_state_04B870_1(o)


func menu_state_04B870_1(o: ISSMenu.Obj) -> void:
	_chans(o, 0, menu_state_04BB44, menu_state_04B5C6, menu_state_04B870)


func menu_state_04C372(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04C372_1
	_show_colour(1)
	menu_state_04C372_1(o)


func menu_state_04C372_1(o: ISSMenu.Obj) -> void:
	_chans(o, 1, menu_state_04C646, menu_state_04C0C4, menu_state_04C372)


# --------------------------------------------------------------------------
# The edit's OK and RESET (the team's first kit colours for the part).

func _edit_ok(o: ISSMenu.Obj, s: int, parts: Callable, reset: Callable, shades: Callable) -> void:
	if _pad(s, PAD_C):
		o.update = parts
		m.play_sfx(95)
	if _pad(s, PAD_RIGHT):
		o.update = reset
		_sfx()
	if _pad(s, PAD_LEFT):
		set_w(_c(s, "shade"), 1 if w(_c(s, "part")) == 2 else 2)
		o.update = shades
		_sfx()
	o.add_w(T, 1)
	m.cursor_draw(s, _c(s, "ok_x"), _c(s, "ok_x") + 0x10, 0x90)


func _edit_reset(o: ISSMenu.Obj, s: int, ok: Callable, shades: Callable) -> void:
	if _pad(s, PAD_C):
		var pal := ISSRom.res(6, 12)
		var part := w(_c(s, "part"))
		var src := w(_sym(s, "team")) * 32 + 0x10 + part * 6
		var dst: int = _c(s, "custom") + 0x10 + part * 6
		for i in (2 if part == 2 else 3):
			set_w(dst + 2 * i, (pal[src + 2 * i] << 8) | pal[src + 2 * i + 1])
		set_w(_c(s, "shade"), 0)
		o.update = shades
		m.play_sfx(95)
	if _pad(s, PAD_B | PAD_LEFT):
		o.update = ok
		_sfx()
	if _pad(s, PAD_RIGHT):
		set_w(_c(s, "shade"), 0)
		o.update = shades
		_sfx()
	o.add_w(T, 1)
	m.cursor_draw(s, _c(s, "reset_x"), _c(s, "reset_x") + 0x18, 0x90)


func menu_state_04BB44(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04BB44_1
	menu_state_04BB44_1(o)


func menu_state_04BB44_1(o: ISSMenu.Obj) -> void:
	_edit_ok(o, 0, menu_state_04B466, menu_state_04BBF8, menu_state_04B5C6)


func menu_state_04BBF8(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04BBF8_1
	menu_state_04BBF8_1(o)


func menu_state_04BBF8_1(o: ISSMenu.Obj) -> void:
	_edit_reset(o, 0, menu_state_04BB44, menu_state_04B5C6)


func menu_state_04C646(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04C646_1
	menu_state_04C646_1(o)


func menu_state_04C646_1(o: ISSMenu.Obj) -> void:
	_edit_ok(o, 1, menu_state_04BF64, menu_state_04C6FA, menu_state_04C0C4)


func menu_state_04C6FA(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04C6FA_1
	menu_state_04C6FA_1(o)


func menu_state_04C6FA_1(o: ISSMenu.Obj) -> void:
	_edit_reset(o, 1, menu_state_04C646, menu_state_04C0C4)
