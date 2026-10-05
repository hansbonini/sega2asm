class_name ISSScreensPassword
extends ISSScreens
## The passwords: entering one (screen $3A, main menu item 3) and showing
## the competition's after a game (screen $3B). A password is up to 60
## characters in rows of four groups of five; the grid holds the 64
## characters (12 a row, $1776 the one under the cursor) with EXIT and OK
## below. C writes the character at the edit place (g_password_bit) and
## moves on, B rubs out the last, Y / A-Z move the edit place. OK checks
## the password and restores its competition (ISSPassword); a wrong one
## sends the letters tumbling.

## Object fields of the tumbling letters (16.16 positions and speeds).
const O_X := 0x10
const O_Z := 0x18
const O_VEL_X := 0x20
const O_FRAME := 0x7A
const O_VEL_Z := 0x82
const O_ANIM := 0x8C


func register(h: Dictionary) -> void:
	h[0x3A] = screen_password
	h[0x3B] = screen_password_show


## The cell of character slot n (bit / 6): four groups of five a row, rows
## 16 apart from y0.
func _slot_xy(n: int, y0: int) -> Vector2i:
	var g := n / 5
	return Vector2i((n % 5) * 8 + (g & 3) * 0x30 + 0x20, (g >> 2) * 16 + y0)


func _char_tile(c: int) -> int:
	return (w(S.g_stadium_vram) >> 5) + 0xC393 + c


func _sl(o: ISSMenu.Obj, off: int) -> int:
	var v := o.l(off)
	return v - 0x100000000 if v >= 0x80000000 else v


# --------------------------------------------------------------------------
# Screen $3A.

func screen_password() -> void:
	set_w(S.g_password_length, 0)
	set_w(S.g_password_bit, 0)
	set_w(0x1776, 0)
	spawn(screen_password_1)
	menu_state_05A66C(spawn(Callable()))


func screen_password_1(o: ISSMenu.Obj) -> void:
	o.update = screen_password_2
	o.set_w(T, 0)
	screen_password_2(o)


## The edit place's cursor, the blinking block at the end of the password,
## line 2's colours 1-8 turning every eight frames.
func screen_password_2(_o: ISSMenu.Obj) -> void:
	var at := _slot_xy(w(S.g_password_bit) / 6, 0x30)
	m.cursor_draw(0, at.x, at.x + 8, at.y)
	if w(S.g_password_length) < 0x168:
		var end := _slot_xy(w(S.g_password_length) / 6, 0x30)
		var t := (w(S.g_stadium_vram) >> 5) + 0x83D3 + ((w(S.g_frame_counter) >> 3) & 3)
		m.rect_fill_tiles(end.x, end.x + 8, end.y, end.y + 8, t)
	if w(S.g_frame_counter) & 7 == 0:
		var first := w(0x798)
		for i in 7:
			set_w(0x798 + 2 * i, w(0x79A + 2 * i))
		set_w(0x7A6, first)
		if w(S.g_fade_step) == 0x18:
			m.cram_dma(0x40, 0x796, 0x20)
	m.boxes_draw_sprites(rom("screen_password_2_data"))


## EXIT: C returns to the main menu.
func menu_state_05A2FE(o: ISSMenu.Obj) -> void:
	o.update = menu_state_05A2FE_1
	o.set_w(T, 0)
	menu_state_05A2FE_1(o)


func menu_state_05A2FE_1(o: ISSMenu.Obj) -> void:
	if pressed(PAD_RIGHT):
		o.update = menu_state_05A3FE
		m.play_sfx(77)
	if pressed(PAD_LEFT):
		set_w(0x1776, 0x3F)
		o.update = menu_state_05A66C
		m.play_sfx(77)
	if pressed(PAD_C):
		goto_screen(0)
		m.play_sfx(95)
	if pressed(PAD_UP):
		set_w(0x1776, 0x3A)
		o.update = menu_state_05A66C
		m.play_sfx(77)
	if pressed(PAD_DOWN):
		set_w(0x1776, 0xA)
		o.update = menu_state_05A66C
		m.play_sfx(77)
	m.cursor_draw(0, 0xB8, 0xC8, 0xC8)


## OK: C checks the password; a good one restores its competition, a bad
## one clears the edit place and sends the letters tumbling.
func menu_state_05A3FE(o: ISSMenu.Obj) -> void:
	o.update = menu_state_05A3FE_1
	o.set_w(T, 0)
	menu_state_05A3FE_1(o)


