class_name ISSMenu
extends Node2D
## The front end as the game runs it: a port of state_menu (menu screens
## built from objects) on a model of the Mega Drive it drew on (ISSVdp for
## VRAM, CRAM and sprites; ISSRam for the work RAM; ISSRom for the data
## blocks and the resource archive). Each frame is state_menu_frame: read
## the pads, run the objects' callbacks, build the pad edges with the menus'
## auto-repeat (state_menu_frame_1), copy the text nametable to plane B and
## draw the sprites. The screens themselves (tbl_screen_handlers) are ports
## of the game's routines in the ISSScreens* scripts, which call the helpers
## below by their ROM names (text_draw_large, rect_flash, cursor_draw ...).
##
## state_screen's presentations (ISSPresentation), state_shootout's kicks
## (ISSShootout) and the boot screens before the title (ISSBoot, main_init)
## run on the same engine.
##
## When a fade to black ends (g_frame_state = 0) the game jumps to
## g_next_state: another menu screen (g_next_screen) or a presentation is
## loaded here; any other state (a match) is handed to the owner through
## next_state, with the game's RAM as the record of what was
## chosen.

signal next_state(state: int)

const S := preload("res://iss/iss_sym.gd")

## Game states: the ROM routines g_next_state holds.
const STATE_MENU := 0x01FF16
const STATE_SCREEN := 0x01FFF4
const STATE_MATCH := 0x0200D2
const STATE_SHOOTOUT := 0x0201FE
## main_init: the boot screens, then the title and the main menu.
const STATE_INIT := 0x000358

const NUM_OBJS := 16
const OBJ_SIZE := 0x8E
## Object field: the frame timer the menu helpers blink and animate with.
const O_TIMER := 0x7C
const SETTINGS_SAVE := "user://iss_settings.bin"


## A menu object (16 of them, $8E bytes each at $FF0976): callbacks and the
## fields the screens keep in it, addressed by their offsets.
class Obj:
	var update := Callable()
	var think := Callable()
	var draw := Callable()
	var f := PackedByteArray()
	var alive := true
	## One of the 16 menu objects (the match's objects are linked into the
	## same list from their own RAM).
	var pooled := true

	func _init() -> void:
		f.resize(ISSMenu.OBJ_SIZE)

	func b(o: int) -> int:
		return f[o]

	func set_b(o: int, v: int) -> void:
		f[o] = v & 0xFF

	func w(o: int) -> int:
		return (f[o] << 8) | f[o + 1]

	func sw(o: int) -> int:
		var v := w(o)
		return v - 65536 if v >= 32768 else v

	func set_w(o: int, v: int) -> void:
		f[o] = (v >> 8) & 0xFF
		f[o + 1] = v & 0xFF

	func l(o: int) -> int:
		return (w(o) << 16) | w(o + 2)

	func set_l(o: int, v: int) -> void:
		set_w(o, (v >> 16) & 0xFFFF)
		set_w(o + 2, v & 0xFFFF)

	func add_w(o: int, v: int) -> void:
		set_w(o, w(o) + v)


var vdp := ISSVdp.new()
var sound := ISSSound.new()
## Figures drawn with the match's sprite classes over the VDP picture (the
## rules screen's referees, the edit screens' players); cleared with each
## screen.
var figures := Node2D.new()
## The active object list, newest first (obj_alloc links at the head).
var objs: Array[Obj] = []
## The current object (a5) while its callbacks run.
var a5: Obj = null
var state := 0
## state_screen's presentations (made when one starts).
var presentation: ISSPresentation = null
## state_shootout's kick (made when one starts).
var shootout: ISSShootout = null
## main_init's boot screens (made when they start).
var boot: ISSBoot = null
## VDP_HVCOUNTER, which the toss, the shoot-out's AIs and animations read
## for random bits: the beam's position, which nothing in the game controls
## (a random number here).
var hv_counter := func() -> int: return randi() & 0xFFFF
var _handlers := {}
var _modules: Array = []


func _init() -> void:
	ISSRam.ensure()
	ISSRom.ensure_loaded()
	ISSInput.ensure_actions()
	add_child(vdp)
	add_child(figures)
	add_child(sound)
	_modules = [ISSScreensMain.new(self), ISSScreensPrematch.new(self), ISSScreensOptions.new(self),
		ISSScreensSquad.new(self), ISSScreensControls.new(self), ISSScreensMarking.new(self),
		ISSScreensFormation.new(self), ISSScreensStrategy.new(self),
		ISSScreensEdit.new(self), ISSScreensColours.new(self),
		ISSScreensPK.new(self), ISSScreensStats.new(self), ISSScreensTraining.new(self),
		ISSScreensLeague.new(self), ISSScreensCards.new(self), ISSScreensTournament.new(self),
		ISSScreensInternational.new(self), ISSScreensWorldSeries.new(self), ISSScreensPassword.new(self),
		ISSScreensScenario.new(self), ISSScreensEnding.new(self),
		ISSScreensCredits.new(self)]
	for mod in _modules:
		mod.register(_handlers)


## Power on: system_init's RAM defaults (the settings survive in a save
## file as they survive a reset in RAM).
static func power_on() -> void:
	ISSRam.ensure()
	ISSRam.clear(0, 0xFFEE)
	_load_settings()
	ISSRam.set_w(0x125A, 0)
	ISSRam.set_w(0x125C, 0)
	ISSRam.set_w(0x125E, 0)
	ISSRam.set_w(0x1260, 0)
	for i in 0x48:
		ISSRam.set_w(S.g_best_times + 2 * i, ISSRom.u16(ISSRom.addr("tbl_best_times") + 2 * i))
		ISSRam.set_w(S.g_best_scores + 2 * i, ISSRom.u16(ISSRom.addr("tbl_best_scores") + 2 * i))
	ISSRam.set_w(0x17DC, 0xFFFF)
	ISSRam.set_w(S.g_random, 0x2FDE)
	ISSRam.set_w(S.g_menu_item, 0)
	for i in 8:
		var a := S.g_control_slots + i * 0x1A
		ISSRam.set_w(a + 0x8, 1)
		ISSRam.set_w(a + 0xA, 0)
		ISSRam.set_w(a + 0xC, 0)
		ISSRam.set_w(a + 0xE, 0)
		ISSRam.set_w(a + 0x10, 2)
		ISSRam.set_w(a + 0x12, 0)
		ISSRam.set_w(a + 0x14, 1)
		ISSRam.set_w(a + 0x16, 3)
		ISSRam.set_w(a + 0x18, 0)
	# Nothing playing yet (sound_init leaves the driver idle).
	ISSRam.set_w(S.g_sound_disabled, 0)


