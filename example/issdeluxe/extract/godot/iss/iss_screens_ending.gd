class_name ISSScreensEnding
extends ISSScreens
## The ends of a competition: game over (screen $27, the human sides out)
## and congratulations (screen $28, a human side won: its flag and slot
## number, the trophy picture, the winners in the team's kit). Each draws a
## picture map from group 19 into the text nametable and its sprites; Start
## goes back to the start of the game (main_init).

func register(h: Dictionary) -> void:
	h[0x27] = screen_game_over
	h[0x28] = screen_congratulations


## Unpack (g, e) and send it to g_unpack_vram, which advances; its VRAM
## address.
func _tiles(g: int, e: int) -> int:
	return m.load_tiles(g, e)


## The picture map of group 19 entry 0 from src (bytes into the map) into
## the text nametable at offset dst: rows x cols cells, skip bytes between
## rows, tile base ($1776 >> 5) | $8000.
func _picture(src: int, dst: int, rows: int, cols: int, skip: int) -> void:
	var map := ISSRom.res(19, 0)
	var base := (w(0x1776) >> 5) | 0x8000
	var tn := l(S.g_text_nametable) & 0xFFFF
	var a := src
	for r in rows:
		for c in cols:
			var v := (map[a] << 8) | map[a + 1]
			ISSRam.set_w(tn + dst + r * 0x80 + c * 2, (v + base) & 0xFFFF)
			a += 2
		a += skip


## n sprites from table t (y, size, tile, x words) at (x0, y0) on tiles from
## $1778.
func _sprites(t: int, n: int, x0: int, y0: int) -> void:
	for i in n:
		var e := t + i * 8
		m.sprite(y0 + ISSRom.u16(e), ISSRom.u16(e + 2) & 0xFF, (w(0x1778) >> 5) + ISSRom.u16(e + 4),
			x0 + ISSRom.u16(e + 6))


## Start: back to main_init.
func _start_over() -> void:
	if pressed(PAD_START):
		set_l(S.g_next_state, ISSMenu.STATE_INIT)
		m.fade_out_start()


func screen_game_over() -> void:
	m.menu_music(0x11)
	for i in 9:
		set_w(0x7BE + 2 * i, 0)
	set_w(0x1776, _tiles(19, 1))
	_picture(0xD8, 0x290, 12, 16, 4)
	set_w(0x7B8, 0x666)
	set_w(0x7BC, 0x222)
	set_w(0x7D0, 0x666)
	set_w(0x7D2, 0x444)
	set_w(0x7D4, 0x888)
	set_w(0x1778, _tiles(4, 25))
	spawn(screen_game_over_1)


func screen_game_over_1(o: ISSMenu.Obj) -> void:
	o.update = screen_game_over_2
	o.set_w(T, 0)
	screen_game_over_2(o)


func screen_game_over_2(_o: ISSMenu.Obj) -> void:
	_start_over()
	_sprites(rom("screen_game_over_2_data"), 5, 0x58, 0x40)


func screen_congratulations() -> void:
	# Plane A: group 26 entry 1, its tiles after g_overlay_vram's.
	var buf := l(S.g_unpack_buffer)
	var end := m.unpack(26, 1, buf)
	var ov := w(S.g_overlay_vram) >> 5
	var a := buf & 0xFFFF
	while a < (end & 0xFFFF):
		ISSRam.set_w(a, ISSRam.w(a) + ov)
		a += 2
	m.vram_dma(0x2000, buf, end - buf)
	# The winner's flag.
	var team := w(0x127C + w(0x1272) * 2)
	m.unpack(6, 2, buf)
	m.vram_dma(w(S.g_overlay_vram) + 0x6460, buf + team * 0xC0, 0xC0)
	set_w(0x1776, _tiles(19, 1))
	_picture(4, 0x292, 15, 14, 8)
	set_w(0x7B8, 0x284)
	set_w(0x7BC, 0x040)
	set_w(0x7D0, 0x48C)
	set_w(0x7D2, 0x062)
	set_w(0x7D4, 0x2A6)
	var c := rom("screen_congratulations_data")
	for i in 10:
		set_w(0x7BE + 2 * i, ISSRom.u16(c + 2 * i))
	set_w(0x1778, _tiles(4, 26))
	# The winner's kit on palette line 0, shaded.
	var kits := ISSRom.res(6, 12)
	for i in 16:
		set_w(S.g_palette_target + 2 * i, (kits[team * 32 + 2 * i] << 8) | kits[team * 32 + 2 * i + 1])
	ISSModes.kit_shades()
	m.text_draw_large(0xA0, 8, rom("screen_congratulations_data2") + w(0x1272) * 2)
	spawn(screen_congratulations_1)


func screen_congratulations_1(o: ISSMenu.Obj) -> void:
	o.update = screen_congratulations_2
	o.set_w(T, 0)
	screen_congratulations_2(o)


func screen_congratulations_2(_o: ISSMenu.Obj) -> void:
	_start_over()
	_sprites(rom("screen_congratulations_2_data"), 12, 0x58, 0x28)
