class_name ISSScreensScenario
extends ISSScreens
## The scenarios (mode $C): twelve second halves to win from where they
## stand (screen $24, the cleared ones stamped), and the result after each
## attempt (screen $25: congratulations with the scenario's number when the
## human's side won), then the password, or once all twelve are cleared
## the mode's ending (screen $26).
##
## RAM: $1270 the scenario under the cursor, $129C two bytes a scenario
## (cleared, attempts), $1272 0 when all are cleared.

func register(h: Dictionary) -> void:
	h[0x24] = screen_scenario_select
	h[0x25] = screen_scenario_failed
	h[0x26] = screen_scenario_ending


func _box(k: int) -> int:
	return rom("menu_data_052956") + k * 8


func screen_scenario_select() -> void:
	m.menu_music(5)
	for k in 12:
		if ISSRam.b(0x129C + k * 2) != 0:
			var b := _box(k)
			m.rect_fill_tiles(ISSRom.u16(b), ISSRom.u16(b + 2), ISSRom.u16(b + 4), ISSRom.u16(b + 6),
				tiles() + 0x330)
	spawn(screen_scenario_select_1)
	menu_state_052754(spawn(Callable()))


func screen_scenario_select_1(o: ISSMenu.Obj) -> void:
	o.update = screen_scenario_select_2
	o.set_w(T, 0)
	screen_scenario_select_2(o)


func screen_scenario_select_2(_o: ISSMenu.Obj) -> void:
	m.boxes_draw_sprites(rom("screen_scenario_select_2_data"))


## The way back (top right): C to the main menu; down / up return to the
## grid's top / bottom row.
func menu_state_052754_1(o: ISSMenu.Obj) -> void:
	o.update = menu_state_052754_2
	o.set_w(T, 0)
	menu_state_052754_2(o)


