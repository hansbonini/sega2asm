class_name ISSScreensSquad
extends ISSScreens
## Select squad (screen 8): the side's eleven (plane B scrolled right by
## $60) and its bench, the mini pitch with their numbers, each player's
## position or shirt number, energy face or status, and the attributes of
## the player under the cursor. C picks a player and C again swaps him with
## another (a substitution during a match, counted by $1836 / $18BE, the
## goalkeeper's by $1838 / $18C0); the marks above choose the captain
## ($1896 / $191E) and the penalty taker ($189A / $1922), reset the order
## or leave. $1768 is the side being set.

const OFF := 0x55
const INDEX := 0x56
const ENERGY := 0x57
const NUMBER := 0x63
const POSITION := 0x65
const KEEPER := 3


func register(h: Dictionary) -> void:
	h[0x08] = screen_select_squad


func _side() -> int:
	return w(0x1768)


func _player(k: int) -> int:
	return m.team_players(_side()) + k * ISSModes.PLAYER_SIZE


func _status_base() -> int:
	return S.g_player_status + w(0x1642 if _side() == 0 else 0x1644) * 20


func _status(p: int) -> int:
	return ISSRam.b(_status_base() + ISSRam.b(p + INDEX)) & 7


func _name(p: int) -> int:
	var team := w(S.g_team_home if _side() == 0 else S.g_team_away)
	return ISSRom.u32(rom("tbl_player_names") + team * 4) + ISSRam.b(p + INDEX) * 8


## The row of player k: the eleven at ($118-$158, $28 + 16k), the bench
## at ($20-$60, $48 + 16(k - 11)).
func _row(k: int) -> Array:
	if k < 11:
		return [0x118, 0x158, k * 16 + 0x28]
	return [0x20, 0x60, (k - 11) * 16 + 0x48]


func screen_select_squad() -> void:
	set_w(0x1784, 0x7B if w(S.g_sound_disabled) == 0x19 else 0x4D)
	set_w(S.g_plane_b_hscroll, 0x60)
	var side := _side()
	if side != w(S.g_left_goal_team):
		m.rect_mirror(0x88, 0xD8, 0x18, 0x78)
	var team := w(S.g_team_home if side == 0 else S.g_team_away)
	var buf := l(S.g_unpack_buffer)
	m.unpack(6, 2, buf)
	m.vram_dma(w(S.g_stadium_vram) + 0x66A0, buf + team * 0xC0, 0xC0)
	m.unpack(6, 1, buf)
	m.vram_dma(w(S.g_stadium_vram) + 0x6760, buf + team * 0x200, 0x200)
	side_icon(side, 0x70, 0x80, 8, 0x18)
	set_l(0x1770, buf)
	set_l(S.g_unpack_buffer, m.unpack(4, 35, buf))
	set_w(0x177C, m.load_tiles(4, 32))
	set_w(0x1774, m.load_tiles(4, 33))
	if side != 0:
		for i in 5:
			set_w(0x7C6 + 2 * i, ISSRom.u16(rom("tbl_away_side_colours") + 2 * i))
		set_w(0x1548, 1)
	menu_text_042824()
	menu_func_0428B0()
	menu_text_04297E()
	m.pitch_place(0x70, 0x18, side)
	if w(0x1638) == 0:
		# Outside a match the substitutions left are not shown.
		m.rect_fill(0, 0x68, 0x18, 0x40, (w(S.g_stadium_vram) >> 5) | 0xC000)
	if side == 0:
		set_w(0x1786, w(0x1838))
		set_w(0x1788, w(0x1836))
	else:
		set_w(0x1786, w(0x18C0))
		set_w(0x1788, w(0x18BE))
	# The order on entry, for RESET.
	buf = l(S.g_unpack_buffer)
	set_l(0x178A, buf)
	for k in 20:
		ISSRam.set_b(buf + k, ISSRam.b(_player(k) + INDEX))
	set_l(S.g_unpack_buffer, buf + 20)
	set_w(0x1776, 0)
	set_w(0x1778, 0)
	set_w(0x177A, 0xFFFF)
	set_w(0x177E, 0)
	set_w(0x1780, 0)
	set_w(0x1782, 0)
	menu_state_04130C(spawn(Callable()))
	screen_squad_player(spawn(Callable()))


