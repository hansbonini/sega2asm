class_name ISSScreensOptions
extends ISSScreens
## Options ($11: game level, game time, sound, rules) and rules ($12:
## fouls, cards, offside, overtime, the referee), both over the settings
## words (g_settings), which are saved as they change (settings_checksum).


func register(h: Dictionary) -> void:
	h[0x11] = screen_options
	h[0x12] = screen_rules


## The boxes of a setting's values: the chosen one highlighted.
func _boxes(table: String, count: int, value: int, first := 0) -> void:
	var a := rom(table)
	for k in range(first, first + count):
		var r := [ISSRom.u16(a), ISSRom.u16(a + 2), ISSRom.u16(a + 4), ISSRom.u16(a + 6)]
		if k == value:
			m.rect_highlight(r[0], r[1], r[2], r[3])
		else:
			m.rect_unhighlight(r[0], r[1], r[2], r[3])
		a += 8


func _cursor(table: String, index: int) -> void:
	var a := rom(table) + index * 8
	m.cursor_draw_large(0, ISSRom.u16(a), ISSRom.u16(a + 2), ISSRom.u16(a + 4) + 1)


## One option row: B (and the pads in back) leaves for the exit item, up /
## down to the neighbours, left / right change the value (wrapping in
## lo..hi, or toggling when step is 0) and save the settings.
func _option(o: ISSMenu.Obj, back: int, back_sfx: bool, exit: Callable, up: Callable, down: Callable,
		addr: int, lo: int, hi: int, me: Callable) -> void:
	if pressed(back):
		o.update = exit
		if back_sfx:
			m.play_sfx(77)
	if pressed(PAD_UP) and back & PAD_UP == 0:
		o.update = up
		m.play_sfx(77)
	if pressed(PAD_DOWN) and back & PAD_DOWN == 0:
		o.update = down
		m.play_sfx(77)
	if hi == lo + 1 and pressed(PAD_LEFT | PAD_RIGHT):
		set_w(addr, w(addr) ^ 1)
		ISSMenu.save_settings()
		o.update = me
		m.play_sfx(77)
	elif hi != lo + 1:
		if pressed(PAD_RIGHT):
			set_w(addr, lo if w(addr) + 1 > hi else w(addr) + 1)
			ISSMenu.save_settings()
			o.update = me
			m.play_sfx(77)
		if pressed(PAD_LEFT):
			set_w(addr, hi if w(addr) - 1 < lo else w(addr) - 1)
			ISSMenu.save_settings()
			o.update = me
			m.play_sfx(77)
	o.add_w(T, 1)


# --------------------------------------------------------------------------
# Screen $11: options.

func screen_options() -> void:
	spawn(screen_options_1)
	var o := spawn(Callable())
	menu_state_04D1BC(o)
	menu_state_04D05C(o)
	menu_state_04CEFA(o)


func screen_options_1(o: ISSMenu.Obj) -> void:
	o.update = screen_options_2
	o.set_w(T, 0)
	screen_options_2(o)


func screen_options_2(_o: ISSMenu.Obj) -> void:
	m.boxes_draw_sprites(rom("tbl_options_boxes"))


