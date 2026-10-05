class_name ISSShootout
extends RefCounted
## state_shootout ($0201FE): one penalty of the shoot-out, seen from behind
## the taker: the goal and the stand in perspective (plane B), the HUD on
## the window plane (the takers' names, the controller icons, the tallies),
## the taker (from behind, a larger frame set), the keeper facing the
## camera and the 16 x 16 ball, all drawn as the game draws them: tiles
## streamed into VRAM slots and hardware sprites. Each kick is a state of
## its own; shootout_next_1 chooses the next (the other side, the
## next round, sudden death, the order screen $1A between rounds for a
## human home side) and shootout_decided_1 where the game goes when it
## is decided. The routines are the ROM's, under their names.

const S := preload("res://iss/iss_sym.gd")

const OWNER := 0x08
const STATE := 0x0C
const VISIBLE := 0x0E
const X := 0x10
const Y := 0x14
const Z := 0x18
const SCREEN_X := 0x1C
const SCREEN_Y := 0x1E
const VEL_X := 0x20
const VEL_Y := 0x24
const TARGET_X := 0x28
const BALL_DIST := 0x2E
const ATTR := 0x32
const KICK_POWER := 0x40
const HEADING := 0x44
const CROUCH := 0x46
const INPUT := 0x48
const TEAM := 0x4A
const ROLE := 0x51
const SLOT := 0x56
const ENERGY := 0x57
const NUMBER := 0x63
const HAIR := 0x64
const POSITION := 0x65
const ACTION := 0x6A
const FRAME := 0x6C
const VRAM := 0x78
const ANIM_FRAME := 0x7A
const TIMER := 0x7C
const SPEED := 0x7E
const VEL_Z := 0x82
const FACING := 0x86
const KICK_DIR := 0x88
const DISTANCE := 0x8A
## Word: the kick's quality (taker), a save made (keeper).
const K8C := 0x8C

## g_restart_type values the shoot-out uses.
const R_MISS := 1
const R_WAIT := 3
const R_GOAL := 0xB

var m: ISSMenu
var objects: ISSObjects
## g_player_tiles (group 1 unpacked, its offset table first) and the two
## sides' head tiles (group 6 entry 6 under the team's head mask), as RAM
## addresses.
var _player_tiles := 0
var _head_tiles := [0, 0]


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


func rom(name: String) -> int:
	return ISSRom.addr(name)


func _hv() -> int:
	return int(m.hv_counter.call()) & 0xFFFF


func _a(at: int) -> ISSObjects.Actor:
	return objects.actor(at)


func _ball() -> ISSObjects.Actor:
	return objects.actor(S.g_ball)


func _director() -> ISSObjects.Actor:
	return objects.actor(S.g_director)


## Add v to every word from a to end.
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
# state_shootout and its frame.

## state_shootout: the large ball and its timer (ball_init_large), the
## HUD and the weather (shootout_hud_init), the view (shootout_view_init), the
## music and the crowd (shootout_sound_init), the commentary queue cleared,
## the taker and the keeper (shootout_setup).
func state_shootout() -> void:
	objects = ISSObjects.new(m)
	ball_init_large()
	shootout_hud_init()
	shootout_view_init()
	shootout_sound_init()
	m.sound.clear_speech()
	shootout_setup()


## state_shootout_frame's own part before the objects: the pads and the
## players' distances to the ball.
func frame_before_objects() -> void:
	shootout_pads()


func frame_after_objects() -> void:
	shootout_crowd_anim()
	shootout_crowd_sfx()


func frame_after_draw() -> void:
	shootout_result()
	shootout_hud()


## ball_init_large: g_director times the kick (restart type 3 until it lets
## go), the ball on the spot (x $80, y $12C) with the 16 x 16 tiles (group 4
## entry 1), priority and line 3.
func ball_init_large() -> void:
	set_w(S.g_restart_setup, 0xFFFF)
	var d := _director()
	objects.link(d)
	d.draw = Callable()
	d.think = Callable()
	d.set_w(TEAM, 0xFFFF)
	set_w(S.g_restart_type, R_WAIT)
	d.update = ball_init_large_1
	ISSRam.set_w(S.g_ball + VRAM, m.load_tiles(4, 1))
	var b := _ball()
	objects.ball = b
	objects.link(b)
	b.set_w(Z, 0)
	b.set_w(X, 0x80)
	b.set_w(Y, 0x12C)
	b.set_w(ATTR, 0xE000)
	b.set_l(VEL_Z, 0)
	b.set_l(SPEED, 0)
	b.think = objects.obj_steer_idle
	b.set_w(INPUT, 0)
	b.set_l(OWNER, 0xFFFFFFFF)
	b.set_b(STATE, 0xFF)
	b.set_w(TEAM, w(S.g_restart_team))
	b.draw = ball_draw
	ball_update_large(b)


func ball_init_large_1(o: ISSMenu.Obj) -> void:
	o.update = ball_init_large_2
	o.set_w(DISTANCE, 0)
	ball_init_large_2(o)


## ball_init_large_2: once the picture is up, the whistle (SFX 81) at 64
## frames and the kick allowed at 80.
func ball_init_large_2(o: ISSMenu.Obj) -> void:
	if w(S.g_frame_state) != 2:
		return
	o.set_w(DISTANCE, o.w(DISTANCE) + 1)
	if o.w(DISTANCE) == 0x40:
		m.play_sfx(81)
	if o.w(DISTANCE) == 0x50:
		set_w(S.g_restart_type, 0xFFFF)
		m.obj_free(o)


## shootout_hud_init: the HUD on the window plane covering the screen
## (register 17 $80): its tiles (group 16 entry 5 under group 17 entry 1),
## its map (group 17 entry 0; out of a match the bottom row of the names'
## panel replaced), the names' rows kept at g_hud_map (the buffer's start,
## the map done with) for the HUD routine,
## line 2 (group 17 entry 2), the flags and names of both teams; snow or
## rain (12 particles).
func shootout_hud_init() -> void:
	m.vdp.window_h = 0x80
	set_l(0x938, 0xFF0000 | S.g_team_home_players)
	set_l(0x93C, 0xFF0000 | S.g_team_away_players)
	set_w(S.g_overlay_vram, m.load_tiles(16, 5))
	var buf := l(S.g_unpack_buffer)
	var end := m.unpack(17, 1, buf)
	m.vram_dma(w(S.g_overlay_vram), buf, end - buf)
	end = m.unpack(17, 0, buf)
	if w(0x1638) == 0:
		var a := (buf & 0xFFFF) + 0x680
		for i in 32:
			ISSRam.set_w(a + 2 * i, ISSRam.w(a + 2 * i + 0x80))
	_add(buf, end, (w(S.g_overlay_vram) >> 5) | 0x8000)
	m.vram_dma(ISSVdp.WINDOW, buf, end - buf)
	# The names' rows (from row 23) copied down to the buffer's start.
	set_l(S.g_hud_map, buf)
	ISSRam.copy(buf & 0xFFFF, (buf & 0xFFFF) + 0x5C0, 0x100)
	set_l(S.g_unpack_buffer, buf + 0x100)
	set_l(S.g_hud_clock_fn, 0)
	m.unpack(17, 2, 0xFF0796)
	buf = l(S.g_unpack_buffer)
	m.unpack(6, 2, buf)
	m.vram_dma(w(S.g_overlay_vram) + 0x680, buf + w(S.g_team_home) * 0xC0, 0xC0)
	m.vram_dma(w(S.g_overlay_vram) + 0x740, buf + w(S.g_team_away) * 0xC0, 0x100)
	m.unpack(6, 1, buf)
	m.vram_dma(w(S.g_overlay_vram) + 0x800, buf + w(S.g_team_home) * 0x200, 0x200)
	m.vram_dma(w(S.g_overlay_vram) + 0xA00, buf + w(S.g_team_away) * 0x200, 0x200)
	var weather := w(S.g_weather)
	if weather != 2 and weather != 0:
		return
	var at := m.load_tiles(4, 12 if weather == 2 else 11)
	for i in 12:
		var o := m.obj_alloc()
		if o == null:
			continue
		o.think = Callable()
		o.set_w(VRAM, at)
		o.draw = objects.particle_draw
		o.set_w(Y, (ISSModes._rand() & 0x7F) + 0x100)
		o.set_w(X, ISSModes._rand() & 0xFF)
		o.set_w(Z, ISSModes._rand() & 0xFF)
		if weather == 2:
			rain_drop(o)
		else:
			snow_flake(o)


