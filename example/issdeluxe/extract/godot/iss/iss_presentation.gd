class_name ISSPresentation
extends RefCounted
## state_screen ($01FFF4): the full-screen presentations between the menus
## and the match, chosen by $1730: 0 the teams on the stadium's big screen
## and the toss before a match (pres_prematch), 1 a goal replayed on
## the big screen (pres_goal), 2 the trophy (pres_trophy).
## state_screen_1 builds the stadium as the match does (its tiles, the
## stand and crowd map streamed into plane B a row at a time as the screen
## scrolls, the sky on plane A); each frame (state_screen_frame_1) the
## new rows come in, the crowd and the lights are animated and the pads
## read. The presentation's own objects are the match's (ISSObjects: the
## players, the referee, the ball and the coin where the game keeps them in
## RAM) and the crowd's flags and the confetti (menu objects).

const S := preload("res://iss/iss_sym.gd")

const X := ISSObjects.X
const Y := ISSObjects.Y
const Z := ISSObjects.Z
const ATTR := ISSObjects.ATTR
const INPUT := ISSObjects.INPUT
const TEAM := ISSObjects.TEAM
const FACING := ISSObjects.FACING
const HEADING := ISSObjects.HEADING
const ACTION := ISSObjects.ACTION
const ANIM_FRAME := ISSObjects.ANIM_FRAME
const TIMER := ISSObjects.TIMER
const DISTANCE := ISSObjects.DISTANCE
const OWNER := ISSObjects.OWNER
const STATE := ISSObjects.STATE
const BALL_DIST := ISSObjects.BALL_DIST
## Object fields: the tiles' VRAM address and a flag the toss keeps.
const VRAM := 0x78
const CHOSEN := 0x8C

var m: ISSMenu
var objects: ISSObjects


func _init(menu: ISSMenu) -> void:
	m = menu


func w(a: int) -> int:
	return ISSRam.w(a)


func sw(a: int) -> int:
	return ISSRam.sw(a)


func l(a: int) -> int:
	return ISSRam.l(a)


func set_w(a: int, v: int) -> void:
	ISSRam.set_w(a, v)


func set_l(a: int, v: int) -> void:
	ISSRam.set_l(a, v & 0xFFFFFFFF)


func add_w(a: int, v: int) -> void:
	ISSRam.add_w(a, v)


func add_l(a: int, v: int) -> void:
	set_l(a, l(a) + v)


func rom(name: String) -> int:
	return ISSRom.addr(name)


## Add v to every word from a to end (a map's tiles to their VRAM place).
func _add(a: int, end: int, v: int) -> void:
	a &= 0xFFFF
	while a < (end & 0xFFFF):
		ISSRam.set_w(a, ISSRam.w(a) + v)
		a += 2


## Unpack (g, e) into the unpack buffer, which advances past it; where.
func _keep(g: int, e: int) -> int:
	var buf := l(S.g_unpack_buffer)
	set_l(S.g_unpack_buffer, m.unpack(g, e, buf))
	return buf


# --------------------------------------------------------------------------
# state_screen_1 and the frame.

## state_screen_1: the stadium (group 18 entry 7's tiles at g_stadium_vram,
## then the stadium's own, group 15), the stand map and its metatiles (the
## scoreboard's clock patched with the minutes played), the palettes, the
## sky (group 16, the weather's) on plane A, the crowd's animation frames
## at $1736; then the presentation's handler and the 30 rows of plane B
## from where it left the scroll.
func state_screen_1() -> void:
	objects = ISSObjects.new(m)
	set_w(S.g_pad_pressed_home, 0)
	set_w(S.g_pad_pressed_away, 0)
	set_w(S.g_pad_pressed_any, 0)
	set_w(0x1548, 0)
	set_w(S.g_stadium_vram, m.load_tiles(18, 7))
	m.load_tiles(15, 4 + w(S.g_stadium))
	var wet := 0 if w(S.g_weather) == 1 else 3
	set_l(S.g_pitch_map, _keep(18, w(0x1630) + wet))
	set_l(S.g_pitch_metatiles, _keep(18, 6))
	_clock()
	m.unpack(16, 9, 0xFF07A6)
	m.unpack(18, 8 + w(0x1630) + wet, 0xFF0000 | S.g_palette_target)
	var buf := l(S.g_unpack_buffer)
	var end := m.unpack(16, w(S.g_weather), buf)
	_add(buf, end, (w(S.g_stadium_vram) >> 5) | 0x8000)
	m.vram_dma(0x2000, buf, end - buf)
	set_l(0x1736, _keep(4, 9))
	set_w(0x172E, w(0x1730))
	match w(0x172E):
		0:
			pres_prematch()
		1:
			pres_goal()
		_:
			pres_trophy()
	var d7 := w(S.g_plane_b_vscroll) >> 3
	for i in 30:
		state_screen_load_row(d7 + i)