## The settings words with their checksum, or the defaults when it fails.
static func _load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_SAVE):
		var b := FileAccess.get_file_as_bytes(SETTINGS_SAVE)
		if b.size() == 18:
			ISSRam.copy_in(S.g_settings_checksum, b)
	var sum := 0xF5F5
	for i in 8:
		sum += ISSRam.w(S.g_settings + 2 * i)
	if ISSRam.w(S.g_settings_checksum) != sum & 0xFFFF:
		ISSRam.set_w(S.g_settings, 2)
		ISSRam.set_w(S.g_opt_time, 2)
		for a in [S.g_opt_mono, S.g_opt_fouls_off, S.g_opt_cards_off, S.g_opt_offside_off]:
			ISSRam.set_w(a, 0)
		ISSRam.set_w(S.g_opt_vgoal, 1)
		ISSRam.set_w(S.g_opt_referee, 1)
		save_settings()


## Keep the settings words (the screens that change them call this).
static func save_settings() -> void:
	var sum := 0xF5F5
	for i in 8:
		sum += ISSRam.w(S.g_settings + 2 * i)
	ISSRam.set_w(S.g_settings_checksum, sum & 0xFFFF)
	var f := FileAccess.open(SETTINGS_SAVE, FileAccess.WRITE)
	if f != null:
		f.store_buffer(ISSRam.slice(S.g_settings_checksum, 18))


# --------------------------------------------------------------------------
# RAM shorthands for the ported code.

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


# --------------------------------------------------------------------------
# States.

## Enter state_menu, state_screen or state_shootout (after g_frame_state
## reached 0), or main_init (the boot screens, which run the module's own
## loop until the title is over).
func enter(st: int) -> void:
	# The state the game leaves is kept at $14 (state_menu_1 reads it).
	set_l(0x14, l(S.g_current_state))
	set_l(S.g_current_state, st)
	state = st
	if st == STATE_INIT:
		for f in figures.get_children():
			f.queue_free()
		vdp.clear_sprites()
		objs.clear()
		vdp.priority_overlay = false
		boot = ISSBoot.new(self)
		boot.run()
		return
	set_l(S.g_unpack_buffer, 0xFF3E18)
	set_w(S.g_unpack_vram, 0x3000)
	_vdp_init_game()
	set_w(S.g_frame_counter, 0xFFFF)
	vdp.clear_sprites()
	objs.clear()
	vdp.priority_overlay = st == STATE_SCREEN
	match st:
		STATE_MENU:
			_state_menu_1()
		STATE_SCREEN:
			# sprites_init, ball_func_00BD42 (the 16 objects cleared), then
			# state_screen_1.
			for f in figures.get_children():
				f.queue_free()
			presentation = ISSPresentation.new(self)
			presentation.state_screen_1()
		STATE_SHOOTOUT:
			for f in figures.get_children():
				f.queue_free()
			shootout = ISSShootout.new(self)
			shootout.state_shootout()
		_:
			push_error("ISSMenu: state $%06X is not ported" % st)
	fade_in_start()


## vdp_init_game: the registers the menus use (backdrop = line 2 colour 0,
## shadow/highlight on, full-screen scroll, no window).
func _vdp_init_game() -> void:
	vdp.reset_registers()
	vdp.backdrop = 0x20
	vdp.shadow_highlight = true


func _physics_process(_delta: float) -> void:
	if state == 0:
		return
	if state == STATE_INIT:
		# The boot module's VBlank, its main thread, then its picture.
		boot.frame()
		if boot != null:
			boot.present()
		return
	frame()
	# main loop: once a fade to black has ended, go to g_next_state.
	if w(S.g_frame_state) == 0:
		var nxt := l(S.g_next_state)
		if nxt == STATE_MENU or nxt == STATE_SCREEN or nxt == STATE_SHOOTOUT:
			enter(nxt)
		else:
			state = 0
			set_l(0x14, l(S.g_current_state))
			set_l(S.g_current_state, nxt)
			next_state.emit(nxt)


## main_init is over: a button pressed on the title goes to the main menu
## (system_init, state_menu screen 0); none to the attract demo
## (mode_start_demo, a match), handed to the owner as state_match.
func _boot_done(pressed: bool) -> void:
	state = 0
	boot = null
	vdp.reset_registers()
	set_l(0x14, 0xFFFFFFFF)
	set_w(S.g_frame_state, 0)
	if pressed or true:
		set_l(S.g_next_state, STATE_MENU)
		set_w(S.g_next_screen, 0)
		set_l(S.g_current_state, STATE_MENU)
		next_state.emit(STATE_MENU)


## One VBlank of state_menu_frame (state_screen_frame: its own frame_1;
## state_shootout_frame: its own routines around the objects').
## The game queues its VRAM, CRAM and sprite changes for the next VBlank,
## which also writes the scroll it computed: the picture shows a frame's
## work one frame later, all of it together. Here they take effect at once,
## so the scroll is written at the end of the frame to go with them.
func frame() -> void:
	_joypad_read_all()
	vdp.clear_sprites()
	if state == STATE_SHOOTOUT:
		shootout.frame_before_objects()
		_objects_update()
		shootout.frame_after_objects()
		_objects_draw_menu()
		shootout.frame_after_draw()
		_write_scroll()
		return
	_objects_update()
	if state == STATE_SCREEN:
		presentation.state_screen_frame_1()
	else:
		_state_menu_frame_1()
	_objects_draw_menu()
	_write_scroll()


