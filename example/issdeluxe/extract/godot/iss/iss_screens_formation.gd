class_name ISSScreensFormation
extends ISSScreens
## Formation change (screen 9): the type of formation (16, the list on the
## right), the players' places on the mini pitch (each one moved by hand),
## the three lines moved together, and attack participation (defenders and
## midfielders marked by bit 7 of the role join the attack). Each panel has
## OK / CANCEL / RESET; the player list is on plane B's left part (scrolled
## in for the per-player panels). $1768 is the side being set.
##
## RAM: $1776 the player under the cursor (1-10), $1778 the line (0 attack,
## 1 midfield, 2 defence), $177A / $1774 the bar / number tiles, $177C the
## list's marks (positions or numbers), $177E a request to redraw them,
## $178C the formation on entry to the list, $1780 / $1784 / $1788 the
## places saved for CANCEL (all, a line, one player), $178E the move sound.

const ROLE := 0x51
const FX := 0x52
const FY := 0x53
const OFF := 0x55
const NUMBER := 0x63
const POSITION := 0x65


func register(h: Dictionary) -> void:
	h[0x09] = screen_formation_change


func _side() -> int:
	return w(0x1768)


func _p(k: int) -> int:
	return player(_side(), k)


func _info() -> int:
	return S.g_team_home_info if _side() == 0 else S.g_team_away_info


func _formation() -> int:
	return w(_info() + ISSModes.TM_FORMATION)


func _set_formation(f: int) -> void:
	set_w(_info() + ISSModes.TM_FORMATION, f)


## Row y of player k in the list.
func _row(k: int) -> int:
	return k * 16 + 0x10


func _left() -> bool:
	return _side() == w(S.g_left_goal_team)


func _sfx() -> void:
	m.play_sfx(w(0x178E))


func screen_formation_change() -> void:
	set_w(0x178E, 0x7B if w(S.g_sound_disabled) == 0x19 else 0x4D)
	set_w(S.g_plane_b_hscroll, 0x60)
	var side := _side()
	if side != w(S.g_left_goal_team):
		# The pitch and the line labels the other way round.
		m.rect_mirror(0x70, 0xF0, 0x28, 0x88)
		m.rect_fill_tiles(0xD8, 0xE8, 0x98, 0xA8, tiles() + 0x350)
		m.rect_fill_tiles(0x78, 0x88, 0x98, 0xA8, tiles() + 0x358)
		m.rect_fill_tiles(0xD0, 0xE0, 0x20, 0x28, tiles() + 0x319)
		m.rect_fill_tiles(0x80, 0x90, 0x20, 0x28, tiles() + 0x31A)
	if side != 0:
		for i in 5:
			set_w(0x7C6 + 2 * i, ISSRom.u16(rom("tbl_away_side_colours") + 2 * i))
		set_w(0x1548, 1)
	var team := w(S.g_team_home if side == 0 else S.g_team_away)
	var buf := l(S.g_unpack_buffer)
	m.unpack(6, 2, buf)
	m.vram_dma(w(S.g_stadium_vram) + 0x6E00, buf + team * 0xC0, 0xC0)
	m.unpack(6, 1, buf)
	m.vram_dma(w(S.g_stadium_vram) + 0x6EC0, buf + team * 0x200, 0x200)
	side_icon(side, 0x70, 0x80, 8, 0x18)
	set_w(0x177A, m.load_tiles(4, 32))
	set_w(0x1774, m.load_tiles(4, 33))
	buf = l(S.g_unpack_buffer)
	set_l(0x1780, buf)
	set_l(0x1784, buf + 0x22)
	set_l(0x1788, buf + 0x32)
	set_l(S.g_unpack_buffer, buf + 0x36)
	for k in range(1, 11):
		m.text_draw_field(0x18, 0x58, _row(k), player_name(side, _p(k)))
	m.pitch_place(0x70, 0x28, side)
	menu_func_044D16()
	set_w(0x1776, 1)
	set_w(0x177C, 0)
	menu_state_042D3A(spawn(Callable()))
	menu_state_043150(spawn(Callable()))


## menu_func_044D16: the list's row of the formation highlighted.
func menu_func_044D16() -> void:
	var f := _formation()
	for i in 16:
		var y := i * 8 + 0x38
		if i == f:
			m.rect_highlight(0x118, 0x140, y, y + 8)
		else:
			m.rect_unhighlight(0x118, 0x140, y, y + 8)