func menu_state_05A3FE_1(o: ISSMenu.Obj) -> void:
	if pressed(PAD_RIGHT):
		set_w(0x1776, 0)
		o.update = menu_state_05A66C
		m.play_sfx(77)
	if pressed(PAD_LEFT):
		o.update = menu_state_05A2FE
		m.play_sfx(77)
	if pressed(PAD_UP):
		set_w(0x1776, 0x3B)
		o.update = menu_state_05A66C
		m.play_sfx(77)
	if pressed(PAD_DOWN):
		set_w(0x1776, 0xB)
		o.update = menu_state_05A66C
		m.play_sfx(77)
	if pressed(PAD_C):
		if ISSPassword.check():
			var bit := w(S.g_password_bit)
			set_l(S.g_next_state, ISSMenu.STATE_MENU)
			set_w(S.g_next_screen, 0x3A)
			var mode := ISSPassword.mode_of_length(w(S.g_password_length))
			if mode >= 0:
				set_w(S.g_next_screen, ISSPassword.resume(mode))
				if mode == 0xA:
					ISSModes.match_setup_random()
					m.menu_music(4)
			set_w(S.g_password_bit, bit)
			m.fade_out_start()
			return
		set_w(S.g_password_bit, 0)
		set_w(0x1776, 0)
		o.update = menu_state_05A3FE_2
		_tumble(rom("menu_state_05A3FE_1_data"))
		m.play_sfx(78)
		return
	m.cursor_draw(0, 0xD0, 0xD8, 0xC8)


## 14 tumbling letters from the positions at data.
func _tumble(data: int) -> void:
	for i in 14:
		var t := m.obj_alloc()
		if t == null:
			continue
		t.set_w(O_X, ISSRom.u16(data + i * 4))
		t.set_w(O_Z, ISSRom.u16(data + i * 4 + 2))
		t.set_w(O_ANIM, 1)
		t.update = menu_state_05A9CA


func menu_state_05A3FE_2(o: ISSMenu.Obj) -> void:
	o.update = menu_state_05A3FE_3
	o.set_w(T, 0x80)
	menu_state_05A3FE_3(o)


func menu_state_05A3FE_3(o: ISSMenu.Obj) -> void:
	o.add_w(T, -1)
	if o.w(T) == 0:
		o.update = menu_state_05A66C


## The grid of 64 characters (12 a row; row 5 has four).
func menu_state_05A66C(o: ISSMenu.Obj) -> void:
	o.update = menu_state_05A66C_1
	o.set_w(T, 0)
	menu_state_05A66C_1(o)


func menu_state_05A66C_1(o: ISSMenu.Obj) -> void:
	var c := w(0x1776)
	if pressed(PAD_RIGHT):
		if c < 0x3F:
			add_w(0x1776, 1)
		else:
			o.update = menu_state_05A2FE
		m.play_sfx(77)
	c = w(0x1776)
	if pressed(PAD_LEFT):
		if c != 0:
			add_w(0x1776, -1)
		else:
			o.update = menu_state_05A3FE
		m.play_sfx(77)
	c = w(0x1776)
	if pressed(PAD_DOWN):
		if c < 0x34:
			add_w(0x1776, 0xC)
		elif c >= 0x3C:
			add_w(0x1776, -0x3C)
		elif c == 0x3B:
			o.update = menu_state_05A3FE
		elif c == 0x3A:
			o.update = menu_state_05A2FE
		else:
			add_w(0x1776, -0x30)
		m.play_sfx(77)
	c = w(0x1776)
	if pressed(PAD_UP):
		if c >= 0xC:
			add_w(0x1776, -0xC)
		elif c < 4:
			add_w(0x1776, 0x3C)
		elif c == 0xA:
			o.update = menu_state_05A2FE
		elif c == 0xB:
			o.update = menu_state_05A3FE
		else:
			add_w(0x1776, 0x30)
		m.play_sfx(77)
	if pressed(PAD_C):
		var at := _slot_xy(w(S.g_password_bit) / 6, 0x30)
		m.rect_fill_tiles(at.x, at.x + 8, at.y, at.y + 8, _char_tile(w(0x1776)))
		if w(S.g_password_bit) == w(S.g_password_length):
			# A new character: a sparkle where it went, the password longer.
			var t := m.obj_alloc()
			if t != null:
				t.set_w(O_ANIM, 0)
				t.set_w(O_Z, at.y)
				t.set_w(O_X, at.x)
				t.update = menu_state_05A9CA
			m.play_sfx(76)
			add_w(S.g_password_length, 6)
		else:
			m.play_sfx(77)
		ISSPassword.write_bits(6, w(0x1776))
		if w(S.g_password_bit) == 0x168:
			set_w(S.g_password_bit, 0)
			o.update = menu_state_05A3FE
	if pressed(PAD_B):
		if w(S.g_password_length) != 0:
			add_w(S.g_password_length, -6)
		else:
			o.update = menu_state_05A2FE
		set_w(S.g_password_bit, w(S.g_password_length))
	if pressed(0x200):
		if w(S.g_password_bit) != 0:
			add_w(S.g_password_bit, -6)
		else:
			set_w(S.g_password_bit, w(S.g_password_length))
			if w(S.g_password_bit) == 0x168:
				set_w(S.g_password_bit, 0x162)
		m.play_sfx(77)
	if pressed(0x140):
		if w(S.g_password_bit) < w(S.g_password_length):
			add_w(S.g_password_bit, 6)
			if w(S.g_password_bit) == 0x168:
				set_w(S.g_password_bit, 0)
		else:
			set_w(S.g_password_bit, 0)
		m.play_sfx(77)
	var cc := w(0x1776)
	var x := (cc % 12) * 16 + 0x20
	m.cursor_draw(0, x, x + 8, (cc / 12) * 16 + 0x78)


