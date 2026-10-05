class_name ISSScreensMain
extends ISSScreens
## The main menu (screen 0, also 7 and $2E): two columns of four items drawn
## as sprites, the chosen one in palette line 1 with its box flashing, and
## the four button codes it listens for.


func register(h: Dictionary) -> void:
	h[0x00] = screen_main_menu
	h[0x07] = screen_main_menu
	h[0x2E] = screen_main_menu


## screen_main_menu: song 3, the menu object and the code object; the
## controllers are not assigned yet ($153E, g_pads_home / away = 0).
func screen_main_menu() -> void:
	m.menu_music(3)
	spawn(screen_main_menu_1)
	spawn(screen_main_menu_3)
	set_w(0x153E, 0)
	set_w(S.g_pads_home, 0)
	set_w(S.g_pads_away, 0)


func screen_main_menu_1(o: ISSMenu.Obj) -> void:
	o.update = screen_main_menu_2
	o.set_w(T, 0)
	screen_main_menu_2(o)


## screen_main_menu_2: items 0-3 down the left column, 4-7 down the right;
## left / right swap columns, up / down wrap in the column, B goes back to
## the first item, C starts the item (fade, SFX 95).
func screen_main_menu_2(o: ISSMenu.Obj) -> void:
	var item := w(S.g_menu_item)
	if pressed(PAD_RIGHT):
		item += 4
		if item > 7:
			item -= 8
		_moved(o, item)
	if pressed(PAD_LEFT):
		item = w(S.g_menu_item) - 4
		if item < 0:
			item += 8
		_moved(o, item)
	if pressed(PAD_DOWN):
		item = w(S.g_menu_item)
		item = item - 3 if item & 3 == 3 else item + 1
		_moved(o, item)
	if pressed(PAD_UP):
		item = w(S.g_menu_item)
		item = item + 3 if item & 3 == 0 else item - 1
		_moved(o, item)
	if pressed(PAD_B):
		set_w(S.g_menu_item, 0)
	if pressed(PAD_C):
		_choose()
	# Draw: the boxes' highlight off, the chosen box flashing, the eight
	# labels as sprites (tiles $336 + of the screen, line 1 when chosen).
	m.rect_unhighlight_all(0, 0x100, 0x10, 0xD0)
	o.add_w(T, 1)
	var r := rom("tbl_main_menu_boxes") + w(S.g_menu_item) * 8
	m.rect_flash(ISSRom.u16(r), ISSRom.u16(r + 2), ISSRom.u16(r + 4), ISSRom.u16(r + 6))
	var a := rom("tbl_main_menu_labels")
	for i in 8:
		var attr := (w(S.g_stadium_vram) >> 5) + (0xA336 if i == w(S.g_menu_item) else 0x8336)
		while true:
			m.sprite(ISSRom.u8(a + 1) * 8 + 0x80, ISSRom.u8(a + 2), attr + ISSRom.u8(a + 3) * 4,
				ISSRom.u8(a) + 0x80)
			a += 4
			if ISSRom.u8(a) == 0xFF:
				break
		a += 1


func _moved(o: ISSMenu.Obj, item: int) -> void:
	set_w(S.g_menu_item, item)
	o.set_w(T, 0)
	m.play_sfx(77)


func _choose() -> void:
	set_l(S.g_next_state, ISSMenu.STATE_MENU)
	var item := w(S.g_menu_item)
	match item:
		0:
			set_w(S.g_next_screen, 0x01)
		1:
			ISSModes.start_international()
			set_w(S.g_next_screen, 0x36)
			if w(0x1260) != 0:
				# Code 4: straight to the finals with a random team.
				set_w(0x127C, randi() % 36)
				ISSModes.international_finals()
				ISSModes.intl_finals_next_game()
				set_w(S.g_weather, 1)
				set_w(0x1630, 0)
				set_l(S.g_next_state, ISSMenu.STATE_SCREEN)
				set_w(0x1730, 2)
		2:
			ISSModes.start_world_series()
			set_w(S.g_next_screen, 0x37)
			if w(0x1260) != 0:
				var t := randi() % 36
				set_w(0x127C, t)
				set_w(0x127E, t)
				set_w(0x1280, t)
				ISSModes.ws_second_series()
				ISSModes.ws_next_game()
				set_w(S.g_weather, 1)
				set_w(0x1630, 0)
				set_l(S.g_next_state, ISSMenu.STATE_SCREEN)
				set_w(0x1730, 2)
		3:
			set_w(S.g_next_screen, 0x3A)
		4:
			ISSModes.start_scenario()
			set_w(S.g_next_screen, 0x24)
			if w(0x1260) != 0:
				var t := randi() % 36
				set_w(0x127C, t)
				set_w(0x127E, t)
				ISSModes.menu_func_05AEAC()
				set_w(S.g_next_screen, 0x26)
		5:
			ISSModes.start_pk()
			set_w(S.g_next_screen, 0x02)
		6:
			set_w(S.g_next_screen, 0x13)
		7:
			set_w(S.g_next_screen, 0x11)
	m.fade_out_start()
	m.play_sfx(95)


## screen_main_menu_3/4: the four button codes (screen_main_menu_4_data,
## 17 bytes each, $FF-terminated). Each press either advances a code's
## position ($125A + 2 * code) or resets it; a completed code stays put
## (SFX 71 + code) and its word is what the game later tests.
func screen_main_menu_3(o: ISSMenu.Obj) -> void:
	o.update = screen_main_menu_4
	screen_main_menu_4(o)


func screen_main_menu_4(_o: ISSMenu.Obj) -> void:
	var d5 := w(S.g_pad_pressed_any)
	if d5 == 0:
		return
	var seq := rom("tbl_button_codes")
	for i in 4:
		var at := 0x125A + 2 * i
		var pos := w(at)
		if ISSRom.u8(seq + pos) < 0x80:
			if ISSRom.u8(seq + pos) == d5:
				set_w(at, pos + 1)
				if ISSRom.u8(seq + pos + 1) >= 0x80:
					m.play_sfx(71 + i)
			else:
				set_w(at, 0)
		seq += 0x11