## shootout_view_init: the view: the shoot-out tiles (group 15 entry 3) at
## g_stadium_vram and the stadium's (entry 4 + stadium), in snow or rain
## the pitch's patch (entry 12) over $2200; the map on plane B (entry 0,
## or 1 for stadiums 3-6); the scoreboard's two pictures (entry 2) kept at
## g_radar_bitmap, the first on the window at $10C0; line 3 for the
## weather; the crowd's frames (group 4 entry 10) at $1736.
func shootout_view_init() -> void:
	set_w(S.g_stadium_vram, m.load_tiles(15, 3))
	m.load_tiles(15, 4 + w(S.g_stadium))
	var buf := l(S.g_unpack_buffer)
	if w(S.g_weather) != 0:
		m.unpack(15, 12, buf)
		m.vram_dma(w(S.g_stadium_vram) + 0x2200, buf, 0x600)
	var stadium := w(S.g_stadium)
	var e := 1 if stadium >= 3 and stadium != 7 else 0
	var end := m.unpack(15, e, buf)
	_add(buf, end, w(S.g_stadium_vram) >> 5)
	m.vram_dma(ISSVdp.PLANE_B, buf, end - buf)
	set_l(S.g_radar_bitmap, buf)
	end = m.unpack(15, 2, buf)
	_add(buf, end, (w(S.g_stadium_vram) >> 5) | 0x8000)
	set_l(S.g_unpack_buffer, end)
	m.vram_dma(ISSVdp.WINDOW + 0xC0, buf, (end - buf) >> 1)
	m.unpack(7 + stadium, 6 + w(S.g_weather), 0xFF07B6)
	set_w(0x7D2, w(0x7B6))
	set_l(0x1736, _keep(4, 10))
	set_w(S.g_plane_a_hscroll, 0)
	set_w(S.g_plane_a_vscroll, 0)
	set_w(S.g_plane_b_hscroll, 0)
	set_w(S.g_plane_b_vscroll, 0)


## shootout_sound_init: the stadium's song (tbl_stadium_songs), the crowd
## (SFX 98, or 102 after a goal), the crowd's timer.
func shootout_sound_init() -> void:
	var song := ISSRom.u16(rom("tbl_stadium_songs") + w(S.g_stadium) * 2)
	set_w(S.g_sound_disabled, 0xFFFF)
	m.play_music(song)
	set_w(S.g_sound_disabled, song)
	var crowd := sw(0x17D8)
	if crowd != 1:
		m.play_sfx(98 if crowd < 1 else 102)
		set_w(0x17D8, 1)
	set_w(0x17DA, 0x40)


## shootout_setup: both kits on lines 0 and 1, the head tiles masked for
## each side, the taker frames (group 1, at g_player_tiles), two VRAM slots;
## the side taking (g_restart_team) has its next taker on the spot ($14FE /
## $1512 orders, $14FA / $14FC the turn) with the ball, the other its
## keeper on the line; each on a controller slot of its side, a human
## side's slots in turn.
func shootout_setup() -> void:
	_kit(0, S.g_palette_target)
	_kit(1, 0x776)
	# tm_hair_tiles: group 6 entry 10, read in place.
	set_l(S.g_team_home_info + 8, ISSRom.res_addr(6, 10))
	set_l(S.g_team_away_info + 8, ISSRom.res_addr(6, 10))
	for side in 2:
		var at := _keep(6, 6)
		_head_tiles[side] = at
		var kit := w(S.g_kit_home if side == 0 else S.g_kit_away)
		var mask := ISSRom.u16(rom("tbl_head_mask_home" if kit & 1 == 0 else "tbl_head_mask_away")
			+ w(S.g_team_home if side == 0 else S.g_team_away) * 2)
		var a := at & 0xFFFF
		while a < (l(S.g_unpack_buffer) & 0xFFFF):
			ISSRam.set_w(a, ISSRam.w(a) & mask)
			a += 2
	set_l(S.g_team_home_info + 4, _head_tiles[0])
	set_l(S.g_team_away_info + 4, _head_tiles[1])
	# g_player_tiles: eight offsets, then group 1's entries unpacked (the
	# buffer is not advanced past them).
	var base := l(S.g_unpack_buffer)
	_player_tiles = base
	set_l(S.g_player_tiles, base)
	var at := base + 0x20
	for k in 8:
		set_l(base + 4 * k, at - base)
		at = m.unpack(1, k, at)
	for i in 2:
		set_w(S.g_npc_vram_slots + 2 * i, w(S.g_unpack_vram))
		add_w(S.g_unpack_vram, 0x600)
	var home: ISSObjects.Actor
	if w(S.g_restart_team) == 0:
		home = _taker(0)
	else:
		home = _keeper(0)
	set_l(0x938, home.ptr())
	var d4 := w(0x1544)
	if w(S.g_restart_team) == 0:
		d4 += 1
		if d4 >= w(S.g_pads_home):
			d4 = 0
		set_w(0x1544, d4)
	_control(home, S.g_control_slots + d4 * 0x1A)
	var away: ISSObjects.Actor
	if w(S.g_restart_team) != 0:
		away = _taker(1)
	else:
		away = _keeper(1)
	set_l(0x93C, away.ptr())
	d4 = w(0x1546)
	if w(S.g_restart_team) != 0:
		d4 += 1
		if d4 >= w(S.g_pads_away):
			d4 = 0
		set_w(0x1546, d4)
	_control(away, 0x15C4 + d4 * 0x1A)


func _control(o: ISSObjects.Actor, slot: int) -> void:
	o.set_b(STATE, 1)
	o.set_l(OWNER, 0xFF0000 | slot)
	set_l(slot, o.ptr())


## A side's kit (16 colours) to RAM at dst.
func _kit(side: int, dst: int) -> void:
	var kit := w(S.g_kit_home if side == 0 else S.g_kit_away)
	if kit == 2:
		ISSRam.copy(dst, 0x185A if side == 0 else 0x18E2, 0x20)
		return
	var data := ISSRom.res(6, 12 if kit == 0 else 13)
	var team := w(S.g_team_home if side == 0 else S.g_team_away)
	for i in 16:
		set_w(dst + 2 * i, (data[team * 32 + 2 * i] << 8) | data[team * 32 + 2 * i + 1])


## The taker: the next in the side's order on the spot, facing away.
func _taker(side: int) -> ISSObjects.Actor:
	var turn := 0x14FA if side == 0 else 0x14FC
	var order := 0x14FE if side == 0 else 0x1512
	var info: int = S.g_team_home_info if side == 0 else S.g_team_away_info
	var k := w(turn)
	add_w(turn, 1)
	if w(info + 0x60) + 6 == w(turn):
		set_w(turn, 0)
	var idx := w(order + k * 2)
	var o := _a((S.g_team_home_players if side == 0 else S.g_team_away_players) + idx * ISSModes.PLAYER_SIZE)
	objects.link(o)
	o.set_w(Z, 0)
	o.set_w(X, 0x80)
	o.set_w(Y, 0x12C)
	o.set_w(FACING, 0)
	o.set_w(ATTR, 0x80 if side == 0 else 0xA0)
	o.think = shootout_taker_ai
	o.set_b(STATE, 0xFF)
	o.set_b(0x0D, 0)
	o.set_w(INPUT, 0)
	o.draw = shootout_setup_draw
	o.set_l(FRAME, rom("misc_data_02C31E"))
	o.set_w(VRAM, 0)
	shootout_taker(o)
	ISSRam.set_l(S.g_ball + OWNER, o.ptr())
	ISSRam.set_b(S.g_ball + STATE, 1)
	return o


## The keeper: the side's first player on the line, facing the camera.
func _keeper(side: int) -> ISSObjects.Actor:
	var o := _a(S.g_team_home_players if side == 0 else S.g_team_away_players)
	objects.link(o)
	o.set_w(Z, 0)
	o.set_w(X, 0x80)
	o.set_w(Y, 0xCC)
	o.set_w(FACING, 0x20)
	o.set_w(ATTR, 0x8000 if side == 0 else 0xA000)
	o.think = shootout_keeper_ai
	o.set_b(STATE, 0xFF)
	o.set_b(0x0D, 0)
	o.set_w(INPUT, 0)
	o.draw = obj_set_frame_draw_draw
	o.set_l(FRAME, 0)
	o.set_w(VRAM, 0)
	shootout_keeper(o)
	return o


## shootout_pads: the pads' edges (no auto-repeat), each human
## controller's buttons held less those its player has used, and every
## player's distance to the ball.
func shootout_pads() -> void:
	var home_n := w(S.g_pads_home)
	var away_n := w(S.g_pads_away)
	var d0 := m._pads_or(0, home_n)
	var d1 := m._pads_or(home_n, away_n)
	var d2 := m._pads_or(0, 8) if w(0x153E) == 0 else d0 | d1
	for e in [[S.g_pad_held_home, S.g_pad_pressed_home, d0], [S.g_pad_held_away, S.g_pad_pressed_away, d1],
			[S.g_pad_held_any, S.g_pad_pressed_any, d2]]:
		var held: int = e[0]
		var d: int = e[2]
		set_w(held, w(held) & d)
		var p := d & ~w(held) & 0xFFFF
		set_w(e[1], p)
		set_w(held, w(held) | p)
	var k := 0
	for side in 2:
		var slots: int = S.g_control_slots if side == 0 else 0x15C4
		for i in (home_n if side == 0 else away_n):
			var a := slots + i * 0x1A
			set_w(a + 8, w(S.g_pad_type + 2 * k))
			var st := w(S.g_pad_state + 2 * k)
			set_w(a + 6, w(a + 6) & st)
			set_w(a + 4, st & ~w(a + 6) & 0xFFFF)
			k += 1
	var bx := w(S.g_ball + X)
	var by := w(S.g_ball + Y)
	for side in 2:
		var base: int = S.g_team_home_players if side == 0 else S.g_team_away_players
		for i in 11:
			var a := base + i * ISSModes.PLAYER_SIZE
			var dx := absi(_s16(ISSRam.w(a + X) - bx))
			var dy := absi(_s16(ISSRam.w(a + Y) - by))
			ISSRam.set_w(a + BALL_DIST, dx + dy)