## The scoreboard's minutes (metatile $18B: tens at its left, units at its
## right, top and bottom halves): the halves' lengths (g_game_time * 2 + 1
## minutes, a minute more in extra time) less what g_match_clock and
## $17CD / $17CE (tens and units of seconds) still show.
func _clock() -> void:
	var a := (l(S.g_pitch_metatiles) & 0xFFFF) + 0xC58
	var d5 := 0
	var half := w(S.g_half)
	for d1 in range(half, -1, -1):
		var d0 := w(S.g_game_time)
		if half >= 2 and d1 < 2:
			d0 += 1
		d5 += d0 * 2 + 1
	d5 = (d5 & 0xFFFF) * 60
	d5 -= ISSRam.b(S.g_match_clock) * 60
	d5 -= ISSRam.b(0x17CD) * 10
	d5 -= ISSRam.b(0x17CE)
	d5 &= 0xFFFFFFFF
	var minutes := (d5 / 60) & 0xFFFF
	if minutes >= 0x8000:
		minutes -= 0x10000
	minutes &= 0xFFFFFFFF
	var tens := (minutes / 10) & 0xFFFF
	var units := (minutes % 10) & 0xFFFF
	ISSRam.set_w(a, tens * 2 + 0x4152)
	ISSRam.set_w(a + 4, tens * 2 + 0x4153)
	ISSRam.set_w(a + 2, units * 2 + 0x413E)
	ISSRam.set_w(a + 6, units * 2 + 0x413F)


## state_screen_load_row: plane B's row d7 (& 31) from the stand map's row d7:
## 17 metatiles, the top or bottom half of each, + the stadium's tiles with
## priority, through $878.
func state_screen_load_row(d7: int) -> void:
	var map := l(S.g_pitch_map) & 0xFFFF
	var a0 := map + (d7 & 0xFFFE) * ISSRam.sw(map) + 4
	var a2 := (l(S.g_pitch_metatiles) & 0xFFFF) + (d7 & 1) * 4
	var base := (w(S.g_stadium_vram) >> 5) | 0x8000
	for i in 17:
		var t := ISSRam.w(a0 + i * 2) * 8
		ISSRam.set_w(0x878 + i * 4, ISSRam.w(a2 + t) + base)
		ISSRam.set_w(0x87A + i * 4, ISSRam.w(a2 + t + 2) + base)
	m.vram_dma((d7 & 0x1F) << 7, 0xFF0878, 0x44)


## state_screen_frame_1: the rows scrolled in, the crowd, the lights and
## the weather's tiles; while the picture is up the pads' edges (no
## auto-repeat; $1548 swaps or merges the sides as in the menus).
func state_screen_frame_1() -> void:
	state_screen_frame_2()
	state_screen_frame_4()
	state_screen_frame_3()
	state_screen_frame_5()
	if w(S.g_frame_state) != 2:
		return
	var home_n := w(S.g_pads_home)
	var away_n := w(S.g_pads_away)
	var d0 := m._pads_or(0, home_n)
	var d1 := m._pads_or(home_n, away_n)
	var d2 := m._pads_or(0, 8) if w(0x153E) == 0 else d0 | d1
	match w(0x1548):
		1:
			var t := d0
			d0 = d1
			d1 = t
		2:
			d0 = d2
		3:
			d1 = d2
	for e in [[S.g_pad_held_home, S.g_pad_pressed_home, d0], [S.g_pad_held_away, S.g_pad_pressed_away, d1],
			[S.g_pad_held_any, S.g_pad_pressed_any, d2]]:
		var held: int = e[0]
		var d: int = e[2]
		set_w(held, w(held) & d)
		var p := d & ~w(held) & 0xFFFF
		set_w(e[1], p)
		set_w(held, w(held) | p)


## state_screen_frame_2: when plane B's scroll crosses a row, the row that
## comes into view (the top one going up, 28 rows down going down).
func state_screen_frame_2() -> void:
	var d7 := w(S.g_plane_b_vscroll) >> 3
	var d0 := (w(0x862) >> 3) - d7
	if d0 != 0:
		if d0 < 0:
			d7 += 0x1C
		state_screen_load_row(d7)
	set_w(0x862, w(S.g_plane_b_vscroll))


## state_screen_frame_3: the floodlights' tile (group 4 entry 3) flickers
## between its two frames.
func state_screen_frame_3() -> void:
	var src := ISSRom.res(4, 3)
	m.vdp.dma(w(S.g_stadium_vram) + 0x2DE0, src, (w(S.g_frame_counter) & 1) << 5, 0x20)


## state_screen_frame_4: every other frame the crowd's next frame (12 tiles
## of the set at $1736, state_screen_frame_4_data's source and place).
func state_screen_frame_4() -> void:
	var f := w(S.g_frame_counter)
	if f & 1:
		return
	var t := rom("state_screen_frame_4_data") + ((f & 0x3E) << 1)
	m.vram_dma(w(S.g_stadium_vram) + 0x2E00 + ISSRom.u16(t + 2), l(0x1736) + ISSRom.u16(t), 0x180)


## state_screen_frame_5: the weather on the stand: in sunshine (0) two
## strips of group 4 entry 7 in turn every 4 frames; in rain or snow (2+)
## two of entry 8 on alternate frames; nothing when it is cloudy (1).
func state_screen_frame_5() -> void:
	var weather := w(S.g_weather)
	var f := w(S.g_frame_counter)
	var at := w(S.g_stadium_vram)
	if weather == 1:
		return
	if weather == 0:
		if f & 3:
			return
		var src := ISSRom.res(4, 7)
		if f & 4 == 0:
			m.vdp.dma(at + 0x2060, src, (f & 0x78) << 3, 0x40)
		else:
			m.vdp.dma(at + 0x20A0, src, ((f + 0x40) & 0x78) << 3, 0x40)
		return
	var rain := ISSRom.res(4, 8)
	if f & 1 == 0:
		m.vdp.dma(at + 0x2060, rain, (f & 0xE) << 5, 0x20)
	else:
		m.vdp.dma(at + 0x20A0, rain, ((f + 8) & 0xE) << 5, 0x20)


