class_name ISSScreensEdit
extends ISSScreens
## Edit player (screen $E): the side's players (the eleven on the right, the
## bench on the left with plane B scrolled), a figure of the player under
## the cursor in the side's kit turning round, and his nine attributes; C
## picks him and left / right spend or take back the team's points
## (tbl_edit_costs per attribute; raising one back up to the record's value
## is free) on a working copy in the referee object (g_referee + $56..$63),
## OK / CANCEL / RESET below. $1768 is the side being set.
##
## RAM: $1776 / $1778 the cursors on the eleven / the bench, $177A the
## player being edited, $177C the attribute under the cursor, $177E / $1780
## the list's marks and faces, $1784 the points left while editing, $1782 /
## $1774 the bar / number tiles, $1786 the move sound; the team's points are
## tm +$14 (all) and +$16 (left).

const RECORD := 0x5A
const NUMBER := 0x63
const POSITION := 0x65
const KEEPER := 3

var _fig: Sprite2D


func register(h: Dictionary) -> void:
	h[0x0E] = screen_edit_player


func _side() -> int:
	return w(0x1768)


func _p(k: int) -> int:
	return player(_side(), k)


func _points_all() -> int:
	return 0x1832 if _side() == 0 else 0x18BA


func _points_left() -> int:
	return 0x1834 if _side() == 0 else 0x18BC


func _sfx() -> void:
	m.play_sfx(w(0x1786))


## The record of the side's squad player (tbl_player_data, 12 bytes).
func _base(p: int) -> int:
	var team := w(S.g_team_home if _side() == 0 else S.g_team_away)
	return ISSRom.u32(rom("tbl_player_data") + team * 4) + ISSRam.b(p + 0x56) * 12


## Player k's row: the eleven at ($118-$158, $28 + 16k), the bench at
## ($20-$60, $48 + 16(k - 11)).
func _row(k: int) -> Array:
	if k < 11:
		return [0x118, 0x158, k * 16 + 0x28]
	return [0x20, 0x60, (k - 11) * 16 + 0x48]


func screen_edit_player() -> void:
	set_w(0x1786, 0x7B if w(S.g_sound_disabled) == 0x19 else 0x4D)
	var side := _side()
	if side != w(S.g_left_goal_team):
		m.rect_mirror(0x88, 0xD8, 0x18, 0x78)
	var team := w(S.g_team_home if side == 0 else S.g_team_away)
	var buf := l(S.g_unpack_buffer)
	m.unpack(6, 2, buf)
	m.vram_dma(w(S.g_stadium_vram) + 0x65A0, buf + team * 0xC0, 0xC0)
	m.unpack(6, 1, buf)
	m.vram_dma(w(S.g_stadium_vram) + 0x6660, buf + team * 0x200, 0x200)
	side_icon(side, 0x70, 0x80, 8, 0x18)
	set_l(0x1770, buf)
	set_l(S.g_unpack_buffer, m.unpack(4, 35, buf))
	set_w(0x1782, m.load_tiles(4, 32))
	set_w(0x1774, m.load_tiles(4, 33))
	for k in 20:
		var r := _row(k)
		m.text_draw_field(r[0], r[1], r[2], player_name(side, _p(k)))
	if side != 0:
		for i in 5:
			set_w(0x7C6 + 2 * i, ISSRom.u16(rom("tbl_away_side_colours") + 2 * i))
		set_w(0x1548, 1)
	menu_func_04AC80()
	# The figure's kit on palette line 0 (the side's kit, or its own colours
	# from the team colours screen: g_kit 2).
	var kit := w(S.g_kit_home if side == 0 else S.g_kit_away)
	var words := []
	if kit == 2:
		for i in 16:
			words.append(w((0x185A if side == 0 else 0x18E2) + 2 * i))
	else:
		var pal := ISSRom.res(6, 13 if kit & 1 else 12)
		for i in 16:
			words.append((pal[team * 32 + 2 * i] << 8) | pal[team * 32 + 2 * i + 1])
	for i in 16:
		set_w(S.g_palette_target + 2 * i, words[i])
	set_w(S.g_referee + 0x86, 0)
	m.pitch_place(0x70, 0x18, side)
	set_w(0x1776, 0)
	set_w(0x1778, 0)
	set_w(0x177E, 0)
	set_w(0x1780, 0)
	set_w(S.g_plane_b_hscroll, 0x60)
	_fig = null
	menu_state_0498AE(spawn(Callable()))
	screen_edit_player_select(spawn(Callable()))