static func _s16(v: int) -> int:
	v &= 0xFFFF
	return v - 0x10000 if v >= 0x8000 else v


## shootout_crowd_anim: the crowd's animation (state_shootout_frame_17_
## data's strips from $1736): every 4 frames, every other frame after a goal.
func shootout_crowd_anim() -> void:
	var f := w(S.g_frame_counter)
	var entry: int
	if w(S.g_restart_type) != R_GOAL:
		if f & 3:
			return
		entry = (f & 0x3C) >> 2
	else:
		if f & 1:
			return
		entry = (f & 0x1E) >> 1
	var a1 := rom("shootout_crowd_anim_data") + entry * 6
	m.vram_dma(w(S.g_stadium_vram) + ISSRom.u16(a1 + 2), l(0x1736) + ISSRom.u16(a1), ISSRom.u16(a1 + 4))


## shootout_crowd_sfx: the crowd: when the ball's holder starts to
## move, a roar (SFX 104) unless it is already roaring, else the murmur
## (99) every $400 frames.
func shootout_crowd_sfx() -> void:
	if w(0x17DA) != 0:
		add_w(0x17DA, -1)
		return
	var owner := l(S.g_ball + OWNER)
	if owner >= 0x80000000:
		return
	if ISSRam.l((owner & 0xFFFF) + SPEED) == 0:
		return
	if w(0x17D8) != 2:
		m.play_sfx(104)
		set_w(0x17D8, 2)
		set_w(0x17DA, 0x25)
		return
	m.play_sfx(99)
	set_w(0x17DA, 0x400)


## shootout_result: the kick's result once the ball is loose: in
## the goal (under $40 high, between x $20 and $E0, beyond y $C4) a goal
## (the side's tally ticked, restart $B), past the posts a miss, touched by
## the keeper a save (commentary $A); g_director then runs the aftermath.
## In a match ($1638) the kick goes back to state_match (restart 7).
func shootout_result() -> void:
	if sw(S.g_restart_type) >= 0:
		return
	var b := _ball()
	var tally := 0x1526 if w(S.g_restart_team) == 0 else 0x1530
	var kick := (w(S.g_shootout_kicks) % 5) * 2
	if b.sw(Y) < 0xC4:
		if w(0x1638) != 0:
			_back_to_match()
			return
		if b.sw(Z) < 0x40 and b.sw(X) < 0xE0 and b.sw(X) > 0x20:
			add_w(0x153A if w(S.g_restart_team) == 0 else 0x153C, 1)
			set_w(tally + kick, 1)
			set_w(S.g_restart_type, R_GOAL)
			set_w(S.g_restart_setup, 0xFFFF)
			var d := _aftermath(shootout_scored)
			b.set_l(OWNER, d.ptr())
			b.set_b(STATE, 2)
			b.think = ball_in_net
			return
		set_w(tally + kick, 0)
		set_w(S.g_restart_type, R_MISS)
		set_w(S.g_restart_setup, 0xFFFF)
		_aftermath(shootout_missed)
		return
	if b.w(TEAM) == w(S.g_restart_team):
		return
	if w(0x1638) != 0:
		_back_to_match()
		return
	set_w(tally + kick, 0)
	set_w(S.g_restart_type, R_MISS)
	set_w(S.g_restart_setup, 0xFFFF)
	_aftermath(shootout_missed)
	m.sound.say(0x0A)


func _back_to_match() -> void:
	set_w(S.g_restart_type, 7)
	set_l(S.g_next_state, ISSMenu.STATE_MATCH)
	m.fade_out_start()


func _aftermath(update: Callable) -> ISSObjects.Actor:
	var d := _director()
	objects.link(d)
	d.draw = Callable()
	d.think = Callable()
	d.set_w(TEAM, 0xFFFF)
	d.update = update
	return d


## The ball's think after a goal: it stops in the net (y $BC) and the
## scoreboard flashes GOAL.
func ball_in_net(o: ISSMenu.Obj) -> void:
	o.think = ball_in_net_1
	ball_in_net_1(o)


func ball_in_net_1(o: ISSMenu.Obj) -> void:
	if o.sw(Y) >= 0xBC:
		return
	o.set_w(Y, 0xBC)
	o.set_l(SPEED, 0)
	var keep := m.a5
	var f := m.obj_alloc()
	m.a5 = keep
	if f == null:
		return
	f.think = Callable()
	f.draw = Callable()
	scoreboard_flash(f)


## scoreboard_flash / _4: 64 frames of the scoreboard's two
## pictures in turn every 4 frames.
func scoreboard_flash(o: ISSMenu.Obj) -> void:
	o.update = scoreboard_flash_1
	o.set_w(TIMER, 0x40)
	scoreboard_flash_1(o)


func scoreboard_flash_1(o: ISSMenu.Obj) -> void:
	o.set_w(TIMER, o.w(TIMER) - 1)
	if o.w(TIMER) == 0:
		m.obj_free(o)
		return
	var f := w(S.g_frame_counter)
	if f & 3:
		return
	m.vram_dma(ISSVdp.WINDOW + 0xC0, l(S.g_radar_bitmap) + (0x280 if f & 4 else 0), 0x280)


## A goal: commentary $2F, the cheer (SFX 100), 128 frames.
func shootout_scored(o: ISSMenu.Obj) -> void:
	o.update = shootout_scored_1
	o.set_w(TIMER, 0x80)
	m.sound.say(0x2F)
	m.play_sfx(100)
	set_w(0x17D8, 3)
	shootout_scored_1(o)


func shootout_scored_1(o: ISSMenu.Obj) -> void:
	o.set_w(TIMER, o.w(TIMER) - 1)
	if o.w(TIMER) == 0:
		o.update = shootout_next


## A miss or a save: the groan (SFX 106), 128 frames.
func shootout_missed(o: ISSMenu.Obj) -> void:
	o.update = shootout_missed_1
	o.set_w(TIMER, 0x80)
	m.play_sfx(106)
	set_w(0x17D8, 1)
	shootout_missed_1(o)


func shootout_missed_1(o: ISSMenu.Obj) -> void:
	o.set_w(TIMER, o.w(TIMER) - 1)
	if o.w(TIMER) == 0:
		o.update = shootout_next


func shootout_next(o: ISSMenu.Obj) -> void:
	o.update = shootout_next_1
	shootout_next_1(o)


## The goals the side behind still needs against the kicks left (the side
## that just kicked counted): the lead less one when the home side kicked.
func _margin() -> int:
	var d := w(0x153C) - w(0x153A)
	if d < 0:
		d = -d
		if w(S.g_restart_team) == 0:
			d -= 1
	return d


## shootout_next_1: in the first five kicks each, decided when the
## lead is more than the kicks left; else the other side kicks, or after
## both the next round (after the fifth the tallies cleared and, with a
## human home side, the order screen $1A). In sudden death decided by a
## lead after both kicked.
func shootout_next_1(o: ISSMenu.Obj) -> void:
	var kicks := w(S.g_shootout_kicks)
	if kicks < 5:
		if _margin() + kicks > 4:
			o.update = shootout_decided
			return
		if w(S.g_restart_team) == 0:
			set_w(S.g_restart_team, 1)
			set_l(S.g_next_state, ISSMenu.STATE_SHOOTOUT)
		else:
			add_w(S.g_shootout_kicks, 1)
			if w(S.g_shootout_kicks) <= 4:
				set_w(S.g_restart_team, 0)
				set_l(S.g_next_state, ISSMenu.STATE_SHOOTOUT)
			else:
				_clear_tallies()
				_next_round()
	else:
		if _margin() != 0:
			o.update = shootout_decided
			return
		if w(S.g_restart_team) == 0:
			set_w(S.g_restart_team, 1)
			set_l(S.g_next_state, ISSMenu.STATE_SHOOTOUT)
		else:
			add_w(S.g_shootout_kicks, 1)
			if w(S.g_shootout_kicks) % 5 == 0:
				_clear_tallies()
			_next_round()
	m.fade_out_start()
	m.obj_free(o)


func _clear_tallies() -> void:
	for i in 10:
		set_w(0x1526 + 2 * i, 0xFFFF)


func _next_round() -> void:
	if w(S.g_pads_home) != 0:
		set_w(S.g_next_screen, 0x1A)
		set_w(0x176A, 0)
		set_l(S.g_next_state, ISSMenu.STATE_MENU)
	else:
		set_w(S.g_restart_team, 0)
		set_l(S.g_next_state, ISSMenu.STATE_SHOOTOUT)