## menu_text_042824: the players' names, the eleven then the bench.
func menu_text_042824() -> void:
	for k in 20:
		var r := _row(k)
		m.text_draw_field(r[0], r[1], r[2], _name(_player(k)))


## The captain / penalty taker pointers (player objects 1-10).
func _ptr_index(addr: int) -> int:
	return ((l(addr) & 0xFFFF) - m.team_players(_side())) / ISSModes.PLAYER_SIZE


func _captain() -> int:
	return 0x1896 if _side() == 0 else 0x191E


func _taker() -> int:
	return 0x189A if _side() == 0 else 0x1922


## menu_func_0428B0: the column of marks cleared, then the penalty taker's
## mark and the captain's (another when he is both). menu_state_0425D8 draws
## them the other way round (taker on top).
func menu_func_0428B0(taker_last := false) -> void:
	var base := (w(S.g_stadium_vram) >> 5) | 0xC000
	m.rect_fill(0xF8, 0x100, 0x28, 0xE0, base)
	var both := l(_captain()) == l(_taker())
	var marks := [[_taker(), base + 0x322], [_captain(), base + 0x320 + (4 if both else 0)]]
	if taker_last:
		marks.reverse()
	for mk: Array in marks:
		var y := _ptr_index(mk[0]) * 16 + 0x28
		m.rect_fill_tiles(0xF8, 0x100, y, y + 16, mk[1])


## menu_text_04297E: substitutions left ("3 substitutes" / "1 substitute").
func menu_text_04297E() -> void:
	var n := w(0x1836 if _side() == 0 else 0x18BE)
	m.rect_fill_tiles(0x38, 0x40, 0x20, 0x28, ((w(S.g_stadium_vram) >> 5) | 0xC000) + 0x133 + n)
	m.text_draw_small(0x58, 0x28, rom("menu_text_04297E_data2") if n == 1 else rom("menu_text_04297E_data"))


# --------------------------------------------------------------------------
# The marks and faces (menu_state_04130C): Y shows positions or numbers
# ($177E), Z faces or statuses ($1780), A steps through the combinations.

func _marks(k: int) -> void:
	var p := _player(k)
	var r := _row(k)
	var x := 0x100 if k < 11 else 8
	var base := (w(S.g_stadium_vram) >> 5) | 0xC000
	var t := base + 0x242
	if w(0x177E) == 0:
		if k < 11 and ISSRam.b(p + OFF) != 0:
			t += 0xA
		else:
			t += (ISSRam.b(p + 0x51) & 0x7F) * 2
	else:
		t = base + (0x1F2 if _side() == 0 else 0x21A) + (ISSRam.b(p + NUMBER) - 1) * 2
	m.rect_fill_tiles(x, x + 8, r[2], r[2] + 16, t)
	var st := _status(p)
	if w(0x1780) == 0 and st != 4:
		m.face_draw(x + 8, r[2], ISSRam.b(p + ENERGY))
	else:
		m.rect_fill_tiles(x + 8, x + 0x18, r[2], r[2] + 16, base + 0x26F + st * 4)