## The figure of player k: a goalkeeper running (keeper_run, action 6 of the
## keeper set), anyone else standing (player_update), in the side's kit.
func _figure(k: int) -> void:
	var p := _p(k)
	ISSRam.set_b(S.g_referee + 0x63, ISSRam.b(p + NUMBER))
	ISSRam.set_b(S.g_referee + 0x64, ISSRam.b(p + 0x64))
	ISSRam.set_b(S.g_referee + 0x56, ISSRam.b(p + 0x56))
	if _fig != null:
		_fig.queue_free()
	var keeper := ISSRam.b(p + POSITION) == KEEPER
	_fig = ISSKeeperSprite.new() if keeper else ISSPlayerSprite.new()
	m.figures.add_child(_fig)
	var words := []
	for i in 16:
		words.append(w(S.g_palette_target + 2 * i))
	_fig.set_kit_words(words)
	if not keeper:
		var team := w(S.g_team_home if _side() == 0 else S.g_team_away)
		var kit := w(S.g_kit_home if _side() == 0 else S.g_kit_away)
		_fig.set_look(team, kit & 1 == 1, ISSRam.b(p + NUMBER), ISSRam.b(p + 0x64))
	_pose()


## The figure stands at obj_x $88, obj_y $158 of the referee object, which
## scrolls with plane B; facing from menu_state_0498AE_1.
func _pose() -> void:
	if _fig == null:
		return
	_fig.set_palette_cram(m.vdp.cram)
	_fig.position = Vector2(0x89 - sw(S.g_plane_b_hscroll), 0xAC)
	if _fig is ISSKeeperSprite:
		_fig.set_pose(6, 0, w(S.g_referee + 0x86), false)
	else:
		_fig.set_pose(ISSFootballer.A_READY, 0, w(S.g_referee + 0x86), false)


## The attribute bars of a record at a (style 1 above the player's record,
## 2 below it).
func _bars(a: int, base: int) -> void:
	for i in 9:
		var v := ISSRam.b(a + i)
		var b := ISSRom.u8(base + i)
		var style := 1 if v > b else (2 if v < b else 0)
		m.bar_draw(0xD0, i * 8 + 0x88, style, v)


## Three digits at x $88-$98, row y.
func _number(v: int, y: int) -> void:
	for d in [2, 1, 0]:
		m.rect_fill_tiles(d * 8 + 0x88, d * 8 + 0x90, y, y + 8, tiles() + 0x323 + v % 10)
		v /= 10


## menu_func_04AC80: the team's points, all and left.
func menu_func_04AC80() -> void:
	_number(w(_points_all()), 0xB8)
	_number(w(_points_left()), 0xC0)


# --------------------------------------------------------------------------
# The list's marks and faces, the bars behind the names, the figure turning.

func _marks(k: int, x: int, y: int) -> void:
	var p := _p(k)
	var t: int
	if w(0x177E) == 0:
		t = tiles() + 0x242
		if k < 11 and ISSRam.b(p + 0x55) != 0:
			t += 0xA
		else:
			t += (ISSRam.b(p + 0x51) & 0x7F) * 2
	else:
		t = tiles() + (0x1F2 if _side() == 0 else 0x21A) + (ISSRam.b(p + NUMBER) - 1) * 2
	m.rect_fill_tiles(x, x + 8, y, y + 16, t)
	var st := player_status(_side(), p)
	if w(0x1780) == 0 and st != 4:
		m.face_draw(x + 8, y, ISSRam.b(p + 0x57))
	else:
		m.rect_fill_tiles(x + 8, x + 0x18, y, y + 16, tiles() + 0x26F + st * 4)


func menu_state_0498AE(o: ISSMenu.Obj) -> void:
	o.update = menu_state_0498AE_1
	for k in 11:
		_marks(k, 0x100, k * 16 + 0x28)
	for k in range(11, 20):
		_marks(k, 8, (k - 11) * 16 + 0x48)
	menu_state_0498AE_1(o)