func _write_scroll() -> void:
	vdp.scroll_a = Vector2i(-sw(S.g_plane_a_hscroll), sw(S.g_plane_a_vscroll))
	vdp.scroll_b = Vector2i(-sw(S.g_plane_b_hscroll), sw(S.g_plane_b_vscroll))


## joypad_read_all: two 6-button pads in ports 1 and 2 (type 1), no
## multitap (the other six slots read as type $F, nothing pressed).
func _joypad_read_all() -> void:
	if w(S.g_frame_state) == 2:
		add_w(S.g_frame_counter, 1)
	for i in 8:
		set_w(S.g_pad_type + 2 * i, 1 if i < 2 else 0xF)
		set_w(S.g_pad_state + 2 * i, ISSInput.raw(i) if i < 2 else 0)


func _pads_or(first: int, n: int) -> int:
	var v := 0
	for i in n:
		v |= w(S.g_pad_state + 2 * (first + i))
	return v


## state_menu_frame_1: the backdrop drifts (screens up to $32), the pad
## edges with auto-repeat (a held button repeats after 17 frames, then every
## 4), the controllers' own edges in g_control_slots and every other frame
## the text nametable rows 1-26 go to plane B.
func _state_menu_frame_1() -> void:
	if w(S.g_screen) <= 0x32:
		set_l(S.g_plane_a_hscroll, l(S.g_plane_a_hscroll) + 0x8000)
		set_l(S.g_plane_a_vscroll, l(S.g_plane_a_vscroll) + 0x8000)
	if w(S.g_frame_state) != 2:
		set_w(S.g_pad_pressed_any, 0)
		set_w(S.g_pad_pressed_home, 0)
		set_w(S.g_pad_pressed_away, 0)
	else:
		var home_n := w(S.g_pads_home)
		var away_n := w(S.g_pads_away)
		var d0 := _pads_or(0, home_n)
		var d1 := _pads_or(home_n, away_n)
		var d2 := _pads_or(0, 8) if w(0x153E) == 0 else d0 | d1
		match w(0x1548):
			1:
				var t := d0
				d0 = d1
				d1 = t
			2:
				d0 = d2
			3:
				d1 = d2
		_edges(S.g_pad_held_home, S.g_pad_pressed_home, 0x1554, d0, d2)
		_edges(S.g_pad_held_away, S.g_pad_pressed_away, 0x155A, d1, d2)
		_edges(S.g_pad_held_any, S.g_pad_pressed_any, 0x154E, d2, d2)
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
	if w(S.g_frame_counter) & 1 == 0:
		var tn := l(S.g_text_nametable) & 0xFFFF
		vdp.dma(0x0080, ISSRam.m, tn + 0x80, 0xD00)


func _edges(held: int, pressed: int, counter: int, d: int, any: int) -> void:
	if w(held) != any:
		set_w(counter, 0x10)
	elif sw(counter) >= 0:
		add_w(counter, -1)
	else:
		set_w(held, 0)
		set_w(counter, 2)
	set_w(held, w(held) & d)
	var p := d & ~w(held) & 0xFFFF
	set_w(pressed, p)
	set_w(held, w(held) | p)


# --------------------------------------------------------------------------
# Objects.

## obj_alloc: a new object at the head of the active list, which becomes
## the current object a5 (null when the 16 are in use). Callbacks default to
## none (-1).
func obj_alloc() -> Obj:
	if objs.filter(func(o: Obj) -> bool: return o.pooled).size() >= NUM_OBJS:
		return null
	var o := Obj.new()
	objs.push_front(o)
	a5 = o
	return o


func obj_free(o: Obj) -> void:
	o.alive = false
	objs.erase(o)


## objects_update: every object's think and update; while a fade runs only
## the objects without a draw callback.
func _objects_update() -> void:
	var fading := w(S.g_frame_state) != 2
	for o: Obj in objs.duplicate():
		if not o.alive:
			continue
		if fading and o.draw.is_valid():
			continue
		a5 = o
		if o.think.is_valid():
			o.think.call(o)
		if o.alive and o.update.is_valid():
			o.update.call(o)
	a5 = null


## objects_draw_menu: one bubble pass of the depth sort on obj_y (larger
## first), then each draw callback with obj_screen_x / y.
func _objects_draw_menu() -> void:
	var i := 1
	while i < objs.size():
		var o := objs[i]
		if o.sw(0x14) > objs[i - 1].sw(0x14):
			objs[i] = objs[i - 1]
			objs[i - 1] = o
		i += 1
	for o: Obj in objs.duplicate():
		if not o.alive or not o.draw.is_valid():
			continue
		var sy := (o.sw(0x14) >> 1) - o.sw(0x18) - sw(S.g_plane_b_vscroll)
		var sx := o.sw(0x10) - sw(S.g_plane_b_hscroll)
		o.set_w(0x1E, sy)
		o.set_w(0x1C, sx)
		o.set_b(0x0E, 0xFF if sy < -16 or sy > 256 or sx < -16 or sx > 272 else 1)
		a5 = o
		o.draw.call(o)
	a5 = null


# --------------------------------------------------------------------------
# Fades (fade_out_start / fade_in_start and their step objects).

func _cram_dma() -> void:
	var words := PackedInt32Array()
	words.resize(64)
	for i in 64:
		words[i] = w(S.g_palette_current + 2 * i)
	vdp.set_cram(words)