## A side's kit (16 colours) to RAM at dst: the edited one ($185A / $18E2)
## for kit 2, else group 6 entry 12 (first) or 13 (second) by team.
func _kit(side: int, dst: int) -> void:
	var kit := w(S.g_kit_home if side == 0 else S.g_kit_away)
	if kit == 2:
		ISSRam.copy(dst, 0x185A if side == 0 else 0x18E2, 0x20)
		return
	var data := ISSRom.res(6, 12 if kit == 0 else 13)
	var team := w(S.g_team_home if side == 0 else S.g_team_away)
	for i in 16:
		set_w(dst + 2 * i, (data[team * 32 + 2 * i] << 8) | data[team * 32 + 2 * i + 1])


## Sprites from a list (a count - 1, then y, size, tile, x words) at
## (d5, d6), the tiles after base's.
func _list(a4: int, base: int, d5: int, d6: int) -> void:
	var n := ISSRom.u16(a4) + 1
	a4 += 2
	for i in n:
		m.sprite(d6 + ISSRom.s16(a4), ISSRom.u16(a4 + 2), (base >> 5) + ISSRom.u16(a4 + 4), d5 + ISSRom.s16(a4 + 6))
		a4 += 8


## pres_prematch_sprites: a list with the tiles at $173A.
func pres_prematch_sprites(a4: int, d5: int, d6: int) -> void:
	_list(a4, w(0x173A), d5, d6)


# --------------------------------------------------------------------------
# 0: before the match (pres_prematch).

## pres_prematch: the sky at the top; down the stand the crowd's 13
## flags, and on the big screen the two captains either side of the referee
## and the ball (plane A at column 8: the pitch, the stadium's group entry
## 3 with its transparent pixels made colour 14) and the toss's picture at
## column 40 (group 19); the teams' names and flags and the toss's words.
func pres_prematch() -> void:
	set_l(S.g_plane_a_hscroll, 0)
	set_l(S.g_plane_a_vscroll, 0)
	ISSRam.set_w(S.g_ball + VRAM, m.load_tiles(4, 0))
	var b := objects.actor(S.g_ball)
	objects.ball = b
	objects.link(b)
	b.set_w(Z, 0)
	b.set_w(X, 0x90)
	b.set_w(Y, 0x500)
	b.set_w(ATTR, 0x6000)
	b.think = objects.obj_steer_idle
	b.set_w(INPUT, 0)
	b.set_w(FACING, 0x10)
	b.set_b(STATE, 2)
	b.set_l(OWNER, 0xFF0000 | S.g_director)
	b.set_w(TEAM, 0xFFFF)
	objects.give_figure(b, "ball")
	objects.ball_update(b)
	var kit := ISSRom.res(4, 38)
	var k := w(S.g_officials_kit) * 16
	for i in 8:
		set_w(0x796 + 2 * i, (kit[k + 2 * i] << 8) | kit[k + 2 * i + 1])
	var r := objects.actor(S.g_referee)
	objects.referee = r
	objects.link(r)
	r.set_w(Z, 0)
	r.set_w(X, 0x80)
	r.set_w(Y, 0x4E0)
	r.set_w(ATTR, 0x4000)
	r.think = objects.referee_think_idle
	r.set_w(FACING, 0x20)
	r.set_w(INPUT, 0)
	r.set_w(TEAM, 0xFFFF)
	objects.give_figure(r, "referee")
	objects.referee_stand(r)
	# The coin, held by the referee (g_director, the sparkle's tiles).
	var coin := objects.actor(S.g_director)
	objects.link(coin)
	coin.think = Callable()
	coin.set_w(VRAM, m.load_tiles(4, 14))
	coin.draw = objects.particle_draw
	coin.set_w(ACTION, 6)
	coin.set_w(Y, r.w(Y) - 1)
	coin.set_w(X, r.w(X))
	coin.set_w(Z, 0x18)
	objects.coin_hold(coin)
	for i in 4:
		set_w(S.g_npc_vram_slots + 2 * i, w(S.g_unpack_vram))
		add_w(S.g_unpack_vram, 0x2E0)
	# The captains: each side's first player object, standing (they are
	# never near the ball).
	for side in 2:
		var p := objects.actor(S.g_team_home_players if side == 0 else S.g_team_away_players)
		objects.link(p)
		p.set_w(Z, 0)
		p.set_w(X, 0x68 if side == 0 else 0xB8)
		p.set_w(Y, 0x500)
		p.set_w(FACING, 0x10 if side == 0 else 0x30)
		p.set_w(HEADING, p.w(FACING))
		p.set_w(ATTR, 0x20 * side)
		p.think = objects.player_think_idle
		p.set_w(INPUT, 0)
		p.set_w(BALL_DIST, 0x7FFF)
		objects.give_figure(p, "player", w(S.g_team_home if side == 0 else S.g_team_away))
		objects.keeper_start_stand_0051B4(p)
	# The toss's picture (group 19) at column 40 of plane A.
	set_w(S.g_overlay_vram, m.load_tiles(19, 1))
	var buf := l(S.g_unpack_buffer)
	var end := m.unpack(19, 0, buf)
	_add(buf, end, w(S.g_overlay_vram) >> 5)
	for row in 16:
		m.vram_dma(0x2000 + 0x350 + (row << 7), buf + 0x90 + row * 0x24, 0x24)
	# The pitch the cameras show (the stadium's group, entries 3 and, in
	# bad weather, 5 over its end) at column 8, colour 0 made 14.
	var g := 7 + w(S.g_stadium)
	m.unpack(g, 3, buf)
	if w(S.g_weather) != 0:
		m.unpack(g, 5, buf + 0x1DC0)
	for i in 0x2001:
		var a := (buf & 0xFFFF) + i
		var v := ISSRam.b(a)
		if v & 0xF0 == 0:
			v |= 0xE0
		if v & 0x0F == 0:
			v |= 0x0E
		ISSRam.set_b(a, v)
	var at := w(S.g_unpack_vram)
	m.vram_dma(at, buf, 0x2000)
	add_w(S.g_unpack_vram, 0x2000)
	end = m.unpack(g, 0, buf)
	_add(buf, end, at >> 5)
	for row in 16:
		m.vram_dma(0x2000 + 0x310 + (row << 7), buf + row * 0x24, 0x24)
	m.unpack(g, 6 + w(S.g_weather), 0xFF07B6)
	set_w(0x7D2, w(0x7B6))
	set_w(0x173A, m.load_tiles(4, 21))
	set_w(0x173C, m.load_tiles(4, 19))
	# The teams' names (group 6 entry 1, 16 tiles each) and flags (entry 2,
	# 6 tiles each) at $173E / $1740.
	end = m.unpack(6, 1, buf)
	for side in 2:
		at = w(S.g_unpack_vram)
		set_w(0x173E + 2 * side, at)
		m.vram_dma(at, buf + w(S.g_team_home if side == 0 else S.g_team_away) * 0x200, 0x200)
		add_w(S.g_unpack_vram, 0x2C0)
	m.unpack(6, 2, buf)
	for side in 2:
		var team := w(S.g_team_home if side == 0 else S.g_team_away)
		m.vram_dma(w(0x173E + 2 * side) + 0x200, buf + team * 0xC0, 0xC0)
	# The crowd's flags.
	var a4 := rom("pres_prematch_data")
	for i in 13:
		var o := m.obj_alloc()
		o.set_w(X, ISSRom.u16(a4))
		o.set_w(Y, ISSRom.u16(a4 + 2))
		o.set_w(Z, 0)
		o.set_w(VRAM, w(0x173C))
		o.draw = objects.flag_fans_draw
		o.think = Callable()
		o.set_w(INPUT, 0)
		o.set_w(FACING, 0)
		var first := ISSRom.u16(a4 + 4) != 0
		var second := ISSRom.u16(a4 + 6) != 0
		if first:
			if second:
				objects.flag_fan_raise(o)
			else:
				objects.flag_fan_hold(o)
		elif second:
			objects.flag_fan_wave_2(o)
		else:
			objects.flag_fan_wave(o)
		a4 += 8
	var c := m.obj_alloc()
	c.draw = Callable()
	c.think = Callable()
	c.update = pres_prematch_1
	c.set_w(TEAM, 0)