func menu_state_0498AE_1(o: ISSMenu.Obj) -> void:
	var p := w(S.g_pad_pressed_home)
	if p & 0x200:
		set_w(0x177E, w(0x177E) ^ 1)
		o.update = menu_state_0498AE
	if p & 0x100:
		set_w(0x1780, w(0x1780) ^ 1)
		o.update = menu_state_0498AE
	if p & PAD_A:
		if w(0x177E) == 0:
			set_w(0x177E, 1)
		else:
			set_w(0x177E, 0)
			set_w(0x1780, w(0x1780) ^ 1)
		o.update = menu_state_0498AE
	# The figure turns round: a quarter turn each way with pauses facing
	# the screen (facing $20).
	var f := maxi((w(S.g_frame_counter) & 0x7F) - 0x20, 0)
	if f > 0x20:
		f = maxi(f - 0x40, 0) + 0x20
	set_w(S.g_referee + 0x86, f)
	_pose()
	m.anim_tiles()
	for k in 20:
		var t := (w(0x1782) >> 5) + ISSRam.b(_p(k) + POSITION) * 8
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


# --------------------------------------------------------------------------
# The cursor on the eleven ($1776) and on the bench ($1778).

func screen_edit_player_select(o: ISSMenu.Obj) -> void:
	o.update = screen_edit_player_select_1
	o.set_w(T, 0)
	var k := w(0x1776)
	_figure(k)
	_bars(_p(k) + RECORD, _base(_p(k)))
	screen_edit_player_select_1(o)


func screen_edit_player_select_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0x60):
		if pressed_home(PAD_B):
			o.update = menu_state_049CE6
		if pressed_home(PAD_UP):
			if w(0x1776) == 0:
				o.update = menu_state_049CE6
			else:
				add_w(0x1776, -1)
				o.update = screen_edit_player_select
			_sfx()
		if pressed_home(PAD_DOWN):
			if w(0x1776) == 10:
				o.update = menu_state_049CE6
			else:
				add_w(0x1776, 1)
				o.update = screen_edit_player_select
			_sfx()
		if pressed_home(PAD_LEFT):
			o.update = menu_state_04A2C6
			_sfx()
		if pressed_home(PAD_C):
			set_w(0x177A, w(0x1776))
			o.update = menu_func_04A4D6
			set_w(0x177C, 0)
			m.play_sfx(95)
	o.add_w(T, 1)
	m.cursor_draw_large(_side(), 0x118, 0x158, w(0x1776) * 16 + 0x28)
	var pl := _p(w(0x1776))
	m.icon_draw_small(0, ISSRam.w(pl + 0x10) - 4, ISSRam.w(pl + 0x14) + 4)


func menu_state_04A2C6(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04A2C6_1
	o.set_w(T, 0)
	var k := w(0x1778) + 11
	_figure(k)
	_bars(_p(k) + RECORD, _base(_p(k)))
	menu_state_04A2C6_1(o)


func menu_state_04A2C6_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0):
		if pressed_home(PAD_B | PAD_RIGHT):
			o.update = screen_edit_player_select
			_sfx()
		if pressed_home(PAD_UP):
			set_w(0x1778, 8 if w(0x1778) == 0 else w(0x1778) - 1)
			o.update = menu_state_04A2C6
			_sfx()
		if pressed_home(PAD_DOWN):
			set_w(0x1778, 0 if w(0x1778) == 8 else w(0x1778) + 1)
			o.update = menu_state_04A2C6
			_sfx()
		if pressed_home(PAD_C):
			set_w(0x177A, w(0x1778) + 11)
			o.update = menu_func_04A4D6
			set_w(0x177C, 0)
			m.play_sfx(95)
	o.add_w(T, 1)
	m.cursor_draw_large(_side(), 0x20, 0x60, w(0x1778) * 16 + 0x48)


# --------------------------------------------------------------------------
# The marks above: RESET ($128) and EXIT ($140); a third mark at $110 is
# never reached (menu_state_049E00_2).

func menu_state_049CE6(o: ISSMenu.Obj) -> void:
	o.update = menu_state_049CE6_1
	menu_state_049CE6_1(o)


