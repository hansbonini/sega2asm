class_name ISSScreensCredits
extends ISSScreens
## The ending (screen $33), the staff roll. After the International Cup
## (mode 8) the credits come a page at a time, each line sliding in and out
## sideways (plane B scrolled by 8-line rows, register 11's cell mode, the
## table at $1776) while the champions' players, their keeper, the referee
## and the ball play scenes across it (ISSObjects: the match's own objects
## and routines). After the World Series or the championship the team
## lines up for a photo that flashes, then the players' pictures pass on
## plane A while the credits scroll up plane B. Start returns to the start
## of the game.

const X := ISSObjects.X
const Y := ISSObjects.Y
const Z := ISSObjects.Z
const INPUT := ISSObjects.INPUT
const FACING := ISSObjects.FACING
const HEADING := ISSObjects.HEADING
const BALL_DIST := ISSObjects.BALL_DIST
const SPEED := ISSObjects.SPEED
const VEL_X := ISSObjects.VEL_X
const VEL_Y := ISSObjects.VEL_Y
const VEL_Z := ISSObjects.VEL_Z
const ANIM_FRAME := ISSObjects.ANIM_FRAME
const OWNER := ISSObjects.OWNER
const STATE := ISSObjects.STATE

var objects: ISSObjects


func register(h: Dictionary) -> void:
	h[0x33] = screen_credits


func _p(k: int) -> ISSObjects.Actor:
	return objects.player(k)


## Add v to every word from a to end (a map's tiles to their VRAM place).
func _add(a: int, end: int, v: int) -> void:
	a &= 0xFFFF
	while a < (end & 0xFFFF):
		ISSRam.set_w(a, ISSRam.w(a) + v)
		a += 2


## Unpack (g, e) into the unpack buffer, its tiles to VRAM at the stadium
## tiles + at; the VRAM address.
func _tiles_at(g: int, e: int, at: int) -> int:
	var buf := l(S.g_unpack_buffer)
	var end := m.unpack(g, e, buf)
	var dst := w(S.g_stadium_vram) + at
	m.vram_dma(dst, buf, end - buf)
	return dst


## Unpack the map (g, e) to the unpack buffer, keep it at RAM var and add
## tile base to its words.
func _map(g: int, e: int, var_addr: int, base: int) -> void:
	var buf := l(S.g_unpack_buffer)
	set_l(var_addr, buf)
	var end := m.unpack(g, e, buf)
	set_l(S.g_unpack_buffer, end)
	_add(buf, end, base)


## An object put on the pitch out of sight (-128, -128), standing.
func _place(o: ISSObjects.Actor, attr: int) -> void:
	objects.link(o)
	o.set_w(Z, 0)
	o.set_w(X, 0xFF80)
	o.set_w(Y, 0xFF80)
	o.set_w(ISSObjects.ATTR, attr)
	o.think = Callable()
	o.set_w(ISSObjects.FOLLOW, 0xFFFF)
	o.set_w(FACING, 0)
	o.set_w(HEADING, 0)
	o.set_w(INPUT, 0)


func screen_credits() -> void:
	objects = ISSObjects.new(m)
	var cup := w(S.g_game_mode) == 8
	if cup:
		m.menu_music(6)
	else:
		m.menu_music(0x19)
		m.play_sfx(99)
	set_w(S.g_training, 1)
	# Plane A: group 26 entry 1; line 2 colours from group 16 entry 9.
	var buf := l(S.g_unpack_buffer)
	var end := m.unpack(26, 1, buf)
	_add(buf, end, w(S.g_overlay_vram) >> 5)
	m.vram_dma(0x2000, buf, end - buf)
	m.unpack(16, 9, 0xFF07A6)
	set_w(0x798, 0x222)
	set_w(0x7A6, 0xEAA)
	set_w(0x7A8, 0xE66)
	if not cup:
		_photo_tiles()
	else:
		_cast()
	var team := w(0x127C)
	var kits := ISSRom.res(6, 12)
	for i in 16:
		set_w(S.g_palette_target + 2 * i, (kits[team * 32 + 2 * i] << 8) | kits[team * 32 + 2 * i + 1])
	if not cup:
		ISSModes.kit_shades()
	set_l(0x1814, 0x20000)
	set_l(0x1818, 0x20000)
	for k in 10:
		var p := _p(k)
		_place(p, 0)
		p.set_b(STATE, 0xFF)
		p.set_w(BALL_DIST, 0x7FFF)
		p.set_w(ISSObjects.ENERGY_TIMER, 0x100)
		p.set_w(ISSObjects.CROUCH, 0)
		# No controller (the original keeps the last match's): a keeper's
		# punt then has no aftertouch.
		p.set_l(OWNER, 0xFFFFFFFF)
		objects.give_figure(p, "keeper" if k == 0 else "player", team)
		if k == 0:
			objects.keeper_update(p)
		else:
			objects.player_update(p)
		p.set_w(ISSObjects.TEAM, 0)
	# The row scroll table ($400 bytes) and the copy of plane A's map
	# ($E00 bytes of the stadium's first tile).
	buf = l(S.g_unpack_buffer)
	set_l(0x1776, buf)
	buf += 0x400
	set_l(0x1786, buf)
	for i in 0x700:
		ISSRam.set_w((buf & 0xFFFF) + 2 * i, w(S.g_stadium_vram) >> 5)
	set_l(S.g_unpack_buffer, buf + 0xE00)
	if cup:
		spawn(screen_credits_2)
		var o := spawn(screen_credits_4)
		o.set_w(0x14, 0x7FFF)
	else:
		spawn(screen_credits_106)
		spawn(screen_credits_108)


## The International Cup's cast: the referee in the level's kit (group 4
## entry 38: the hardest levels' other set, $125E), running at 1.5, and
## the ball held out of play (state 2, by g_director).
func _cast() -> void:
	var level := 1
	set_w(0x125E, 0)
	if w(S.g_game_level) > 2:
		set_w(0x125E, 1)
		level = 3
	var kit := ISSRom.res(4, 38)
	for i in 6:
		set_w(0x79A + 2 * i, (kit[level * 16 + 4 + 2 * i] << 8) | kit[level * 16 + 5 + 2 * i])
	set_l(0x17B4, 0x18000)
	set_l(0x17B8, 0x18000)
	ISSRam.set_b(S.g_ball + STATE, 2)
	ISSRam.set_l(S.g_ball + OWNER, 0xFF0000 | S.g_director)
	objects.referee = objects.actor(S.g_referee)
	var r := objects.referee
	_place(r, 0x4000)
	objects.give_figure(r, "referee")
	objects.sys_state_001670(r)
	m.unpack(7, 6, 0xFF07B6)
	objects.ball = objects.actor(S.g_ball)
	var b := objects.ball
	objects.link(b)
	b.set_w(Z, 0)
	b.set_l(VEL_Z, 0)
	b.set_l(SPEED, 0)
	b.set_w(INPUT, 0)
	b.set_w(X, 0xFF80)
	b.set_w(Y, 0xFF80)
	b.set_w(ISSObjects.TEAM, 0)
	b.set_w(ISSObjects.ATTR, 0x6000)
	b.think = Callable()
	objects.give_figure(b, "ball")
	objects.ball_update(b)
	set_l(S.g_camera_focus, 0xFF0000 | S.g_ball)


