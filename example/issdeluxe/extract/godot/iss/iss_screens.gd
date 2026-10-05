class_name ISSScreens
extends RefCounted
## Base of the front-end screen ports: each subclass registers the screen
## handlers it ports (tbl_screen_handlers) and keeps the ROM's structure,
## one function per routine, named after it. Shorthands for the RAM
## (ISSRam), the symbols (S) and the menu engine's helpers (m).

const S := preload("res://iss/iss_sym.gd")
const PAD_UP := 0x01
const PAD_DOWN := 0x02
const PAD_LEFT := 0x04
const PAD_RIGHT := 0x08
const PAD_B := 0x10
const PAD_C := 0x20
const PAD_A := 0x40
const PAD_START := 0x80
const T := ISSMenu.O_TIMER

var m: ISSMenu


func _init(menu: ISSMenu) -> void:
	m = menu


## Override: map screen numbers to their handlers.
func register(_handlers: Dictionary) -> void:
	pass


func w(a: int) -> int:
	return ISSRam.w(a)


func sw(a: int) -> int:
	return ISSRam.sw(a)


func l(a: int) -> int:
	return ISSRam.l(a)


func set_w(a: int, v: int) -> void:
	ISSRam.set_w(a, v)


func set_l(a: int, v: int) -> void:
	ISSRam.set_l(a, v)


func add_w(a: int, v: int) -> void:
	ISSRam.add_w(a, v)


## g_pad_pressed_any & bits.
func pressed(bits: int) -> bool:
	return w(S.g_pad_pressed_any) & bits != 0


## g_pad_pressed_home & bits (the edit screens listen to the first pad).
func pressed_home(bits: int) -> bool:
	return w(S.g_pad_pressed_home) & bits != 0


func rom(name: String) -> int:
	return ISSRom.addr(name)


## A new object with only an update callback (draw and think -1).
func spawn(update: Callable) -> ISSMenu.Obj:
	var o := m.obj_alloc()
	if o != null:
		o.update = update
	return o


## Leave for screen n of state_menu with the fade, as the screens do.
func goto_screen(n: int) -> void:
	set_l(S.g_next_state, ISSMenu.STATE_MENU)
	set_w(S.g_next_screen, n)
	m.fade_out_start()


## The first tile of the backdrop group in the front plane's high
## priority ((g_stadium_vram >> 5) | $C000), the base of the screens' tiles.
func tiles() -> int:
	return (w(S.g_stadium_vram) >> 5) | 0xC000


## The side's icon (controller number or CPU) at (x0..x1, y0..y1).
func side_icon(side: int, x0: int, x1: int, y0: int, y1: int) -> void:
	var t := tiles()
	if side == 0:
		t += 0x180 + (w(0x1642) * 4 if w(S.g_pads_home) != 0 else 0x20)
	else:
		t += 0x1A4 + (w(0x1644) * 4 if w(S.g_pads_away) != 0 else 0x20)
	m.rect_fill_tiles(x0, x1, y0, y1, t)


## Scroll plane B towards x (8 a frame); true while it moves.
func scrolling(target: int) -> bool:
	var h := sw(S.g_plane_b_hscroll)
	if h == target:
		return false
	set_w(S.g_plane_b_hscroll, h + (8 if target > h else -8))
	return true


## Player k (0-19) of a side: its object.
func player(side: int, k: int) -> int:
	return m.team_players(side) + k * ISSModes.PLAYER_SIZE


## The player's name (tbl_player_names: 8 bytes per squad index) for the
## side's team.
func player_name(side: int, p: int) -> int:
	var team := w(S.g_team_home if side == 0 else S.g_team_away)
	return ISSRom.u32(rom("tbl_player_names") + team * 4) + ISSRam.b(p + 0x56) * 8


## The player's status (g_player_status of the side's team: 0-3 or 4 for
## unavailable).
func player_status(side: int, p: int) -> int:
	var base: int = S.g_player_status + w(0x1642 if side == 0 else 0x1644) * 20
	return ISSRam.b(base + ISSRam.b(p + 0x56)) & 7


## The controller icon of a competition slot: its pad's number for a
## human slot (below $1266), else the computer's.
func slot_icon(slot: int) -> int:
	var t := tiles() + 0x180
	return t + slot * 4 if slot < w(0x1266) else t + 0x20


## One number of a competition's "human teams" grid: its count in $1266;
## left / right to the one beside it, down / up through the column. The
## large cursor at cursor (x0, x1, y), the number's box (x0, x1, y0, y1).
func humans_item(o: ISSMenu.Obj, n: int, here: Callable, beside: Callable, down: Callable, up: Callable,
		cursor: Array, box: Array) -> void:
	set_w(0x1266, n)
	if pressed(PAD_LEFT | PAD_RIGHT):
		o.update = beside
		m.play_sfx(77)
	if pressed(PAD_DOWN):
		o.update = down
		m.play_sfx(77)
	if pressed(PAD_UP):
		o.update = up
		m.play_sfx(77)
	o.add_w(T, 1)
	m.cursor_draw_large(0, cursor[0], cursor[1], cursor[2])
	if o.update == here:
		m.rect_highlight(box[0], box[1], box[2], box[3])
	else:
		m.rect_unhighlight(box[0], box[1], box[2], box[3])
