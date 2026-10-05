class_name ISSScreensPK
extends ISSScreens
## PK order (screen $1A): the side's outfield players (1-10); C gives the
## one under the cursor the next place in the order (his place number in
## the column beside him) and moves on to the next player not yet taken; B
## takes the last back (or, with none taken in PK mode, goes back to the
## stadium). Five takers, then OK; in sudden death (g_shootout_kicks >= 5)
## or during a match ($1638) one kicker is chosen ("the kicker."). The
## order is $14FE (home) / $1512 (away) after the $14FA / $14FC already
## taken. $1768 is the side choosing.
##
## RAM: $1776 the player under the cursor, $177E the takers chosen now,
## $177A / $177C the list's marks and faces, $1778 the bar tiles, $1780 the
## move sound.

const ORDER := [0x14FE, 0x1512]
const TAKEN := [0x14FA, 0x14FC]


func register(h: Dictionary) -> void:
	h[0x1A] = screen_pk_order


func _side() -> int:
	return w(0x1768)


func _p(k: int) -> int:
	return player(_side(), k)


func _y(k: int) -> int:
	return k * 16 + 0x20


func _order() -> int:
	return ORDER[_side()]


func _taken() -> int:
	return w(TAKEN[_side()])


func _sfx() -> void:
	m.play_sfx(w(0x1780))


## Player k is already in the order (the takers so far and those chosen
## now).
func _in_order(k: int) -> bool:
	for i in _taken() + w(0x177E):
		if w(_order() + 2 * i) == k:
			return true
	return false


func screen_pk_order() -> void:
	# The shoot-out's song (25) unless it plays already; the crowd's
	# effect 102 once.
	if w(S.g_sound_disabled) == 3:
		set_w(0x1780, 0x4D)
	else:
		set_w(0x1780, 0x7B)
		if sw(S.g_sound_disabled) >= 0:
			if w(S.g_sound_disabled) != 0x19:
				m.play_music(0x19)
				set_w(S.g_sound_disabled, 0x19)
		else:
			m.play_music(0x19)
			set_w(S.g_sound_disabled, 0x19)
		if w(0x17D8) != 1:
			m.play_sfx(102)
			set_w(0x17D8, 1)
	var side := _side()
	side_icon(side, 0x28, 0x38, 8, 0x18)
	var team := w(S.g_team_home if side == 0 else S.g_team_away)
	var buf := l(S.g_unpack_buffer)
	m.unpack(6, 2, buf)
	m.vram_dma(w(S.g_stadium_vram) + 0x6400, buf + team * 0xC0, 0xC0)
	m.unpack(6, 1, buf)
	m.vram_dma(w(S.g_stadium_vram) + 0x64C0, buf + team * 0x200, 0x200)
	set_l(0x1770, buf)
	set_l(S.g_unpack_buffer, m.unpack(4, 35, buf))
	set_w(0x1778, m.load_tiles(4, 32))
	for k in range(1, 11):
		m.text_draw_field(0xA8, 0xE8, _y(k), player_name(side, _p(k)))
	if side != 0:
		for i in 5:
			set_w(0x7C6 + 2 * i, ISSRom.u16(rom("tbl_away_side_colours") + 2 * i))
		set_w(0x1548, 1)
	if w(0x1638) != 0 or w(S.g_shootout_kicks) >= 5:
		m.text_draw_small(0x20, 0x40, rom("str_pk_kicker"))
		m.rect_fill(0xD0, 0xF8, 0x10, 0x18, tiles())
	set_w(0x177E, 0)
	# The cursor on the first player not yet in the order.
	var k := 1
	while _in_order(k):
		k += 1
	set_w(0x1776, k)
	set_w(0x177A, 0)
	set_w(0x177C, 0)
	menu_state_04FD86(spawn(Callable()))
	menu_state_04FFE0(spawn(Callable()))


# --------------------------------------------------------------------------
# The list's marks and faces (Y / Z / A as on the other lists), the bars.