## The photo ending's pictures: the team photo (group 19), the players'
## pictures (groups 20 and 22) as maps at $177A / $177E / $1782, their
## colours, and the sprite sets of the crowd's flags and banners (group 4
## entries 22-24, 27) at $178A-$1790.
func _photo_tiles() -> void:
	m.unpack(19, 2, 0xFF0776)
	var at := _tiles_at(19, 1, 0x3000)
	_map(19, 0, 0x177A, at >> 5)
	m.unpack(20, 2, 0xFF07B6)
	at = _tiles_at(20, 1, 0x20)
	_map(20, 0, 0x177E, (at >> 5) | 0x4000)
	at = _tiles_at(22, 1, 0x3CE0)
	_map(22, 0, 0x1782, at >> 5)
	set_w(0x178A, _tiles_at(4, 22, 0x4380))
	set_w(0x178C, _tiles_at(4, 23, 0x5140))
	set_w(0x178E, m.load_tiles(4, 24))
	set_w(0x1790, m.load_tiles(4, 27))


# --------------------------------------------------------------------------
# The helpers of the credits.

## screen_credits_2: the row scroll table to the VDP every frame.
func screen_credits_2(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_3
	screen_credits_3(o)


func screen_credits_3(_o: ISSMenu.Obj) -> void:
	m.vdp.set_line_scroll(l(0x1776) & 0xFFFF, true)


## screen_credits_104: a page of the credits (type 0 large, 2 small, else the
## big font; x, y in cells; the text) with every row moved out of sight
## ($100 to the right).
func screen_credits_104(a: int) -> void:
	m.rect_fill(0x10, 0xF0, 0x10, 0xD0, tiles())
	var kind := ISSRom.u8(a)
	a += 1
	while kind < 0x80:
		var x := ISSRom.u8(a) * 8
		var y := ISSRom.u8(a + 1) * 8
		a = _text(kind, x, y, a + 2)
		kind = ISSRom.u8(a)
		a += 1
	var t := l(0x1776) + 2
	for r in 32:
		ISSRam.set_l(t + r * 0x20, 0x01000000)


func _text(kind: int, x: int, y: int, a: int) -> int:
	if kind == 0:
		return m.text_draw_large(x, y, a)
	if kind == 2:
		return m.text_draw_small(x, y, a)
	return screen_credits_1(x, y, a)


## screen_credits_1: the big 16 x 32 font (screen_credits_1_data, 2 x 4 cells a
## character from '@', tiles from $320).
func screen_credits_1(x: int, y: int, a: int) -> int:
	var c := (l(S.g_text_nametable) & 0xFFFF) + (y >> 3) * 0x80 + (x >> 3) * 2
	var base := (w(S.g_stadium_vram) >> 5) + 0xC320
	var font := rom("screen_credits_1_data")
	var ch := ISSRom.u8(a)
	a += 1
	while ch < 0x80:
		var g := font + (ch - 0x40) * 16
		var i := 0
		for off in [0, 2, 0x80, 0x82, 0x100, 0x102, 0x180, 0x182]:
			ISSRam.set_w(c + off, (ISSRom.u16(g + i * 2) + base) & 0xFFFF)
			i += 1
		c += 4
		ch = ISSRom.u8(a)
		a += 1
	return a


## screen_credits_105: the rows from y0 to y1 slide dx pixels.
func _rows(y0: int, y1: int, dx: int) -> void:
	var a := l(0x1776) + 2 + (y0 >> 3) * 0x20
	for i in (y1 >> 3) - (y0 >> 3):
		ISSRam.set_w(a, ISSRam.w(a) + dx)
		a += 0x20


## Two large lines (type, x, y, text) shown every other 32 frames, the
## rows $70-$98 blank in between.
func _blink(a: int) -> void:
	if w(S.g_frame_counter) & 0x20 == 0:
		m.rect_fill(0x10, 0xF0, 0x70, 0x98, tiles())
		return
	for i in 2:
		a = m.text_draw_large(ISSRom.u8(a + 1) * 8, ISSRom.u8(a + 2) * 8, a + 3)


## Start: the music stops, back to main_init.
func _start_over() -> void:
	if pressed(PAD_START):
		if sw(S.g_sound_disabled) >= 0:
			set_w(S.g_sound_disabled, 0xFFFF)
			m.sound.stop_music()
		set_l(S.g_next_state, ISSMenu.STATE_INIT)
		m.fade_out_start()


# --------------------------------------------------------------------------
# The International Cup's staff roll (screen_credits_4 - screen_credits_103).

func screen_credits_4(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_5
	screen_credits_104(rom("menu_data_058772"))
	# The first page shows at once.
	var a := l(0x1776) + 2
	for r in 32:
		ISSRam.set_w(a + r * 0x20, 0)
	o.set_w(T, 0)
	screen_credits_5(o)


func screen_credits_5(o: ISSMenu.Obj) -> void:
	o.add_w(T, 1)
	if o.w(T) == 0x100:
		o.update = screen_credits_6


func screen_credits_6(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_7
	o.set_w(T, 0)
	screen_credits_7(o)


func screen_credits_7(o: ISSMenu.Obj) -> void:
	_rows(0x48, 0x68, 2)
	_rows(0x70, 0x90, -2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_8


func screen_credits_8(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_9
	screen_credits_104(rom("screen_credits_8_data"))
	_p(1).set_w(X, -0x30)
	_p(1).set_w(Y, 0xC0)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x10)
	_p(1).set_w(HEADING, 0x10)
	_p(1).update = objects.player_start_run_005D5C
	_p(2).set_w(X, 0x130)
	_p(2).set_w(Y, 0x130)
	_p(2).set_w(INPUT, 0xF)
	_p(2).set_w(FACING, 0x30)
	_p(2).set_w(HEADING, 0x30)
	_p(2).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_9(o)


func screen_credits_9(o: ISSMenu.Obj) -> void:
	_rows(0x40, 0x60, 2)
	_rows(0x70, 0x98, -2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_10


func screen_credits_10(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_11
	_p(1).set_w(INPUT, 0)
	_p(1).set_w(FACING, 0x20)
	_p(1).set_w(HEADING, 0x20)
	_p(1).update = objects.player_start_fist_pump_00943E
	_p(2).set_w(INPUT, 0)
	_p(2).set_w(FACING, 0x20)
	_p(2).set_w(HEADING, 0x20)
	_p(2).update = objects.player_start_fist_pump_00943E
	o.set_w(T, 0)
	screen_credits_11(o)


func screen_credits_11(o: ISSMenu.Obj) -> void:
	o.add_w(T, 1)
	if o.w(T) == 0xA0:
		o.update = screen_credits_12


func screen_credits_12(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_13
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x10)
	_p(1).set_w(HEADING, 0x10)
	_p(1).update = objects.player_start_run_005D5C
	_p(2).set_w(INPUT, 0xF)
	_p(2).set_w(FACING, 0x30)
	_p(2).set_w(HEADING, 0x30)
	_p(2).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_13(o)


func screen_credits_13(o: ISSMenu.Obj) -> void:
	_rows(0x40, 0x60, 2)
	_rows(0x70, 0x98, -2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_14


func screen_credits_14(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_15
	screen_credits_104(rom("screen_credits_14_data"))
	_p(1).set_w(X, -0x30)
	_p(1).set_w(Y, 0x168)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x10)
	_p(1).set_w(HEADING, 0x10)
	_p(1).update = objects.player_start_run_005D5C
	_p(2).set_w(X, 0x130)
	_p(2).set_w(Y, 0xB0)
	_p(2).set_w(INPUT, 0xF)
	_p(2).set_w(FACING, 0x30)
	_p(2).set_w(HEADING, 0x30)
	_p(2).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_15(o)


func screen_credits_15(o: ISSMenu.Obj) -> void:
	_rows(0x38, 0x80, -2)
	_rows(0x90, 0xA0, 2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_16


func screen_credits_16(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_17
	_p(1).set_w(INPUT, 0)
	_p(1).set_w(FACING, 0x20)
	_p(1).set_w(HEADING, 0x20)
	_p(1).update = objects.player_start_arm_up_009506
	_p(2).set_w(INPUT, 0)
	_p(2).set_w(FACING, 0x20)
	_p(2).set_w(HEADING, 0x20)
	_p(2).update = objects.player_start_arm_up_009506
	o.set_w(T, 0)
	screen_credits_17(o)


func screen_credits_17(o: ISSMenu.Obj) -> void:
	o.add_w(T, 1)
	if o.w(T) == 0xA0:
		o.update = screen_credits_18


func screen_credits_18(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_19
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x10)
	_p(1).set_w(HEADING, 0x10)
	_p(1).update = objects.player_start_run_005D5C
	_p(2).set_w(INPUT, 0xF)
	_p(2).set_w(FACING, 0x30)
	_p(2).set_w(HEADING, 0x30)
	_p(2).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_19(o)


func screen_credits_19(o: ISSMenu.Obj) -> void:
	_rows(0x38, 0x80, -2)
	_rows(0x90, 0xA0, 2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_20


func screen_credits_20(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_21
	screen_credits_104(rom("screen_credits_20_data"))
	_p(1).set_w(X, -0x18)
	_p(1).set_w(Y, 0xA0)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x10)
	_p(1).set_w(HEADING, 0x10)
	_p(1).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_21(o)


func screen_credits_21(o: ISSMenu.Obj) -> void:
	if o.w(T) < 0x80:
		_rows(0x18, 0x60, 2)
	o.add_w(T, 1)
	if o.w(T) == 0xC0:
		o.update = screen_credits_22


func screen_credits_22(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_23
	_p(1).set_w(X, 0x120)
	_p(1).set_w(Y, 0x120)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x30)
	_p(1).set_w(HEADING, 0x30)
	_p(1).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_23(o)


func screen_credits_23(o: ISSMenu.Obj) -> void:
	if o.w(T) < 0x80:
		_rows(0x70, 0x80, -2)
	o.add_w(T, 1)
	if o.w(T) == 0xC0:
		o.update = screen_credits_24


func screen_credits_24(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_25
	_p(1).set_w(X, -0x20)
	_p(1).set_w(Y, 0x160)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x10)
	_p(1).set_w(HEADING, 0x10)
	_p(1).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_25(o)


func screen_credits_25(o: ISSMenu.Obj) -> void:
	if o.w(T) < 0x80:
		_rows(0x90, 0xA0, 2)
	o.add_w(T, 1)
	if o.w(T) == 0xC0:
		o.update = screen_credits_26


func screen_credits_26(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_27
	_p(1).set_w(X, 0x120)
	_p(1).set_w(Y, 0x1A0)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x30)
	_p(1).set_w(HEADING, 0x30)
	_p(1).update = objects.player_start_run_005D5C
	_p(2).set_w(X, -0x20)
	_p(2).set_w(Y, 0x1A0)
	_p(2).set_w(INPUT, 0xF)
	_p(2).set_w(FACING, 0x10)
	_p(2).set_w(HEADING, 0x10)
	_p(2).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	o.set_w(ANIM_FRAME, 0)
	screen_credits_27(o)


func screen_credits_27(o: ISSMenu.Obj) -> void:
	if o.w(T) < 0x80:
		_rows(0xB0, 0xC0, -2)
	if o.w(T) == 0x40:
		_p(2).update = objects.player_start_sit_after_a_slide_008F16
	if o.w(T) == 0x48:
		ISSRam.set_l(S.g_foul_victim, 0xFFFFFFFF)
		_p(1).update = objects.player_knocked_over
	o.add_w(T, 1)
	if o.w(T) == 0x200:
		o.update = screen_credits_28


func screen_credits_28(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_29
	o.set_w(T, 0)
	screen_credits_29(o)


func screen_credits_29(o: ISSMenu.Obj) -> void:
	_rows(0x18, 0x60, 2)
	_rows(0x70, 0x80, -2)
	_rows(0x90, 0xA0, 2)
	_rows(0xB0, 0xC0, -2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_30


func screen_credits_30(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_31
	screen_credits_104(rom("screen_credits_30_data"))
	_p(1).set_w(X, -0x20)
	_p(1).set_w(Y, 0xC0)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x10)
	_p(1).set_w(HEADING, 0x10)
	_p(1).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_31(o)


func screen_credits_31(o: ISSMenu.Obj) -> void:
	if o.w(T) < 0x80:
		_rows(0x40, 0x60, 2)
	o.add_w(T, 1)
	if o.w(T) == 0xC0:
		o.update = screen_credits_32


func screen_credits_32(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_33
	_p(1).set_w(X, 0x120)
	_p(1).set_w(Y, 0x110)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x30)
	_p(1).set_w(HEADING, 0x30)
	_p(1).update = objects.player_start_run_005D5C
	_p(2).set_w(X, -0x20)
	_p(2).set_w(Y, 0x150)
	_p(2).set_w(INPUT, 0xF)
	_p(2).set_w(FACING, 0x10)
	_p(2).set_w(HEADING, 0x10)
	_p(2).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_33(o)


func screen_credits_33(o: ISSMenu.Obj) -> void:
	_rows(0x70, 0x80, -2)
	_rows(0x90, 0xA0, 2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_34


func screen_credits_34(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_35
	_p(1).set_w(INPUT, 0)
	_p(1).set_w(FACING, 0x20)
	_p(1).set_w(HEADING, 0x20)
	_p(1).update = objects.player_start_arm_up_009506
	_p(2).set_w(INPUT, 0)
	_p(2).set_w(FACING, 0x20)
	_p(2).set_w(HEADING, 0x20)
	_p(2).update = objects.player_start_arm_up_009506
	o.set_w(T, 0)
	screen_credits_35(o)


func screen_credits_35(o: ISSMenu.Obj) -> void:
	o.add_w(T, 1)
	if o.w(T) == 0xA0:
		o.update = screen_credits_36


func screen_credits_36(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_37
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x30)
	_p(1).set_w(HEADING, 0x30)
	_p(1).update = objects.player_start_run_005D5C
	_p(2).set_w(INPUT, 0xF)
	_p(2).set_w(FACING, 0x10)
	_p(2).set_w(HEADING, 0x10)
	_p(2).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_37(o)


func screen_credits_37(o: ISSMenu.Obj) -> void:
	_rows(0x40, 0x60, 2)
	_rows(0x70, 0x80, -2)
	_rows(0x90, 0xA0, 2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_38


func screen_credits_38(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_39
	screen_credits_104(rom("screen_credits_38_data"))
	_p(1).set_w(X, 0x120)
	_p(1).set_w(Y, 0xB0)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x30)
	_p(1).set_w(HEADING, 0x30)
	_p(1).update = objects.player_start_run_005D5C
	_p(2).set_w(X, 0x1E0)
	_p(2).set_w(Y, 0xB0)
	_p(2).set_w(INPUT, 0xF)
	_p(2).set_w(FACING, 0x30)
	_p(2).set_w(HEADING, 0x30)
	_p(2).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_39(o)


func screen_credits_39(o: ISSMenu.Obj) -> void:
	_rows(0x38, 0x80, -2)
	_rows(0x90, 0xA0, 2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_40


func screen_credits_40(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_41
	_p(1).set_w(INPUT, 0)
	_p(1).set_w(FACING, 0x20)
	_p(1).set_w(HEADING, 0x20)
	_p(1).update = objects.player_start_fist_pump_00943E
	_p(2).set_w(INPUT, 0)
	_p(2).set_w(FACING, 0x20)
	_p(2).set_w(HEADING, 0x20)
	_p(2).update = objects.player_start_fist_pump_00943E
	o.set_w(T, 0)
	screen_credits_41(o)


func screen_credits_41(o: ISSMenu.Obj) -> void:
	o.add_w(T, 1)
	if o.w(T) == 0xA0:
		o.update = screen_credits_42


func screen_credits_42(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_43
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x30)
	_p(1).set_w(HEADING, 0x30)
	_p(1).update = objects.player_start_run_005D5C
	_p(2).set_w(INPUT, 0xF)
	_p(2).set_w(FACING, 0x30)
	_p(2).set_w(HEADING, 0x30)
	_p(2).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_43(o)


func screen_credits_43(o: ISSMenu.Obj) -> void:
	_rows(0x38, 0x80, -2)
	_rows(0x90, 0xA0, 2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_44


func screen_credits_44(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_45
	screen_credits_104(rom("screen_credits_44_data"))
	_p(1).set_w(X, 0x118)
	_p(1).set_w(Y, 0x80)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x30)
	_p(1).set_w(HEADING, 0x30)
	_p(1).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_45(o)


func screen_credits_45(o: ISSMenu.Obj) -> void:
	if o.w(T) < 0x80:
		_rows(0x20, 0x40, -2)
	o.add_w(T, 1)
	if o.w(T) == 0xC0:
		o.update = screen_credits_46


func screen_credits_46(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_47
	_p(1).set_w(X, -0x30)
	_p(1).set_w(Y, 0xD0)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x10)
	_p(1).set_w(HEADING, 0x10)
	_p(1).update = objects.player_start_run_005D5C
	_p(2).set_w(X, 0x130)
	_p(2).set_w(Y, 0x110)
	_p(2).set_w(INPUT, 0xF)
	_p(2).set_w(FACING, 0x30)
	_p(2).set_w(HEADING, 0x30)
	_p(2).update = objects.player_start_run_005D5C
	_p(3).set_w(X, -0x30)
	_p(3).set_w(Y, 0x150)
	_p(3).set_w(INPUT, 0xF)
	_p(3).set_w(FACING, 0x10)
	_p(3).set_w(HEADING, 0x10)
	_p(3).update = objects.player_start_run_005D5C
	_p(4).set_w(X, 0x130)
	_p(4).set_w(Y, 0x190)
	_p(4).set_w(INPUT, 0xF)
	_p(4).set_w(FACING, 0x30)
	_p(4).set_w(HEADING, 0x30)
	_p(4).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_47(o)


func screen_credits_47(o: ISSMenu.Obj) -> void:
	_rows(0x50, 0x60, 2)
	_rows(0x70, 0x80, -2)
	_rows(0x90, 0xA0, 2)
	_rows(0xB0, 0xC0, -2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_48


func screen_credits_48(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_49
	for k in range(1, 5):
		_p(k).set_w(INPUT, 0)
		_p(k).set_w(FACING, 0x20)
		_p(k).set_w(HEADING, 0x20)
		_p(k).update = objects.player_start_fist_pump_00943E
	o.set_w(T, 0)
	screen_credits_49(o)


func screen_credits_49(o: ISSMenu.Obj) -> void:
	o.add_w(T, 1)
	if o.w(T) == 0xA0:
		o.update = screen_credits_50


func screen_credits_50(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_51
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x10)
	_p(1).set_w(HEADING, 0x10)
	_p(1).update = objects.player_start_run_005D5C
	_p(2).set_w(INPUT, 0xF)
	_p(2).set_w(FACING, 0x30)
	_p(2).set_w(HEADING, 0x30)
	_p(2).update = objects.player_start_run_005D5C
	_p(3).set_w(INPUT, 0xF)
	_p(3).set_w(FACING, 0x10)
	_p(3).set_w(HEADING, 0x10)
	_p(3).update = objects.player_start_run_005D5C
	_p(4).set_w(INPUT, 0xF)
	_p(4).set_w(FACING, 0x30)
	_p(4).set_w(HEADING, 0x30)
	_p(4).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_51(o)


func screen_credits_51(o: ISSMenu.Obj) -> void:
	_rows(0x20, 0x40, -2)
	_rows(0x50, 0x60, 2)
	_rows(0x70, 0x80, -2)
	_rows(0x90, 0xA0, 2)
	_rows(0xB0, 0xC0, -2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_52


func screen_credits_52(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_53
	screen_credits_104(rom("screen_credits_52_data"))
	_p(1).set_w(X, -0x30)
	_p(1).set_w(Y, 0xD0)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x10)
	_p(1).set_w(HEADING, 0x10)
	_p(1).update = objects.player_start_run_005D5C
	_p(2).set_w(X, 0x130)
	_p(2).set_w(Y, 0x120)
	_p(2).set_w(INPUT, 0xF)
	_p(2).set_w(FACING, 0x30)
	_p(2).set_w(HEADING, 0x30)
	_p(2).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_53(o)


func screen_credits_53(o: ISSMenu.Obj) -> void:
	_rows(0x48, 0x68, 2)
	_rows(0x70, 0x90, -2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_54


func screen_credits_54(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_55
	_p(1).set_w(INPUT, 0)
	_p(1).set_w(FACING, 0x20)
	_p(1).set_w(HEADING, 0x20)
	_p(1).update = objects.player_start_fist_pump_00943E
	_p(2).set_w(INPUT, 0)
	_p(2).set_w(FACING, 0x20)
	_p(2).set_w(HEADING, 0x20)
	_p(2).update = objects.player_start_fist_pump_00943E
	o.set_w(T, 0)
	screen_credits_55(o)


func screen_credits_55(o: ISSMenu.Obj) -> void:
	o.add_w(T, 1)
	if o.w(T) == 0xA0:
		o.update = screen_credits_56


func screen_credits_56(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_57
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x10)
	_p(1).set_w(HEADING, 0x10)
	_p(1).update = objects.player_start_run_005D5C
	_p(2).set_w(INPUT, 0xF)
	_p(2).set_w(FACING, 0x30)
	_p(2).set_w(HEADING, 0x30)
	_p(2).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_57(o)


func screen_credits_57(o: ISSMenu.Obj) -> void:
	_rows(0x48, 0x68, 2)
	_rows(0x70, 0x90, -2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_58


func screen_credits_58(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_59
	screen_credits_104(rom("screen_credits_58_data"))
	_p(1).set_w(X, -0x20)
	_p(1).set_w(Y, 0x80)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x10)
	_p(1).set_w(HEADING, 0x10)
	_p(1).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_59(o)


func screen_credits_59(o: ISSMenu.Obj) -> void:
	if o.w(T) < 0x80:
		_rows(0x28, 0x38, 2)
	o.add_w(T, 1)
	if o.w(T) == 0xC0:
		o.update = screen_credits_60


func screen_credits_60(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_61
	_p(1).set_w(X, 0x120)
	_p(1).set_w(Y, 0xC0)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x30)
	_p(1).set_w(HEADING, 0x30)
	_p(1).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_61(o)


func screen_credits_61(o: ISSMenu.Obj) -> void:
	if o.w(T) < 0x80:
		_rows(0x48, 0x58, -2)
	o.add_w(T, 1)
	if o.w(T) == 0xC0:
		o.update = screen_credits_62


func screen_credits_62(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_63
	_p(1).set_w(X, -0x20)
	_p(1).set_w(Y, 0x100)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x10)
	_p(1).set_w(HEADING, 0x10)
	_p(1).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_63(o)


func screen_credits_63(o: ISSMenu.Obj) -> void:
	if o.w(T) < 0x80:
		_rows(0x68, 0x78, 2)
	o.add_w(T, 1)
	if o.w(T) == 0xC0:
		o.update = screen_credits_64


func screen_credits_64(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_65
	_p(1).set_w(X, 0x120)
	_p(1).set_w(Y, 0x140)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x30)
	_p(1).set_w(HEADING, 0x30)
	_p(1).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_65(o)


func screen_credits_65(o: ISSMenu.Obj) -> void:
	if o.w(T) < 0x80:
		_rows(0x88, 0x98, -2)
	o.add_w(T, 1)
	if o.w(T) == 0xC0:
		o.update = screen_credits_66


func screen_credits_66(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_67
	_p(1).set_w(X, -0x20)
	_p(1).set_w(Y, 0x180)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x10)
	_p(1).set_w(HEADING, 0x10)
	_p(1).update = objects.player_start_run_005D5C
	_p(2).set_w(X, 0x120)
	_p(2).set_w(Y, 0x180)
	_p(2).set_w(INPUT, 0xF)
	_p(2).set_w(FACING, 0x30)
	_p(2).set_w(HEADING, 0x30)
	_p(2).update = objects.player_start_run_005D5C
	_p(3).set_w(X, 0x186)
	_p(3).set_w(Y, 0x180)
	_p(3).set_w(INPUT, 0xF)
	_p(3).set_w(FACING, 0x30)
	_p(3).set_w(HEADING, 0x30)
	_p(3).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_67(o)


func screen_credits_67(o: ISSMenu.Obj) -> void:
	if o.w(T) == 0x40:
		_p(2).update = objects.player_start_sit_after_a_slide_008F16
		_p(1).update = objects.player_start_leap_0098F2
	if o.w(T) == 0x60:
		_p(3).update = objects.player_start_sit_after_a_slide_008F16
	if o.w(T) == 0x68:
		ISSRam.set_l(S.g_foul_victim, 0xFFFFFFFF)
		_p(1).update = objects.player_knocked_over
	if o.w(T) < 0x80:
		_rows(0xA8, 0xB8, 2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_68


func screen_credits_68(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_69
	o.set_w(T, 0)
	screen_credits_69(o)


func screen_credits_69(o: ISSMenu.Obj) -> void:
	_rows(0x28, 0x38, 2)
	_rows(0x48, 0x58, -2)
	_rows(0x68, 0x78, 2)
	_rows(0x88, 0x98, -2)
	_rows(0xA8, 0xB8, 2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_70


func screen_credits_70(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_71
	screen_credits_104(rom("screen_credits_70_data"))
	o.set_w(T, 0)
	screen_credits_71(o)


func screen_credits_71(o: ISSMenu.Obj) -> void:
	_rows(0x48, 0x58, -2)
	_rows(0x68, 0x78, 2)
	_rows(0x88, 0x98, -2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_72


func screen_credits_72(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_73
	o.set_w(T, 0)
	screen_credits_73(o)


func screen_credits_73(o: ISSMenu.Obj) -> void:
	o.add_w(T, 1)
	if o.w(T) == 0xA0:
		o.update = screen_credits_74


func screen_credits_74(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_75
	o.set_w(T, 0)
	screen_credits_75(o)


func screen_credits_75(o: ISSMenu.Obj) -> void:
	_rows(0x48, 0x58, -2)
	_rows(0x68, 0x78, 2)
	_rows(0x88, 0x98, -2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_76


func screen_credits_76(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_77
	_p(0).set_w(X, 0xD8)
	_p(0).set_w(Y, 0x280)
	_p(0).set_w(INPUT, 0)
	_p(0).set_w(FACING, 0x30)
	_p(0).set_w(HEADING, 0x30)
	_p(0).update = objects.keeper_hold_catch
	ISSRam.set_l(S.g_ball + OWNER, _p(0).ptr())
	ISSRam.set_b(S.g_ball + STATE, 0x2)
	_p(1).set_w(X, 0x28)
	_p(1).set_w(Y, 0x0)
	_p(1).set_w(INPUT, 0)
	_p(1).set_w(FACING, 0x10)
	_p(1).set_w(HEADING, 0x10)
	_p(1).update = objects.player_update
	ISSRam.set_w(S.g_left_goal_team, 0x1)
	o.set_w(T, 0)
	screen_credits_77(o)


func screen_credits_77(o: ISSMenu.Obj) -> void:
	if o.w(T) < 0xA0:
		objects.ball.add_w(Y, -2)
		_p(0).add_w(Y, -2)
		_p(1).add_w(Y, 2)
	if o.w(T) == 0xA0:
		_p(0).update = objects.keeper_punt
	if o.w(T) == 0x100:
		_p(0).update = objects.keeper_punt_run
	if o.w(T) == 0x120:
		_p(1).update = objects.player_start_walk_arms_out_009B1A
	o.add_w(T, 1)
	if o.w(T) == 0x140:
		_p(0).update = objects.keeper_start_get_up_0049F2
		o.update = screen_credits_78


func screen_credits_78(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_79
	screen_credits_104(rom("screen_credits_78_data"))
	o.set_w(T, 0)
	screen_credits_79(o)


func screen_credits_79(o: ISSMenu.Obj) -> void:
	_rows(0x50, 0x70, -2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_80


func screen_credits_80(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_81
	o.set_w(T, 0)
	screen_credits_81(o)


func screen_credits_81(o: ISSMenu.Obj) -> void:
	o.add_w(T, 1)
	if o.w(T) == 0xA0:
		o.update = screen_credits_82


func screen_credits_82(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_83
	o.set_w(T, 0)
	screen_credits_83(o)


func screen_credits_83(o: ISSMenu.Obj) -> void:
	if o.w(T) < 0x80:
		_rows(0x50, 0x70, -2)
	objects.ball.add_w(Y, -2)
	_p(0).add_w(Y, -2)
	_p(1).add_w(Y, 2)
	o.add_w(T, 1)
	if o.w(T) == 0xC0:
		ISSRam.set_l(S.g_ball + OWNER, 0xFF0000 | S.g_director)
		ISSRam.set_b(S.g_ball + STATE, 0x2)
		ISSRam.set_l(S.g_ball + SPEED, 0)
		ISSRam.set_l(S.g_ball + VEL_Z, 0)
		ISSRam.set_w(S.g_ball + Z, 0)
		o.update = screen_credits_84


func screen_credits_84(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_85
	screen_credits_104(rom("screen_credits_84_data"))
	_p(1).set_w(X, 0xC0)
	_p(1).set_w(Y, 0x0)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x28)
	_p(1).set_w(HEADING, 0x28)
	_p(1).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	screen_credits_85(o)


func screen_credits_85(o: ISSMenu.Obj) -> void:
	_rows(0x40, 0x98, 2)
	_p(1).add_w(Y, 2)
	_p(1).set_l(SPEED, 0)
	_p(1).set_l(VEL_X, 0)
	_p(1).set_l(VEL_Y, 0)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_86


func screen_credits_86(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_87
	_p(1).update = objects.player_start_jump_009594
	o.set_w(T, 0)
	screen_credits_87(o)


func screen_credits_87(o: ISSMenu.Obj) -> void:
	_p(1).set_l(SPEED, 0)
	_p(1).set_l(VEL_X, 0)
	_p(1).set_l(VEL_Y, 0)
	o.add_w(T, 1)
	if o.w(T) == 0xA0:
		o.update = screen_credits_88


func screen_credits_88(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_89
	o.set_w(T, 0)
	screen_credits_89(o)


func screen_credits_89(o: ISSMenu.Obj) -> void:
	_rows(0x40, 0x98, -2)
	_p(1).add_w(Y, 2)
	_p(1).set_l(SPEED, 0)
	_p(1).set_l(VEL_X, 0)
	_p(1).set_l(VEL_Y, 0)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_90


func screen_credits_90(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_91
	screen_credits_104(rom("screen_credits_90_data"))
	_p(1).set_w(X, 0x40)
	_p(1).set_w(Y, 0x200)
	_p(1).set_w(INPUT, 0x20)
	_p(1).set_w(FACING, 0x30)
	_p(1).set_w(HEADING, 0x30)
	_p(1).update = objects.player_stop_ball
	_p(1).set_w(BALL_DIST, 0)
	ISSRam.set_l(S.g_ball + OWNER, _p(1).ptr())
	ISSRam.set_b(S.g_ball + STATE, 0x1)
	ISSRam.set_w(S.g_ball + X, _p(1).w(X))
	ISSRam.set_w(S.g_ball + Y, _p(1).w(Y))
	_p(1).set_w(Z, 0)
	o.set_w(T, 0)
	screen_credits_91(o)


func screen_credits_91(o: ISSMenu.Obj) -> void:
	_rows(0x40, 0x98, -2)
	_p(1).add_w(Y, -2)
	_p(1).set_l(SPEED, 0)
	objects.ball.add_w(Y, -2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_92


func screen_credits_92(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_93
	o.set_w(T, 0)
	screen_credits_93(o)


func screen_credits_93(o: ISSMenu.Obj) -> void:
	o.add_w(T, 1)
	if o.w(T) == 0xA0:
		o.update = screen_credits_94


func screen_credits_94(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_95
	o.set_w(T, 0)
	screen_credits_95(o)


func screen_credits_95(o: ISSMenu.Obj) -> void:
	_rows(0x40, 0x98, 2)
	_p(1).add_w(Y, -2)
	_p(1).set_l(SPEED, 0)
	objects.ball.add_w(Y, -2)
	o.add_w(T, 1)
	if o.w(T) == 0x90:
		_p(1).set_w(BALL_DIST, 0x7FFF)
		ISSRam.set_b(S.g_ball + STATE, 0x2)
		ISSRam.set_l(S.g_ball + OWNER, 0xFF0000 | S.g_director)
		ISSRam.set_l(S.g_ball + SPEED, 0)
		ISSRam.set_l(S.g_ball + VEL_Z, 0)
		ISSRam.set_w(S.g_ball + Z, 0)
		o.update = screen_credits_96


func screen_credits_96(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_97
	_p(1).set_w(X, 0x10)
	_p(1).set_w(Y, 0x0)
	_p(1).set_w(INPUT, 0xF)
	_p(1).set_w(FACING, 0x20)
	_p(1).set_w(HEADING, 0x20)
	_p(1).set_l(SPEED, 0)
	_p(1).update = objects.player_start_run_005D5C
	_p(2).set_w(X, 0xC2)
	_p(2).set_w(Y, 0x0)
	_p(2).set_w(INPUT, 0xF)
	_p(2).set_w(FACING, 0x20)
	_p(2).set_w(HEADING, 0x20)
	_p(2).set_l(SPEED, 0)
	_p(2).update = objects.player_start_run_005D5C
	_p(3).set_w(X, 0x102)
	_p(3).set_w(Y, 0x84)
	_p(3).set_w(INPUT, 0xF)
	_p(3).set_w(FACING, 0x30)
	_p(3).set_w(HEADING, 0x30)
	_p(3).set_l(SPEED, 0)
	_p(3).update = objects.player_start_run_005D5C
	_p(4).set_w(X, 0xA8)
	_p(4).set_w(Y, 0x1FE)
	_p(4).set_w(INPUT, 0xF)
	_p(4).set_w(FACING, 0x0)
	_p(4).set_w(HEADING, 0x0)
	_p(4).set_l(SPEED, 0)
	_p(4).update = objects.player_start_run_005D5C
	_p(5).set_w(X, -0x10)
	_p(5).set_w(Y, 0x168)
	_p(5).set_w(INPUT, 0xF)
	_p(5).set_w(FACING, 0x10)
	_p(5).set_w(HEADING, 0x10)
	_p(5).set_l(SPEED, 0)
	_p(5).update = objects.player_start_run_005D5C
	o.set_w(T, 0)
	o.set_w(ANIM_FRAME, 0)
	screen_credits_97(o)


## The five run a figure (screen_credits_97_data: frame, player, heading,
## d-pad), all ending facing the camera.
func screen_credits_97(o: ISSMenu.Obj) -> void:
	o.add_w(T, 1)
	var a := rom("screen_credits_97_data")
	while true:
		if o.w(T) == ISSRom.u16(a):
			var p := _p(ISSRom.u16(a + 2))
			p.set_w(HEADING, ISSRom.u16(a + 4))
			p.set_w(INPUT, ISSRom.u16(a + 6))
		a += 8
		if ISSRom.s16(a) < 0:
			break
	if o.w(T) == 0x286:
		o.update = screen_credits_98


func screen_credits_98(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_99
	objects.referee.set_w(X, 0x110)
	objects.referee.set_w(Y, 0xE0)
	objects.referee.set_w(INPUT, 0xF)
	objects.referee.set_w(FACING, 0x30)
	objects.referee.set_w(HEADING, 0x30)
	objects.referee.update = objects.sys_state_001670
	o.set_w(T, 0)
	screen_credits_99(o)


## The referee stops facing the camera, signals a free kick (the five
## stand still) and the kick-off; the five pump their fists one by one.
func screen_credits_99(o: ISSMenu.Obj) -> void:
	o.add_w(T, 1)
	if o.w(T) == 0x28:
		objects.referee.set_w(INPUT, 0)
		objects.referee.set_w(HEADING, 0x20)
	if o.w(T) == 0x60:
		objects.referee.update = objects.sys_state_001988
		ISSRam.set_w(S.g_restart_type, 0x2)
		ISSRam.set_w(S.g_restart_team, 0)
		ISSRam.set_w(S.g_left_goal_team, 0x1)
		ISSRam.set_w(S.g_pitch_middle_y, 0x100)
		for k in range(1, 6):
			_p(k).update = objects.player_start_stand_still_009352
	if o.w(T) == 0xC0:
		objects.referee.update = objects.sys_state_001988
		ISSRam.set_w(S.g_restart_type, 0x0)
		ISSRam.set_w(S.g_restart_team, 0)
		ISSRam.set_w(S.g_left_goal_team, 0x1)
		ISSRam.set_w(S.g_pitch_middle_y, 0x100)
	if o.w(T) > 0xC4:
		_p(o.w(T) - 0xC4).update = objects.player_start_fist_pump_00943E
	if o.w(T) == 0xC9:
		o.update = screen_credits_100


## The last page with the level played (menu_data_058BBA).
func screen_credits_100(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_101
	screen_credits_104(rom("screen_credits_100_data"))
	m.text_draw_large(0x78, 0x50, rom("menu_data_058BBA") + w(S.g_game_level) * 2)
	o.set_w(T, 0)
	screen_credits_101(o)


func screen_credits_101(o: ISSMenu.Obj) -> void:
	_rows(0x10, 0x20, 2)
	_rows(0x28, 0x60, -2)
	_rows(0x70, 0x98, 2)
	_rows(0xA8, 0xB8, -2)
	_rows(0xC0, 0xC8, 2)
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_102


func screen_credits_102(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_103
	o.set_w(T, 0)
	screen_credits_103(o)


## Below the top level the message to try a harder one blinks; Start goes
## back to the start of the game.
func screen_credits_103(_o: ISSMenu.Obj) -> void:
	if w(S.g_game_level) < 4:
		_blink(rom("menu_data_058B40"))
	_start_over()


# --------------------------------------------------------------------------
# The World Series' and the championship's ending.

## The credits scroll up plane B a pixel a frame to $1400 (the players
## moving with it); the row about to come in is drawn from
## screen_credits_107_data (a list of lines per 32 rows), the one gone out
## cleared.
func screen_credits_106(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_107
	screen_credits_107(o)


func screen_credits_107(_o: ISSMenu.Obj) -> void:
	if w(S.g_plane_b_vscroll) != 0x1400:
		add_w(S.g_plane_b_vscroll, 1)
		for k in 11:
			_p(k).add_w(Y, 2)
	var vs := w(S.g_plane_b_vscroll)
	var y0 := (vs + 0xF8) & 0xF8
	m.rect_fill(0x10, 0xF0, y0, y0 + 8, tiles())
	var row := (vs >> 3) + 0x1C
	var r := row & 0x1F
	var a := ISSRom.u32(rom("screen_credits_107_data") + (row >> 5) * 4)
	var kind := ISSRom.u8(a)
	a += 1
	while kind < 0x80:
		var x := ISSRom.u8(a)
		if ISSRom.u8(a + 1) == r:
			_text(kind, x * 8, r * 8, a + 2)
			return
		a += 2
		while ISSRom.u8(a) < 0x80:
			a += 1
		kind = ISSRom.u8(a + 1)
		a += 2


## The team photo: the stadium picture (the map at $1782) four times
## across plane A, eight players lined up in front (screen_credits_108_data:
## x, y and what they do), all coming in from the right with plane A.
func screen_credits_108(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_109
	var src := l(0x1782) & 0xFFFF
	var dst := (l(0x1786) & 0xFFFF) + 0x280
	for r in 0x12:
		for c in 0x10:
			var v := ISSRam.w(src)
			for k in 4:
				ISSRam.set_w(dst + k * 0x20, v)
			src += 2
			dst += 2
		src += 4
		dst += 0x60
	m.vram_dma(0x2000, l(0x1786), 0xE00)
	var t := rom("screen_credits_108_data")
	for k in 8:
		var p := _p(k + 1)
		p.set_w(X, ISSRom.u16(t))
		p.set_w(Y, ISSRom.u16(t + 2))
		p.set_w(FACING, 0x20)
		p.set_w(HEADING, 0x20)
		p.update = _routine(ISSRom.u32(t + 4))
		t += 8
	set_w(S.g_plane_a_hscroll, 0xFF00)
	screen_credits_109(o)


## The routines the photo's table names.
func _routine(a: int) -> Callable:
	match a:
		0x51B4:
			return objects.keeper_start_stand_0051B4
		0x9484:
			return objects.player_start_knee_slide_009484
		0x9506:
			return objects.player_start_arm_up_009506
		0x943E:
			return objects.player_start_fist_pump_00943E
	return objects.player_update


func screen_credits_109(o: ISSMenu.Obj) -> void:
	if sw(S.g_plane_a_hscroll) < 0:
		add_w(S.g_plane_a_hscroll, 1)
		for k in 8:
			_p(k + 1).add_w(X, -1)
	else:
		o.update = screen_credits_110


func screen_credits_110(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_111
	o.set_w(T, 0)
	screen_credits_111(o)


func screen_credits_111(o: ISSMenu.Obj) -> void:
	o.add_w(T, 1)
	if o.w(T) == 0x80:
		o.update = screen_credits_112


## The flash: the players freeze as in a photo, the first picture's frame
## drawn, the music changes.
func screen_credits_112(o: ISSMenu.Obj) -> void:
	o.update = screen_credits_113
	m.fade_white_start()
	o.set_w(T, 0)
	screen_credits_113(o)


func screen_credits_113(o: ISSMenu.Obj) -> void:
	o.add_w(T, 1)
	if o.w(T) == 0x18:
		set_w(S.g_plane_a_hscroll, 0xFF00)
		menu_func_059040()
		set_w(S.g_plane_a_hscroll, 0)
		for k in 8:
			_p(k + 1).update = Callable()
		m.menu_music(7)
	if o.w(T) == 0x80:
		o.update = menu_state_058E82


## Plane A scrolls left half a pixel a frame through the pictures (a new
## frame drawn every 256 pixels by menu_func_059040, the frozen players
## going with it), with the sprite sets of menu_state_058E82_1_data; at
## $900 the level and the closing message.
func menu_state_058E82(o: ISSMenu.Obj) -> void:
	o.update = menu_state_058E82_1
	menu_func_059040()
	menu_state_058E82_1(o)


func menu_state_058E82_1(o: ISSMenu.Obj) -> void:
	if w(S.g_plane_a_hscroll) == 0x900:
		o.update = menu_state_058E82_2
	else:
		set_l(S.g_plane_a_hscroll, l(S.g_plane_a_hscroll) + 0x8000)
		for k in 8:
			_p(k + 1).add_l(X, -0x8000)
		if l(S.g_plane_a_hscroll) == 0x08000000:
			for k in 8:
				_p(k + 1).add_w(X, 0x900)
		if l(S.g_plane_a_hscroll) & 0xFFFFFF == 0:
			o.update = menu_state_058E82
	var a := rom("menu_state_058E82_1_data") + (w(S.g_plane_a_hscroll) >> 8) * 10
	for i in 2:
		var var_addr := ISSRom.s16(a)
		if var_addr >= 0:
			var tile := w(var_addr) >> 5
			var s := ISSRom.u32(a + 2)
			for j in ISSRom.u16(s) + 1:
				var e := s + 2 + j * 8
				var x := (ISSRom.u16(e + 6) + ISSRom.u16(a + 6) - w(S.g_plane_a_hscroll)) & 0x1FF
				m.sprite(ISSRom.u16(e) + ISSRom.u16(a + 8), ISSRom.u16(e + 2) & 0xFF,
					tile + ISSRom.u16(e + 4), 1 if x == 0 else x)
		a += 10


func menu_state_058E82_2(o: ISSMenu.Obj) -> void:
	o.update = menu_state_058E82_3
	m.text_draw_large(0x78, 0x50, rom("menu_data_058BBA") + w(S.g_game_level) * 2)
	menu_state_058E82_3(o)


## The closing message: lost the championship, the second series won by
## another team, or (below the top level) try a harder one.
func menu_state_058E82_3(_o: ISSMenu.Obj) -> void:
	var me := w(0x127C)
	if me != w(0x127E):
		_blink(rom("menu_state_058E82_3_data"))
	elif me != w(0x1280):
		_blink(rom("menu_state_058E82_3_data2"))
	elif w(S.g_game_level) < 4:
		_blink(rom("menu_data_058B40"))
	_start_over()


## menu_func_059040: the next picture's frame on plane A: the half of the
## map ahead of the scroll filled with the backdrop's tile, then a picture
## (menu_func_059040_data: its map at $177A / $177E / $1782, the part of it
## and the cells it goes to) inside a border ($33F on).
func menu_func_059040() -> void:
	var d2 := ((w(S.g_stadium_vram) >> 5) | 0x4000) & 0xFFFF
	var hs := w(S.g_plane_a_hscroll)
	var a1 := (l(0x1786) & 0xFFFF) + ((((hs + 0x100) & 0x100) >> 2))
	for r in 0x1C:
		for c in 0x20:
			ISSRam.set_w(a1, d2)
			a1 += 2
		a1 += 0x40
	d2 += 0x33F
	var e := rom("menu_func_059040_data") + (((hs + 0x100) & 0xFFFF) >> 8) * 14
	var x0 := ISSRom.u16(e + 6)
	var x1 := ISSRom.u16(e + 8)
	var y0 := ISSRom.u16(e + 0xA)
	var y1 := ISSRom.u16(e + 0xC)
	var n := x1 - x0
	var skip_to := (0x3E - n) * 2
	var skip_from := (0x12 - n) * 2
	a1 = (l(0x1786) & 0xFFFF) + (x0 - 1) * 2 + (y0 - 1) * 0x80
	var a0 := (l(ISSRom.u16(e)) & 0xFFFF) + ISSRom.u16(e + 2) * 2 + ISSRom.u16(e + 4) * 0x24
	a1 = _frame_row(a1, d2, d2 + 1, d2 + 0x800, n)
	a1 += skip_to
	a0 += skip_from
	for r in y1 - y0:
		ISSRam.set_w(a1, (d2 + 2) & 0xFFFF)
		a1 += 2
		for i in n:
			ISSRam.set_w(a1, ISSRam.w(a0))
			a0 += 2
			a1 += 2
		ISSRam.set_w(a1, (d2 + 0x802) & 0xFFFF)
		a1 += 2 + skip_to
		a0 += skip_from
	_frame_row(a1, d2 + 0x1000, d2 + 0x1001, d2 + 0x1800, n)
	m.vram_dma(0x2000, l(0x1786), 0xE00)


## A border row of a picture's frame: the left corner, n edge cells, the
## right corner; the address after it.
func _frame_row(a: int, left: int, edge: int, right: int, n: int) -> int:
	ISSRam.set_w(a, left & 0xFFFF)
	a += 2
	for i in n:
		ISSRam.set_w(a, edge & 0xFFFF)
		a += 2
	ISSRam.set_w(a, right & 0xFFFF)
	return a + 2