## The places of the formation in use: the team's own (tbl_team_formations)
## when it is that formation, else the generic one (tbl_formations); eleven
## (x, y, role) after the formation byte.
func _formation_table() -> int:
	var team := w(S.g_team_home if _side() == 0 else S.g_team_away)
	var a := ISSRom.u32(rom("tbl_team_formations") + team * 4)
	if ISSRom.s8(a) != _formation():
		a = ISSRom.u32(rom("tbl_formations") + _formation() * 4)
	return a + 1


## Copy the eleven's fields (offsets) to RAM at dst / back from src.
func _save(dst: int, fields: Array) -> void:
	for k in 11:
		for f: int in fields:
			ISSRam.set_b(dst, ISSRam.b(_p(k) + f))
			dst += 1


func _restore(src: int, fields: Array) -> void:
	for k in 11:
		for f: int in fields:
			ISSRam.set_b(_p(k) + f, ISSRam.b(src))
			src += 1


## The fields given (FX, FY, ROLE) from the formation table.
func _load(fields: Array) -> void:
	var a := _formation_table()
	for k in 11:
		for i in 3:
			if [FX, FY, ROLE][i] in fields:
				ISSRam.set_b(_p(k) + [FX, FY, ROLE][i], ISSRom.u8(a + i))
		a += 3


# --------------------------------------------------------------------------
# The list's marks, the bars, and the eleven gliding to their places
# (menu_state_042D3A).

func menu_state_042D3A(o: ISSMenu.Obj) -> void:
	o.update = menu_state_042D3A_1
	for k in range(1, 11):
		var p := _p(k)
		var t: int
		if w(0x177C) == 0:
			t = tiles() + 0x242
			t += 0xA if ISSRam.b(p + OFF) != 0 else (ISSRam.b(p + ROLE) & 0x7F) * 2
		else:
			t = tiles() + (0x1F2 if _side() == 0 else 0x21A) + (ISSRam.b(p + NUMBER) - 1) * 2
		m.rect_fill_tiles(0x10, 0x18, _row(k), _row(k) + 16, t)
	menu_state_042D3A_1(o)


func menu_state_042D3A_1(o: ISSMenu.Obj) -> void:
	if w(0x177E) != 0:
		set_w(0x177E, 0)
		o.update = menu_state_042D3A
	if w(S.g_pad_pressed_home) & 0x240:
		set_w(0x177C, w(0x177C) ^ 1)
		o.update = menu_state_042D3A
	for k in range(1, 11):
		var t := (w(0x177A) >> 5) + ISSRam.b(_p(k) + POSITION) * 8
		var x := 0x98 - sw(S.g_plane_b_hscroll)
		var y := (k - 1) * 16 + 0xA0 - sw(S.g_plane_b_vscroll)
		m.sprite(y, 0x0D, t | 0x4000, x)
		m.sprite(y, 0x0D, t | 0x4800, x + 0x20)
	var left := _left()
	for k in range(1, 11):
		var p := _p(k)
		var role := ISSRam.b(p + ROLE) & 0x7F
		var fx := ISSRam.sb(p + FX)
		var fy := ISSRam.sb(p + FY)
		var tx: int
		var ty: int
		if left:
			tx = -role * 0x2C + 0x6C + fx + 0x70
			ty = fy + 0x30 + 0x28
		else:
			tx = role * 0x2C + 0x14 - fx + 0x70
			ty = -fy + 0x30 + 0x28
		ISSRam.set_w(p + 0x10, ISSRam.sw(p + 0x10) + _glide(tx - ISSRam.sw(p + 0x10)))
		ISSRam.set_w(p + 0x14, ISSRam.sw(p + 0x14) + _glide(ty - ISSRam.sw(p + 0x14)))
	m.pitch_draw(_side())
	m.boxes_draw_sprites(rom("menu_state_042D3A_1_data"))


## A sixteenth of the way, at least a pixel.
static func _glide(d: int) -> int:
	if d == 0:
		return 0
	var s := d >> 4
	return s if s != 0 else (1 if d > 0 else -1)


# --------------------------------------------------------------------------
# The marks above: RESET ($128) and EXIT ($140).

func menu_state_042FD4(o: ISSMenu.Obj) -> void:
	o.update = menu_state_042FD4_1
	menu_state_042FD4_1(o)