## A tumbling letter: up at 4-7, falling half a pixel a frame per frame,
## drifting -3..4 sideways; with O_ANIM its frame (menu_state_05A9CA_1_data)
## advances every 8-39 frames up to 2. Gone below $E0.
func menu_state_05A9CA(o: ISSMenu.Obj) -> void:
	o.update = menu_state_05A9CA_1
	o.set_w(O_FRAME, 0)
	o.set_w(T, (ISSModes._rand() & 0x1F) + 8)
	o.set_w(O_VEL_Z, (ISSModes._rand() & 3) + 4)
	o.set_w(O_VEL_X, ((ISSModes._rand() & 7) - 3) & 0xFFFF)
	menu_state_05A9CA_1(o)


func menu_state_05A9CA_1(o: ISSMenu.Obj) -> void:
	var vz := _sl(o, O_VEL_Z) - 0x8000
	o.set_l(O_VEL_Z, vz & 0xFFFFFFFF)
	o.set_l(O_Z, (_sl(o, O_Z) - vz) & 0xFFFFFFFF)
	o.set_l(O_X, (_sl(o, O_X) - _sl(o, O_VEL_X)) & 0xFFFFFFFF)
	if o.sw(O_Z) > 0xE0:
		m.obj_free(o)
		return
	if o.w(O_ANIM) != 0:
		o.add_w(T, -1)
		if o.w(T) == 0:
			o.set_w(T, (ISSModes._rand() & 0x1F) + 8)
			if o.w(O_FRAME) < 2:
				o.add_w(O_FRAME, 1)
	var d := rom("menu_state_05A9CA_1_data") + o.w(O_FRAME) * 10
	var x := (o.w(O_X) + ISSRom.u16(d + 6)) & 0x1FF
	if x == 0:
		x = 1
	m.sprite((o.w(O_Z) + ISSRom.u16(d)) & 0xFFFF, ISSRom.u16(d + 2) & 0xFF,
		(w(0x176C) >> 5) + ISSRom.u16(d + 4), x)


# --------------------------------------------------------------------------
# Screen $3B: the competition's password, shown after 64 frames with a
# sparkle; C goes on to the pre-match menu (a scenario to its list).

func screen_password_show() -> void:
	ISSPassword.encode(w(S.g_game_mode))
	ISSPassword.seal()
	spawn(screen_password_show_1)


func screen_password_show_1(o: ISSMenu.Obj) -> void:
	o.update = screen_password_show_2
	o.set_w(T, 0x40)
	screen_password_show_2(o)


func screen_password_show_2(o: ISSMenu.Obj) -> void:
	if o.w(T) != 0:
		o.add_w(T, -1)
		if o.w(T) == 0:
			set_w(S.g_password_bit, 0)
			for n in w(S.g_password_length) / 6:
				var c := ISSPassword.read_bits(6)
				var at := _slot_xy(n, 0x50)
				m.rect_fill_tiles(at.x, at.x + 8, at.y, at.y + 8, _char_tile(c))
			_tumble(rom("screen_password_show_2_data2"))
			m.play_sfx(78)
	elif pressed(PAD_C):
		goto_screen(0x24 if w(S.g_game_mode) == 0xC else 6)
	m.boxes_draw_sprites(rom("screen_password_show_2_data"))
