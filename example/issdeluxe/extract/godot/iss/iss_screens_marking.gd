class_name ISSScreensMarking
extends ISSScreens
## Man-to-man marking (screen $B): the side's outfield players on the right
## (plane B scrolled right by $60), the opponents' on the left, each with
## position or shirt number, energy face or status, the mini pitch of the
## side under the cursor and the attributes of the player under it. C on
## one of the side's players and C on an opponent sets the marking (+$54 of
## the player object: the opponent's object index 1-10, $FF none); the two
## columns of numbers between show who marks whom. $1768 is the side being
## set; $1776 / $1778 the cursors on the side / the opponents, $177A the
## player picked (-1 none), $1782 the side on the mini pitch.

const MARK := 0x54
const OFF := 0x55
const ENERGY := 0x57
const NUMBER := 0x63
const POSITION := 0x65


func register(h: Dictionary) -> void:
	h[0x0B] = screen_man_marking


func _side() -> int:
	return w(0x1768)


func _own(k: int) -> int:
	return player(_side(), k)


func _opp(k: int) -> int:
	return player(_side() ^ 1, k)


## The rows: player k (1-10) at y = $28 + 16k.
func _y(k: int) -> int:
	return k * 16 + 0x28


## The shirt number tiles of a side's players (2 cells each): the side
## being set uses $1F2 for the home side and $21A for the away side.
func _numbers(side: int) -> int:
	return tiles() + (0x1F2 if side == 0 else 0x21A)


func screen_man_marking() -> void:
	set_w(0x1784, 0x7B if w(S.g_sound_disabled) == 0x19 else 0x4D)
	set_w(S.g_plane_b_hscroll, 0x60)
	var side := _side()
	if side != 0:
		for i in 5:
			set_w(0x7C6 + 2 * i, ISSRom.u16(rom("tbl_away_side_colours") + 2 * i))
		set_w(0x1548, 1)
	var teams := [w(S.g_team_home), w(S.g_team_away)]
	var buf := l(S.g_unpack_buffer)
	# The two teams' little heads, then the side's photo.
	m.unpack(6, 2, buf)
	m.vram_dma(w(S.g_stadium_vram) + 0x6600, buf + teams[side] * 0xC0, 0xC0)
	m.vram_dma(w(S.g_stadium_vram) + 0x68C0, buf + teams[side ^ 1] * 0xC0, 0xC0)
	m.unpack(6, 1, buf)
	m.vram_dma(w(S.g_stadium_vram) + 0x66C0, buf + teams[side] * 0x200, 0x200)
	side_icon(side, 0x70, 0x80, 8, 0x18)
	set_l(0x1770, buf)
	set_l(S.g_unpack_buffer, m.unpack(4, 35, buf))
	set_w(0x1780, m.load_tiles(4, 32))
	set_w(0x1774, m.load_tiles(4, 33))
	# The names: the opponents' outfield players on the left, the side's on
	# the right with the marking numbers.
	for k in range(1, 11):
		m.text_draw_field(0x20, 0x60, _y(k), player_name(side ^ 1, _opp(k)))
	for k in range(1, 11):
		var p := _own(k)
		m.text_draw_field(0x118, 0x158, _y(k), player_name(side, p))
		var mk := ISSRam.b(p + MARK)
		if mk < 0x80:
			m.rect_fill_tiles(0xF8, 0x100, _y(k), _y(k) + 16,
				_numbers(side ^ 1) + (ISSRam.b(_opp(mk) + NUMBER) - 1) * 2)
			m.rect_fill_tiles(0x60, 0x68, _y(mk), _y(mk) + 16,
				_numbers(side) + (ISSRam.b(p + NUMBER) - 1) * 2)
	m.pitch_place(0x70, 0x18, 0)
	m.pitch_place(0x70, 0x18, 1)
	set_w(0x1776, 1)
	set_w(0x1778, 1)
	set_w(0x177A, 0xFFFF)
	set_w(0x177C, 0)
	set_w(0x177E, 0)
	set_w(0x1782, w(S.g_left_goal_team))
	menu_state_046DBA(spawn(Callable()))
	menu_state_047436(spawn(Callable()))