func menu_state_052754_2(o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		goto_screen(0)
		m.play_sfx(95)
	if pressed(PAD_DOWN):
		o.update = menu_state_052754
		set_w(0x1270, w(0x1270) % 3)
		m.play_sfx(77)
	if pressed(PAD_UP):
		o.update = menu_state_052754
		set_w(0x1270, w(0x1270) % 3 + 9)
		m.play_sfx(77)
	o.add_w(T, 1)
	m.cursor_draw(0, 0xE0, 0xF8, 8)


## The scenario's description (tbl_scenario_texts: two large lines, six
## small) and the grid's cursor; C plays it.
func menu_state_052754(o: ISSMenu.Obj) -> void:
	o.update = menu_state_052754_3
	o.set_w(T, 0)
	var a := ISSRom.u32(rom("tbl_scenario_texts") + w(0x1270) * 4)
	a = m.text_draw_large(0x28, 0x80, a)
	a = m.text_draw_large(0x40, 0x90, a)
	for i in 6:
		a = m.text_draw_small(0x18, 0xA0 + i * 8, a)
	m.rect_highlight(0x40, 0xF0, 0x90, 0xA0)
	menu_state_052754_3(o)


func menu_state_052754_3(o: ISSMenu.Obj) -> void:
	if pressed(PAD_B):
		o.update = menu_state_052754_1
	if pressed(PAD_C):
		ISSModes.scenario_setup()
		set_l(S.g_next_state, ISSMenu.STATE_MATCH)
		m.fade_out_start()
		m.play_sfx(95)
		return
	if pressed(PAD_RIGHT):
		add_w(0x1270, 1)
		if w(0x1270) > 0xB:
			set_w(0x1270, 0)
		o.update = menu_state_052754
		m.play_sfx(77)
	if pressed(PAD_LEFT):
		add_w(0x1270, -1)
		if sw(0x1270) < 0:
			set_w(0x1270, 0xB)
		o.update = menu_state_052754
		m.play_sfx(77)
	if pressed(PAD_DOWN):
		if w(0x1270) > 8:
			o.update = menu_state_052754_1
		else:
			add_w(0x1270, 3)
			o.update = menu_state_052754
		m.play_sfx(77)
	if pressed(PAD_UP):
		if w(0x1270) < 3:
			o.update = menu_state_052754_1
		else:
			add_w(0x1270, -3)
			o.update = menu_state_052754
		m.play_sfx(77)
	o.add_w(T, 1)
	var b := _box(w(0x1270))
	m.cursor_draw_large(0, ISSRom.u16(b), ISSRom.u16(b + 2), ISSRom.u16(b + 4) + 1)


# --------------------------------------------------------------------------
# Screen $25: the attempt recorded; a win shows "CONGRATULATIONS!!
# Scenario clear!!" with the scenario's number.

func screen_scenario_failed() -> void:
	m.menu_music(5)
	ISSModes.scenario_record_result()
	if sw(S.g_score_home) > sw(S.g_score_away):
		var a := m.text_draw_large(0x38, 0x48, rom("screen_scenario_failed_data"))
		m.text_draw_large(0x38, 0x60, a)
		m.rect_highlight(0x38, 0xC8, 0x48, 0x58)
		m.rect_fill_tiles(0x80, 0x88, 0x60, 0x70, tiles() + 0x320 + w(0x1270) * 2)
	spawn(screen_scenario_failed_1)


func screen_scenario_failed_1(o: ISSMenu.Obj) -> void:
	o.update = screen_scenario_failed_2
	screen_scenario_failed_2(o)


func screen_scenario_failed_2(_o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		goto_screen(0x26 if sw(0x1272) >= 0 else 0x3B)
		m.play_sfx(95)
	m.boxes_draw_sprites(rom("screen_scenario_failed_2_data"))


# --------------------------------------------------------------------------
# Screen $26: all twelve cleared. In a window a player dribbles across a
# pitch whose lines scroll in perspective (plane B, register 11's line
# mode, the table at $1776), with the dog after him when the twelve took
# under 16 attempts in all; under it each scenario's line slides in and out
# (its number and the attempts it took), then the mode's total and the
# copyright. Start returns to the start of the game.

const X := ISSObjects.X
const Y := ISSObjects.Y
const INPUT := ISSObjects.INPUT
const HEADING := ISSObjects.HEADING

var objects: ISSObjects


func screen_scenario_ending() -> void:
	m.menu_music(8)
	objects = ISSObjects.new(m)
	var buf := l(S.g_unpack_buffer)
	var end := m.unpack(26, 1, buf)
	var a := buf & 0xFFFF
	while a < (end & 0xFFFF):
		ISSRam.set_w(a, ISSRam.w(a) + (w(S.g_overlay_vram) >> 5))
		a += 2
	m.vram_dma(0x2000, buf, end - buf)
	# The line scroll table, all 0.
	set_l(0x1776, buf)
	ISSRam.clear(buf & 0xFFFF, 0x380)
	set_l(S.g_unpack_buffer, buf + 0x380)
	m.vdp.set_line_scroll(buf & 0xFFFF, false)
	if w(S.g_game_level) <= 2:
		ISSRam.copy(0x776, S.g_palette_target, 0x20)
	var team := w(S.g_team_home)
	var kits := ISSRom.res(6, 12)
	for i in 16:
		set_w(S.g_palette_target + 2 * i, (kits[team * 32 + 2 * i] << 8) | kits[team * 32 + 2 * i + 1])
	set_l(0x1814, 0x1C000)
	set_l(0x1818, 0x1C000)
	# The window: figures only between the masks at its sides.
	var clip := Control.new()
	clip.clip_contents = true
	clip.position = Vector2(0x50, 0)
	clip.size = Vector2(0x60, 224)
	m.figures.add_child(clip)
	objects.parent = clip
	var p := objects.player(1)
	objects.link(p)
	p.set_w(ISSObjects.Z, 0)
	p.set_w(X, 0x40)
	p.set_w(Y, 0xF4)
	p.set_w(ISSObjects.ATTR, 0x80)
	p.think = Callable()
	p.set_b(ISSObjects.STATE, 0xFF)
	p.set_w(ISSObjects.FOLLOW, 0xFFFF)
	p.set_w(ISSObjects.FACING, 0x10)
	p.set_w(HEADING, 0x10)
	p.set_w(INPUT, 0xF)
	objects.give_figure(p, "player", team)
	p.set_w(ISSObjects.BALL_DIST, 0x7FFF)
	objects.player_start_run_005D5C(p)
	# The original's first step finds the ball (left by the last match in
	# reach) and starts the dribble; the port starts it as it ends up.
	p.update = objects.player_start_run
	p.set_w(ISSObjects.TEAM, 0)
	m.unpack(7, 6, 0xFF07B6)
	objects.ball = objects.actor(S.g_ball)
	var b := objects.ball
	objects.link(b)
	b.set_w(ISSObjects.Z, 0)
	b.set_w(X, 0x48)
	b.set_w(Y, 0xF4)
	b.think = objects.obj_steer_idle
	b.set_w(INPUT, 0)
	b.set_w(ISSObjects.FACING, 0x10)
	b.set_w(HEADING, 0x10)
	b.set_b(ISSObjects.STATE, 1)
	b.set_l(ISSObjects.OWNER, p.ptr())
	b.set_w(ISSObjects.TEAM, 0)
	b.set_w(ISSObjects.ATTR, 0xE000)
	objects.give_figure(b, "ball")
	objects.ball_update(b)
	var kit := ISSRom.res(4, 38)
	for i in 8:
		set_w(0x796 + 2 * i, (kit[0x30 + 2 * i] << 8) | kit[0x31 + 2 * i])
	if _attempts() < 0x10:
		set_l(0x17B4, 0x1B000)
		set_l(0x17B8, 0x1B000)
		set_w(0x125E, 1)
		objects.referee = objects.actor(S.g_referee)
		var d := objects.referee
		objects.link(d)
		d.set_w(ISSObjects.Z, 0)
		d.set_w(X, 0x34)
		d.set_w(Y, 0x100)
		d.set_w(ISSObjects.ATTR, 0xC000)
		d.set_w(ISSObjects.TEAM, 0xFFFF)
		d.think = Callable()
		d.set_w(INPUT, 0xF)
		d.set_w(ISSObjects.FACING, 0x10)
		d.set_w(HEADING, 0x10)
		objects.give_figure(d, "referee")
		objects.sys_state_00148C(d)
	spawn(screen_scenario_ending_1)
	set_w(0x177A, 0xFFFF)
	spawn(menu_state_053A66)


## The attempts at all twelve (at most 99).
func _attempts() -> int:
	var n := 0
	for k in 12:
		n = mini(n + ISSRam.b(0x129C + k * 2 + 1), 0x63)
	return n


func screen_scenario_ending_1(o: ISSMenu.Obj) -> void:
	o.update = screen_scenario_ending_2
	o.set_w(T, 0)
	screen_scenario_ending_2(o)


## Once faded in, the world moves left 1.5625 a frame under the player (who
## keeps the pace from $80 on); the dog stops ahead of $B4 and starts again
## behind $60. The pitch's lines: 16 at the horizon stepping a pixel every
## 32 frames, 56 below in perspective. The window's side masks (sprites over
## the figures, tile $70 in line 1).
func screen_scenario_ending_2(o: ISSMenu.Obj) -> void:
	if w(S.g_frame_state) == 2:
		var p := objects.player(1)
		p.add_l(X, -0x19000)
		if p.sw(X) >= 0x80:
			p.set_l(ISSObjects.VEL_X, 0x19000)
			p.set_l(ISSObjects.SPEED, 0x19000)
		objects.ball.add_l(X, -0x19000)
		var d := objects.actor(S.g_referee)
		d.add_l(X, -0x19000)
		if d.sw(X) >= 0xB4:
			d.set_w(INPUT, 0)
			d.set_w(HEADING, 0)
		if d.sw(X) < 0x60:
			d.set_w(INPUT, 0xF)
			d.set_w(HEADING, 0x10)
		o.add_w(T, 1)
		var t := l(0x1776) & 0xFFFF
		var a := t + 0x122
		for i in 0x10:
			ISSRam.set_w(a, -((((o.w(T) >> 5) + 0x10) & 0x1F) - 0x10))
			a += 4
		for k in 0x38:
			var v := -((((o.w(T) * 2) + 0x20) & 0x3F) - 0x20)
			ISSRam.set_w(a, int(float(v * k) / 0x37))
			a += 4
		m.vdp.set_line_scroll(t, false)
	var s := rom("screen_scenario_ending_2_data")
	for i in 12:
		m.sprite(ISSRom.u16(s + 2), 0xF, ((w(S.g_stadium_vram) >> 5) + 0xA070) & 0xFFFF, ISSRom.u16(s))
		s += 4


## The next line ($177A the scenario, 12 the mode's total, 13 the
## copyright): drawn, then slid in from the right, held and slid out to the
## left (the lines from $98 on), 256 frames each; the last stays.
func menu_state_053A66(o: ISSMenu.Obj) -> void:
	o.update = menu_state_053A66_1
	o.set_w(T, 0x100)
	m.rect_fill(0x28, 0xD8, 0x98, 0xD8, tiles())
	add_w(0x177A, 1)
	var k := w(0x177A)
	if k > 0xC:
		var a := m.text_draw_large(0x28, 0x98, rom("menu_state_053A66_data3"))
		a = m.text_draw_small(0x28, 0xB8, a)
		a = m.text_draw_small(0x28, 0xC0, a)
		m.text_draw_small(0x28, 0xD0, a)
		menu_state_053A66_1(o)
		return
	var a := rom("menu_state_053A66_data2" if k == 0xC else "menu_state_053A66_data")
	a = m.text_draw_large(0x30, 0x98, a)
	m.text_draw_large(0x30, 0xB0, a)
	var digits := rom("menu_state_053A66_data4")
	var tries: int
	if k != 0xC:
		var n := k + 1
		if n / 10 != 0:
			m.text_draw_large(0x78, 0x98, digits + (n / 10) * 2)
		m.text_draw_large(0x80, 0x98, digits + (n % 10) * 2)
		tries = ISSRam.b(0x129C + k * 2 + 1)
	else:
		tries = _attempts()
	if tries <= 3:
		m.text_draw_large(0x70, 0xB0, rom("menu_state_053A66_data5") + tries * 4)
	else:
		if tries / 10 != 0:
			m.text_draw_large(0x68, 0xB0, digits + (tries / 10) * 2)
		m.text_draw_large(0x70, 0xB0, digits + (tries % 10) * 2)
	menu_state_053A66_1(o)


func menu_state_053A66_1(o: ISSMenu.Obj) -> void:
	var d := o.w(T)
	if d > 0xC0:
		d -= 0x80
	elif d > 0x40:
		d = 0x40
	var a := (l(0x1776) & 0xFFFF) + 0x262
	for i in 0x40:
		ISSRam.set_w(a, d * 4 - 0x100)
		a += 4
	if w(0x177A) < 0xD:
		o.add_w(T, -1)
		if o.w(T) == 0:
			o.update = menu_state_053A66
		return
	if o.w(T) > 0x40:
		o.add_w(T, -1)
	if pressed(PAD_START):
		if sw(S.g_sound_disabled) >= 0:
			set_w(S.g_sound_disabled, 0xFFFF)
			m.sound.stop_music()
		set_l(S.g_next_state, ISSMenu.STATE_INIT)
		m.fade_out_start()