## pres_prematch_1: the music (song $19), the crowd (SFX 98 and 80).
func pres_prematch_1(o: ISSMenu.Obj) -> void:
	o.update = pres_prematch_2
	o.set_w(DISTANCE, 0)
	m.menu_music(0x19)
	m.play_sfx(98)
	set_w(0x17D8, 1)
	m.play_sfx(80)
	pres_prematch_2(o)


## pres_prematch_2: after 80 frames the view goes down the stand 2
## pixels a frame to the big screen ($220), the kits' colours coming in
## half-way ($150); Start before then skips to the match. The names slide
## in from the sides, stop either side of VS, and go on out.
func pres_prematch_2(o: ISSMenu.Obj) -> void:
	o.add_w(DISTANCE, 1)
	if o.sw(DISTANCE) > 0x50:
		if w(S.g_plane_a_vscroll) == 0x220:
			o.update = pres_prematch_3
		else:
			add_w(S.g_plane_a_vscroll, 2)
			add_w(S.g_plane_b_vscroll, 2)
			if w(S.g_plane_a_vscroll) == 0x150:
				_kit(0, S.g_palette_target)
				_kit(1, 0x776)
				m.cram_dma(0, S.g_palette_target, 0x40)
	if w(S.g_pad_pressed_any) & 0x80 and sw(S.g_plane_a_vscroll) < 0x150:
		set_l(S.g_next_state, ISSMenu.STATE_MATCH)
		m.fade_out_start()
	var d5 := o.sw(DISTANCE) * 8 - 0x40
	if d5 > 0xC4:
		d5 = maxi(0, d5 - 0x24C) + 0xC4
	d5 = mini(d5, 0x140)
	if d5 == 0xC4:
		_list_n(rom("pres_prematch_2_data3"), 1, w(0x173A), 0x80, 0x40)
	_list_n(rom("pres_prematch_2_data2"), 3, w(0x1740), d5, 0x40)
	_list_n(rom("pres_prematch_2_data"), 3, w(0x173E), 0x100 - d5, 0x40)


## n sprites of four words (no count word) at (x0 + x, y0 + y).
func _list_n(a4: int, n: int, base: int, x0: int, y0: int) -> void:
	for i in n:
		m.sprite(y0 + ISSRom.s16(a4), ISSRom.u16(a4 + 2), (base >> 5) + ISSRom.u16(a4 + 4), x0 + ISSRom.s16(a4 + 6))
		a4 += 8


## The toss's colours: line 0 the officials' kit (group 4 entry 37), line
## 1 the picture's (group 19 entry 2), four fixed ones on line 3; the view
## moved to the toss's picture (the figures off screen).
func _toss_view() -> void:
	var data := ISSRom.res(4, 37)
	var k := w(S.g_officials_kit) * 32
	for i in 16:
		set_w(S.g_palette_target + 2 * i, (data[k + 2 * i] << 8) | data[k + 2 * i + 1])
	m.unpack(19, 2, 0xFF0776)
	set_w(0x7B8, 0x284)
	set_w(0x7BC, 0x040)
	set_w(0x7D2, 0x062)
	set_w(0x7D4, 0x2A6)
	m.cram_dma(0, S.g_palette_target, 0x80)
	set_w(S.g_plane_b_hscroll, 0x200)
	set_w(S.g_plane_a_hscroll, 0x100)