# --------------------------------------------------------------------------
# The marks and faces (menu_state_046DBA): Y shows positions or numbers
# ($177C), Z faces or statuses ($177E), A steps through the combinations.

func _marks(side: int, p: int, x: int, y: int) -> void:
	if w(0x177C) == 0:
		var t := tiles() + 0x242
		if ISSRam.b(p + OFF) != 0:
			t += 0xA
		else:
			t += (ISSRam.b(p + 0x51) & 0x7F) * 2
		m.rect_fill_tiles(x, x + 8, y, y + 16, t)
	else:
		m.rect_fill_tiles(x, x + 8, y, y + 16, _numbers(side) + (ISSRam.b(p + NUMBER) - 1) * 2)
	var st := player_status(side, p)
	if w(0x177E) == 0 and st != 4:
		m.face_draw(x + 8, y, ISSRam.b(p + ENERGY))
	else:
		m.rect_fill_tiles(x + 8, x + 0x18, y, y + 16, tiles() + 0x26F + st * 4)


func menu_state_046DBA(o: ISSMenu.Obj) -> void:
	o.update = menu_state_046DBA_1
	var side := _side()
	for k in range(1, 11):
		_marks(side ^ 1, _opp(k), 8, _y(k))
	for k in range(1, 11):
		_marks(side, _own(k), 0x100, _y(k))
	menu_state_046DBA_1(o)


func menu_state_046DBA_1(o: ISSMenu.Obj) -> void:
	var p := w(S.g_pad_pressed_home)
	if p & 0x200:
		set_w(0x177C, w(0x177C) ^ 1)
		o.update = menu_state_046DBA
	if p & 0x100:
		set_w(0x177E, w(0x177E) ^ 1)
		o.update = menu_state_046DBA
	if p & PAD_A:
		if w(0x177C) == 0:
			set_w(0x177C, 1)
		else:
			set_w(0x177C, 0)
			set_w(0x177E, w(0x177E) ^ 1)
		o.update = menu_state_046DBA
	m.anim_tiles()
	# The bars behind the names, coloured by position (two mirrored 4 x 2
	# sprites each): the side's at $198, the opponents' at $A0.
	for col in 2:
		var x := (0x198 if col == 0 else 0xA0) - sw(S.g_plane_b_hscroll)
		for k in range(1, 11):
			var pl := _own(k) if col == 0 else _opp(k)
			var t := (w(0x1780) >> 5) + ISSRam.b(pl + POSITION) * 8
			var y := k * 16 + 0xA8 - sw(S.g_plane_b_vscroll)
			m.sprite(y, 0x0D, t | 0x4000, x)
			m.sprite(y, 0x0D, t | 0x4800, x + 0x20)
	o.add_w(T, 1)
	if sw(S.g_plane_b_hscroll) < 0x30:
		m.pad_icon_draw(1, 0xF3, 0x80)
	else:
		m.pad_icon_draw(0, 0x65, 0x80)
	m.pitch_draw(w(0x1782))


# --------------------------------------------------------------------------
# The cursors.

## Show the side's (or the opponents') mini pitch, mirroring the plane's
## pitch when it changes.
func _show_pitch(side: int) -> void:
	if side != w(0x1782):
		set_w(0x1782, side)
		m.rect_mirror(0x88, 0xD8, 0x18, 0x78)


func _bars(p: int, x: int) -> void:
	for i in 9:
		m.bar_draw(x, i * 8 + 0x88, 0, ISSRam.b(p + 0x5A + i))