func menu_state_04130C(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04130C_1
	for k in 20:
		_marks(k)
	menu_state_04130C_1(o)


func menu_state_04130C_1(o: ISSMenu.Obj) -> void:
	if w(0x1782) != 0:
		set_w(0x1782, 0)
		o.update = menu_state_04130C
	var p := w(S.g_pad_pressed_home)
	if p & 0x200:
		set_w(0x177E, w(0x177E) ^ 1)
		o.update = menu_state_04130C
	if p & 0x100:
		set_w(0x1780, w(0x1780) ^ 1)
		o.update = menu_state_04130C
	if p & PAD_A:
		if w(0x177E) == 0:
			set_w(0x177E, 1)
		else:
			set_w(0x177E, 0)
			set_w(0x1780, w(0x1780) ^ 1)
		o.update = menu_state_04130C
	m.anim_tiles()
	# The bars behind the names, coloured by position (two mirrored 4 x 2
	# sprites each).
	for k in 20:
		var pl := _player(k)
		var t := (w(0x177C) >> 5) + ISSRam.b(pl + POSITION) * 8
		var x := (0x198 if k < 11 else 0xA0) - sw(S.g_plane_b_hscroll)
		var y := (k * 16 + 0xA8 if k < 11 else (k - 11) * 16 + 0xC8) - sw(S.g_plane_b_vscroll)
		m.sprite(y, 0x0D, t | 0x4000, x)
		m.sprite(y, 0x0D, t | 0x4800, x + 0x20)
	o.add_w(T, 1)
	if sw(S.g_plane_b_hscroll) < 0x30:
		m.pad_icon_draw(1, 0xF3, 0x80)
	else:
		m.pad_icon_draw(0, 0x65, 0x80)
	m.pitch_draw(_side())
	if w(0x1638) != 0:
		m.boxes_draw_sprites(rom("menu_state_04130C_1_data"))


# --------------------------------------------------------------------------
# The cursor on the eleven ($1776) or the bench ($1778); $177A = the player
# picked (-1 none).

## The attributes of player k as bars (beside the photo while one is picked).
func _bars(k: int) -> void:
	var a := _player(k) + 0x5A
	var x := 0xD8 if sw(0x177A) < 0 else 0x90
	for i in 9:
		m.bar_draw(x, i * 8 + 0x88, 0, ISSRam.b(a + i))


## C on a second player: swap the two (cursor k against the picked one).
## A goalkeeper only changes places with a goalkeeper; bringing a substitute
## on needs both to be available (status not 4) and, during a match, a
## substitution left. Returns false (SFX 94) when refused.
func _swap(k: int, back: Callable, o: ISSMenu.Obj) -> bool:
	var picked := w(0x177A)
	var a3 := _player(k)
	var a4 := _player(picked)
	var k3 := ISSRam.b(a3 + POSITION) == KEEPER
	var k4 := ISSRam.b(a4 + POSITION) == KEEPER
	if k3 != k4:
		return false
	if (k < 11) != (picked < 11):
		if _status(a4) == 4 or _status(a3) == 4:
			return false
		if w(0x1638) != 0:
			# During a match: a goalkeeper change uses the keeper's
			# substitution, any other one of the three.
			if k4:
				var gk: int = 0x1838 if _side() == 0 else 0x18C0
				if w(gk) == 0:
					return false
				set_w(gk, 0)
			else:
				var subs: int = 0x1836 if _side() == 0 else 0x18BE
				if w(subs) == 0:
					return false
				add_w(subs, -1)
			menu_text_04297E()
	else:
		var t := ISSRam.b(a3 + OFF)
		ISSRam.set_b(a3 + OFF, ISSRam.b(a4 + OFF))
		ISSRam.set_b(a4 + OFF, t)
	var r := _row(k)
	m.text_draw_field(r[0], r[1], r[2], _name(a4))
	r = _row(picked)
	m.text_draw_field(r[0], r[1], r[2], _name(a3))
	for i in 0x10:
		var t := ISSRam.b(a3 + INDEX + i)
		ISSRam.set_b(a3 + INDEX + i, ISSRam.b(a4 + INDEX + i))
		ISSRam.set_b(a4 + INDEX + i, t)
	set_w(0x1782, 1)
	set_w(0x177A, 0xFFFF)
	o.update = back
	m.play_sfx(95)
	return true


## B with a player picked: put him back.
func _unpick(o: ISSMenu.Obj, back: Callable) -> void:
	var r := _row(w(0x177A))
	m.rect_unhighlight(r[0], r[1], r[2], r[2] + 16)
	set_w(0x177A, 0xFFFF)
	o.update = back


func _pick(k: int) -> void:
	set_w(0x177A, k)
	var r := _row(k)
	m.rect_highlight(r[0], r[1], r[2], r[2] + 16)
	m.play_sfx(95)


## The panels (the picked player's and the cursor's) and the cursor.
func _squad_cursor(o: ISSMenu.Obj, k: int) -> void:
	o.add_w(T, 1)
	if sw(0x177A) < 0:
		m.rect_flash(0xB0, 0xF8, 0x78, 0xD8)
		m.rect_unhighlight(0x68, 0xB0, 0x78, 0xD8)
	else:
		m.rect_unhighlight(0xB0, 0xF8, 0x78, 0xD8)
		m.rect_flash(0x68, 0xB0, 0x78, 0xD8)
	var r := _row(k)
	m.cursor_draw_large(_side(), r[0], r[1], r[2])


func screen_squad_player(o: ISSMenu.Obj) -> void:
	o.update = screen_squad_player_1
	o.set_w(T, 0)
	_bars(w(0x1776))
	screen_squad_player_1(o)


func screen_squad_player_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0x60):
		var p := w(S.g_pad_pressed_home)
		if p & PAD_B:
			if sw(0x177A) < 0:
				o.update = menu_state_04172C
			else:
				_unpick(o, screen_squad_player)
		if p & PAD_C:
			if sw(0x177A) < 0:
				_pick(w(0x1776))
			elif not _swap(w(0x1776), screen_squad_player, o):
				m.play_sfx(94)
		if p & PAD_UP:
			if w(0x1776) == 0:
				o.update = menu_state_04172C
			else:
				add_w(0x1776, -1)
				o.update = screen_squad_player
			m.play_sfx(w(0x1784))
		if p & PAD_DOWN:
			if w(0x1776) == 10:
				o.update = menu_state_04172C
			else:
				add_w(0x1776, 1)
				o.update = screen_squad_player
			m.play_sfx(w(0x1784))
		if p & PAD_LEFT:
			o.update = menu_state_042046
			m.play_sfx(w(0x1784))
	_squad_cursor(o, w(0x1776))
	var pl := _player(w(0x1776))
	m.icon_draw_small(0, ISSRam.w(pl + 0x10) - 4, ISSRam.w(pl + 0x14) + 4)