## dma_queue_add_cram: n bytes of RAM at src to CRAM byte address dst.
func cram_dma(dst: int, src: int, n: int) -> void:
	for i in n / 2:
		vdp.cram[(dst / 2 + i) & 63] = w(src + 2 * i)
	vdp.set_cram(vdp.cram)


## dma_queue_add: n bytes of RAM at src (an $FFxxxx address) to VRAM dst.
func vram_dma(dst: int, src: int, n: int) -> void:
	vdp.dma(dst, ISSRam.m, src & 0xFFFF, n)


## Start a fade to black; false when one is already running.
func fade_out_start() -> bool:
	if w(S.g_fade_step) != 0x18:
		return false
	set_w(S.g_frame_state, 1)
	var keep := a5
	var o := obj_alloc()
	a5 = keep
	o.update = _fade_out_step
	set_w(S.g_fade_step, 0x17)
	ISSRam.copy(S.g_palette_current, S.g_palette_target, 0x80)
	return true


func _fade_out_step(o: Obj) -> void:
	if w(S.g_fade_step) == 0:
		set_w(S.g_frame_state, 0)
		obj_free(o)
		return
	add_w(S.g_fade_step, -1)
	for i in 64:
		var a := S.g_palette_current + 2 * i
		var c := w(a)
		if c & 0x00E0:
			c -= 0x20
		elif c & 0x000E:
			c -= 2
		elif c & 0x0E00:
			c -= 0x200
		set_w(a, c)
	_cram_dma()


## fade_white_start: a flash: every colour brightens towards white a step
## a frame (24 frames), then back to g_palette_target; the objects keep
## running meanwhile.
func fade_white_start() -> void:
	var keep := a5
	var o := obj_alloc()
	a5 = keep
	if o == null:
		return
	o.update = _fade_white_step
	ISSRam.copy(S.g_palette_current, S.g_palette_target, 0x80)


func _fade_white_step(o: Obj) -> void:
	for i in 64:
		var a := S.g_palette_current + 2 * i
		var c := w(a)
		if c & 0x0E00 != 0x0E00:
			c += 0x200
		elif c & 0x000E != 0x000E:
			c += 2
		elif c & 0x00E0 != 0x00E0:
			c += 0x20
		set_w(a, c)
	_cram_dma()
	add_w(S.g_fade_step, 1)
	if w(S.g_fade_step) == 0x30:
		o.update = _fade_white_back_step


func _fade_white_back_step(o: Obj) -> void:
	for i in 64:
		var t := w(S.g_palette_target + 2 * i)
		var a := S.g_palette_current + 2 * i
		var c := w(a)
		# A colour starts darkening when the step falls to 48 minus its
		# brightness, one component step a frame.
		var lum := ((t >> 1) & 7) + ((t >> 5) & 7) + ((t >> 9) & 7)
		if lum + w(S.g_fade_step) - 0x30 >= 0:
			continue
		if (t & 0x0E00) != (c & 0x0E00):
			c -= 0x200
		elif (t & 0x000E) != (c & 0x000E):
			c -= 2
		elif (t & 0x00E0) != (c & 0x00E0):
			c -= 0x20
		set_w(a, c)
	_cram_dma()
	add_w(S.g_fade_step, -1)
	if w(S.g_fade_step) == 0x18:
		obj_free(o)


func fade_in_start() -> void:
	var keep := a5
	var o := obj_alloc()
	a5 = keep
	o.update = _fade_in_step
	ISSRam.clear(S.g_palette_current, 0x80)
	set_w(S.g_fade_step, 0)
	set_w(S.g_frame_state, 1)


func _fade_in_step(o: Obj) -> void:
	for i in 64:
		var t := w(S.g_palette_target + 2 * i)
		var a := S.g_palette_current + 2 * i
		var c := w(a)
		# A colour starts brightening when the step reaches 24 minus its
		# brightness (r + g + b), one component step a frame.
		var lum := ((t >> 1) & 7) + ((t >> 5) & 7) + ((t >> 9) & 7)
		if lum + w(S.g_fade_step) - 0x18 < 0:
			continue
		if (t & 0x0E00) != (c & 0x0E00):
			c += 0x200
		elif (t & 0x000E) != (c & 0x000E):
			c += 2
		elif (t & 0x00E0) != (c & 0x00E0):
			c += 0x20
		set_w(a, c)
	_cram_dma()
	add_w(S.g_fade_step, 1)
	if w(S.g_fade_step) == 0x18:
		set_w(S.g_frame_state, 2)
		obj_free(o)


# --------------------------------------------------------------------------
# Loading (state_menu_1, screen_load).

## Copy resource entry (g, e) to RAM at dst as decompress_factor5 would;
## the end address (a1).
func unpack(g: int, e: int, dst: int) -> int:
	var data := ISSRom.res(g, e)
	ISSRam.copy_in(dst & 0xFFFF, data)
	return dst + data.size()


## Unpack (g, e) into the unpack buffer and DMA it to g_unpack_vram, which
## advances; the VRAM address it went to.
func load_tiles(g: int, e: int) -> int:
	var buf := l(S.g_unpack_buffer)
	var end := unpack(g, e, buf)
	var at := w(S.g_unpack_vram)
	vdp.dma(at, ISSRam.m, buf & 0xFFFF, end - buf)
	set_w(S.g_unpack_vram, at + end - buf)
	return at