func menu_state_042FD4_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0x60):
		if pressed_home(PAD_C):
			ISSModes.prematch_return()
			set_l(S.g_next_state, ISSMenu.STATE_MENU)
			m.fade_out_start()
			m.play_sfx(95)
		if pressed_home(PAD_LEFT | PAD_RIGHT):
			o.update = menu_state_042FD4_2
			_sfx()
		if pressed_home(PAD_UP | PAD_DOWN):
			o.update = menu_state_043150
			_sfx()
	o.add_w(T, 1)
	m.cursor_draw(_side(), 0x140, 0x158, 8)


## RESET: the team's own formation back.
func menu_state_042FD4_2(o: ISSMenu.Obj) -> void:
	o.update = menu_state_042FD4_3
	menu_state_042FD4_3(o)


func menu_state_042FD4_3(o: ISSMenu.Obj) -> void:
	if not scrolling(0x60):
		if pressed_home(PAD_B | PAD_LEFT | PAD_RIGHT):
			o.update = menu_state_042FD4
			_sfx()
		if pressed_home(PAD_UP | PAD_DOWN):
			o.update = menu_state_043150
			_sfx()
		if pressed_home(PAD_C):
			ISSModes._team_formation(_side())
			menu_func_044D16()
			m.play_sfx(95)
	o.add_w(T, 1)
	m.cursor_draw(_side(), 0x128, 0x140, 8)


# --------------------------------------------------------------------------
# The four panels: type of formation (right), the pitch, the lines and
# attack participation (left, top to bottom).

func _panel(o: ISSMenu.Obj, me: Callable, x0: int, x1: int, y0: int, y1: int) -> void:
	o.add_w(T, 1)
	if o.update == me:
		m.rect_flash(x0, x1, y0, y1)
	else:
		m.rect_unhighlight(x0, x1, y0, y1)


func menu_state_043150(o: ISSMenu.Obj) -> void:
	o.update = menu_state_043150_1
	o.set_w(T, 0)
	menu_state_043150_1(o)


func menu_state_043150_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0x60):
		if pressed_home(PAD_B | PAD_UP | PAD_DOWN):
			o.update = menu_state_042FD4
			_sfx()
		if pressed_home(PAD_LEFT):
			o.update = menu_state_043250
			_sfx()
		if pressed_home(PAD_C):
			set_w(0x178C, _formation())
			_save(l(0x1780), [ROLE, FX, FY])
			o.update = menu_state_044258
			m.play_sfx(95)
	_panel(o, menu_state_043150_1, 0x100, 0x158, 0x18, 0xD8)


func menu_state_043250(o: ISSMenu.Obj) -> void:
	o.update = menu_state_043250_1
	o.set_w(T, 0)
	menu_state_043250_1(o)


func menu_state_043250_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0x60):
		if pressed_home(PAD_C):
			_save(l(0x1780), [FX, FY])
			set_w(0x1776, 1)
			o.update = menu_state_0435E0
			m.play_sfx(95)
		if pressed_home(PAD_B):
			o.update = menu_state_042FD4
		if pressed_home(PAD_RIGHT):
			o.update = menu_state_043150
			_sfx()
		if pressed_home(PAD_UP):
			o.update = menu_state_0434B2
			_sfx()
		if pressed_home(PAD_DOWN):
			o.update = menu_state_043382
			_sfx()
	_panel(o, menu_state_043250_1, 0x68, 0xF8, 0x18, 0x90)


func menu_state_043382(o: ISSMenu.Obj) -> void:
	o.update = menu_state_043382_1
	o.set_w(T, 0)
	menu_state_043382_1(o)


func menu_state_043382_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0x60):
		if pressed_home(PAD_B):
			o.update = menu_state_042FD4
		if pressed_home(PAD_C):
			_save(l(0x1780), [FX, FY])
			set_w(0x1778, 0)
			o.update = menu_state_044612
			m.play_sfx(95)
		if pressed_home(PAD_RIGHT):
			o.update = menu_state_043150
			_sfx()
		if pressed_home(PAD_UP):
			o.update = menu_state_043250
			_sfx()
		if pressed_home(PAD_DOWN):
			o.update = menu_state_0434B2
			_sfx()
	_panel(o, menu_state_043382_1, 0x68, 0xF8, 0x90, 0xB8)