## shootout_decided: decided: the commentary ($14 a win, $13 when
## a CPU side won a game with a human in it), 256 frames.
func shootout_decided(o: ISSMenu.Obj) -> void:
	o.update = shootout_decided_1
	o.set_w(TIMER, 0x100)
	var pads := w(S.g_pads_home) if w(0x153A) > w(0x153C) else w(S.g_pads_away)
	if w(0x153E) == 0 or pads != 0:
		m.sound.say(0x14)
	else:
		m.sound.say(0x13)
	shootout_decided_1(o)


## shootout_decided_1: then the menus: the main menu, or the
## competition's own screen with its result recorded (the tournament $22,
## the International Cup's finals $2D, the World Series $30, the
## championship: the ending $33 or game over $27).
func shootout_decided_1(o: ISSMenu.Obj) -> void:
	o.set_w(TIMER, o.w(TIMER) - 1)
	if o.w(TIMER) != 0:
		return
	set_l(S.g_next_state, ISSMenu.STATE_MENU)
	set_w(S.g_next_screen, 0)
	var mode := w(S.g_game_mode)
	if mode == 5:
		ISSModes.tournament_result()
		set_w(S.g_next_screen, 0x22)
	if mode == 8:
		ISSModes.intl_finals_result()
		set_w(S.g_next_screen, 0x2D)
	if mode == 9:
		set_w(S.g_next_screen, 0x30)
	if mode == 0xA:
		ISSModes.championship_result()
		ISSModes.championship_end()
		set_w(S.g_next_screen, 0x33 if w(0x1272) == 0 else 0x27)
	m.fade_out_start()


## shootout_hud: the HUD routine of the frame (g_hud_clock_fn:
## the names in turn), then out of a match the tallies: five marks a side
## (or the kicks of sudden death's round), a ball tile for one not taken,
## a tick or a cross.
func shootout_hud() -> void:
	match l(S.g_hud_clock_fn):
		1:
			shootout_hud_away()
		2:
			shootout_hud_show()
		_:
			shootout_hud_home()
	if w(0x1638) != 0:
		return
	var kicks := w(S.g_shootout_kicks)
	var last := 4 if kicks < 5 else kicks % 5
	var d3 := w(S.g_ball + VRAM) >> 5
	for side in 2:
		var a4 := 0x1526 if side == 0 else 0x1530
		for d4 in last + 1:
			var mark := ISSRam.sw(a4 + d4 * 2)
			var tile := (d3 | 0xE000) if mark < 0 else ((mark * 4 + d3 + 0x1E) | 0xC000)
			m.sprite(0x148, 5, tile, d4 * 16 + (0x98 if side == 0 else 0x118))


## shootout_hud_home: the home side's player in the names' panel: his
## name (tbl_player_names, 8 letters), his role's icon, the controller's
## icon (or CPU); next frame the away side's (_1), then the panel to the
## window (_2).
func shootout_hud_home() -> void:
	_hud_names(0)
	set_l(S.g_hud_clock_fn, 1)


func shootout_hud_away() -> void:
	_hud_names(1)
	set_l(S.g_hud_clock_fn, 2)


func shootout_hud_show() -> void:
	m.vram_dma(ISSVdp.WINDOW + 0x5C0, l(S.g_hud_map), 0x100)
	set_l(S.g_hud_clock_fn, 0)


func _hud_names(side: int) -> void:
	var d5 := (w(S.g_overlay_vram) >> 5) | 0xC000
	var o := l(0x938 if side == 0 else 0x93C) & 0xFFFF
	var hud := l(S.g_hud_map) & 0xFFFF
	var col := 0 if side == 0 else 0x20
	var names := ISSRom.u32(rom("tbl_player_names") + w(S.g_team_home if side == 0 else S.g_team_away) * 4)
	names += ISSRam.b(o + SLOT) * 8
	for i in 8:
		var t := ISSRom.u8(names + i) + 0x33 + d5
		ISSRam.set_w(hud + col + 0xC + 2 * i, t)
		ISSRam.set_w(hud + col + 0xC + 2 * i + 0x40, t + 0x50)
	var role := (ISSRam.b(o + ROLE) & 3) * 2 + 0x10 + d5
	ISSRam.set_w(hud + col + 0xA, role)
	ISSRam.set_w(hud + col + 0xA + 0x40, role + 1)
	var a1 := hud + col + 6
	if w(S.g_pads_home if side == 0 else S.g_pads_away) == 0:
		var t := (0x2C if side == 0 else 0x30) + d5
		ISSRam.set_w(a1, t)
		ISSRam.set_w(a1 + 0x40, t + 1)
		ISSRam.set_w(a1 + 2, t + 2)
		ISSRam.set_w(a1 + 0x42, t + 3)
		return
	# The controller's icon (the slot's pad type: a 6-button pad or not;
	# the ROM reads the slot $8E bytes apart) and the pad's number.
	var n := w(0x1544 if side == 0 else 0x1546)
	var slots: int = S.g_control_slots if side == 0 else 0x15C4
	var t := (0x18 if ISSRam.w(slots + n * ISSModes.PLAYER_SIZE + 8) != 0 else 0x1A) + d5
	ISSRam.set_w(a1 + 0x40, t)
	ISSRam.set_w(a1 + 0x42, t + 1)
	var p := (n + (0 if side == 0 else w(S.g_pads_home))) * 2 + 0x1C + d5
	ISSRam.set_w(a1, p)
	ISSRam.set_w(a1 + 2, p + 1)


# --------------------------------------------------------------------------
# The weather.

## rain_drop: a rain streak falling across (4 pixels a frame
## left and down), then its splash (action 1, 3 frames every 8), and again
## from a random place.
func rain_drop(o: ISSMenu.Obj) -> void:
	o.update = rain_drop_1
	o.set_w(ACTION, 0)
	o.set_w(ANIM_FRAME, 0)
	rain_drop_1(o)


func rain_drop_1(o: ISSMenu.Obj) -> void:
	o.set_w(X, o.w(X) - 4)
	o.set_w(Z, o.w(Z) - 4)
	if o.sw(Z) < 0:
		o.update = rain_drop_splash


func rain_drop_splash(o: ISSMenu.Obj) -> void:
	o.update = rain_drop_2
	o.set_w(ACTION, 1)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 8)
	rain_drop_2(o)


func rain_drop_2(o: ISSMenu.Obj) -> void:
	o.set_w(TIMER, o.w(TIMER) - 1)
	if o.w(TIMER) != 0:
		return
	o.set_w(TIMER, 8)
	o.set_w(ANIM_FRAME, o.w(ANIM_FRAME) + 1)
	if o.sw(ANIM_FRAME) <= 2:
		return
	o.set_w(ANIM_FRAME, 2)
	o.set_w(Y, (ISSModes._rand() & 0x7F) + 0x100)
	var d0 := ISSModes._rand() & 0x1FF
	var d1 := 0x100
	if d0 >= 0x100:
		d1 = d0 & 0xFF
		d0 = 0x100
	o.set_w(X, d0)
	o.set_w(Z, d1)
	o.update = rain_drop


## snow_flake: a snowflake (action 2) falling at
## one of three speeds by its depth, the nearest drifting, then gone
## (action 3) and again from the top.
func snow_flake(o: ISSMenu.Obj) -> void:
	o.update = snow_flake_1
	o.set_w(ACTION, 2)
	o.set_w(ANIM_FRAME, 0)
	if o.sw(Y) > 0x120:
		o.set_w(ANIM_FRAME, 2 if o.sw(Y) > 0x160 else 1)
	snow_flake_1(o)


func snow_flake_1(o: ISSMenu.Obj) -> void:
	var d0 := 0x3000
	if o.w(ANIM_FRAME) != 0:
		if o.w(ANIM_FRAME) == 2:
			var r := (ISSModes._rand() & 3) - 2
			if r < 0:
				r += 1
			o.set_w(X, o.w(X) + r)
			d0 = 0x9000
		else:
			d0 = 0x6000
	var z := (o.l(Z) - d0) & 0xFFFFFFFF
	o.set_l(Z, z)
	if z >= 0x80000000:
		o.update = snow_flake_gone


func snow_flake_gone(o: ISSMenu.Obj) -> void:
	o.update = snow_flake_2
	o.set_w(ACTION, 3)
	o.set_w(TIMER, 8)
	snow_flake_2(o)


func snow_flake_2(o: ISSMenu.Obj) -> void:
	o.set_w(TIMER, o.w(TIMER) - 1)
	if o.w(TIMER) != 0:
		return
	o.set_w(Y, (ISSModes._rand() & 0x7F) + 0x100)
	o.set_w(Z, 0x100)
	o.set_w(X, ISSModes._rand() & 0xFF)
	o.update = snow_flake


# --------------------------------------------------------------------------
# The ball (ball_update_large, ball_draw).