## state_menu_1: reset the scrolls and pad edges, take g_next_screen, and
## unless the game comes from another menu screen of the same kind load the
## cursor (group 4 entry 28, 29 from $3A) and icon (31) tiles and the
## backdrop group's tiles before the screen.
func _state_menu_1() -> void:
	for a in [S.g_plane_b_hscroll, S.g_plane_b_vscroll, S.g_plane_a_hscroll, S.g_plane_a_vscroll]:
		set_l(a, 0)
	set_w(S.g_pad_pressed_any, 0)
	set_w(S.g_pad_pressed_home, 0)
	set_w(S.g_pad_pressed_away, 0)
	set_w(0x154E, 0x10)
	set_w(0x1554, 0x10)
	set_w(0x155A, 0x10)
	set_w(0x1548, 0)
	for i in 4:
		set_w(S.g_control_slots + i * 0x1A + 4, 0)
		set_w(0x15C4 + i * 0x1A + 4, 0)
	set_w(0x175A, w(S.g_screen))
	set_w(S.g_screen, w(S.g_next_screen))
	set_w(0x1768, w(0x176A))
	var scr := w(S.g_screen)
	var prev := w(0x175A)
	if l(0x14) == STATE_MENU and not (scr >= 0x26 and scr <= 0x28) \
			and not (prev >= 0x26 and prev <= 0x28) and scr < 0x33 and prev < 0x33:
		screen_load()
		return
	if scr != 0x33:
		set_w(0x176C, load_tiles(4, 28 if scr < 0x3A else 29))
		set_w(0x176E, load_tiles(4, 31))
	var bg := 23
	if scr >= 0x34 and scr <= 0x38:
		bg = 26
	if scr >= 0x3A:
		bg = 24
	var buf := l(S.g_unpack_buffer)
	var end := unpack(bg, 0, buf)
	if scr == 0x39:
		end = unpack(25, 0, buf + 0x3000)
	if scr in [0x26, 0x27, 0x28, 0x33]:
		for sub in [[0xF, 0xC], [0xE, 0xB], [0x1, 0xA]]:
			recolour((buf + 0x1000) & 0xFFFF, 0x2000, sub[0], sub[1])
	var at := w(S.g_unpack_vram)
	set_w(S.g_stadium_vram, at)
	set_w(S.g_overlay_vram, at)
	set_w(S.g_unpack_vram, at + end - buf)
	vdp.dma(at, ISSRam.m, buf & 0xFFFF, end - buf)
	set_w(0x1760, w(S.g_unpack_vram))
	screen_load()


## engine_func_01FEE2: replace colour index from by to in n bytes of tiles.
func recolour(a: int, n: int, from: int, to: int) -> void:
	for i in n:
		var v := ISSRam.b(a + i)
		if v & 0x0F == from:
			v = (v & 0xF0) | to
		if v & 0xF0 == from << 4:
			v = (v & 0x0F) | (to << 4)
		ISSRam.set_b(a + i, v)


## screen_load: the screen's tiles (group 27 + screen, entry 0) after the
## backdrop's, the backdrop map on plane A (+ g_overlay_vram's tile), the
## screen's map as the text nametable (priority toggled, + g_stadium_vram's
## tile), the palettes (screen lines 0-1, backdrop lines 2-3), then the
## screen's handler builds its objects and the nametable goes to plane B.
func screen_load() -> void:
	var scr := w(S.g_screen)
	set_w(S.g_unpack_vram, w(0x1760))
	var buf := l(S.g_unpack_buffer)
	var g := 27 + scr
	var end := unpack(g, 0, buf)
	var at := w(S.g_unpack_vram)
	vdp.dma(at, ISSRam.m, buf & 0xFFFF, end - buf)
	set_w(S.g_unpack_vram, at + end - buf + 0x780)
	if scr != 0x39:
		end = unpack(23 if scr < 0x3A else 24, 1, buf)
	else:
		end = unpack(25, 1 if w(S.g_weather) == 1 else 2, buf)
		if w(S.g_weather) == 1:
			if w(0x1630) == 2:
				ISSRam.copy((buf + 0x700) & 0xFFFF, (buf + 0xE00) & 0xFFFF, 0x100)
		elif w(0x1630) != 0:
			ISSRam.copy((buf + 0x700) & 0xFFFF, (buf + 0xE00) & 0xFFFF, 0x100)
	var base := w(S.g_overlay_vram) >> 5
	var a := buf & 0xFFFF
	while a < (end & 0xFFFF):
		ISSRam.set_w(a, ISSRam.w(a) + base)
		a += 2
	vdp.dma(0x2000, ISSRam.m, buf & 0xFFFF, end - buf)
	set_l(S.g_text_nametable, buf)
	end = unpack(g, 1, buf)
	base = w(S.g_stadium_vram) >> 5
	a = buf & 0xFFFF
	while a < (end & 0xFFFF):
		ISSRam.set_w(a, (ISSRam.w(a) ^ 0x8000) + base)
		a += 2
	set_l(S.g_unpack_buffer, end)
	if scr != 0x39:
		unpack(g, 2, 0xFF0000 | S.g_palette_target)
		var bg := 0
		if scr >= 0x34:
			bg = 3
		if scr >= 0x3A:
			bg = 1
		unpack(23 + bg, 2, 0xFF0796)
	else:
		var gi := w(0x1630) * 2 + (0 if w(S.g_weather) == 1 else 6)
		unpack(25, 3 + gi / 2, 0xFF0000 | S.g_palette_target)
		unpack(23, 2, 0xFF0796)
	for f in figures.get_children():
		f.queue_free()
	var h: Callable = _handlers.get(scr, Callable())
	if h.is_valid():
		h.call()
	else:
		push_error("ISSMenu: screen $%02X is not ported" % scr)
	vdp.dma(0x0000, ISSRam.m, buf & 0xFFFF, 0x1000)


# --------------------------------------------------------------------------
# Sound.

func play_music(id: int) -> void:
	sound.play_music(id)


func play_sfx(id: int) -> void:
	sound.play_sfx(id)


## The menus' music rule (screen_main_menu ...): start song id unless
## g_sound_disabled says it is the one playing.
func menu_music(id: int) -> void:
	if w(S.g_sound_disabled) != id:
		play_music(id)
		set_w(S.g_sound_disabled, id)


# --------------------------------------------------------------------------
# The front-end helpers ($01F076-$01F80E). Rectangles are in pixels
# (x0..x1, y0..y1, ends exclusive) and work on whole cells of the text
# nametable.