func menu_state_042046(o: ISSMenu.Obj) -> void:
	o.update = menu_state_042046_1
	o.set_w(T, 0)
	_bars(w(0x1778) + 11)
	menu_state_042046_1(o)


func menu_state_042046_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0):
		var p := w(S.g_pad_pressed_home)
		if p & PAD_B:
			if sw(0x177A) < 0:
				o.update = screen_squad_player
			else:
				_unpick(o, menu_state_042046)
		if p & PAD_C:
			if sw(0x177A) < 0:
				_pick(w(0x1778) + 11)
			elif not _swap(w(0x1778) + 11, menu_state_042046, o):
				m.play_sfx(94)
		if p & PAD_DOWN:
			set_w(0x1778, 0 if w(0x1778) == 8 else w(0x1778) + 1)
			o.update = menu_state_042046
			m.play_sfx(w(0x1784))
		if p & PAD_UP:
			set_w(0x1778, 8 if w(0x1778) == 0 else w(0x1778) - 1)
			o.update = menu_state_042046
			m.play_sfx(w(0x1784))
		if p & PAD_RIGHT:
			o.update = screen_squad_player
			m.play_sfx(w(0x1784))
	_squad_cursor(o, w(0x1778) + 11)


# --------------------------------------------------------------------------
# The marks above the eleven, left to right: captain ($108), penalty taker
# ($118), RESET ($128), EXIT ($140). Up / down go back to the eleven.

func _top(o: ISSMenu.Obj, left: Callable, right: Callable, x0: int, x1: int) -> bool:
	if scrolling(0x60):
		_top_cursor(o, x0, x1)
		return false
	var p := w(S.g_pad_pressed_home)
	if p & PAD_LEFT:
		o.update = left
		m.play_sfx(w(0x1784))
	if p & PAD_RIGHT:
		o.update = right
		m.play_sfx(w(0x1784))
	if p & PAD_UP:
		set_w(0x1776, 10)
		o.update = screen_squad_player
		m.play_sfx(w(0x1784))
	if p & PAD_DOWN:
		set_w(0x1776, 0)
		o.update = screen_squad_player
		m.play_sfx(w(0x1784))
	return true


func _top_cursor(o: ISSMenu.Obj, x0: int, x1: int) -> void:
	o.add_w(T, 1)
	m.cursor_draw(_side(), x0, x1, 8)