## The marking of the side's player k off: both numbers cleared.
func _unmark(k: int) -> void:
	var p := _own(k)
	var mk := ISSRam.b(p + MARK)
	if mk < 0x80:
		m.rect_fill(0x60, 0x68, _y(mk), _y(mk) + 16, tiles())
	m.rect_fill(0xF8, 0x100, _y(k), _y(k) + 16, tiles())
	ISSRam.set_b(p + MARK, 0xFF)


## The cursor on the side's players ($1776, 1-10).
func menu_state_047436(o: ISSMenu.Obj) -> void:
	o.update = menu_state_047436_1
	o.set_w(T, 0)
	_show_pitch(_side())
	_bars(_own(w(0x1776)), 0xD8)
	menu_state_047436_1(o)


func menu_state_047436_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0x60):
		if pressed_home(PAD_UP):
			if w(0x1776) == 1:
				o.update = menu_state_04720C
			else:
				add_w(0x1776, -1)
				o.update = menu_state_047436
			m.play_sfx(w(0x1784))
		if pressed_home(PAD_DOWN):
			if w(0x1776) == 10:
				o.update = menu_state_04720C
			else:
				add_w(0x1776, 1)
				o.update = menu_state_047436
			m.play_sfx(w(0x1784))
		if pressed_home(PAD_LEFT):
			o.update = menu_state_047726
			m.play_sfx(w(0x1784))
		if pressed_home(PAD_B):
			if sw(0x177A) < 0:
				# B on a marking player takes the marking off; on another
				# goes to EXIT.
				if ISSRam.b(_own(w(0x1776)) + MARK) < 0x80:
					_unmark(w(0x1776))
					m.play_sfx(95)
				else:
					o.update = menu_state_04720C
			else:
				m.rect_unhighlight(0x118, 0x158, _y(w(0x177A)), _y(w(0x177A)) + 16)
				set_w(0x177A, 0xFFFF)
		if pressed_home(PAD_C):
			if sw(0x177A) < 0:
				set_w(0x177A, w(0x1776))
				m.rect_highlight(0x118, 0x158, _y(w(0x1776)), _y(w(0x1776)) + 16)
				o.update = menu_state_047726
				m.play_sfx(95)
			else:
				o.update = menu_state_047726
				m.play_sfx(94)
	o.add_w(T, 1)
	if o.update == menu_state_047436_1:
		m.rect_flash(0xB0, 0xF8, 0x78, 0xD8)
	else:
		m.rect_unhighlight(0xB0, 0xF8, 0x78, 0xD8)
	m.cursor_draw_large(_side(), 0x118, 0x158, _y(w(0x1776)))
	var pl := _own(w(0x1776))
	m.icon_draw_small(0, ISSRam.w(pl + 0x10) - 4, ISSRam.w(pl + 0x14) + 4)


## EXIT: C leaves for the pre-match menu (or the other side's turn).
func menu_state_04720C(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04720C_1
	menu_state_04720C_1(o)


func menu_state_04720C_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0x60):
		if pressed_home(PAD_C):
			ISSModes.prematch_return()
			set_l(S.g_next_state, ISSMenu.STATE_MENU)
			m.fade_out_start()
			m.play_sfx(95)
		if pressed_home(PAD_LEFT | PAD_RIGHT):
			o.update = menu_state_04720C_2
			m.play_sfx(w(0x1784))
		_back_to_list(o)
	o.add_w(T, 1)
	m.cursor_draw(_side(), 0x140, 0x158, 8)


## Up / down from the marks above: the last or first of the side's players.
func _back_to_list(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_UP):
		o.update = menu_state_047436
		set_w(0x1776, 10)
		m.play_sfx(w(0x1784))
	if pressed_home(PAD_DOWN):
		o.update = menu_state_047436
		set_w(0x1776, 1)
		m.play_sfx(w(0x1784))