## pres_prematch_3: the home side calls heads or tails (with no human on
## that side any pad does it).
func pres_prematch_3(o: ISSMenu.Obj) -> void:
	o.update = pres_prematch_4
	o.set_w(TEAM, 0)
	o.set_w(CHOSEN, 0)
	o.set_w(ANIM_FRAME, 0)
	_toss_view()
	if w(S.g_pads_home) == 0:
		set_w(0x1548, 2)
		set_w(S.g_pad_held_home, 0xFFFF)
		set_w(S.g_pad_held_away, 0xFFFF)
	pres_prematch_4(o)


## pres_prematch_4: up / down between HEADS and TAILS (SFX 123), C
## calls it (SFX 95); the call blinks for 64 frames.
func pres_prematch_4(o: ISSMenu.Obj) -> void:
	if o.w(CHOSEN) == 0:
		if w(S.g_pad_pressed_home) & 3:
			o.set_w(ANIM_FRAME, o.w(ANIM_FRAME) ^ 1)
			m.play_sfx(123)
		if w(S.g_pad_pressed_home) & 0x20:
			o.set_w(DISTANCE, 0)
			o.set_w(CHOSEN, 1)
			m.play_sfx(95)
	else:
		o.add_w(DISTANCE, 1)
		if o.w(DISTANCE) == 0x40:
			o.update = pres_prematch_5
	var blink := o.w(DISTANCE) & 8 != 0
	if o.w(CHOSEN) == 0 or o.w(ANIM_FRAME) != 0 or blink:
		pres_prematch_sprites(rom("pres_prematch_4_data"), 0x88, 0x40)
	if o.w(CHOSEN) == 0 or o.w(ANIM_FRAME) == 0 or blink:
		pres_prematch_sprites(rom("pres_prematch_4_data2"), 0x88, 0x60)
	pres_prematch_sprites(rom("tbl_toss_cursor_home"), 0x68, o.w(ANIM_FRAME) * 32 + 0x40)


## pres_prematch_5: back to the big screen (the kits' colours, the
## stadium's line 3), the referee tosses the coin.
func pres_prematch_5(o: ISSMenu.Obj) -> void:
	o.update = pres_prematch_6
	o.set_w(DISTANCE, 0)
	m.unpack(7 + w(S.g_stadium), 6 + w(S.g_weather), 0xFF07B6)
	set_w(0x7D2, w(0x7B6))
	_kit(0, S.g_palette_target)
	_kit(1, 0x776)
	m.cram_dma(0, S.g_palette_target, 0x80)
	set_w(S.g_plane_b_hscroll, 0)
	set_w(S.g_plane_a_hscroll, 0)
	objects.referee.update = objects.referee_toss_coin
	objects.actor(S.g_director).update = objects.coin_toss
	pres_prematch_6(o)


## pres_prematch_6: 128 frames of the toss.
func pres_prematch_6(o: ISSMenu.Obj) -> void:
	o.add_w(DISTANCE, 1)
	if o.w(DISTANCE) == 0x80:
		o.update = pres_prematch_7


## pres_prematch_7: how the coin fell (a random bit), shown on the
## toss's picture.
func pres_prematch_7(o: ISSMenu.Obj) -> void:
	o.update = pres_prematch_8
	o.set_w(DISTANCE, 0)
	o.set_w(CHOSEN, m.hv_counter.call() & 1)
	_toss_view()
	pres_prematch_8(o)


## pres_prematch_8: the coin lands (196 frames): the hand's two halves
## part from frame 96, the coin's face (HEADS / TAILS).
func pres_prematch_8(o: ISSMenu.Obj) -> void:
	o.add_w(DISTANCE, 1)
	if o.w(DISTANCE) == 0xC4:
		o.update = pres_prematch_9
	var d5 := maxi(0, o.sw(DISTANCE) - 0x60) << 2
	var d6 := 0x10 - d5
	d5 += 0x40
	pres_prematch_sprites(rom("pres_prematch_8_data4"), d5, d6)
	var face := "pres_prematch_8_data" if o.w(CHOSEN) == 0 else "pres_prematch_8_data2"
	pres_prematch_sprites(rom(face), 0x80, 0x34)
	pres_prematch_sprites(rom("pres_prematch_8_data3"), 0x40, 0x10)


## pres_prematch_9: the winner of the toss (the caller if the call was
## right) picks KICK OFF or one of the ends; a CPU side waits 32-63 frames.
func pres_prematch_9(o: ISSMenu.Obj) -> void:
	o.update = pres_prematch_10
	if o.w(ANIM_FRAME) != o.w(CHOSEN):
		o.set_w(TEAM, o.w(TEAM) ^ 1)
	o.set_w(CHOSEN, 0)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 0xFFFF)
	o.set_w(DISTANCE, (m.hv_counter.call() & 0x1F) + 0x20)
	set_w(0x1548, 0 if o.w(TEAM) == 0 else 1)
	pres_prematch_10(o)