func menu_state_049CE6_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0x60):
		if pressed_home(PAD_C):
			ISSModes.prematch_return()
			set_l(S.g_next_state, ISSMenu.STATE_MENU)
			m.fade_out_start()
			m.play_sfx(95)
		if pressed_home(PAD_LEFT):
			o.update = menu_state_049E00
			_sfx()
		if pressed_home(PAD_RIGHT):
			o.update = menu_state_049E00
			_sfx()
		_to_list(o)
	_top_cursor(o, 0x140, 0x158)


func _to_list(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_DOWN):
		set_w(0x1776, 0)
		o.update = screen_edit_player_select
		_sfx()
	if pressed_home(PAD_UP):
		set_w(0x1776, 10)
		o.update = screen_edit_player_select
		_sfx()


func _top_cursor(o: ISSMenu.Obj, x0: int, x1: int) -> void:
	o.add_w(T, 1)
	m.cursor_draw(_side(), x0, x1, 8)


## RESET: every player's record back as it was, and the team's points.
func menu_state_049E00(o: ISSMenu.Obj) -> void:
	o.update = menu_state_049E00_1
	menu_state_049E00_1(o)


func menu_state_049E00_1(o: ISSMenu.Obj) -> void:
	if not scrolling(0x60):
		if pressed_home(PAD_B | PAD_RIGHT):
			o.update = menu_state_049CE6
			_sfx()
		if pressed_home(PAD_LEFT):
			o.update = menu_state_049CE6
			_sfx()
		_to_list(o)
		if pressed_home(PAD_C):
			for k in 20:
				var p := _p(k)
				var b := _base(p)
				for i in 12:
					ISSRam.set_b(p + RECORD + i, ISSRom.u8(b + i))
			ISSModes.edit_points_reset(_side())
			menu_func_04AC80()
			o.update = screen_edit_player_select
			m.play_sfx(95)
	_top_cursor(o, 0x128, 0x140)


func menu_state_049E00_2(o: ISSMenu.Obj) -> void:
	if not scrolling(0x60):
		if pressed_home(PAD_B | PAD_LEFT):
			o.update = menu_state_049CE6
			_sfx()
		if pressed_home(PAD_RIGHT):
			o.update = menu_state_049E00
			_sfx()
		_to_list(o)
	_top_cursor(o, 0x110, 0x128)


# --------------------------------------------------------------------------
# Editing player $177A: the attribute cursor ($177C) and the arrows.

## menu_func_04A4D6: the points left and a working copy of the player's
## record in the referee object; his row lit.
func menu_func_04A4D6(o: ISSMenu.Obj) -> void:
	set_w(0x1784, w(_points_left()))
	var p := _p(w(0x177A))
	for i in 14:
		ISSRam.set_b(S.g_referee + 0x56 + i, ISSRam.b(p + 0x56 + i))
	var r := _row(w(0x177A))
	m.rect_highlight(r[0], r[1], r[2], r[2] + 16)
	menu_state_04A54C(o)


func _work() -> int:
	return S.g_referee + RECORD


func _work_base() -> int:
	return _base(S.g_referee)