## The exit mark (top right): C back to the main menu.
func menu_state_04CE58(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04CE58_1
	menu_state_04CE58_1(o)


func menu_state_04CE58_1(o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		goto_screen(0)
		m.play_sfx(95)
	if pressed(PAD_UP):
		o.update = menu_state_04D2C6
		m.play_sfx(77)
	if pressed(PAD_DOWN):
		o.update = menu_state_04CEFA
		m.play_sfx(77)
	o.add_w(T, 1)
	m.cursor_draw(0, 0xE0, 0xF8, 8)


## Game level 0-4.
func menu_state_04CEFA(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04CEFA_1
	_boxes("tbl_options_level_boxes", 5, w(S.g_settings))
	menu_state_04CEFA_1(o)


func menu_state_04CEFA_1(o: ISSMenu.Obj) -> void:
	_option(o, PAD_B | PAD_UP, true, menu_state_04CE58, Callable(), menu_state_04D05C,
		S.g_settings, 0, 4, menu_state_04CEFA)
	_cursor("tbl_options_level_boxes", w(S.g_settings))


## Game time 1-3.
func menu_state_04D05C(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04D05C_1
	_boxes("tbl_options_time_boxes", 3, w(S.g_opt_time), 1)
	menu_state_04D05C_1(o)


func menu_state_04D05C_1(o: ISSMenu.Obj) -> void:
	_option(o, PAD_B, false, menu_state_04CE58, menu_state_04CEFA, menu_state_04D1BC,
		S.g_opt_time, 1, 3, menu_state_04D05C)
	_cursor("tbl_options_time_boxes", w(S.g_opt_time) - 1)


## Sound: stereo / mono.
func menu_state_04D1BC(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04D1BC_1
	_boxes("tbl_options_sound_boxes", 2, w(S.g_opt_mono))
	menu_state_04D1BC_1(o)


func menu_state_04D1BC_1(o: ISSMenu.Obj) -> void:
	_option(o, PAD_B, false, menu_state_04CE58, menu_state_04D05C, menu_state_04D2C6,
		S.g_opt_mono, 0, 1, menu_state_04D1BC)
	_cursor("tbl_options_sound_boxes", w(S.g_opt_mono))


## Rules: C opens the rules screen.
func menu_state_04D2C6(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04D2C6_1
	menu_state_04D2C6_1(o)


func menu_state_04D2C6_1(o: ISSMenu.Obj) -> void:
	if pressed(PAD_B | PAD_DOWN):
		o.update = menu_state_04CE58
		m.play_sfx(77)
	if pressed(PAD_C):
		goto_screen(0x12)
		m.play_sfx(95)
	if pressed(PAD_UP):
		o.update = menu_state_04D1BC
		m.play_sfx(77)
	o.add_w(T, 1)
	m.cursor_draw_large(0, 0x18, 0x40, 0x71)


# --------------------------------------------------------------------------
# Screen $12: rules. The three referees stand under their names (drawn
# with the match's officials, kits from group 4 entry 38); the chosen one
# turns round while the referee row is being set. Code 3 ($125E) makes
# them dance.

const REFEREE_DANCE := 0xF
const REFEREE_STAND := 1


func screen_rules() -> void:
	spawn(screen_rules_1)
	var o := spawn(Callable())
	menu_state_04D968(o)
	menu_state_04D85E(o)
	menu_state_04D754(o)
	menu_state_04D64A(o)
	menu_state_04D552(o)
	# The referees' tile slots and their kits in lines 0-2 (colours 0-7).
	for i in 3:
		set_w(S.g_npc_vram_slots + 2 * i, w(S.g_unpack_vram))
		add_w(S.g_unpack_vram, 0x2E0)
	var kits := ISSRom.res(4, 38)
	for line in 3:
		var dst: int = [S.g_palette_target, 0x776, 0x796][line]
		for i in 16:
			ISSRam.set_b(dst + i, kits[line * 16 + i])
	var a := rom("tbl_rules_referee_boxes")
	for i in 3:
		var f := ISSNPCSprite.new()
		f.kit = i
		f.action = REFEREE_DANCE if w(0x125E) != 0 else REFEREE_STAND
		f.facing = 0x20
		f.position = Vector2(ISSRom.u16(a) + 0x1C, ISSRom.u16(a + 4) + 0x36)
		m.figures.add_child(f)
		a += 8


func screen_rules_1(o: ISSMenu.Obj) -> void:
	o.update = screen_rules_2
	screen_rules_2(o)


func screen_rules_2(_o: ISSMenu.Obj) -> void:
	m.boxes_draw_sprites(rom("tbl_rules_boxes"))


## The exit mark: C back to the options.
func menu_state_04D4B0(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04D4B0_1
	menu_state_04D4B0_1(o)


func menu_state_04D4B0_1(o: ISSMenu.Obj) -> void:
	if pressed(PAD_C):
		goto_screen(0x11)
		m.play_sfx(95)
	if pressed(PAD_UP):
		o.update = menu_state_04D968
		m.play_sfx(77)
	if pressed(PAD_DOWN):
		o.update = menu_state_04D552
		m.play_sfx(77)
	o.add_w(T, 1)
	m.cursor_draw(0, 0xE0, 0xF8, 8)


func _toggle_row(o: ISSMenu.Obj, table: String, addr: int, me: Callable) -> void:
	o.update = me
	_boxes(table, 2, w(addr))


## Fouls on / off.
func menu_state_04D552(o: ISSMenu.Obj) -> void:
	_toggle_row(o, "tbl_rules_foul_boxes", S.g_opt_fouls_off, menu_state_04D552_1)
	menu_state_04D552_1(o)


func menu_state_04D552_1(o: ISSMenu.Obj) -> void:
	_option(o, PAD_B | PAD_UP, true, menu_state_04D4B0, Callable(), menu_state_04D64A,
		S.g_opt_fouls_off, 0, 1, menu_state_04D552)
	_cursor("tbl_rules_foul_boxes", w(S.g_opt_fouls_off))


## Yellow cards on / off.
func menu_state_04D64A(o: ISSMenu.Obj) -> void:
	_toggle_row(o, "tbl_rules_card_boxes", S.g_opt_cards_off, menu_state_04D64A_1)
	menu_state_04D64A_1(o)


func menu_state_04D64A_1(o: ISSMenu.Obj) -> void:
	_option(o, PAD_B, false, menu_state_04D4B0, menu_state_04D552, menu_state_04D754,
		S.g_opt_cards_off, 0, 1, menu_state_04D64A)
	_cursor("tbl_rules_card_boxes", w(S.g_opt_cards_off))


## Offside on / off.
func menu_state_04D754(o: ISSMenu.Obj) -> void:
	_toggle_row(o, "tbl_rules_offside_boxes", S.g_opt_offside_off, menu_state_04D754_1)
	menu_state_04D754_1(o)


func menu_state_04D754_1(o: ISSMenu.Obj) -> void:
	_option(o, PAD_B, false, menu_state_04D4B0, menu_state_04D64A, menu_state_04D85E,
		S.g_opt_offside_off, 0, 1, menu_state_04D754)
	_cursor("tbl_rules_offside_boxes", w(S.g_opt_offside_off))


## Overtime: V-goal / full extra time.
func menu_state_04D85E(o: ISSMenu.Obj) -> void:
	_toggle_row(o, "tbl_rules_overtime_boxes", S.g_opt_vgoal, menu_state_04D85E_1)
	menu_state_04D85E_1(o)


func menu_state_04D85E_1(o: ISSMenu.Obj) -> void:
	_option(o, PAD_B, false, menu_state_04D4B0, menu_state_04D754, menu_state_04D968,
		S.g_opt_vgoal, 0, 1, menu_state_04D85E)
	_cursor("tbl_rules_overtime_boxes", w(S.g_opt_vgoal))


## The referee: Carlos, Heinz, Hasegawa or any of them.
func menu_state_04D968(o: ISSMenu.Obj) -> void:
	o.update = menu_state_04D968_1
	o.set_w(T, 0)
	_boxes("tbl_rules_referee_boxes", 4, w(S.g_opt_referee))
	menu_state_04D968_1(o)


func menu_state_04D968_1(o: ISSMenu.Obj) -> void:
	_option(o, PAD_B | PAD_DOWN, true, menu_state_04D4B0, menu_state_04D85E, Callable(),
		S.g_opt_referee, 0, 3, menu_state_04D968)
	# The chosen referee turns round (facing 0-63 with a pause facing the
	# screen) while this row is current; the others face the screen.
	var figs := m.figures.get_children()
	for i in mini(3, figs.size()):
		var facing := 0x20
		if o.update == menu_state_04D968_1 and i == w(S.g_opt_referee):
			var d := ((o.w(T) + 0x40) & 0x7F) - 0x20
			d = maxi(d, 0)
			if d > 0x20:
				d = maxi(d - 0x40, 0) + 0x20
			facing = d
		figs[i].facing = facing
	var a := rom("tbl_rules_referee_boxes") + w(S.g_opt_referee) * 8
	if o.update == menu_state_04D968_1:
		m.rect_flash(ISSRom.u16(a), ISSRom.u16(a + 2), ISSRom.u16(a + 4), ISSRom.u16(a + 6))
	else:
		m.rect_highlight(ISSRom.u16(a), ISSRom.u16(a + 2), ISSRom.u16(a + 4), ISSRom.u16(a + 6))