func menu_state_0434B2(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0434B2_1
	o.set_w(T, 0)
	menu_state_0434B2_1(o)


func menu_state_0434B2_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0x60):
		if pressed_home(PAD_C):
			_save(l(0x1780), [ROLE])
			set_w(0x1776, 1)
			o.update = menu_state_043CD2
			m.play_sfx(95)
		if pressed_home(PAD_B):
			o.update = menu_state_042FD4
		if pressed_home(PAD_RIGHT):
			o.update = menu_state_043150
			_sfx()
		if pressed_home(PAD_UP):
			o.update = menu_state_043382
			_sfx()
		if pressed_home(PAD_DOWN):
			o.update = menu_state_043250
			_sfx()
	_panel(o, menu_state_0434B2_1, 0x68, 0xF8, 0xB8, 0xD8)


# --------------------------------------------------------------------------
# Type of formation: up / down through the 16 (the eleven take their
# places), the list's RESET below; C keeps it, B restores the one on entry.

func menu_state_044258(o: ISSMenu.Obj) -> void:
	o.update = menu_state_044258_1
	_load([FX, FY, ROLE])
	menu_func_044D16()
	m.rect_highlight(0x100, 0x158, 0x18, 0xD8)
	menu_state_044258_1(o)


func menu_state_044258_1(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_B):
		_set_formation(w(0x178C))
		_restore(l(0x1780), [ROLE, FX, FY])
		menu_func_044D16()
		set_w(0x177E, 1)
		o.update = menu_state_043150
	if pressed_home(PAD_C):
		set_w(0x177E, 1)
		o.update = menu_state_043150
		m.play_sfx(95)
	if pressed_home(PAD_UP):
		if _formation() == 0:
			o.update = menu_state_044258_2
		else:
			_set_formation(_formation() - 1)
			o.update = menu_state_044258
		_sfx()
	if pressed_home(PAD_DOWN):
		if _formation() == 15:
			o.update = menu_state_044258_2
		else:
			_set_formation(_formation() + 1)
			o.update = menu_state_044258
		_sfx()
	o.add_w(T, 1)
	m.cursor_draw(_side(), 0x118, 0x140, _formation() * 8 + 0x38)


## The list's RESET: the team's own formation.
func menu_state_044258_2(o: ISSMenu.Obj) -> void:
	o.update = menu_state_044258_3
	menu_state_044258_3(o)


func menu_state_044258_3(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_UP):
		_set_formation(15)
		o.update = menu_state_044258
		_sfx()
	if pressed_home(PAD_DOWN):
		_set_formation(0)
		o.update = menu_state_044258
		_sfx()
	if pressed_home(PAD_C):
		var team := w(S.g_team_home if _side() == 0 else S.g_team_away)
		var a := ISSRom.u32(rom("tbl_team_formations") + team * 4)
		_set_formation(ISSRom.s8(a))
		a += 1
		for k in 11:
			ISSRam.set_b(_p(k) + FX, ISSRom.u8(a))
			ISSRam.set_b(_p(k) + FY, ISSRom.u8(a + 1))
			ISSRam.set_b(_p(k) + ROLE, ISSRom.u8(a + 2))
			a += 3
		menu_func_044D16()
		o.update = menu_state_043150
		m.play_sfx(95)
	o.add_w(T, 1)
	m.cursor_draw(_side(), 0x128, 0x140, 0xC0)


# --------------------------------------------------------------------------
# One player's place: the cursor on the list (plane B scrolled to 0), C
# picks him (he blinks) and the pad moves him (-16..16 across, -40..40
# along; mirrored for the side defending the right goal).

func menu_state_0435E0(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0435E0_1
	o.set_w(T, 0)
	m.rect_highlight(0x68, 0xF8, 0x18, 0x90)
	m.rect_unhighlight(0x18, 0x58, _row(w(0x1776)), _row(w(0x1776)) + 16)
	menu_state_0435E0_1(o)


func menu_state_0435E0_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0):
		if pressed_home(PAD_UP):
			if w(0x1776) == 1:
				o.update = menu_state_043790
			else:
				add_w(0x1776, -1)
			_sfx()
		if pressed_home(PAD_DOWN):
			if w(0x1776) == 10:
				o.update = menu_state_043790
			else:
				add_w(0x1776, 1)
			_sfx()
		if pressed_home(PAD_B):
			o.update = menu_state_043790
		if pressed_home(PAD_C):
			var p := _p(w(0x1776))
			if ISSRam.b(p + OFF) != 0:
				m.play_sfx(94)
			else:
				ISSRam.set_b(l(0x1788), ISSRam.b(p + FX))
				ISSRam.set_b(l(0x1788) + 1, ISSRam.b(p + FY))
				m.rect_highlight(0x18, 0x58, _row(w(0x1776)), _row(w(0x1776)) + 16)
				o.update = menu_state_0435E0_2
				m.play_sfx(95)
	_list_cursor(o)