## ball_update_large: the 16 x 16 ball (action 4): bounce and friction as
## the match's, its spin frame 0-2, 3 frames further on beyond y $110 and
## again beyond y $F0 (smaller as it goes away).
func ball_update_large(o: ISSMenu.Obj) -> void:
	var b := o as ISSObjects.Actor
	b.update = ball_update_large_1
	b.set_w(ACTION, 4)
	objects.velocity_from_heading(b, b.w(FACING))
	ball_update_large_1(b)


func ball_update_large_1(o: ISSMenu.Obj) -> void:
	var b := o as ISSObjects.Actor
	b.add_l(Z, b.l(VEL_Z))
	var z := b.sw(Z)
	if z < 0:
		b.set_w(Z, 0)
		var vz := -(b.sl(VEL_Z) >> 1)
		if vz < 0x2000:
			vz = 0
		b.set_l(VEL_Z, vz & 0xFFFFFFFF)
	elif z == 0:
		var f := ISSRom.u16(rom("tbl_ball_friction") + w(S.g_weather) * 2)
		var sp := b.sl(SPEED)
		sp -= sp >> f
		if sp < 0:
			sp = 0
			b.set_w(VEL_X, 0)
			b.set_w(VEL_Y, 0)
		b.set_l(SPEED, sp & 0xFFFFFFFF)
		b.add_l(ANIM_FRAME, b.l(SPEED) >> 2)
	else:
		b.add_l(VEL_Z, -(0x1CCC if w(S.g_is_pal) != 0 else 0x1400))
		b.add_l(ANIM_FRAME, 0x2000)
	var frame := b.w(ANIM_FRAME) % 3
	if b.sw(Y) < 0x110:
		frame += 3
	if b.sw(Y) < 0xF0:
		frame += 3
	b.set_w(ANIM_FRAME, frame)
	b.set_w(FACING, b.w(HEADING))
	objects.velocity_from_heading(b, b.w(FACING))
	b.add_l(X, b.l(VEL_X))
	b.add_l(Y, -b.sl(VEL_Y))


## ball_draw: tbl_ball_anims[action][direction][frame]: the ball (flipped
## facing left) and its shadow obj_z pixels lower.
func ball_draw(o: ISSMenu.Obj) -> void:
	if o.b(VISIBLE) == 0xFF:
		return
	var t := ISSRom.u32(rom("tbl_ball_anims") + o.w(ACTION) * 4)
	t = ISSRom.u32(t + (((o.w(FACING) + 4) & 0x38) >> 1))
	var a4 := ISSRom.u32(t + o.w(ANIM_FRAME) * 4)
	var d3 := o.w(VRAM) >> 5
	var d5 := o.sw(SCREEN_Y)
	var d6 := o.sw(SCREEN_X)
	var attr := o.w(ATTR)
	if o.sw(FACING) >= 0x28:
		m.sprite(d5 + ISSRom.s16(a4), ISSRom.u16(a4 + 2) & 0xFF, ((d3 + ISSRom.u16(a4 + 4)) ^ 0x800) | attr,
			d6 + ISSRom.s16(a4 + 8))
	else:
		m.sprite(d5 + ISSRom.s16(a4), ISSRom.u16(a4 + 2) & 0xFF, (d3 + ISSRom.u16(a4 + 4)) | attr,
			d6 + ISSRom.s16(a4 + 6))
	a4 += 10
	m.sprite(d5 + o.sw(Z) + ISSRom.s16(a4), ISSRom.u16(a4 + 2) & 0xFF, (d3 + ISSRom.u16(a4 + 4)) | attr,
		d6 + ISSRom.s16(a4 + 6))


# --------------------------------------------------------------------------
# The figures as the VDP draws them: the frame's tiles streamed into the
# object's VRAM slot (g_npc_vram_slots), then its sprite pieces.

func _take_slot(o: ISSObjects.Actor) -> bool:
	if o.w(VRAM) != 0:
		return true
	for i in 6:
		var a := S.g_npc_vram_slots + 2 * i
		if w(a) != 0:
			o.set_w(VRAM, w(a))
			set_w(a, 0)
			return true
	return false


## shootout_setup_draw: the taker (tbl_taker_anims[action][direction]
## [frame]): body tiles from g_player_tiles, head ($40 bytes of the side's
## head tiles by shirt number) and hair ($80 of group 6 entry 10 by style);
## the pieces through tbl_sprite_attr_left / _right by obj_attr.
func shootout_setup_draw(o: ISSMenu.Obj) -> void:
	var a := o as ISSObjects.Actor
	if a.b(VISIBLE) == 0xFF:
		return
	if not _take_slot(a):
		return
	var t := ISSRom.u32(rom("tbl_taker_anims") + a.w(ACTION) * 4)
	t = ISSRom.u32(t + (((a.w(FACING) + 4) & 0x38) >> 1))
	var a4 := ISSRom.u32(t + a.w(ANIM_FRAME) * 4)
	var vram := a.w(VRAM)
	if a4 != a.l(FRAME):
		var pt := _player_tiles & 0xFFFF
		var src := pt + ISSRam.l(pt + ISSRom.u16(a4)) + ISSRom.u16(a4 + 2)
		m.vram_dma(vram, 0xFF0000 | src, ISSRom.u16(a4 + 4))
		var side := 0 if a.w(TEAM) == 0 else 1
		var head := ISSRom.s16(a4 + 6)
		if head >= 0:
			var h: int = (int(_head_tiles[side]) & 0xFFFF) + head + (a.b(NUMBER) - 1) * 0xC0
			m.vram_dma(vram + 0x4C0, 0xFF0000 | h, 0x40)
		var hair := ISSRom.s16(a4 + 0xA)
		if hair >= 0:
			m.vdp.dma(vram + 0x500, ISSRom.res(6, 10), hair + a.b(HAIR) * 0x280, 0x80)
		a.set_l(FRAME, a4)
	var p := a4 + 0xC
	var n := ISSRom.u16(p) + 1
	p += 2
	var left := ((a.w(FACING) + 4) & 0x3F) >= 0x28
	var attrs := rom("tbl_sprite_attr_left" if left else "tbl_sprite_attr_right") + a.w(ATTR)
	var d3 := vram >> 5
	for i in n:
		var tile := ISSRom.u16(attrs + ISSRom.u8(p + 3)) + d3 + ISSRom.u16(p + 4)
		m.sprite(a.sw(SCREEN_Y) + ISSRom.s16(p), ISSRom.u8(p + 2), tile,
			a.sw(SCREEN_X) + ISSRom.s16(p + (8 if left else 6)))
		p += 10


## obj_set_frame_draw_draw: the keeper (tbl_keeper_anims[action]
## [direction][frame]): body tiles from group 2; the pieces with obj_attr,
## flipped facing left.
func obj_set_frame_draw_draw(o: ISSMenu.Obj) -> void:
	var a := o as ISSObjects.Actor
	if a.b(VISIBLE) == 0xFF:
		return
	if not _take_slot(a):
		return
	var t := ISSRom.u32(rom("tbl_keeper_anims") + a.w(ACTION) * 4)
	t = ISSRom.u32(t + ((a.w(FACING) + 2) & 0x3C))
	var a4 := ISSRom.u32(t + a.w(ANIM_FRAME) * 4)
	var vram := a.w(VRAM)
	if a4 != a.l(FRAME):
		m.vdp.dma(vram, ISSRom.res(2, ISSRom.u16(a4) >> 2), ISSRom.u16(a4 + 2), ISSRom.u16(a4 + 4))
		a.set_l(FRAME, a4)
	var p := a4 + 6
	var n := ISSRom.u16(p) + 1
	p += 2
	var left := ((a.w(FACING) + 2) & 0x3F) >= 0x20
	var d3 := vram >> 5
	for i in n:
		var tile := (ISSRom.u16(p + 4) + d3) | a.w(ATTR)
		if left:
			tile ^= 0x800
		m.sprite(a.sw(SCREEN_Y) + ISSRom.s16(p), ISSRom.u8(p + 2), tile,
			a.sw(SCREEN_X) + ISSRom.s16(p + (8 if left else 6)))
		p += 10


# --------------------------------------------------------------------------
# The taker (shootout_taker) and his think.

## direction_to: the angle 0-63 from o to (x, y), tbl_atan_octants by the
## ratio |dy| * 256 / |dx|.
func direction_to(o: ISSObjects.Actor, x: int, y: int) -> int:
	var t := rom("tbl_atan_octants")
	var dy := _s16(y - o.w(Y))
	if dy < 0:
		t += 0x44
		dy = -dy
	var d1 := dy << 8
	var dx := _s16(x - o.w(X))
	if dx < 0:
		t += 0x22
		dx = -dx
	if dx == 0:
		return ISSRom.u16(t)
	var q := d1 / dx
	if q > 0xFFFF:
		q = d1 & 0xFFFF
	var k: int
	if q > 0x11A:
		if q > 0x2CB:
			if q > 0x6BE:
				k = 0 if q > 0x145B else 2
			else:
				k = 4 if q > 0x3FE else 6
		elif q > 0x1AB:
			k = 8 if q > 0x21D else 0xA
		else:
			k = 0xC if q > 0x159 else 0xE
	elif q > 0x79:
		if q > 0xBD:
			k = 0x10 if q > 0xE8 else 0x12
		else:
			k = 0x14 if q > 0x99 else 0x16
	elif q > 0x40:
		k = 0x18 if q > 0x5B else 0x1A
	elif q > 0x26:
		k = 0x1C
	else:
		k = 0x1E if q > 0xD else 0x20
	return ISSRom.u16(t + k)