func menu_state_04FD86(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04FD86_1
	for k in range(1, 11):
		var p := _p(k)
		var t: int
		if w(0x177A) == 0:
			t = tiles() + 0x242
			t += 0xA if ISSRam.b(p + 0x55) != 0 else (ISSRam.b(p + 0x51) & 0x7F) * 2
		else:
			t = tiles() + (0x1F2 if _side() == 0 else 0x21A) + (ISSRam.b(p + 0x63) - 1) * 2
		m.rect_fill_tiles(0x90, 0x98, _y(k), _y(k) + 16, t)
		var st := player_status(_side(), p)
		if w(0x177C) == 0 and st != 4:
			m.face_draw(0x98, _y(k), ISSRam.b(p + 0x57))
		else:
			m.rect_fill_tiles(0x98, 0xA8, _y(k), _y(k) + 16, tiles() + 0x26F + st * 4)
	menu_state_04FD86_1(o)


func menu_state_04FD86_1(o: ISSMenu.Obj) -> void:
	var p := w(S.g_pad_pressed_home)
	if p & 0x200:
		set_w(0x177A, w(0x177A) ^ 1)
		o.update = menu_state_04FD86
	if p & 0x100:
		set_w(0x177C, w(0x177C) ^ 1)
		o.update = menu_state_04FD86
	if p & PAD_A:
		if w(0x177A) == 0:
			set_w(0x177A, 1)
		else:
			set_w(0x177A, 0)
			set_w(0x177C, w(0x177C) ^ 1)
		o.update = menu_state_04FD86
	m.anim_tiles()
	for k in range(1, 11):
		var t := (w(0x1778) >> 5) + ISSRam.b(_p(k) + 0x65) * 8
		var x := 0x128 - sw(S.g_plane_b_hscroll)
		var y := k * 16 + 0xA0 - sw(S.g_plane_b_vscroll)
		m.sprite(y, 0x0D, t | 0x4000, x)
		m.sprite(y, 0x0D, t | 0x4800, x + 0x20)
	m.boxes_draw_sprites(rom("menu_state_04FD86_1_data"))


# --------------------------------------------------------------------------
# Choosing.

func menu_state_04FFE0(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04FFE0_1
	o.set_w(T, 0)
	var p := _p(w(0x1776))
	for i in 9:
		m.bar_draw(0x58, i * 8 + 0x80, 0, ISSRam.b(p + 0x5A + i))
	# Clear his place number (taken back with B).
	m.rect_fill(0x88, 0x90, _y(w(0x1776)), _y(w(0x1776)) + 16, tiles())
	menu_state_04FFE0_1(o)


## The next player down (or up) not yet in the order, wrapping 10 -> 1.
func _next(step: int) -> int:
	var k := w(0x1776)
	while true:
		k += step
		if k > 10:
			k = 1
		elif k < 1:
			k = 10
		if not _in_order(k):
			return k
	return k


func menu_state_04FFE0_1(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_B):
		if w(0x177E) == 0:
			if w(S.g_game_mode) == 2 and w(S.g_shootout_kicks) < 5:
				set_l(S.g_next_state, ISSMenu.STATE_MENU)
				set_w(S.g_next_screen, 4)
				m.fade_out_start()
		else:
			add_w(0x177E, -1)
			set_w(0x1776, w(_order() + 2 * (_taken() + w(0x177E))))
			o.update = menu_state_04FFE0
	var next := false
	if pressed_home(PAD_C):
		var p := _p(w(0x1776))
		if ISSRam.b(p + 0x55) != 0:
			m.play_sfx(94)
		else:
			set_w(_order() + 2 * (_taken() + w(0x177E)), w(0x1776))
			# His place in the order: the other side's number tiles.
			var t := tiles() + (0x21A if _side() == 0 else 0x1F2) + w(0x177E) * 2
			m.rect_fill_tiles(0x88, 0x90, _y(w(0x1776)), _y(w(0x1776)) + 16, t)
			m.play_sfx(95)
			add_w(0x177E, 1)
			if w(0x1638) != 0 or w(S.g_shootout_kicks) >= 5 or w(0x177E) == 5:
				o.update = menu_state_04FFE0_2
				return
			# On to the next player, as down does (up is not looked at).
			next = true
	if not next and pressed_home(PAD_UP):
		set_w(0x1776, _next(-1))
		o.update = menu_state_04FFE0
		_sfx()
	if next or pressed_home(PAD_DOWN):
		set_w(0x1776, _next(1))
		o.update = menu_state_04FFE0
		_sfx()
	o.add_w(T, 1)
	m.cursor_draw_large(_side(), 0xA8, 0xE8, _y(w(0x1776)))


## OK: the shoot-out starts (or, in PK mode with two sides of pads, the
## other side chooses); B takes the last taker back.
func menu_state_04FFE0_2(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04FFE0_3
	menu_state_04FFE0_3(o)


func menu_state_04FFE0_3(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_C):
		if w(0x1638) != 0:
			set_l(S.g_next_state, ISSMenu.STATE_SHOOTOUT)
			m.fade_out_start()
			m.play_sfx(95)
			return
		if _side() == 0 and w(S.g_pads_away) != 0:
			set_w(0x176A, 1)
			set_w(S.g_next_screen, 0x1A)
			set_l(S.g_next_state, ISSMenu.STATE_MENU)
			m.fade_out_start()
			m.play_sfx(95)
			return
		set_w(S.g_restart_team, 0)
		set_l(S.g_next_state, ISSMenu.STATE_SHOOTOUT)
		m.fade_out_start()
		m.play_sfx(95)
		return
	if pressed_home(PAD_B):
		add_w(0x177E, -1)
		o.update = menu_state_04FFE0
	o.add_w(T, 1)
	m.cursor_draw(_side(), 0xD8, 0xE8, 0xD0)