func _cell(x: int, y: int) -> int:
	return (l(S.g_text_nametable) & 0xFFFF) + (y >> 3) * 0x80 + (x >> 3) * 2


func _border(x0: int, x1: int, y0: int, y1: int, fn: Callable) -> void:
	var c0 := x0 >> 3
	var c1 := (x1 >> 3) - 1
	var r0 := y0 >> 3
	var r1 := (y1 >> 3) - 1
	for c in range(c0, c1 + 1):
		fn.call(_cell(c * 8, r0 * 8))
	for r in range(r0, r1 + 1):
		fn.call(_cell(c1 * 8, r * 8))
	for c in range(c1, c0 - 1, -1):
		fn.call(_cell(c * 8, r1 * 8))
	for r in range(r1, r0 - 1, -1):
		fn.call(_cell(c0 * 8, r * 8))


## rect_highlight: the palette bit ($2000) on the rectangle's border cells.
func rect_highlight(x0: int, x1: int, y0: int, y1: int) -> void:
	_border(x0, x1, y0, y1, func(a: int) -> void: ISSRam.or_w(a, 0x2000))


func rect_unhighlight(x0: int, x1: int, y0: int, y1: int) -> void:
	_border(x0, x1, y0, y1, func(a: int) -> void: ISSRam.and_w(a, 0xDFFF))


## engine_text_01F142: the palette bit off on every cell of the rectangle.
func rect_unhighlight_all(x0: int, x1: int, y0: int, y1: int) -> void:
	for c in range(x0 >> 3, x1 >> 3):
		for r in range(y0 >> 3, y1 >> 3):
			ISSRam.and_w(_cell(c * 8, r * 8), 0xDFFF)


## rect_flash: the border highlighted while bit 3 of the object's timer is
## clear.
func rect_flash(x0: int, x1: int, y0: int, y1: int) -> void:
	var on := 0x2000 if a5.w(O_TIMER) & 8 == 0 else 0
	_border(x0, x1, y0, y1, func(a: int) -> void: ISSRam.set_w(a, (ISSRam.w(a) & 0xDFFF) | on))


## rect_fill: every cell of the rectangle = word v.
func rect_fill(x0: int, x1: int, y0: int, y1: int, v: int) -> void:
	for c in range(x0 >> 3, x1 >> 3):
		for r in range(y0 >> 3, y1 >> 3):
			ISSRam.set_w(_cell(c * 8, r * 8), v)


## rect_fill_tiles: consecutive tile words from v, column by column; the
## word after the last (d4 when it returns, which some screens go on with).
func rect_fill_tiles(x0: int, x1: int, y0: int, y1: int, v: int) -> int:
	for c in range(x0 >> 3, x1 >> 3):
		for r in range(y0 >> 3, y1 >> 3):
			ISSRam.set_w(_cell(c * 8, r * 8), v)
			v += 1
	return v


## result_mark_draw: a result mark (3 x 2 cells, tiles $1E0 + 6v: v 0
## won, 1 lost, 2 drawn) at (x, y), priority on.
func result_mark_draw(x: int, y: int, v: int) -> void:
	var a := _cell(x, y)
	var t := ((w(S.g_stadium_vram) >> 5) | 0x8000) + 0x1E0 + v * 6
	for i in 3:
		ISSRam.set_w(a + 2 * i, t + 2 * i)
		ISSRam.set_w(a + 0x80 + 2 * i, t + 2 * i + 1)


## flags_wave: the waving flags: every fourth frame one of three
## strips of 6 tiles (8 frames each, unpacked at $1770) goes to VRAM
## $3C00, $3CC0 or $3D80, a frame apart.
func flags_wave() -> void:
	var fc := w(S.g_frame_counter)
	var f := ((fc >> 2) & 7) * 0xC0
	var sv := w(S.g_stadium_vram)
	if fc & 3 == 0:
		vram_dma(sv + 0x3C00, l(0x1770) + f, 0xC0)
		return
	if (fc + 1) & 3 == 0:
		vram_dma(sv + 0x3CC0, l(0x1770) + f + 0x600, 0xC0)
	if (fc + 2) & 3 == 0:
		vram_dma(sv + 0x3D80, l(0x1770) + f + 0xC00, 0xC0)


func _font_base(large: bool) -> int:
	return (w(S.g_stadium_vram) >> 5) + (0xC090 if large else 0xC130)


## A string argument as the text helpers read a0: a ROM or RAM address
## ($FFxxxx) or bytes. Returns the bytes up to the terminator (bit 7 set)
## and the address after it (a0 when the routine returns).
func _str(src) -> Array:
	if src is PackedByteArray:
		var n := 0
		while n < src.size() and src[n] < 0x80:
			n += 1
		return [src.slice(0, n), -1]
	var a: int = src
	var out := PackedByteArray()
	if a >= 0xFF0000:
		while ISSRam.b(a) < 0x80:
			out.append(ISSRam.b(a))
			a += 1
	else:
		out = ISSRom.string(a)
		a += out.size()
	return [out, a + 1]


## text_draw_large: an 8x16 string ('-' = first glyph) at (x, y); returns
## the address after the string's terminator when src is one.
func text_draw_large(x: int, y: int, src) -> int:
	var r := _str(src)
	var a := _cell(x, y)
	var base := _font_base(true)
	for ch: int in r[0]:
		ISSRam.set_w(a, base + ch - 0x2D)
		ISSRam.set_w(a + 0x80, base + ch - 0x2D + 0x50)
		a += 2
	return r[1]


## text_draw_small: an 8x8 string at (x, y).
func text_draw_small(x: int, y: int, src) -> int:
	var r := _str(src)
	var a := _cell(x, y)
	var base := _font_base(false)
	for ch: int in r[0]:
		ISSRam.set_w(a, base + ch - 0x2D)
		a += 2
	return r[1]