## shootout_taker: standing behind the ball until the pass button (a low
## kick, jog on the spot first) or the lofted one (a high kick, the ready
## stance).
func shootout_taker(o: ISSMenu.Obj) -> void:
	var a := o as ISSObjects.Actor
	a.update = shootout_taker_3
	a.set_w(ACTION, 0)
	a.set_w(ANIM_FRAME, 0)
	a.set_l(SPEED, 0)
	a.set_l(VEL_X, 0)
	a.set_l(VEL_Y, 0)
	shootout_taker_3(a)


func shootout_taker_3(o: ISSMenu.Obj) -> void:
	if o.w(INPUT) & 0x10:
		o.update = shootout_taker_jog_on_the_spot
	if o.w(INPUT) & 0x20:
		o.update = shootout_taker_ready_stance


## shootout_taker_ready_stance / _4: the run-up for the high kick (action
## 1, a frame every 4): the button pressed again before frame 10 sets the
## kick's quality from tbl_kick_quality (position bonus + energy + shot
## power + the run-up's length beyond 24, times 4, + 0-3); at frame 10 the
## kick toward the d-pad's side of the goal; then he waits for the result.
func shootout_taker_ready_stance(o: ISSMenu.Obj) -> void:
	_run_up(o, shootout_taker_4, 1, 0x20)
	shootout_taker_4(o)


func shootout_taker_jog_on_the_spot(o: ISSMenu.Obj) -> void:
	_run_up(o, shootout_taker_5, 2, 0x10)
	shootout_taker_5(o)


func _run_up(o: ISSMenu.Obj, update: Callable, action: int, button: int) -> void:
	o.update = update
	o.set_w(ACTION, action)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 4)
	o.set_l(SPEED, 0x8000)
	o.set_l(VEL_X, 0)
	o.set_l(VEL_Y, 0)
	o.set_w(DISTANCE, 0)
	o.set_w(K8C, 0xFFFF)
	var slot := o.l(OWNER) & 0xFFFF
	ISSRam.set_w(slot + 6, ISSRam.w(slot + 6) | button)
	o.set_w(INPUT, o.w(INPUT) & ~button & 0xFFFF)


## The kick's quality: tbl_kick_quality's byte in the low half of the
## index word (the high half kept, as the game does).
func _quality(o: ISSObjects.Actor, button: int) -> void:
	if o.sw(K8C) >= 0:
		return
	o.set_w(DISTANCE, o.w(DISTANCE) + 1)
	if o.sw(ANIM_FRAME) >= 0xA or o.w(INPUT) & button == 0:
		return
	var d0 := ISSRom.u8(rom("tbl_position_bonus") + o.b(POSITION))
	d0 = (d0 + o.b(ENERGY)) & 0xFF
	d0 = (d0 + o.b(0x5C)) & 0xFF
	d0 = (d0 + maxi(0, o.sw(DISTANCE) - 0x18)) & 0xFFFF
	d0 = (d0 * 4) & 0xFFFF
	d0 += ISSModes._rand() & 3
	o.set_w(K8C, (d0 & 0xFF00) | ISSRom.u8(rom("tbl_kick_quality") + _s16(d0)))


## The point aimed at: the d-pad's side (heading + 16 folded to 0-32, x4,
## less 64), the middle without a direction.
func _aim(o: ISSObjects.Actor) -> int:
	if o.w(INPUT) & 0xF == 0:
		return ((0x10 << 2) - 0x40) & 0xFFFF
	var d0 := (o.w(HEADING) + 0x10) & 0x3F
	if d0 > 0x20:
		d0 = 0x40 - d0
	return ((d0 << 2) - 0x40) & 0xFFFF


func shootout_taker_4(o: ISSMenu.Obj) -> void:
	var a := o as ISSObjects.Actor
	_quality(a, 0x20)
	a.set_w(TIMER, a.w(TIMER) - 1)
	if a.w(TIMER) != 0:
		return
	a.set_w(TIMER, 4)
	a.set_w(ANIM_FRAME, a.w(ANIM_FRAME) + 1)
	if a.w(ANIM_FRAME) == 0xA:
		var d0 := _aim(a)
		set_w(0x14F2, d0)
		a.set_w(KICK_DIR, direction_to(a, _s16(d0) + 0x80, 0xC4))
		var q := a.sw(K8C)
		if q < 0:
			a.set_w(DISTANCE, 0)
			set_w(0x14F4, 0xF)
		else:
			if q == 0:
				a.set_w(DISTANCE, 8)
				set_w(0x14F4, 0x10)
			if q == 1:
				a.set_w(DISTANCE, 0)
				set_w(0x14F4, 0xF)
			if q == 2:
				a.set_w(DISTANCE, 4)
				set_w(0x14F4, 0xF)
		_kick(a, "tbl_taker_high_kick")
	_kicked(a)


func shootout_taker_5(o: ISSMenu.Obj) -> void:
	var a := o as ISSObjects.Actor
	_quality(a, 0x10)
	a.set_w(TIMER, a.w(TIMER) - 1)
	if a.w(TIMER) != 0:
		return
	a.set_w(TIMER, 4)
	a.set_w(ANIM_FRAME, a.w(ANIM_FRAME) + 1)
	if a.w(ANIM_FRAME) == 0xA:
		var d0 := _s16(_aim(a))
		if d0 < 0:
			if a.w(K8C) == 0:
				d0 = -0x80
		elif a.w(K8C) == 0:
			d0 = 0x80
		set_w(0x14F2, d0 & 0xFFFF)
		a.set_w(KICK_DIR, direction_to(a, d0 + 0x80, 0xC4))
		set_w(0x14F4, 0)
		var q := a.sw(K8C)
		if q < 0:
			a.set_w(DISTANCE, 0)
		else:
			if q == 0:
				a.set_w(DISTANCE, 4)
			if q == 1:
				a.set_w(DISTANCE, 0)
			if q == 2:
				a.set_w(DISTANCE, 4)
		_kick(a, "tbl_taker_low_kick")
	_kicked(a)


## After the kick he holds his last frame until the result: a goal (turn
## or side step) or not (shuffle or run), chosen at random.
func _kicked(a: ISSObjects.Actor) -> void:
	if a.sw(ANIM_FRAME) <= 0x17:
		return
	a.set_w(ANIM_FRAME, 0x17)
	if sw(S.g_restart_type) < 0:
		return
	a.update = shootout_taker_6 if w(S.g_restart_type) == R_GOAL else shootout_taker_8


## shootout_taker_1 / _2: the kick (low or high): the ball's speed and lift
## from the table by obj_distance (NTSC / PAL), along obj_kick_dir, loose;
## SFX 84.
func _kick(a: ISSObjects.Actor, table: String) -> void:
	if ISSRam.l(S.g_ball + OWNER) != a.ptr():
		return
	var b := _ball()
	var k := ((a.w(DISTANCE) & 0xFFFC) + (w(S.g_is_pal) & 1)) * 4
	var t := rom(table) + k
	b.set_l(SPEED, ISSRom.u32(t))
	b.set_l(VEL_Z, ISSRom.u32(t + 8))
	b.set_w(Z, b.w(Z) + 1)
	b.set_w(FACING, a.w(KICK_DIR))
	b.set_w(HEADING, a.w(KICK_DIR))
	b.update = ball_update_large
	b.think = objects.obj_steer_idle
	b.set_l(OWNER, 0xFFFFFFFF)
	b.set_b(STATE, 0xFF)
	set_l(S.g_camera_focus, 0xFF0000 | S.g_ball)
	m.play_sfx(84)


func shootout_taker_6(o: ISSMenu.Obj) -> void:
	_after(o, shootout_taker_7, 3 if _hv() & 1 == 0 else 4)
	shootout_taker_7(o)


func shootout_taker_7(o: ISSMenu.Obj) -> void:
	_after_step(o, 6)


func shootout_taker_8(o: ISSMenu.Obj) -> void:
	_after(o, shootout_taker_9, 5 if _hv() & 1 == 0 else 6)
	shootout_taker_9(o)


func shootout_taker_9(o: ISSMenu.Obj) -> void:
	_after_step(o, 3)


func _after(o: ISSMenu.Obj, update: Callable, action: int) -> void:
	o.update = update
	o.set_w(ACTION, action)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 8)
	o.set_l(SPEED, 0)
	o.set_l(VEL_X, 0)
	o.set_l(VEL_Y, 0)