func menu_state_04A54C(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04A54C_1
	_number(w(0x1784), 0xC0)
	_bars(_work(), _work_base())
	menu_state_04A54C_1(o)


func menu_state_04A54C_1(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_B):
		o.update = menu_state_04A7FC
	if pressed_home(PAD_UP):
		if w(0x177C) > 0:
			add_w(0x177C, -1)
		else:
			o.update = menu_state_04A7FC
		_sfx()
	if pressed_home(PAD_DOWN):
		if w(0x177C) < 8:
			add_w(0x177C, 1)
		else:
			o.update = menu_state_04A7FC
		_sfx()
	var i := w(0x177C)
	var a := _work() + i
	var base := ISSRom.u8(_work_base() + i)
	var cost := ISSRom.u8(rom("tbl_edit_costs") + i)
	if pressed_home(PAD_RIGHT) and ISSRam.b(a) < 9:
		if base > ISSRam.b(a):
			ISSRam.set_b(a, ISSRam.b(a) + 1)
		elif w(0x1784) - cost >= 0:
			set_w(0x1784, w(0x1784) - cost)
			ISSRam.set_b(a, ISSRam.b(a) + 1)
		o.update = menu_state_04A54C
		_sfx()
	if pressed_home(PAD_LEFT) and ISSRam.b(a) != 0:
		if base < ISSRam.b(a):
			set_w(0x1784, w(0x1784) + cost)
		ISSRam.set_b(a, ISSRam.b(a) - 1)
		o.update = menu_state_04A54C
		_sfx()
	o.add_w(T, 1)
	if o.update == menu_state_04A54C_1:
		m.rect_flash(0x68, 0xF8, 0x78, 0xD8)
	else:
		m.rect_unhighlight(0x68, 0xF8, 0x78, 0xD8)
	m.icon_draw_small(1, 0xCA, w(0x177C) * 8 + 0x88)
	m.icon_draw_small(2, 0xE2, w(0x177C) * 8 + 0x88)


## Back to the list the player came from.
func _done(o: ISSMenu.Obj) -> void:
	var r := _row(w(0x177A))
	m.rect_unhighlight(r[0], r[1], r[2], r[2] + 16)
	o.update = screen_edit_player_select if w(0x177A) < 11 else menu_state_04A2C6
	m.play_sfx(95)


## Up / down from the buttons: the last or first attribute.
func _to_attributes(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_UP):
		set_w(0x177C, 8)
		o.update = menu_state_04A54C
		_sfx()
	if pressed_home(PAD_DOWN):
		set_w(0x177C, 0)
		o.update = menu_state_04A54C
		_sfx()


## OK ($D8): the copy and the points kept.
func menu_state_04A7FC(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04A7FC_1
	o.set_w(T, 0)
	menu_state_04A7FC_1(o)


func menu_state_04A7FC_1(o: ISSMenu.Obj) -> void:
	if pressed_home(PAD_C):
		set_w(_points_left(), w(0x1784))
		var p := _p(w(0x177A))
		for i in 9:
			ISSRam.set_b(p + RECORD + i, ISSRam.b(_work() + i))
		_done(o)
	_to_attributes(o)
	if pressed_home(PAD_LEFT):
		o.update = menu_state_04A988
		_sfx()
	if pressed_home(PAD_RIGHT):
		o.update = menu_state_04AB24
		_sfx()
	o.add_w(T, 1)
	m.cursor_draw(_side(), 0xD8, 0xE8, 0x80)


## CANCEL ($B8): nothing kept.
func menu_state_04A988(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04A988_1
	o.set_w(T, 0)
	menu_state_04A988_1(o)


func menu_state_04A988_1(o: ISSMenu.Obj) -> void:
	_to_attributes(o)
	if pressed_home(PAD_LEFT):
		o.update = menu_state_04AB24
		_sfx()
	if pressed_home(PAD_B | PAD_RIGHT):
		o.update = menu_state_04A7FC
		_sfx()
	if pressed_home(PAD_C):
		_number(w(_points_left()), 0xC0)
		_done(o)
	o.add_w(T, 1)
	m.cursor_draw(_side(), 0xB8, 0xD8, 0x80)


## RESET ($A0): the copy back to the record, the points spent returned.
func menu_state_04AB24(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04AB24_1
	o.set_w(T, 0)
	menu_state_04AB24_1(o)


func menu_state_04AB24_1(o: ISSMenu.Obj) -> void:
	_to_attributes(o)
	if pressed_home(PAD_B | PAD_LEFT):
		o.update = menu_state_04A7FC
		_sfx()
	if pressed_home(PAD_RIGHT):
		o.update = menu_state_04A988
		_sfx()
	if pressed_home(PAD_C):
		var base := _work_base()
		for i in 9:
			var d := ISSRam.b(_work() + i) - ISSRom.u8(base + i)
			if d >= 0:
				add_w(0x1784, ISSRom.u8(rom("tbl_edit_costs") + i) * d)
			ISSRam.set_b(_work() + i, ISSRom.u8(base + i))
		o.update = menu_state_04A54C
		m.play_sfx(95)
	o.add_w(T, 1)
	m.cursor_draw(_side(), 0xA0, 0xB8, 0x80)