func _list_cursor(o: ISSMenu.Obj) -> void:
	o.add_w(T, 1)
	m.cursor_draw_large(_side(), 0x18, 0x58, _row(w(0x1776)))
	var p := _p(w(0x1776))
	m.icon_draw_small(0, ISSRam.w(p + 0x10) - 4, ISSRam.w(p + 0x14) + 4)


func menu_state_0435E0_2(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0435E0_3
	menu_state_0435E0_3(o)


func menu_state_0435E0_3(o: ISSMenu.Obj) -> void:
	var p := _p(w(0x1776))
	ISSRam.set_b(p + 0xE, 0)
	if pressed_home(PAD_B):
		ISSRam.set_b(p + 0xE, 1)
		ISSRam.set_b(p + FX, ISSRam.b(l(0x1788)))
		ISSRam.set_b(p + FY, ISSRam.b(l(0x1788) + 1))
		o.update = menu_state_0435E0
	if pressed_home(PAD_C):
		ISSRam.set_b(p + 0xE, 1)
		o.update = menu_state_0435E0
		m.play_sfx(95)
	_move([p])


## The pad moves the players given within their limits, with the move
## sound: for one player only when he moved, for a line on every press.
func _move(ps: Array, every := false) -> void:
	var left := _left()
	var dirs := [
		[PAD_RIGHT if left else PAD_LEFT, FX, 1, 0x10],
		[PAD_LEFT if left else PAD_RIGHT, FX, -1, -0x10],
		[PAD_DOWN if left else PAD_UP, FY, 1, 0x28],
		[PAD_UP if left else PAD_DOWN, FY, -1, -0x28],
	]
	for d: Array in dirs:
		if not pressed_home(d[0]):
			continue
		var moved := false
		for p: int in ps:
			var v := ISSRam.sb(p + d[1])
			if (d[2] > 0 and v < d[3]) or (d[2] < 0 and v > d[3]):
				ISSRam.set_b(p + d[1], v + d[2])
				moved = true
		if moved or every:
			_sfx()


## The buttons under the list: OK ($10), CANCEL ($20), RESET ($40) at y $C0.
func _list_button(o: ISSMenu.Obj, x0: int, x1: int) -> void:
	o.add_w(T, 1)
	m.cursor_draw(_side(), x0, x1, 0xC0)


## Up / down from the buttons: back to the list's last or first player.
func _to_list(o: ISSMenu.Obj, list: Callable) -> void:
	if pressed_home(PAD_UP):
		set_w(0x1776, 10)
		o.update = list
		_sfx()
	if pressed_home(PAD_DOWN):
		set_w(0x1776, 1)
		o.update = list
		_sfx()


func menu_state_043790(o: ISSMenu.Obj) -> void:
	o.update = menu_state_043790_1
	menu_state_043790_1(o)


func menu_state_043790_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0):
		if pressed_home(PAD_C):
			o.update = menu_state_043250
			m.play_sfx(95)
		if pressed_home(PAD_RIGHT):
			o.update = menu_state_04389E
			_sfx()
		if pressed_home(PAD_LEFT):
			o.update = menu_state_0439D4
			_sfx()
		_to_list(o, menu_state_0435E0)
	_list_button(o, 0x10, 0x20)


## CANCEL: the places on entry to the panel.
func menu_state_04389E(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04389E_1
	menu_state_04389E_1(o)


func menu_state_04389E_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0):
		if pressed_home(PAD_RIGHT):
			o.update = menu_state_0439D4
			_sfx()
		if pressed_home(PAD_B | PAD_LEFT):
			o.update = menu_state_043790
			_sfx()
		_to_list(o, menu_state_0435E0)
		if pressed_home(PAD_C):
			_restore(l(0x1780), [FX, FY])
			o.update = menu_state_04389E
			m.play_sfx(95)
	_list_button(o, 0x20, 0x40)