## text_draw_field: a large string in the field x0..x1 at y with its
## leading '@' (spaces) moved to the end; reads as many characters as the
## field has cells (src: address or bytes).
func text_draw_field(x0: int, x1: int, y: int, src) -> void:
	var n := (x1 >> 3) - (x0 >> 3)
	var chars := PackedByteArray()
	if src is PackedByteArray:
		chars = src
	else:
		for i in n:
			chars.append(ISSRam.b(src + i) if src >= 0xFF0000 else ISSRom.u8(src + i))
	var a := _cell(x0, y)
	var i := 0
	var lead := 0
	while i < chars.size() and chars[i] == 0x40:
		i += 1
		n -= 1
		lead += 1
	var base := _font_base(true)
	for k in n:
		var ch: int = chars[i + k] if i + k < chars.size() else 0x40
		ISSRam.set_w(a, base + ch - 0x2D)
		ISSRam.set_w(a + 0x80, base + ch - 0x2D + 0x50)
		a += 2
	for k in lead:
		ISSRam.set_w(a, base + 0x13)
		ISSRam.set_w(a + 0x80, base + 0x13 + 0x50)
		a += 2


## bar_draw: an attribute bar of steps (0-8) at (x, y): two cells of four
## steps then the end cap, style d2 (font tiles $250 + 8 * style).
func bar_draw(x: int, y: int, style: int, steps: int) -> void:
	var a := _cell(x, y)
	var base := (w(S.g_stadium_vram) >> 5) | 0xC000
	base += 0x250 + style * 8
	steps += 1
	var d := 0
	while d < 8:
		ISSRam.set_w(a, base + clampi(steps - d, 0, 4))
		a += 2
		d += 4
	ISSRam.set_w(a, base + maxi(0, steps - d) + 5)


## engine_text_01F468: a bar of seven cells of eight steps (style * 9 tiles
## from $283).
func bar_draw_wide(x: int, y: int, style: int, steps: int) -> void:
	var a := _cell(x, y)
	var base := ((w(S.g_stadium_vram) >> 5) | 0xC000) + 0x283 + style * 9
	var d := 0
	while d < 0x38:
		ISSRam.set_w(a, base + clampi(steps - d, 0, 8))
		a += 2
		d += 8


## sprite_alloc and its four words (y and x already with the +128).
func sprite(y: int, size: int, attr: int, x: int) -> bool:
	return vdp.add_sprite(y & 0x3FF, size, attr & 0xFFFF, x & 0x1FF)


## A sprite x as the helpers place them: + 128 - plane B's scroll, never 0
## (x = 0 would mask the line).
func _sx(x: int) -> int:
	var v := (x + 0x80 - sw(S.g_plane_b_hscroll)) & 0x1FF
	return 1 if v == 0 else v


## boxes_draw_sprites: the translucent boxes (shadow sprites, tile $70 in
## line 3) over the cell rectangles of the table at addr (x0, x1, y0, y1
## words, a negative x0 ends it).
func boxes_draw_sprites(addr: int) -> void:
	var tile := ((w(S.g_stadium_vram) >> 5) + 0x6070) & 0xFFFF
	while ISSRom.s16(addr) >= 0:
		var x0 := ISSRom.s16(addr)
		var x1 := ISSRom.s16(addr + 2)
		var y0 := ISSRom.s16(addr + 4)
		var y1 := ISSRom.s16(addr + 6)
		var x := x0
		while x < x1:
			var cw := mini(x1 - x, 4)
			var y := y0
			while y < y1:
				var ch := mini(y1 - y, 4)
				sprite(y * 8 + 0x80, ((cw - 1) << 2) | ((ch - 1) & 3), tile, _sx(x * 8))
				y += ch
			x += cw
		addr += 8


## cursor_draw_large: the animated 16-pixel-high bar cursor of frame set
## set (30 tiles each) from x0 to x1 at y (pixel positions of the cell
## corner + 4).
func cursor_draw_large(set: int, x0: int, x1: int, y: int) -> void:
	var t := set * 0x1E
	if a5.w(O_TIMER) & 7:
		t += 0xF
	t += (w(0x176C) >> 5) + 0x28
	t |= 0xC000
	x0 -= 4
	x1 -= 4
	y -= 4
	var sy := y + 0x80 - sw(S.g_plane_b_vscroll)
	sprite(sy, 0x02, t, _sx(x0))
	sprite(sy, 0x02, t | 0x0800, _sx(x1))
	x0 += 8
	t += 3
	while x1 - x0 != 0:
		var n := mini(x1 - x0, 0x20)
		var x := x0
		x0 += n
		sprite(sy, (((n >> 3) - 1) << 2) | 2, t, _sx(x))


## cursor_draw: the 8-pixel-high bar cursor (frame sets of 20 tiles).
func cursor_draw(set: int, x0: int, x1: int, y: int) -> void:
	var t := set * 0x14
	if a5.w(O_TIMER) & 7:
		t += 0xA
	t += w(0x176C) >> 5
	t |= 0xC000
	x0 -= 4
	x1 -= 4
	y -= 4
	var sy := y + 0x80 - sw(S.g_plane_b_vscroll)
	var n := mini(x1 - x0, 0x20)
	sprite(sy, (((n >> 3) - 1) << 2) | 1, t, _sx(x0))
	x0 += n
	sprite(sy, 0x01, t | 0x1800, _sx(x1))
	t += 2
	while x1 - x0 != 0:
		n = mini(x1 - x0, 0x20)
		var x := x0
		x0 += n
		sprite(sy, (((n >> 3) - 1) << 2) | 1, t, _sx(x))