## RESET: every marking off.
func menu_state_04720C_2(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04720C_3
	menu_state_04720C_3(o)


func menu_state_04720C_3(o: ISSMenu.Obj) -> void:
	if not scrolling(0x60):
		if pressed_home(PAD_B | PAD_LEFT | PAD_RIGHT):
			o.update = menu_state_04720C
			m.play_sfx(w(0x1784))
		_back_to_list(o)
		if pressed_home(PAD_C):
			for k in 11:
				ISSRam.set_b(_own(k) + MARK, 0xFF)
			m.rect_fill(0x60, 0x68, 0x38, 0xD8, tiles())
			m.rect_fill(0xF8, 0x100, 0x38, 0xD8, tiles())
			m.play_sfx(95)
	o.add_w(T, 1)
	m.cursor_draw(_side(), 0x128, 0x140, 8)


## The cursor on the opponents ($1778, 1-10): C sets the picked player's
## marking (the opponent's previous marker freed).
func menu_state_047726(o: ISSMenu.Obj) -> void:
	o.update = menu_state_047726_1
	o.set_w(T, 0)
	_show_pitch(_side() ^ 1)
	_bars(_opp(w(0x1778)), 0x90)
	menu_state_047726_1(o)


func menu_state_047726_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0):
		if pressed_home(PAD_RIGHT):
			o.update = menu_state_047436
			m.play_sfx(w(0x1784))
		if pressed_home(PAD_B):
			if sw(0x177A) >= 0:
				m.rect_unhighlight(0x118, 0x158, _y(w(0x177A)), _y(w(0x177A)) + 16)
			set_w(0x177A, 0xFFFF)
			o.update = menu_state_047436
			m.play_sfx(w(0x1784))
		if pressed_home(PAD_C):
			if sw(0x177A) < 0:
				o.update = menu_state_047436
				m.play_sfx(94)
			else:
				_mark(w(0x177A), w(0x1778))
				set_w(0x1776, 1 if w(0x1776) == 10 else w(0x1776) + 1)
				set_w(0x177A, 0xFFFF)
				o.update = menu_state_047436
				m.play_sfx(95)
		if pressed_home(PAD_DOWN):
			set_w(0x1778, 1 if w(0x1778) == 10 else w(0x1778) + 1)
			o.update = menu_state_047726
			m.play_sfx(w(0x1784))
		if pressed_home(PAD_UP):
			set_w(0x1778, 10 if w(0x1778) == 1 else w(0x1778) - 1)
			o.update = menu_state_047726
			m.play_sfx(w(0x1784))
	o.add_w(T, 1)
	if o.update == menu_state_047726_1:
		m.rect_flash(0x68, 0xB0, 0x78, 0xD8)
	else:
		m.rect_unhighlight(0x68, 0xB0, 0x78, 0xD8)
	m.cursor_draw_large(_side(), 0x20, 0x60, _y(w(0x1778)))
	var pl := _opp(w(0x1778))
	m.icon_draw_small(0, ISSRam.w(pl + 0x10) - 4, ISSRam.w(pl + 0x14) + 4)


## The side's player k marks opponent j: the old numbers of both cleared,
## the new ones drawn, the pick's highlight off.
func _mark(k: int, j: int) -> void:
	var p := _own(k)
	var mk := ISSRam.b(p + MARK)
	if mk < 0x80:
		m.rect_fill(0x60, 0x68, _y(mk), _y(mk) + 16, tiles())
	for i in 11:
		if ISSRam.b(_own(i) + MARK) == j:
			m.rect_fill(0xF8, 0x100, _y(i), _y(i) + 16, tiles())
			ISSRam.set_b(_own(i) + MARK, 0xFF)
			break
	ISSRam.set_b(p + MARK, j)
	m.rect_fill_tiles(0x60, 0x68, _y(j), _y(j) + 16, _numbers(_side()) + (ISSRam.b(p + NUMBER) - 1) * 2)
	m.rect_fill_tiles(0xF8, 0x100, _y(k), _y(k) + 16,
		_numbers(_side() ^ 1) + (ISSRam.b(_opp(j) + NUMBER) - 1) * 2)
	m.rect_unhighlight(0x118, 0x158, _y(k), _y(k) + 16)