## RESET: the formation's places.
func menu_state_0439D4(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0439D4_1
	menu_state_0439D4_1(o)


func menu_state_0439D4_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0):
		if pressed_home(PAD_B | PAD_RIGHT):
			o.update = menu_state_043790
			_sfx()
		if pressed_home(PAD_LEFT):
			o.update = menu_state_04389E
			_sfx()
		_to_list(o, menu_state_0435E0)
		if pressed_home(PAD_C):
			_load([FX, FY])
			m.play_sfx(95)
	_list_button(o, 0x40, 0x58)


# --------------------------------------------------------------------------
# Attack participation: the cursor on the defenders and midfielders (the
# forwards, role 0, come last and are skipped); C marks one, B unmarks him
# (or, unmarked, goes to the buttons).

func menu_state_043CD2(o: ISSMenu.Obj) -> void:
	o.update = menu_state_043CD2_1
	o.set_w(T, 0)
	while ISSRam.b(_p(w(0x1776)) + ROLE) == 0:
		add_w(0x1776, -1)
	m.rect_highlight(0x68, 0xF8, 0xB8, 0xD8)
	menu_state_043CD2_1(o)


func menu_state_043CD2_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0):
		var p := _p(w(0x1776))
		if pressed_home(PAD_B):
			if ISSRam.b(p + ROLE) & 0x80 == 0:
				o.update = menu_state_043E8E
			else:
				ISSRam.set_b(p + ROLE, ISSRam.b(p + ROLE) ^ 0x80)
		if pressed_home(PAD_C) and ISSRam.b(p + ROLE) & 0x80 == 0:
			ISSRam.set_b(p + ROLE, ISSRam.b(p + ROLE) | 0x80)
			m.play_sfx(95)
		if pressed_home(PAD_UP):
			if w(0x1776) == 1:
				o.update = menu_state_043E8E
			else:
				add_w(0x1776, -1)
			_sfx()
		if pressed_home(PAD_DOWN):
			if w(0x1776) == 10:
				o.update = menu_state_043E8E
			else:
				add_w(0x1776, 1)
				if ISSRam.b(_p(w(0x1776)) + ROLE) == 0:
					add_w(0x1776, -1)
					o.update = menu_state_043E8E
			_sfx()
	_list_cursor(o)


func menu_state_043E8E(o: ISSMenu.Obj) -> void:
	o.update = menu_state_043E8E_1
	menu_state_043E8E_1(o)


func menu_state_043E8E_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0):
		if pressed_home(PAD_C):
			o.update = menu_state_0434B2
			m.play_sfx(95)
		if pressed_home(PAD_RIGHT):
			o.update = menu_state_043F9C
			_sfx()
		if pressed_home(PAD_LEFT):
			o.update = menu_state_0440CE
			_sfx()
		_to_list(o, menu_state_043CD2)
	_list_button(o, 0x10, 0x20)


func menu_state_043F9C(o: ISSMenu.Obj) -> void:
	o.update = menu_state_043F9C_1
	menu_state_043F9C_1(o)


func menu_state_043F9C_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0):
		if pressed_home(PAD_RIGHT):
			o.update = menu_state_0440CE
			_sfx()
		if pressed_home(PAD_B | PAD_LEFT):
			o.update = menu_state_043E8E
			_sfx()
		_to_list(o, menu_state_043CD2)
		if pressed_home(PAD_C):
			_restore(l(0x1780), [ROLE])
			o.update = menu_state_043F9C
			m.play_sfx(95)
	_list_button(o, 0x20, 0x40)


func menu_state_0440CE(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0440CE_1
	menu_state_0440CE_1(o)


func menu_state_0440CE_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0):
		if pressed_home(PAD_B | PAD_RIGHT):
			o.update = menu_state_043E8E
			_sfx()
		if pressed_home(PAD_LEFT):
			o.update = menu_state_043F9C
			_sfx()
		_to_list(o, menu_state_043CD2)
		if pressed_home(PAD_C):
			_load([ROLE])
			m.play_sfx(95)
	_list_button(o, 0x40, 0x58)


# --------------------------------------------------------------------------
# The lines: left / right choose one (the cursor over its arrow), C picks
# it (its players blink) and the pad moves them all; the buttons OK ($A8),
# CANCEL ($B8), RESET ($D8) at y $A8.

func menu_state_044612(o: ISSMenu.Obj) -> void:
	o.update = menu_state_044612_1
	m.rect_highlight(0x68, 0xF8, 0x90, 0xB8)
	menu_state_044612_1(o)