## EXIT: C leaves for the pre-match menu (or the other side's turn).
func menu_state_04172C(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04172C_1
	menu_state_04172C_1(o)


func menu_state_04172C_1(o: ISSMenu.Obj) -> void:
	if _top(o, menu_state_041844, menu_state_041AEA, 0x140, 0x158):
		if pressed_home(PAD_C):
			ISSModes.prematch_return()
			set_l(S.g_next_state, ISSMenu.STATE_MENU)
			m.fade_out_start()
			m.play_sfx(95)
		_top_cursor(o, 0x140, 0x158)


## RESET: the order on entry back, and the substitutions left.
func menu_state_041844(o: ISSMenu.Obj) -> void:
	o.update = menu_state_041844_1
	menu_state_041844_1(o)


func menu_state_041844_1(o: ISSMenu.Obj) -> void:
	if _top(o, menu_state_0419C8, menu_state_04172C, 0x128, 0x140):
		if pressed_home(PAD_B):
			o.update = menu_state_04172C
			m.play_sfx(w(0x1784))
		if pressed_home(PAD_C):
			if _side() == 0:
				set_w(0x1838, w(0x1786))
				set_w(0x1836, w(0x1788))
			else:
				set_w(0x18C0, w(0x1786))
				set_w(0x18BE, w(0x1788))
			var saved := l(0x178A)
			for k in 20:
				var a4 := _player(k)
				var a1 := a4
				while ISSRam.b(a1 + INDEX) != ISSRam.b(saved + k):
					a1 += ISSModes.PLAYER_SIZE
				for i in 0x11:
					var t := ISSRam.b(a4 + OFF + i)
					ISSRam.set_b(a4 + OFF + i, ISSRam.b(a1 + OFF + i))
					ISSRam.set_b(a1 + OFF + i, t)
			set_w(0x1782, 1)
			menu_text_042824()
			if w(0x1638) != 0:
				menu_text_04297E()
			m.play_sfx(95)
		_top_cursor(o, 0x128, 0x140)


## The penalty taker's mark: C to move it.
func menu_state_0419C8(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0419C8_1
	o.set_w(T, 0)
	menu_state_0419C8_1(o)


func menu_state_0419C8_1(o: ISSMenu.Obj) -> void:
	if _top(o, menu_state_041AEA, menu_state_041844, 0x118, 0x128):
		if pressed_home(PAD_C):
			o.update = menu_state_0425D8
			m.play_sfx(95)
		if pressed_home(PAD_B):
			o.update = menu_state_04172C
		_top_cursor(o, 0x118, 0x128)


## The captain's mark: C to move it.
func menu_state_041AEA(o: ISSMenu.Obj) -> void:
	o.update = menu_state_041AEA_1
	o.set_w(T, 0)
	menu_state_041AEA_1(o)


func menu_state_041AEA_1(o: ISSMenu.Obj) -> void:
	if _top(o, menu_state_04172C, menu_state_0419C8, 0x108, 0x118):
		if pressed_home(PAD_B):
			o.update = menu_state_04172C
		if pressed_home(PAD_C):
			o.update = menu_state_042452
			m.play_sfx(95)
		_top_cursor(o, 0x108, 0x118)


## Moving a mark (captain or penalty taker) up and down players 1-10.
func _move_mark(o: ISSMenu.Obj, addr: int, back: Callable, me: Callable) -> void:
	if not scrolling(0x60):
		var first := m.team_players(_side()) + ISSModes.PLAYER_SIZE
		var last := first + 9 * ISSModes.PLAYER_SIZE
		var cur := l(addr) & 0xFFFF
		if pressed_home(PAD_C):
			o.update = back
			m.play_sfx(95)
		if pressed_home(PAD_UP):
			set_l(addr, 0xFF0000 | (last if cur <= first else cur - ISSModes.PLAYER_SIZE))
			o.update = me
			m.play_sfx(w(0x1784))
		if pressed_home(PAD_DOWN):
			cur = l(addr) & 0xFFFF
			set_l(addr, 0xFF0000 | (first if cur >= last else cur + ISSModes.PLAYER_SIZE))
			o.update = me
			m.play_sfx(w(0x1784))
	o.add_w(T, 1)
	var y := _ptr_index(addr) * 16 + 0x28
	m.cursor_draw_large(_side(), 0xF8, 0x100, y)
	var pl := l(addr) & 0xFFFF
	m.icon_draw_small(0, ISSRam.w(pl + 0x10) - 4, ISSRam.w(pl + 0x14) + 4)


func menu_state_042452(o: ISSMenu.Obj) -> void:
	o.update = menu_state_042452_1
	o.set_w(T, 0)
	menu_func_0428B0()
	menu_state_042452_1(o)


func menu_state_042452_1(o: ISSMenu.Obj) -> void:
	_move_mark(o, _captain(), menu_state_041AEA, menu_state_042452)


func menu_state_0425D8(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0425D8_1
	o.set_w(T, 0)
	menu_func_0428B0(true)
	menu_state_0425D8_1(o)


func menu_state_0425D8_1(o: ISSMenu.Obj) -> void:
	_move_mark(o, _taker(), menu_state_0419C8, menu_state_0425D8)