## A CPU side's choice: every 8 frames the next item, the choice when its
## time is up; a human's: C chooses, up / down move (SFX 123, 95).
func _choose(o: ISSMenu.Obj, items: int) -> void:
	var pads := w(S.g_pads_home if o.w(TEAM) == 0 else S.g_pads_away)
	var step := false
	var chosen := false
	if pads == 0:
		o.add_w(DISTANCE, -1)
		if o.w(DISTANCE) == 0:
			chosen = true
		elif o.w(DISTANCE) & 7 == 0:
			step = true
	if not step and not chosen and w(S.g_pad_pressed_home) & 0x20:
		chosen = true
	if chosen:
		o.set_w(CHOSEN, 1)
		o.set_w(DISTANCE, 0)
		m.play_sfx(95)
	if not step and w(S.g_pad_pressed_home) & 2:
		step = true
	if items == 2:
		if step or w(S.g_pad_pressed_home) & 3:
			o.set_w(ANIM_FRAME, o.w(ANIM_FRAME) ^ 1)
			m.play_sfx(123)
		return
	if step:
		o.add_w(ANIM_FRAME, 1)
		if o.sw(ANIM_FRAME) > 2:
			o.set_w(ANIM_FRAME, 0)
		m.play_sfx(123)
	if w(S.g_pad_pressed_home) & 1:
		o.add_w(ANIM_FRAME, -1)
		if o.sw(ANIM_FRAME) < 0:
			o.set_w(ANIM_FRAME, 2)
		m.play_sfx(123)


## The choosing side's cursor (on its side of the picture) and every 8
## frames its colours cycled (tbl_toss_colours_home / 03C444 on line 0's last
## four).
func _cursor(o: ISSMenu.Obj, d6: int) -> void:
	if o.w(TEAM) == 0:
		pres_prematch_sprites(rom("tbl_toss_cursor_home"), 0x58, d6)
	else:
		pres_prematch_sprites(rom("tbl_toss_cursor_away"), 0xB8, d6)
	o.add_w(TIMER, 1)
	if o.w(TIMER) & 7:
		return
	var t := rom("tbl_toss_colours_home" if o.w(TEAM) == 0 else "tbl_toss_colours_away") + (w(S.g_frame_counter) & 0x18)
	for i in 4:
		set_w(0x76E + 2 * i, ISSRom.u16(t + 2 * i))
	m.cram_dma(0, S.g_palette_target, 0x20)


## pres_prematch_10: KICK OFF, LEFT or RIGHT; after 64 frames of the
## choice blinking an end gives the other side the kick-off ($1634) and
## the ends (g_left_goal_team), then the match; KICK OFF lets the other
## side pick the end.
func pres_prematch_10(o: ISSMenu.Obj) -> void:
	if o.w(CHOSEN) == 0:
		_choose(o, 3)
	else:
		o.add_w(DISTANCE, 1)
		if o.w(DISTANCE) == 0x40:
			if o.w(ANIM_FRAME) != 0:
				set_w(0x1634, o.w(TEAM) ^ 1)
				set_w(S.g_left_goal_team, (o.w(ANIM_FRAME) - 1) ^ o.w(TEAM))
				set_l(S.g_next_state, ISSMenu.STATE_MATCH)
				m.fade_out_start()
			else:
				o.update = pres_prematch_11
	if w(S.g_fade_step) != 0x18:
		return
	var blink := o.w(DISTANCE) & 8 != 0
	var c := o.w(CHOSEN) == 0
	if c or o.w(ANIM_FRAME) != 0 or blink:
		pres_prematch_sprites(rom("pres_prematch_10_data"), 0x88, 0x30)
	if c or o.w(ANIM_FRAME) != 1 or blink:
		pres_prematch_sprites(rom("tbl_toss_end_left"), 0x88, 0x50)
	if c or o.w(ANIM_FRAME) != 2 or blink:
		pres_prematch_sprites(rom("tbl_toss_end_right"), 0x88, 0x70)
	_cursor(o, o.w(ANIM_FRAME) * 32 + 0x30)


## pres_prematch_11: the other side picks an end.
func pres_prematch_11(o: ISSMenu.Obj) -> void:
	o.update = pres_prematch_12
	o.set_w(CHOSEN, 0)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 0xFFFF)
	o.set_w(TEAM, o.w(TEAM) ^ 1)
	o.set_w(DISTANCE, (ISSModes._rand() & 0x1F) + 0x20)
	set_w(0x1548, 0 if o.w(TEAM) == 0 else 1)
	pres_prematch_12(o)


## pres_prematch_12: LEFT or RIGHT, then the match.
func pres_prematch_12(o: ISSMenu.Obj) -> void:
	if o.w(CHOSEN) == 0:
		_choose(o, 2)
	else:
		o.add_w(DISTANCE, 1)
		if o.w(DISTANCE) == 0x40:
			set_w(0x1634, o.w(TEAM) ^ 1)
			set_w(S.g_left_goal_team, o.w(ANIM_FRAME) ^ o.w(TEAM))
			set_l(S.g_next_state, ISSMenu.STATE_MATCH)
			m.fade_out_start()
	if w(S.g_fade_step) != 0x18:
		return
	var blink := o.w(DISTANCE) & 8 != 0
	var c := o.w(CHOSEN) == 0
	if c or o.w(ANIM_FRAME) != 0 or blink:
		pres_prematch_sprites(rom("tbl_toss_end_left"), 0x88, 0x50)
	if c or o.w(ANIM_FRAME) == 0 or blink:
		pres_prematch_sprites(rom("tbl_toss_end_right"), 0x88, 0x70)
	_cursor(o, o.w(ANIM_FRAME) * 32 + 0x50)


# --------------------------------------------------------------------------
# 1: a goal (pres_goal).