func menu_state_044612_1(o: ISSMenu.Obj) -> void:
	var left := _left()
	if pressed_home(PAD_LEFT if left else PAD_RIGHT):
		set_w(0x1778, 0 if w(0x1778) >= 2 else w(0x1778) + 1)
		_sfx()
	if pressed_home(PAD_RIGHT if left else PAD_LEFT):
		set_w(0x1778, 2 if w(0x1778) <= 0 else w(0x1778) - 1)
		_sfx()
	if pressed_home(PAD_B | PAD_UP | PAD_DOWN):
		o.update = menu_state_044A0E
		_sfx()
	if pressed_home(PAD_C):
		var a := l(0x1784)
		for p: int in _line():
			ISSRam.set_b(a, ISSRam.b(p + FX))
			ISSRam.set_b(a + 1, ISSRam.b(p + FY))
			a += 2
		o.update = menu_state_044612_2
		m.play_sfx(95)
	o.add_w(T, 1)
	var d3 := w(0x1778) if left else 2 - w(0x1778)
	var x := 0xD8 - d3 * 0x30
	m.cursor_draw(_side(), x, x + 0x10, 0x9C)


## The eleven's objects in line $1778.
func _line() -> Array:
	var out := []
	for k in 11:
		if ISSRam.b(_p(k) + ROLE) & 0x7F == w(0x1778):
			out.append(_p(k))
	return out


func menu_state_044612_2(o: ISSMenu.Obj) -> void:
	o.update = menu_state_044612_3
	for p: int in _line():
		ISSRam.set_b(p + 0xE, 0)
	menu_state_044612_3(o)


func menu_state_044612_3(o: ISSMenu.Obj) -> void:
	_move(_line(), true)
	if pressed_home(PAD_C):
		for k in 11:
			ISSRam.set_b(_p(k) + 0xE, 1)
		o.update = menu_state_044612
		m.play_sfx(95)
	if pressed_home(PAD_B):
		var a := l(0x1784)
		for k in 11:
			var p := _p(k)
			if ISSRam.b(p + ROLE) & 0x7F == w(0x1778):
				ISSRam.set_b(p + FX, ISSRam.b(a))
				ISSRam.set_b(p + FY, ISSRam.b(a + 1))
				a += 2
			ISSRam.set_b(p + 0xE, 1)
		o.update = menu_state_044612
		m.play_sfx(95)


func _line_button(o: ISSMenu.Obj, x0: int, x1: int) -> void:
	o.add_w(T, 1)
	m.cursor_draw(_side(), x0, x1, 0xA8)


func menu_state_044A0E(o: ISSMenu.Obj) -> void:
	o.update = menu_state_044A0E_1
	menu_state_044A0E_1(o)


func menu_state_044A0E_1(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_RIGHT):
		o.update = menu_state_044AD6
		_sfx()
	if pressed_home(PAD_LEFT):
		o.update = menu_state_044BC6
		_sfx()
	if pressed_home(PAD_C):
		o.update = menu_state_043382
		m.play_sfx(95)
	if pressed_home(PAD_UP | PAD_DOWN):
		o.update = menu_state_044612
		_sfx()
	_line_button(o, 0xA8, 0xB8)


func menu_state_044AD6(o: ISSMenu.Obj) -> void:
	o.update = menu_state_044AD6_1
	menu_state_044AD6_1(o)


func menu_state_044AD6_1(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_RIGHT):
		o.update = menu_state_044BC6
		_sfx()
	if pressed_home(PAD_LEFT):
		o.update = menu_state_044A0E
		_sfx()
	if pressed_home(PAD_UP | PAD_DOWN):
		o.update = menu_state_044612
		_sfx()
	if pressed_home(PAD_C):
		_restore(l(0x1780), [FX, FY])
		o.update = menu_state_044AD6
		m.play_sfx(95)
	_line_button(o, 0xB8, 0xD8)


func menu_state_044BC6(o: ISSMenu.Obj) -> void:
	o.update = menu_state_044BC6_1
	menu_state_044BC6_1(o)


func menu_state_044BC6_1(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_RIGHT):
		o.update = menu_state_044A0E
		_sfx()
	if pressed_home(PAD_LEFT):
		o.update = menu_state_044AD6
		_sfx()
	if pressed_home(PAD_UP | PAD_DOWN):
		o.update = menu_state_044612
		_sfx()
	if pressed_home(PAD_C):
		_load([FX, FY])
		o.update = menu_state_043382
		m.play_sfx(95)
	_line_button(o, 0xD8, 0xF0)