## pad_icon_draw: the animated controller (0, 1) or CPU (2+) icon at (x, y).
func pad_icon_draw(icon: int, x: int, y: int) -> void:
	var t := icon * 16 + ((a5.w(O_TIMER) >> 2) & 7) * 2 + (w(0x176E) >> 5) + 0x18
	t |= 0xC000 if icon < 2 else 0x8000
	sprite(y + 0x80, 0x01, t, _sx(x))


## icon_draw_small: an 8x8 animated icon of set (8 frames) at (x, y).
func icon_draw_small(set: int, x: int, y: int) -> void:
	var t := set * 8 + ((a5.w(O_TIMER) >> 2) & 7) + (w(0x176E) >> 5)
	sprite(y + 0x80, 0x00, t | 0xC000, _sx(x))


## engine_load_01F80E: the animated tiles of the edit screens' faces and
## figures, from the unpacked set at $1770 (group 4 entry 35): five strips
## stepped on staggered frames.
func anim_tiles() -> void:
	var fc := w(S.g_frame_counter)
	var src := l(0x1770)
	var vram := w(S.g_stadium_vram)
	var strip := func(table: String, frame: int, count: int, dst: int, n: int) -> void:
		var off := ISSRom.u16(ISSRom.addr(table) + 2 * (frame % count))
		vram_dma(vram + dst, src + off, n)
	if fc & 0xF == 0:
		strip.call("tbl_anim_tiles_1", fc >> 4, 6, 0x3C00, 0x40)
	elif (fc + 1) & 0xF == 0:
		strip.call("tbl_anim_tiles_2", fc >> 4, 7, 0x3C40, 0x80)
	elif (fc + 2) & 7 == 0:
		strip.call("tbl_anim_tiles_3", fc >> 3, 9, 0x3CC0, 0x80)
	elif (fc + 3) & 7 == 0:
		strip.call("tbl_anim_tiles_4", fc >> 3, 7, 0x3D40, 0x40)
	elif (fc + 5) & 3 == 0:
		strip.call("tbl_anim_tiles_5", fc >> 2, 12, 0x3D80, 0x40)


## engine_text_01F78E: a 2 x 2 face (energy 0-4, from the table of four
## words each) at (x, y), palette line 1.
func face_draw(x: int, y: int, index: int) -> void:
	var a := _cell(x, y)
	var t := ISSRom.addr("engine_text_01F78E_data") + index * 8
	var base := ((w(S.g_stadium_vram) >> 5) | 0xA000) + 0x1E0
	ISSRam.set_w(a, base + ISSRom.u16(t))
	ISSRam.set_w(a + 0x80, base + ISSRom.u16(t + 2))
	ISSRam.set_w(a + 2, base + ISSRom.u16(t + 4))
	ISSRam.set_w(a + 0x82, base + ISSRom.u16(t + 6))


## engine_text_01FADE: mirror the cells of a rectangle left to right (the
## mini pitch for the side defending the right goal).
func rect_mirror(x0: int, x1: int, y0: int, y1: int) -> void:
	var n := (x1 >> 3) - (x0 >> 3)
	for r in range(y0 >> 3, y1 >> 3):
		var row := []
		for c in n:
			row.append(ISSRam.w(_cell(x0 + c * 8, r * 8)))
		for c in n:
			ISSRam.set_w(_cell(x0 + c * 8, r * 8), int(row[n - 1 - c]) ^ 0x0800)


## The side's player objects (20, $8E bytes each).
func team_players(side: int) -> int:
	return S.g_team_home_players if side == 0 else S.g_team_away_players


## engine_func_01FB24: the eleven's places on the mini pitch at (dx, dy)
## (obj_x / obj_y of the player objects) from their role and formation
## place, mirrored unless the side defends the left goal; all visible.
func pitch_place(dx: int, dy: int, side: int) -> void:
	var a := team_players(side)
	var left := side == w(S.g_left_goal_team)
	ISSRam.set_w(a + 0x10, (0 if left else 0x80) + dx)
	ISSRam.set_w(a + 0x14, 0x30 + dy)
	ISSRam.set_b(a + 0xE, 1)
	for k in range(1, 11):
		a += ISSModes.PLAYER_SIZE
		var role := ISSRam.b(a + 0x51) & 0x7F
		var fx := ISSRam.sb(a + 0x52)
		var fy := ISSRam.sb(a + 0x53)
		if left:
			ISSRam.set_w(a + 0x10, -role * 0x2C + 0x6C + fx + dx)
			ISSRam.set_w(a + 0x14, fy + 0x30 + dy)
		else:
			ISSRam.set_w(a + 0x10, role * 0x2C + 0x14 - fx + dx)
			ISSRam.set_w(a + 0x14, -fy + 0x30 + dy)
		ISSRam.set_b(a + 0xE, 1)


## engine_draw_01FC0A: the eleven's shirt numbers on the mini pitch (the
## number tiles at $1774; another colour for a player marked by bit 7 of
## the role; blinking when not visible; none for the handicap's absentees).
func pitch_draw(side: int) -> void:
	var a := team_players(side)
	for k in 11:
		if ISSRam.b(a + 0x55) == 0:
			var t := w(0x1774) >> 5
			if ISSRam.b(a + 0xE) == 0 and w(S.g_frame_counter) & 8 == 0:
				t += 0x78
			else:
				t += (ISSRam.b(a + 0x63) - 1) * 2
				if ISSRam.b(a + 0x51) & 0x80:
					t += 0x28 if side == w(S.g_left_goal_team) else 0x50
			var x := (ISSRam.w(a + 0x10) - sw(S.g_plane_b_hscroll) + 0x78) & 0x1FF
			sprite(ISSRam.w(a + 0x14) + 0x7C, 4, t | 0xC000, 1 if x == 0 else x)
		a += ISSModes.PLAYER_SIZE


## A ROM string (bytes up to $FF) by symbol, optionally at an offset.
static func rom_str(name: String, offset := 0) -> PackedByteArray:
	return ISSRom.string(ISSRom.addr(name) + offset)