## Palette lines 2 and 3 as state_match leaves them, which the goal's
## presentation keeps: line 2 group 17 entry 2 with the officials' kit over
## its first eight colours (the fourth kit while $125E is set,
## match_create_objects) and group 16 entry 9 over the rest
## (match_init_hud); line 3 the stadium's colours for the weather
## (group 7 + stadium, entry 6 + weather; colour 14 = colour 0).
static func match_palette() -> void:
	ISSRam.copy_in(0x796, ISSRom.res(17, 2))
	var kit := ISSRom.res(4, 38)
	var k := (3 if ISSRam.w(0x125E) != 0 else ISSRam.w(S.g_officials_kit)) * 16
	for i in 8:
		ISSRam.set_w(0x796 + 2 * i, (kit[k + 2 * i] << 8) | kit[k + 2 * i + 1])
	ISSRam.copy_in(0x7A6, ISSRom.res(16, 9))
	ISSRam.copy_in(0x7B6, ISSRom.res(7 + ISSRam.w(S.g_stadium), 6 + ISSRam.w(S.g_weather)))
	ISSRam.set_w(0x7D2, ISSRam.w(0x7B6))



## pres_goal: the big screen ($1630's picture set, group 19 or 20
## for the third stand) with the goal's picture (sprites, group 4 entry 22
## + $1734: 0 a goal, 1 a lead by one, 2 a hat-trick) in the scorers' kit
## ($1732 the side), and for the last two confetti.
func pres_goal() -> void:
	set_l(S.g_plane_a_hscroll, 0)
	set_l(S.g_plane_b_hscroll, 0)
	set_l(S.g_plane_a_vscroll, 0x2200000)
	set_l(S.g_plane_b_vscroll, 0x2200000)
	var g := 20 if w(0x1630) == 2 else 19
	set_w(S.g_overlay_vram, m.load_tiles(g, 1))
	var buf := l(S.g_unpack_buffer)
	var end := m.unpack(g, 0, buf)
	_add(buf, end, w(S.g_overlay_vram) >> 5)
	var skip := 0x90 if w(0x1734) == 0 else 0
	for row in 16:
		m.vram_dma(0x2000 + 0x310 + (row << 7), buf + skip + row * 0x24, 0x24)
	m.unpack(g, 2, 0xFF0776)
	set_w(0x7B8, 0x284)
	set_w(0x7BC, 0x040)
	set_w(0x7D2, 0x062)
	set_w(0x7D4, 0x2A6)
	set_w(0x173A, m.load_tiles(4, 22 + mini(w(0x1734), 2)))
	_kit(0 if w(0x1732) == 0 else 1, S.g_palette_target)
	ISSModes.kit_shades()
	if w(0x1734) != 0:
		var at := m.load_tiles(4, 13)
		for i in 14:
			var o := m.obj_alloc()
			if o == null:
				continue
			o.think = Callable()
			o.set_w(VRAM, at)
			o.draw = objects.particle_draw
			o.set_w(Y, 0x540)
			o.set_w(X, ISSModes._rand() & 0xFF)
			o.set_w(Z, ISSModes._rand() & 0x7F)
			objects.confetti_fall(o)
	set_w(0x173C, 0x140)
	var c := m.obj_alloc()
	c.draw = Callable()
	c.think = Callable()
	c.update = pres_goal_1


## pres_goal_1: the music (song $19) and the crowd: a goal's cheer
## (SFX 102) once, a lead's or a hat-trick's (101 after the second goal,
## else 99) and SFX 80.
func pres_goal_1(o: ISSMenu.Obj) -> void:
	o.update = pres_goal_2
	m.menu_music(0x19)
	if w(0x1734) == 0:
		if w(0x17D8) != 1:
			m.play_sfx(102)
			set_w(0x17D8, 1)
	else:
		m.play_sfx(101 if sw(0x17D8) > 2 else 99)
		set_w(0x17D8, 2)
		m.play_sfx(80)
	pres_goal_2(o)


## pres_goal_2: 320 frames (or Start) of the picture, then back to
## the match.
func pres_goal_2(_o: ISSMenu.Obj) -> void:
	add_w(0x173C, -1)
	if w(0x173C) == 0 or w(S.g_pad_pressed_any) & 0x80:
		set_l(S.g_next_state, ISSMenu.STATE_MATCH)
		m.fade_out_start()
	var t: String = ["pres_goal_2_data", "pres_goal_2_data2", "pres_goal_2_data3"][mini(w(0x1734), 2)]
	_list(rom(t), w(0x173A), 0x50, 0x20)


# --------------------------------------------------------------------------
# 2: the trophy (pres_trophy).