func _after_step(o: ISSMenu.Obj, last: int) -> void:
	o.set_w(TIMER, o.w(TIMER) - 1)
	if o.w(TIMER) != 0:
		return
	o.set_w(TIMER, 8)
	o.set_w(ANIM_FRAME, o.w(ANIM_FRAME) + 1)
	if o.sw(ANIM_FRAME) > last:
		o.set_w(ANIM_FRAME, last)


## shootout_taker_ai: once the kick is allowed a human side's taker follows
## its controller (the buttons held, the d-pad's angle from
## tbl_dpad_angles); the CPU's presses lofted or pass and a direction once,
## at random.
func shootout_taker_ai(o: ISSMenu.Obj) -> void:
	o.think = shootout_taker_ai_1
	o.set_w(CROUCH, 0)
	o.set_w(INPUT, 0)
	o.set_w(HEADING, o.w(FACING))
	shootout_taker_ai_1(o)


func shootout_taker_ai_1(o: ISSMenu.Obj) -> void:
	if sw(S.g_restart_type) >= 0:
		return
	var pads := w(S.g_pads_home if o.w(TEAM) == 0 else S.g_pads_away)
	o.think = shootout_taker_ai_2 if pads != 0 else shootout_taker_ai_4


func shootout_taker_ai_2(o: ISSMenu.Obj) -> void:
	o.think = shootout_taker_ai_3
	o.set_w(CROUCH, 0)
	shootout_taker_ai_3(o)


func shootout_taker_ai_3(o: ISSMenu.Obj) -> void:
	_follow_pad(o, false)


func _follow_pad(o: ISSMenu.Obj, reset_heading: bool) -> void:
	if o.b(STATE) & 0x80:
		return
	var slot := o.l(OWNER) & 0xFFFF
	var d0 := ISSRam.w(slot + 4)
	o.set_w(INPUT, d0)
	if d0 & 0xF:
		o.set_w(HEADING, ISSRom.u16(rom("tbl_dpad_angles") + (d0 & 0xF) * 2))
	elif reset_heading:
		o.set_w(HEADING, o.w(FACING))


func shootout_taker_ai_4(o: ISSMenu.Obj) -> void:
	o.think = shootout_taker_ai_5
	o.set_w(INPUT, 0x2F if _hv() & 1 == 0 else 0x1F)
	o.set_w(HEADING, _hv() & 0x3F & 0xFFF8)


func shootout_taker_ai_5(_o: ISSMenu.Obj) -> void:
	pass


# --------------------------------------------------------------------------
# The keeper (shootout_keeper) and his think.

## shootout_keeper: facing the camera (action 27) until the ball moves:
## then pass + a direction a low dive (crouch, 31), pass the step across
## (33), lofted + a direction the jump (30), lofted the one-arm reach (32);
## a goal (restart $B) beaten (28), a miss or save the dive (34 / 35).
func shootout_keeper(o: ISSMenu.Obj) -> void:
	var a := o as ISSObjects.Actor
	a.update = shootout_keeper_wait
	a.set_w(ACTION, 0x1B)
	a.set_w(ANIM_FRAME, 0)
	a.set_l(SPEED, 0)
	a.set_l(VEL_X, 0)
	a.set_l(VEL_Y, 0)
	set_w(0x14F8, 0)
	shootout_keeper_wait(a)


func shootout_keeper_wait(o: ISSMenu.Obj) -> void:
	var rt := sw(S.g_restart_type)
	if rt >= 0:
		if rt == R_GOAL:
			o.update = shootout_keeper_beaten
		if rt == R_MISS:
			o.update = shootout_keeper_dive
	if ISSRam.l(S.g_ball + SPEED) == 0:
		return
	var input := o.w(INPUT)
	if input & 0x10:
		o.update = shootout_keeper_crouch if input & 0xF else shootout_keeper_step
	if input & 0x20:
		o.update = shootout_keeper_jump if input & 0xF else shootout_keeper_reach


func _keeper_start(o: ISSMenu.Obj, update: Callable, action: int, timer: int) -> void:
	o.update = update
	o.set_w(ACTION, action)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, timer)
	o.set_l(SPEED, 0)
	o.set_l(VEL_X, 0)
	o.set_l(VEL_Y, 0)


## Frames to last every n, held.
func _keeper_anim(o: ISSMenu.Obj, n: int, last: int) -> bool:
	o.set_w(TIMER, o.w(TIMER) - 1)
	if o.w(TIMER) != 0:
		return false
	o.set_w(TIMER, n)
	o.set_w(ANIM_FRAME, o.w(ANIM_FRAME) + 1)
	if o.sw(ANIM_FRAME) <= last:
		return false
	o.set_w(ANIM_FRAME, last)
	return true


func shootout_keeper_beaten(o: ISSMenu.Obj) -> void:
	_keeper_start(o, shootout_keeper_beaten_1, 0x1C, 6)
	o.set_w(FACING, 0x10 if ISSRam.sw(S.g_ball + X) > 0xA0 else 0x30)
	shootout_keeper_beaten_1(o)


func shootout_keeper_beaten_1(o: ISSMenu.Obj) -> void:
	_keeper_anim(o, 6, 2)


## shootout_keeper_step: the step across (8 frames, every 3), the ball
## caught within 16 pixels and below 48 held in front of him.
func shootout_keeper_step(o: ISSMenu.Obj) -> void:
	_keeper_start(o, shootout_keeper_step_1, 0x21, 3)
	o.set_w(KICK_DIR, 0x20)
	set_w(0x14F6, 0x20)
	set_w(0x14F8, 0x10)
	shootout_keeper_step_1(o)


func shootout_keeper_step_1(o: ISSMenu.Obj) -> void:
	var a := o as ISSObjects.Actor
	if _keeper_anim(a, 3, 7):
		var rt := sw(S.g_restart_type)
		if rt >= 0:
			a.update = shootout_keeper_step_hands_over_face if rt == R_GOAL else shootout_keeper_dive
	if ISSRam.l(S.g_ball + OWNER) != a.ptr():
		shootout_keeper_step_3(a)
	else:
		shootout_keeper_step_4(a, 0, 8)


func shootout_keeper_step_hands_over_face(o: ISSMenu.Obj) -> void:
	_keeper_start(o, shootout_keeper_step_2, 0x1D, 6)
	shootout_keeper_step_2(o)


func shootout_keeper_step_2(o: ISSMenu.Obj) -> void:
	_keeper_anim(o, 6, 0xD)


func shootout_keeper_dive(o: ISSMenu.Obj) -> void:
	_keeper_start(o, shootout_keeper_dive_1, 0x22 if _hv() & 1 == 0 else 0x23, 8)
	shootout_keeper_dive_1(o)


func shootout_keeper_dive_1(o: ISSMenu.Obj) -> void:
	_keeper_anim(o, 8, 2)


## shootout_keeper_jump / _crouch: the dive to the d-pad's side (up and
## across with tbl_keeper_leap, or low with the crouch's table), landing
## then sliding to a stop; a touch deflects the ball.
func shootout_keeper_jump(o: ISSMenu.Obj) -> void:
	_dive_start(o, shootout_keeper_jump_1, 0x1E, 0x2C)
	shootout_keeper_jump_1(o)


func shootout_keeper_crouch(o: ISSMenu.Obj) -> void:
	_dive_start(o, shootout_keeper_crouch_1, 0x1F, 0x1C)
	shootout_keeper_crouch_1(o)


func _dive_start(o: ISSMenu.Obj, update: Callable, action: int, reach: int) -> void:
	_keeper_start(o, update, action, 3)
	var d0 := o.w(HEADING)
	set_w(0x14F6, d0)
	set_w(0x14F8, reach)
	o.set_w(FACING, 0x30 if _s16(d0) > 0x20 else 0x10)
	o.set_w(KICK_DIR, o.w(FACING))
	o.set_w(K8C, 0)


func shootout_keeper_jump_1(o: ISSMenu.Obj) -> void:
	_dive(o as ISSObjects.Actor, 3, "tbl_keeper_leap", 0x30)


func shootout_keeper_crouch_1(o: ISSMenu.Obj) -> void:
	_dive(o as ISSObjects.Actor, 2, "tbl_keeper_low_dive", 0x20)


func _gravity() -> int:
	return 0x451E if w(S.g_is_pal) != 0 else 0x3000