## pres_trophy: the trophy song ($12); VICTORY down both sides of
## plane A (group 21), the crowd between them on plane B (the stand map's
## sides blanked with metatile $6D, a strip of it repeated further down),
## the cup's picture in four sprite strips (group 4 entry 27) at the
## heights $173E / $1742 / $1746 / $174A, in the winners' first kit
## ($127C's).
func pres_trophy() -> void:
	m.menu_music(0x12)
	set_l(S.g_plane_a_hscroll, 0)
	set_l(S.g_plane_b_hscroll, 0)
	set_l(S.g_plane_a_vscroll, 0)
	set_l(S.g_plane_b_vscroll, 0x1600000)
	var a0 := (l(S.g_pitch_map) & 0xFFFF) + 4
	for row in 0x30:
		for i in 4:
			ISSRam.set_w(a0, 0x6D)
			a0 += 2
		a0 += 0x10
		for i in 4:
			ISSRam.set_w(a0, 0x6D)
			a0 += 2
	var a2 := (l(S.g_pitch_map) & 0xFFFF) + 0x300
	var a1 := a2 + 0x80
	for n in 5:
		ISSRam.copy(a1, a2, 0x80)
		a1 += 0x80
	var kit := ISSRom.res(4, 38)
	for i in 8:
		set_w(0x796 + 2 * i, (kit[2 * i] << 8) | kit[2 * i + 1])
	var t := rom("pres_trophy_data")
	for i in 16:
		set_w(0x7B6 + 2 * i, ISSRom.u16(t + 2 * i))
	set_w(S.g_overlay_vram, m.load_tiles(21, 1))
	var buf := l(S.g_unpack_buffer)
	var end := m.unpack(21, 0, buf)
	_add(buf, end, w(S.g_overlay_vram) >> 5)
	for row in 32:
		m.vram_dma(0x2000 + (row << 7), buf + (row << 4), 0x10)
	for row in 32:
		m.vram_dma(0x2000 + 0x2E + (row << 7), buf + (row << 4), 0x10)
	set_w(0x173C, m.load_tiles(4, 27))
	var kits := ISSRom.res(6, 12)
	var team := w(0x127C)
	for i in 16:
		set_w(S.g_palette_target + 2 * i, (kits[team * 32 + 2 * i] << 8) | kits[team * 32 + 2 * i + 1])
	ISSModes.kit_shades()
	set_l(0x173E, 0x240000)
	set_l(0x1742, 0x480000)
	set_l(0x1746, 0x600000)
	set_l(0x174A, 0x600000)
	var c := m.obj_alloc()
	c.draw = Callable()
	c.think = Callable()
	c.update = pres_trophy_1


func pres_trophy_1(o: ISSMenu.Obj) -> void:
	o.update = pres_trophy_2
	pres_trophy_2(o)


## pres_trophy_2: the crowd scrolls up to $1C0 (0.625 a frame), the
## picture's strips rising at their own speeds.
func pres_trophy_2(o: ISSMenu.Obj) -> void:
	if sw(S.g_plane_b_vscroll) >= 0x1C0:
		o.update = pres_trophy_3
	else:
		add_l(S.g_plane_b_vscroll, 0xA000)
		add_l(0x174A, -0x8000)
		add_l(0x1746, -0x8000)
		add_l(0x1742, -0x6000)
		add_l(0x173E, -0x3000)
	pres_trophy_draw()


## pres_trophy_3 / _4: the picture held for 400 frames.
func pres_trophy_3(o: ISSMenu.Obj) -> void:
	o.update = pres_trophy_4
	set_w(0x173A, 0x190)
	pres_trophy_4(o)


func pres_trophy_4(o: ISSMenu.Obj) -> void:
	add_w(0x173A, -1)
	if w(0x173A) == 0:
		o.update = pres_trophy_5
	pres_trophy_draw()


func pres_trophy_5(o: ISSMenu.Obj) -> void:
	o.update = pres_trophy_6
	pres_trophy_6(o)


## pres_trophy_6: the crowd scrolls back to the top 4 pixels a frame
## while the strips drop away; at $140 the stand's own colours.
func pres_trophy_6(o: ISSMenu.Obj) -> void:
	if w(S.g_plane_b_vscroll) == 0:
		o.update = pres_trophy_7
	else:
		add_w(S.g_plane_b_vscroll, -4)
	if sw(0x173E) < 0x100:
		for a in [0x173E, 0x1742, 0x1746, 0x174A]:
			add_w(a, 6)
	if w(S.g_plane_b_vscroll) == 0x140:
		m.unpack(18, 8, 0xFF0000 | S.g_palette_target)
		m.cram_dma(0, S.g_palette_target, 0x40)
	pres_trophy_draw()


func pres_trophy_7(o: ISSMenu.Obj) -> void:
	o.update = pres_trophy_8
	set_w(0x173A, 0x60)
	pres_trophy_8(o)


## pres_trophy_8: 96 frames on, where the competition goes: the
## ending ($33) after the International Cup or a won championship, the
## World Series' second series ($37) or the championship ($38).
func pres_trophy_8(o: ISSMenu.Obj) -> void:
	if w(0x173A) != 0:
		add_w(0x173A, -1)
		return
	set_l(S.g_next_state, ISSMenu.STATE_MENU)
	if w(S.g_game_mode) == 8 or w(0x1260) != 0:
		set_w(S.g_next_screen, 0x33)
	elif w(0x126C) == 0:
		ISSModes.ws_second_series()
		set_w(S.g_next_screen, 0x37)
	else:
		ISSModes.start_championship()
		ISSModes.match_setup_random()
		set_w(S.g_next_screen, 0x38)
	m.fade_out_start()
	m.obj_free(o)


## pres_trophy_draw: the cup's picture, four sprite lists (the
## International Cup's last one its own) each at its strip's height, with
## priority.
func pres_trophy_draw() -> void:
	var t := rom("pres_trophy_draw_data2" if w(S.g_game_mode) == 8 else "pres_trophy_draw_data")
	var base := w(0x173C) >> 5
	for k in 4:
		var a4 := ISSRom.u32(t + k * 4)
		var dy := sw(0x173E + k * 4)
		var n := ISSRom.u16(a4) + 1
		a4 += 2
		for i in n:
			m.sprite(ISSRom.s16(a4) + 0x40 + dy, ISSRom.u16(a4 + 2), (base + ISSRom.u16(a4 + 4)) | 0x8000,
				ISSRom.s16(a4 + 6) + 0x40)
			a4 += 8