func _dive(a: ISSObjects.Actor, launch: int, table: String, height: int) -> void:
	if a.sw(ANIM_FRAME) < launch:
		a.set_w(TIMER, a.w(TIMER) - 1)
		if a.w(TIMER) == 0:
			a.set_w(TIMER, 3)
			a.add_w(ANIM_FRAME, 1)
			if a.w(ANIM_FRAME) == launch:
				var k := (w(S.g_is_pal) & 1) * 4
				a.set_l(SPEED, ISSRom.u32(rom(table) + k))
				a.set_l(VEL_Z, ISSRom.u32(rom(table) + k + 8))
				objects.velocity_from_heading(a, a.w(KICK_DIR))
	else:
		a.add_l(X, a.l(VEL_X))
		a.add_l(Y, -a.sl(VEL_Y))
		if a.sw(ANIM_FRAME) < launch + 2:
			if a.sw(VEL_Z) < 0:
				a.set_w(ANIM_FRAME, launch + 1)
			a.add_l(VEL_Z, -_gravity())
			a.add_l(Z, a.sl(VEL_Z))
			if a.sl(Z) < 0:
				a.set_w(Z, 0)
				a.set_w(ANIM_FRAME, launch + 2)
		else:
			var sp := a.l(SPEED)
			a.set_l(SPEED, sp - (sp >> 2))
			var stop := ISSRom.u32(rom("tbl_keeper_slide_stop") + (w(S.g_is_pal) & 1) * 4)
			if stop > a.l(SPEED):
				var rt := sw(S.g_restart_type)
				if rt >= 0 and rt != R_GOAL:
					a.update = shootout_keeper_dive
			objects.velocity_from_heading(a, a.w(KICK_DIR))
	if a.w(K8C) == 0 and _deflect(a, height, 0, false):
		a.set_w(K8C, 1)


## shootout_keeper_reach: up with one arm (tbl_keeper_leap's lift),
## down again; a touch between 8 and 48 above him stops the ball dead.
func shootout_keeper_reach(o: ISSMenu.Obj) -> void:
	_keeper_start(o, shootout_keeper_reach_1, 0x20, 4)
	set_w(0x14F6, 0x20)
	set_w(0x14F8, 0x20)
	o.set_w(K8C, 0)
	shootout_keeper_reach_1(o)


func shootout_keeper_reach_1(o: ISSMenu.Obj) -> void:
	var a := o as ISSObjects.Actor
	if a.sw(ANIM_FRAME) < 2:
		a.set_w(TIMER, a.w(TIMER) - 1)
		if a.w(TIMER) == 0:
			a.set_w(TIMER, 4)
			a.add_w(ANIM_FRAME, 1)
			if a.w(ANIM_FRAME) == 2:
				a.set_l(VEL_Z, ISSRom.u32(rom("tbl_keeper_leap") + (w(S.g_is_pal) & 1) * 4 + 8))
	else:
		a.add_l(VEL_Z, -_gravity())
		a.add_l(Z, a.sl(VEL_Z))
		if a.sl(Z) < 0:
			a.set_w(Z, 0)
			a.set_l(SPEED, 0)
			a.set_l(VEL_X, 0)
			a.set_l(VEL_Y, 0)
			a.set_w(ANIM_FRAME, 3)
			var rt := sw(S.g_restart_type)
			if rt >= 0 and rt != R_GOAL:
				a.update = shootout_keeper_dive
	if a.w(K8C) == 0 and _deflect(a, 0x30, 8, true):
		a.set_w(K8C, 1)


## shootout_keeper_step_3: the ball (on the ground or loose) within 16
## pixels and 0-47 above his feet is his.
func shootout_keeper_step_3(a: ISSObjects.Actor) -> bool:
	if a.sw(BALL_DIST) > 0x10:
		return false
	if ISSRam.sb(S.g_ball + STATE) > 1:
		return false
	var dz := _s16(ISSRam.w(S.g_ball + Z) - a.w(Z))
	if dz < 0 or dz >= 0x30:
		return false
	var b := _ball()
	b.set_l(OWNER, a.ptr())
	set_w(0x17C2, b.w(TEAM))
	b.set_w(TEAM, a.w(TEAM))
	set_l(S.g_last_touch, a.ptr())
	a.set_w(CROUCH, 0)
	b.update = ball_update_large
	b.think = objects.obj_steer_idle
	b.set_b(STATE, 1)
	return true


## shootout_keeper_step_4: the ball held d5 in front of him, d4 up.
func shootout_keeper_step_4(a: ISSObjects.Actor, d4: int, d5: int) -> void:
	var b := _ball()
	b.set_l(OWNER, a.ptr())
	set_w(0x17C2, b.w(TEAM))
	b.set_w(TEAM, a.w(TEAM))
	var t := rom("tbl_direction_x") + a.w(FACING) * 2
	b.set_w(X, ((d5 * ISSRom.s16(t)) >> 8) + a.w(X))
	b.set_w(Y, -((d5 * ISSRom.s16(t + 0x80)) >> 8) + a.w(Y))
	b.set_w(Z, d4 + a.w(Z))
	b.update = ball_update_large
	b.think = objects.obj_steer_idle
	b.set_w(FACING, a.w(FACING))
	b.set_w(HEADING, a.w(FACING))
	b.set_l(VEL_Z, 0)
	b.set_l(SPEED, a.l(SPEED))
	set_w(0x1A3C, 0)
	b.set_b(STATE, 2)


## shootout_keeper_jump_2 / crouch_2 / reach_2: a touch within 24 pixels
## (and 0 to height above him, or from low for the reach) sends the ball off
## along his dive at half speed and half lift (the reach: dead, a quarter of
## the lift); SFX 90.
func _deflect(a: ISSObjects.Actor, height: int, low: int, dead: bool) -> bool:
	if a.sw(BALL_DIST) > 0x18:
		return false
	if ISSRam.sb(S.g_ball + STATE) >= 2:
		return false
	var dz := _s16(ISSRam.w(S.g_ball + Z) - a.w(Z))
	if dz < low or dz >= height:
		return false
	var b := _ball()
	set_w(0x17C2, b.w(TEAM))
	b.set_w(TEAM, a.w(TEAM))
	b.set_l(OWNER, 0xFFFFFFFF)
	b.set_b(STATE, 0xFF)
	set_l(S.g_camera_focus, 0xFF0000 | S.g_ball)
	b.set_w(FACING, a.w(KICK_DIR))
	b.set_w(HEADING, a.w(KICK_DIR))
	if dead:
		b.set_l(SPEED, 0)
		b.set_l(VEL_Z, (b.sl(VEL_Z) >> 2) & 0xFFFFFFFF)
	else:
		b.set_l(SPEED, b.l(SPEED) >> 1)
		b.set_l(VEL_Z, (b.sl(VEL_Z) >> 1) & 0xFFFFFFFF)
	b.update = ball_update_large
	b.think = objects.obj_steer_idle
	m.play_sfx(90)
	return true


## shootout_keeper_ai: a human side's keeper follows its controller; the
## CPU's waits 8 frames once the ball is loose, then guesses: half the time
## a random direction (or none), else toward the ball's target; lofted or
## pass at random, or lofted when the ball rises.
func shootout_keeper_ai(o: ISSMenu.Obj) -> void:
	o.think = shootout_keeper_ai_1
	o.set_w(CROUCH, 0)
	shootout_keeper_ai_1(o)


func shootout_keeper_ai_1(o: ISSMenu.Obj) -> void:
	if sw(S.g_restart_type) < 0:
		var pads := w(S.g_pads_home if o.w(TEAM) == 0 else S.g_pads_away)
		o.think = shootout_keeper_ai_2 if pads != 0 else shootout_keeper_ai_4
	o.set_w(INPUT, 0)
	o.set_w(HEADING, o.w(FACING))


func shootout_keeper_ai_2(o: ISSMenu.Obj) -> void:
	o.think = shootout_keeper_ai_3
	o.set_w(CROUCH, 0)
	shootout_keeper_ai_3(o)


func shootout_keeper_ai_3(o: ISSMenu.Obj) -> void:
	_follow_pad(o, true)


func shootout_keeper_ai_4(o: ISSMenu.Obj) -> void:
	o.think = shootout_keeper_ai_5
	o.set_w(CROUCH, 0)
	o.set_w(KICK_POWER, 8)
	shootout_keeper_ai_5(o)


func shootout_keeper_ai_5(o: ISSMenu.Obj) -> void:
	if ISSRam.sb(S.g_ball + STATE) >= 0:
		return
	o.set_w(KICK_POWER, o.w(KICK_POWER) - 1)
	if o.w(KICK_POWER) == 0:
		o.think = shootout_keeper_ai_6


func shootout_keeper_ai_6(o: ISSMenu.Obj) -> void:
	o.think = shootout_keeper_ai_7
	o.set_w(INPUT, 0)
	var d4 := _hv()
	if d4 & 1 == 0:
		o.set_w(HEADING, _hv() & 0x3F)
		if _hv() & 1:
			o.set_w(INPUT, 0xF)
	else:
		var tx := ISSRam.sw(S.g_ball + TARGET_X)
		if tx > o.sw(X):
			o.set_w(HEADING, 0x10)
			o.set_w(INPUT, 0xF)
		elif tx < o.sw(X):
			o.set_w(HEADING, 0x30)
			o.set_w(INPUT, 0xF)
	if d4 & 2 == 0:
		o.set_w(INPUT, o.w(INPUT) | (0x20 if _hv() & 1 == 0 else 0x10))
	elif ISSRam.sw(S.g_ball + VEL_Z) > 1:
		o.set_w(INPUT, o.w(INPUT) | 0x20)
	else:
		o.set_w(INPUT, o.w(INPUT) | 0x10)


func shootout_keeper_ai_7(_o: ISSMenu.Obj) -> void:
	pass
