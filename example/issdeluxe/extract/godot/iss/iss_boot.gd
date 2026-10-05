class_name ISSBoot
extends RefCounted
## The boot module (boot_main, $144318): the screens before the title, a
## small program of its own with its own objects (19 of $36 bytes at $66A,
## run every VBlank), DMA queue, sprite buffer, palette fades and raster
## effects, run here as the game runs it: main_init calls it for screens
## 4 (SEGA), 3 (Konami), 2 (Factor 5), 0 (the intro) and 1 (the title),
## which says whether a button was pressed (the menus) or not (the attract
## demo); warm_start runs the title alone after the demo. Its RAM is the game's work RAM (ISSRam) at the module's own
## offsets, its picture ISSVdp with the module's registers (planes 64 x 64
## at $A000 and $E000, the scroll table in cell mode). The main thread of
## each screen is a coroutine waiting on the VBlank (boot_wait), as the
## program spins on its frame counter. The routines are the ROM's, under
## their names.

## The VBlank is over: the screen's main thread goes on.
signal vblank
## The title's HInt (line 90) has run: its palette split is in place.
signal hint

const S := preload("res://iss/iss_sym.gd")

## The module's RAM.
const LINE := 0x14         # the HInt's lines to skip (the raster routines)
const FRAME := 0x16        # frame counter (boot_wait compares it with WAIT)
const WAIT := 0x18
const SCREEN := 0x1C       # g_next_state: the screen number
const PAD_TYPES := 0x26    # 8 words
const PAD_STATES := 0x36   # 8 words
const SPRITE_NEXT := 0x2CA # long: the next sprite entry; $2CE the count
const SPRITE_COUNT := 0x2CE
const SPRITES := 0x2E0     # 64 x 8 bytes
const PAL_TARGET := 0x4E0  # 64 words: the palette the fades go to
const PAL_CURRENT := 0x5A0 # 64 words: the palette shown
const OBJ_FREE := 0x662
const OBJ_ACTIVE := 0x666
const OBJECTS := 0x66A
const OBJ_SIZE := 0x36
const NUM_OBJECTS := 19
const OBJ_COUNT := 0xFFC
const HSCROLL := 0xAA6     # 256 lines x (plane A, plane B)
const VSCROLL := 0xEA6     # 32 words (VSRAM)
const UNPACK := 0x8000     # the unpack buffer ($FFFF8000)
const REG1 := 0xF26        # register 1's bits ($64 display on)
const PAL := 0xF2A         # byte: -1 on a PAL machine
const F_SCROLL := 0xF2B    # a scroll object runs
const F_ANIM := 0xF2C      # an animation object runs
const F_DMA := 0xF2F       # a DMA runs
const F_FADE_IN := 0xF30
const PRESSED := 0xF32     # byte: -1 once a button was pressed
const F_FADE_OUT := 0xF34
const SOUND := 0xF38       # word: -1 no music, else the song

enum { DMA_VRAM, DMA_CRAM, DMA_VSRAM }

var m: ISSMenu
## The screens to run instead of main_init's (the test scripts).
static var screens_override: Array = []
## The line the title's second palette starts from (ISSVdp.NO_SPLIT shows
## the first palette everywhere, as the harness renders a frame).
static var title_split := 91
## The queued DMAs (boot_dma_queue_add): [kind, destination, source, words].
var dma: Array = []
## The active objects' RAM addresses (the head of the list first) and each
## object's routine (+$12).
var active: Array[int] = []
var free: Array[int] = []
var routines := {}
## $1E: the screen's own VBlank routine; $32: its HInt routine.
var frame_cb := Callable()
var hblank := Callable()
## Register 0 bit 4: the HInt enabled (the raster routines run).
var hint_on := false
## VSRAM: whole-screen vertical scrolls of planes A and B.
var vsram := [0, 0]
## The last vertical scroll a raster routine wrote (the lines before its
## first keep it).
var _vsram_last := 0
## Set when the boot is over: whether a button was pressed on the title.
var finished := false
var pressed := false


func _init(menu: ISSMenu) -> void:
	m = menu


func w(a: int) -> int:
	return ISSRam.w(a)


func sw(a: int) -> int:
	return ISSRam.sw(a)


func b(a: int) -> int:
	return ISSRam.b(a)


func sb(a: int) -> int:
	return ISSRam.sb(a)


func l(a: int) -> int:
	return ISSRam.l(a)


func set_w(a: int, v: int) -> void:
	ISSRam.set_w(a, v)


func set_b(a: int, v: int) -> void:
	ISSRam.set_b(a, v)


func set_l(a: int, v: int) -> void:
	ISSRam.set_l(a, v & 0xFFFFFFFF)


func add_w(a: int, v: int) -> void:
	ISSRam.set_w(a, ISSRam.w(a) + v)


func rom(name: String) -> int:
	return ISSRom.addr(name)


# --------------------------------------------------------------------------
# main_init's part: the screens in turn.

## main_init: screens 4, 3, 2 and 0, then 1 (the title), which decides
## between the menus and the attract demo.
func run(warm := false) -> void:
	var screens: Array = [1] if warm else [4, 3, 2, 0, 1]
	if not screens_override.is_empty():
		screens = screens_override
	for scr in screens:
		pressed = await boot_main(scr)
	finished = true
	m._boot_done(pressed)


## boot_main / boot_screen_run: the module's RAM cleared, the VDP set up
## and cleared, the screen run, then the display off; true when a button
## was pressed.
func boot_main(scr: int) -> bool:
	ISSRam.clear(0, 0x184C)
	ISSRam.clear(0x8000, 0x7C00)
	frame_cb = Callable()
	hblank = Callable()
	boot_vdp_init()
	set_w(FRAME, 0)
	set_w(SCREEN, scr)
	set_w(SOUND, 0xFFFF)
	match scr:
		4:
			await boot_sega()
		3:
			await boot_konami()
		2:
			await boot_factor5()
		0:
			await boot_intro()
		1:
			await boot_title()
	frame_cb = Callable()
	if sw(SOUND) >= 0:
		set_w(SOUND, 0xFFFF)
		m.sound.stop_music()
	m.vdp.backdrop = 0
	boot_display_off()
	hint_on = false
	return sb(PRESSED) != 0


## boot_vdp_init: NTSC here ($F2A), register 1's bits, the module's
## planes (A $A000, B $E000, sprites $DA00, the scroll table $C800), VRAM
## $0000-$9FFF, the planes and the CRAM cleared.
func boot_vdp_init() -> void:
	set_b(PAL, 0)
	set_w(REG1, 4)
	frame_cb = Callable()
	m.vdp.display = false
	m.vdp.backdrop = 0
	# Register 12 = 0: H32 without shadow / highlight.
	m.vdp.shadow_highlight = false
	m.vdp.plane_a = 0xA000
	m.vdp.plane_b = 0xE000
	_clear_vram(0x0000, 0xA000)
	_clear_vram(0xA000, 0x1000)
	_clear_vram(0xE000, 0x1000)
	for i in 64:
		m.vdp.set_cram_word(i, 0)
	dma.clear()


func _clear_vram(at: int, n: int) -> void:
	var zero := PackedByteArray()
	zero.resize(n)
	m.vdp.dma(at, zero)


## boot_display_off: the display off (register 1 without bit 6).
func boot_display_off() -> void:
	set_w(REG1, w(REG1) & 0x3F)
	m.vdp.display = false


## boot_display_on: the display on (register 1 | $64).
func boot_display_on() -> void:
	set_w(REG1, w(REG1) | 0x64)
	m.vdp.display = true


## boot_vdp_registers: the screens' registers: sprites $DA00, backdrop colour
## 0, plane A $A000, plane B $E000, 64 x 64 cells, no window, the scroll
## table in cell mode at $C800, HInt every line (off until a screen turns
## it on).
func boot_vdp_registers() -> void:
	m.vdp.backdrop = 0
	m.vdp.plane_a = 0xA000
	m.vdp.plane_b = 0xE000
	m.vdp.plane_cols = 64
	m.vdp.plane_rows = 64
	m.vdp.window_h = 0
	m.vdp.window_v = 0
	set_w(LINE, 0)
	hint_on = false


## boot_planes_clear: planes B and A cleared ($1000 words each).
func boot_planes_clear() -> void:
	_clear_vram(0xE000, 0x2000)
	_clear_vram(0xA000, 0x2000)


## boot_scroll_clear: the scroll table (256 lines) and VSRAM cleared.
func boot_scroll_clear() -> void:
	ISSRam.clear(HSCROLL, 0x400)
	dma_queue_add(DMA_VRAM, 0xC800, 0xFF0000 | HSCROLL, 0x200)
	ISSRam.clear(VSCROLL, 0x40)
	dma_queue_add(DMA_VSRAM, 0, 0xFF0000 | VSCROLL, 0x20)


## boot_pal_frames: a 60 Hz frame count on a 50 Hz machine (the remainder
## carried in $F28); unchanged here.
func boot_pal_frames(n: int) -> int:
	if b(PAL) == 0:
		return n
	var v := n * 50 + w(0xF28)
	set_w(0xF28, v % 60)
	return v / 60


## boot_wait: d0 frames (the frame counter from 0 to it); a button press
## ends it, except on the SEGA screen.
func boot_wait(n: int) -> void:
	n = boot_pal_frames(n)
	set_w(WAIT, n)
	set_w(FRAME, 0)
	while true:
		if sb(PRESSED) < 0 and w(SCREEN) != 4:
			return
		if w(FRAME) == w(WAIT):
			return
		await vblank


# --------------------------------------------------------------------------
# The VBlank (boot_vblank) and what the picture shows.

## boot_vblank_1: the frame counter, the queued DMAs, the pads
## (boot_vblank_pads), a button pressed (_2), the screen's own routine
## ($1E); then the main thread goes on.
func frame() -> void:
	set_w(LINE, 1)
	add_w(FRAME, 1)
	if w(SCREEN) == 1:
		ISSRam.copy(0x1806, 0x620, 0x40)
	dma_flush()
	_pads()
	boot_vblank_pressed()
	if frame_cb.is_valid():
		frame_cb.call()
	vblank.emit()


## boot_vblank_pads: the two ports' pads, type 1 (the others $F, nothing
## pressed), their buttons as the game reads them.
func _pads() -> void:
	for i in 8:
		set_w(PAD_TYPES + 2 * i, 1 if i < 2 else 0xF)
		set_w(PAD_STATES + 2 * i, ISSInput.raw(i) if i < 2 else 0)


## boot_vblank_pressed: Start on any pad sets $F32 (on the title only
## after 24 frames).
func boot_vblank_pressed() -> void:
	if w(SCREEN) == 1 and w(FRAME) <= 0x17:
		return
	var any := 0
	for i in 8:
		any |= w(PAD_STATES + 2 * i)
	if any & 0x80:
		set_b(PRESSED, 0xFF)


## The picture as the VDP shows it after this frame: the scroll table (in
## VRAM at $C800, cell mode), VSRAM, and the raster routine's lines (the
## sprites and the palette reach the VDP by their DMAs).
func present() -> void:
	m.vdp.set_line_scroll(0xC800, true, true)
	m.vdp.scroll_a = Vector2i(0, _s10(vsram[0]))
	m.vdp.scroll_b = Vector2i(0, _s10(vsram[1]))
	m.vdp.vlines_a = PackedInt32Array()
	m.vdp.vlines_b = PackedInt32Array()
	m.vdp.cram_split = ISSVdp.NO_SPLIT
	if hint_on and hblank.is_valid():
		hblank.call()
		hint.emit()


static func _s10(v: int) -> int:
	v &= 0x7FF
	return v - 0x800 if v >= 0x400 else v


# --------------------------------------------------------------------------
# Objects (boot_obj_alloc, boot_obj_free, boot_objects_run).

## boot_objects_init: the 19 objects cleared and chained on the free list.
func boot_objects_init() -> void:
	ISSRam.clear(OBJECTS, OBJ_SIZE * NUM_OBJECTS)
	free.clear()
	active.clear()
	routines.clear()
	for k in NUM_OBJECTS:
		free.append(OBJECTS + k * OBJ_SIZE)
	set_w(OBJ_COUNT, 0)


## boot_obj_alloc: an object off the free list onto the head of the active
## list, running fn every VBlank; its address (0 when none is free).
func obj_alloc(fn: Callable) -> int:
	if free.is_empty():
		return 0
	var o: int = free.pop_front()
	active.push_front(o)
	routines[o] = fn
	add_w(OBJ_COUNT, 1)
	return o


func obj_free(o: int) -> void:
	if not routines.has(o):
		return
	active.erase(o)
	routines.erase(o)
	free.push_front(o)
	add_w(OBJ_COUNT, -1)


## boot_objects_run: every active object's routine, head first.
func boot_objects_run() -> void:
	for o in active.duplicate():
		if routines.has(o):
			routines[o].call(o)


## boot_sprites_reset: the sprite buffer empty.
func boot_sprites_reset() -> void:
	set_l(SPRITE_NEXT, 0xFF0000 | SPRITES)
	set_w(SPRITE_COUNT, 0)


## boot_sprite_alloc: the next of the 64 sprite entries, linked from the
## one before (whose x is never left 0); -1 when the buffer is full.
func boot_sprite_alloc() -> int:
	if w(SPRITE_COUNT) >= 0x40:
		return -1
	var a1 := ISSRam.l(SPRITE_NEXT) & 0xFFFF
	if w(a1 - 2) & 0x1FF == 0:
		set_w(a1 - 2, 1)
	set_b(a1 - 5, b(SPRITE_COUNT + 1))
	add_w(SPRITE_COUNT, 1)
	set_l(SPRITE_NEXT, 0xFF0000 | (a1 + 8))
	return a1


## boot_sprite_set: sprite entry a1 = piece (y, size, tile, x words, 10
## bytes each) at object o's position (+$C y, +$8 x), its tile + d3.
func boot_sprite_set(o: int, a1: int, piece: int, d3: int) -> void:
	set_w(a1, w(o + 0xC) + ISSRom.u16(piece))
	set_b(a1 + 2, ISSRom.u16(piece + 2) & 0xFF)
	set_w(a1 + 4, d3 + ISSRom.u16(piece + 4))
	set_w(a1 + 6, w(o + 8) + ISSRom.u16(piece + 6))


## boot_sprites_flush: the sprite buffer to the VDP (the last entry's link
## ended, or an empty first entry) and empty again.
func boot_sprites_flush() -> void:
	if w(SPRITE_COUNT) == 0:
		for i in 4:
			set_w(SPRITES + 2 * i, 0)
	else:
		set_b((ISSRam.l(SPRITE_NEXT) & 0xFFFF) - 5, 0)
	dma_queue_add(DMA_VRAM, 0xDA00, 0xFF0000 | SPRITES, 0x200)
	set_l(SPRITE_NEXT, 0xFF0000 | SPRITES)
	set_w(SPRITE_COUNT, 0)


# --------------------------------------------------------------------------
# The DMA queue (boot_dma_queue_add, boot_dma_flush): VRAM ($2000), CRAM
# ($6000) or VSRAM ($A000) from RAM, n words.

## inc: the VDP's auto-increment (register 15), 2 but for the column writes
## of plane B (boot_intro_column_wipe_2, boot_title_word_scroll_2: $80, a row).
func dma_queue_add(kind: int, dest: int, src: int, words: int, inc := 2) -> void:
	dma.append([kind, dest, src, words, inc])


func dma_flush() -> void:
	set_b(F_DMA, 0xFF)
	for q: Array in dma:
		var dest: int = q[1]
		var src: int = q[2] & 0xFFFF
		var n: int = q[3]
		match int(q[0]):
			DMA_VRAM:
				if int(q[4]) != 2:
					for i in n:
						m.vdp.set_vram_w(dest + i * int(q[4]), ISSRam.w(src + 2 * i))
					continue
				m.vdp.dma(dest, ISSRam.m, src, n * 2)
				if dest == 0xDA00:
					# The sprite table: the entries along the links from
					# the first (the last one's link is 0).
					var count := 0
					var i := 0
					while count < 64:
						count += 1
						var link := b(src + i * 8 + 3)
						if link == 0:
							break
						i = link
					m.vdp.set_sprites_from_ram(src, count)
			DMA_CRAM:
				for i in n:
					m.vdp.set_cram_word((dest >> 1) + i, ISSRam.w(src + 2 * i))
			DMA_VSRAM:
				for i in mini(n, 2):
					vsram[(dest >> 1) + i] = ISSRam.w(src + 2 * i)
	dma.clear()
	set_b(F_DMA, 0)


## Unpack boot resource (n, e) into the unpack buffer; its length.
func _unpack_res(n: int, e: int) -> int:
	var data := ISSRom.unpack(ISSRom.boot_res(n, e))
	ISSRam.copy_in(UNPACK, data)
	return data.size()


## n words of ROM at src to RAM at dst.
func _copy_rom(src: int, dst: int, n: int) -> void:
	for i in n:
		set_w(dst + 2 * i, ISSRom.u16(src + 2 * i))


# --------------------------------------------------------------------------
# Palette fades (objects).

## boot_fade_in: a fade in: every d1 frames each colour of the d4 from
## d3 steps one level per channel toward the target palette ($4E0), 16
## steps; $F30 while it runs. A button press ends it (not on the SEGA
## screen).
func boot_fade_in(d1: int, d2: int, d3: int, d4: int) -> void:
	set_b(F_FADE_IN, 0xFF)
	var o := obj_alloc(boot_fade_in_1)
	if o == 0:
		return
	d1 = boot_pal_frames(d1)
	set_w(o + 0x16, d1)
	set_w(o + 0x18, d2)
	set_w(o + 0x1E, d1)
	set_w(o + 0x1A, d3 * 2)
	set_w(o + 0x1C, (d4 & 0x3F) - 1)


func boot_fade_in_1(o: int) -> void:
	if w(SCREEN) != 4 and sb(PRESSED) < 0:
		set_b(F_FADE_IN, 0)
		obj_free(o)
		return
	if w(o + 0x1E) != 0:
		add_w(o + 0x1E, -1)
		return
	set_w(o + 0x1E, w(o + 0x16))
	if sw(o + 0x18) >= 0x10:
		set_b(F_FADE_IN, 0)
		obj_free(o)
		return
	add_w(o + 0x18, 1)
	var a0 := PAL_TARGET + w(o + 0x1A)
	var a1 := PAL_CURRENT + w(o + 0x1A)
	for i in w(o + 0x1C) + 1:
		var t := w(a0)
		var c := w(a1)
		var d6 := 0
		if (c & 0xF00) < (t & 0xF00):
			d6 |= 0x200
		if (c & 0xF0) < (t & 0xF0):
			d6 |= 0x20
		if (c & 0xF) < (t & 0xF):
			d6 |= 2
		set_w(a1, c + d6)
		a0 += 2
		a1 += 2
	dma_queue_add(DMA_CRAM, 0, 0xFF0000 | PAL_CURRENT, 0x40)


## boot_fade_in_bright: a fade in by brightness: every d1 frames, each of
## the d4 colours from d3 whose brightness (its levels added) + the step
## is 24 or more moves one channel (blue, red, then green) one level
## toward the target; 24 steps; $F30 while it runs. A button press ends
## it.
func boot_fade_in_bright(d1: int, d2: int, d3: int, d4: int) -> void:
	set_b(F_FADE_IN, 0xFF)
	var o := obj_alloc(boot_fade_in_bright_1)
	if o == 0:
		return
	d1 = boot_pal_frames(d1)
	set_w(o + 0x16, d1)
	set_w(o + 0x18, d2)
	set_w(o + 0x1E, d1)
	set_w(o + 0x1A, d3 * 2)
	set_w(o + 0x1C, (d4 & 0x3F) - 1)


func boot_fade_in_bright_1(o: int) -> void:
	if sb(PRESSED) < 0:
		set_b(F_FADE_IN, 0)
		obj_free(o)
		return
	if w(o + 0x1E) != 0:
		add_w(o + 0x1E, -1)
		return
	set_w(o + 0x1E, w(o + 0x16))
	if sw(o + 0x18) >= 0x18:
		set_b(F_FADE_IN, 0)
		obj_free(o)
		return
	add_w(o + 0x18, 1)
	var a0 := PAL_TARGET + w(o + 0x1A)
	var a1 := PAL_CURRENT + w(o + 0x1A)
	for i in w(o + 0x1C) + 1:
		var t := w(a0)
		var d1 := t >> 1
		var d0 := d1
		d1 >>= 4
		d0 += d1
		d1 >>= 4
		d0 = (d0 & 0xF) + (d1 & 0xF) + w(o + 0x18) - 0x18
		if d0 >= 0:
			var c := w(a1)
			var add := 0
			if (t & 0xE00) != (c & 0xE00):
				add = 0x200
			elif (t & 0xE) != (c & 0xE):
				add = 2
			elif (t & 0xE0) != (c & 0xE0):
				add = 0x20
			set_w(a1, c + add)
		a0 += 2
		a1 += 2
	dma_queue_add(DMA_CRAM, 0, 0xFF0000 | PAL_CURRENT, 0x40)


## boot_fade_out: a fade out: every frame each channel of every colour
## (96 on the title, else 64) down one level, in both palettes, until all
## are black; $F34 while it runs.
func boot_fade_out() -> void:
	var o := obj_alloc(boot_fade_out_1)
	if o == 0:
		return
	set_b(o + 0x16, 0xFF)
	set_b(F_FADE_OUT, 0xFF)
	set_w(o + 0x1E, 1)


func boot_fade_out_1(o: int) -> void:
	if b(o + 0x16) == 0:
		obj_free(o)
		set_b(F_FADE_OUT, 0)
		return
	set_b(o + 0x16, 0)
	var n := 96 if w(SCREEN) == 1 else 64
	for i in n:
		var v := w(PAL_TARGET + 2 * i)
		var d1 := v & 0xF00
		var d2 := v & 0xF0
		var d3 := v & 0xF
		if d1 > 0:
			d1 -= 0x200
		if d2 > 0:
			d2 -= 0x20
		if d3 > 0:
			d3 -= 2
		var nv := d1 | d2 | d3
		if nv != v:
			set_b(o + 0x16, 0xFF)
		set_w(PAL_CURRENT + 2 * i, nv)
		set_w(PAL_TARGET + 2 * i, nv)
	dma_queue_add(DMA_CRAM, 0, 0xFF0000 | PAL_CURRENT, 0x40)


## boot_fade_out_end: the fade out to its end, then the display off.
func boot_fade_out_end() -> void:
	boot_fade_out()
	while b(F_FADE_OUT) != 0:
		await vblank
	boot_display_off()


## The screens' common end (loc_149954): the fades over, the palette shown
## made the target, a fade out (64 frames at most), the display off after
## 3 frames, the VDP and the scroll tables cleared 3 frames later.
func boot_screen_end() -> void:
	while b(F_FADE_IN) != 0:
		await vblank
	while b(F_FADE_OUT) != 0:
		await vblank
	ISSRam.copy(PAL_TARGET, PAL_CURRENT, 0x80)
	boot_fade_out()
	var d1 := (w(FRAME) + 0x40) & 0xFFFF
	while true:
		if w(FRAME) == d1:
			set_b(F_FADE_OUT, 0)
		if b(F_FADE_OUT) == 0:
			break
		await vblank
	await boot_wait(3)
	boot_display_off()
	await boot_wait(3)
	boot_vdp_init()
	boot_scroll_clear()


# --------------------------------------------------------------------------
# Scrolling (boot_scroll_object): an object adding d1 (its low word) to the
# scroll table's rows (d2: the first row in its high word, the count in
# its low) of plane A (d3 0), B (1) or both (2), and d3's high word to
# VSRAM, every frame (every other with d4), for d1's high word frames (0:
# until a button press); $F2B while it runs.

func boot_scroll_object(d1: int, d2: int, d3: int, d4: int) -> void:
	var o := obj_alloc(boot_scroll_object_1)
	if o == 0:
		return
	set_b(F_SCROLL, 0xFF)
	set_w(o + 0x10, 0xFFFF)
	set_w(o + 0x22, d1 & 0xFFFF)
	set_w(o + 0x1C, (d1 >> 16) & 0xFFFF)
	set_w(o + 0x18, ((d2 & 0xFFFF) - 1) & 0xFFFF)
	set_w(o + 0x16, (((d2 >> 16) & 0xFFFF) << 5) & 0xFFFF)
	set_w(o + 0x1A, d3 & 0xFFFF)
	set_w(o + 0x26, (d3 >> 16) & 0xFFFF)
	set_w(o + 0x34, d4)
	set_b(o + 0x32, 1)


func boot_scroll_object_1(o: int) -> void:
	if sb(PRESSED) < 0:
		obj_free(o)
		set_b(F_SCROLL, 0)
		return
	set_b(F_SCROLL, 0xFF)
	if w(o + 0x1C) != 0:
		add_w(o + 0x1C, -1)
		if w(o + 0x1C) == 0:
			set_b(F_SCROLL, 0)
			obj_free(o)
			return
	if w(o + 0x34) != 0:
		set_b(o + 0x32, -sb(o + 0x32))
		if sb(o + 0x32) < 0:
			return
	if w(o + 0x22) != 0:
		var a0 := HSCROLL + w(o + 0x16)
		var d1 := sw(o + 0x22)
		for i in w(o + 0x18) + 1:
			if w(o + 0x1A) != 1:
				add_w(a0, d1)
			if w(o + 0x1A) != 0:
				add_w(a0 + 2, d1)
			a0 += 0x20
		dma_queue_add(DMA_VRAM, 0xC800, 0xFF0000 | HSCROLL, 0x200)
	if w(o + 0x26) != 0:
		var d0 := sw(o + 0x26)
		if w(o + 0x1A) != 1:
			add_w(VSCROLL, d0)
		if w(o + 0x1A) != 0:
			add_w(VSCROLL + 2, d0)
		dma_queue_add(DMA_VSRAM, 0, 0xFF0000 | VSCROLL, 2)


# --------------------------------------------------------------------------
# The raster routine of the SEGA and Factor 5 screens (boot_raster_vblank).

## boot_raster_vblank: the screens' VBlank routine: the HInt on (every line,
## the first 6 skipped), boot_raster_lines on it, the objects; on the
## SEGA screen a button press leaves only the objects (boot_objects_vblank).
func boot_raster_vblank() -> void:
	set_b(F_DMA, 0xFF)
	set_w(LINE, 6)
	hint_on = true
	hblank = boot_raster_lines
	boot_objects_run()
	if w(SCREEN) == 4 and b(PRESSED) != 0:
		frame_cb = boot_objects_vblank


## boot_objects_vblank: a VBlank routine of the objects and the sprites alone.
func boot_objects_vblank() -> void:
	boot_objects_run()
	boot_sprites_flush()


## boot_raster_lines: from the seventh line, 209 lines of vertical
## scroll (both planes) from a sine table (boot_raster_sine, 208
## words) scaled by the amplitude $1002 (down $100 a frame to 0) from the
## phase $1004 (on 4 a frame): the picture ripples, each line showing the
## row |line + wave|, folded back from 207 (the ROM compares the whole
## long after divu/swap, so a quotient above 0 takes the mirrored branch),
## 9 rows up; -9 for the rest.
func boot_raster_lines() -> void:
	var amp := w(0x1002)
	if amp != 0:
		amp = maxi(0, amp - 0x100)
		set_w(0x1002, amp)
	var d7 := amp >> 8
	var d3 := w(0x1004)
	if d3 >= 0x1A0:
		d3 = 0
	var table := rom("boot_raster_sine")
	var lines := PackedInt32Array()
	lines.resize(224)
	lines.fill(_vsram_last)
	var first := 7
	for n in 209:
		var d0 := ((ISSRom.s16(table + d3) * d7) >> 5) + n
		if d0 < 0:
			d0 = -d0
		if d0 >= 207:
			d0 = 207 - d0 % 207
		d0 += -9 - n
		if first + n < 224:
			lines[first + n] = d0
		d3 += 2
		if d3 >= 0x1A0:
			d3 = 0
	for y in range(mini(224, first + 209), 224):
		lines[y] = -9
	_vsram_last = -9
	m.vdp.vlines_a = lines
	m.vdp.vlines_b = lines
	var ph := w(0x1004) + 4
	if ph >= 0x1A0:
		ph -= 0x1A0
	set_w(0x1004, ph & 0xFFFF)


# --------------------------------------------------------------------------
# Screen 4: SEGA (boot_sega).

## boot_sega: the logo's tiles (boot_res4 entry 0) and map (entry 1,
## plane B) and its palette (boot_sega_palette), the ripple from amplitude
## $4100; 3 frames, the fade in (2 frames a step), 20 frames (25 more on
## PAL), the colours cycled (boot_sega_shine), 120 frames, the fade out.
func boot_sega() -> void:
	boot_display_off()
	boot_objects_init()
	boot_sprites_reset()
	boot_vdp_registers()
	boot_planes_clear()
	boot_scroll_clear()
	_copy_rom(rom("boot_sega_palette"), PAL_TARGET, 16)
	_unpack_res(4, 0)
	dma_queue_add(DMA_VRAM, 0x0000, 0xFF0000 | UNPACK, 0x2E0)
	dma_flush()
	_unpack_res(4, 1)
	dma_queue_add(DMA_VRAM, 0xE000, 0xFF0000 | UNPACK, 0x800)
	dma_flush()
	set_w(0x1002, 0x4100)
	set_w(0x1004, 0x7000)
	frame_cb = boot_raster_vblank
	boot_display_on()
	await boot_wait(3)
	boot_fade_in(2, 0, 0, 0x10)
	while b(F_FADE_IN) != 0:
		await vblank
	await boot_wait(0x14)
	if sb(PAL) < 0:
		await boot_wait(0x19)
	await boot_sega_shine()
	await boot_wait(0x78)
	await boot_fade_out_end()


## boot_sega_shine: the logo's palette again, then 13 times its colours
## 1-13 moved up one place every 2 frames (the shine running along it).
func boot_sega_shine() -> void:
	_copy_rom(rom("boot_sega_palette"), PAL_TARGET, 16)
	for k in 13:
		var first := w(PAL_TARGET + 2)
		for i in 12:
			set_w(PAL_TARGET + 2 + 2 * i, w(PAL_TARGET + 4 + 2 * i))
		set_w(PAL_TARGET + 2 + 24, first)
		boot_sega_shine_1()
		await boot_wait(2)


func boot_sega_shine_1() -> void:
	dma_queue_add(DMA_CRAM, 0, 0xFF0000 | PAL_TARGET, 0x10)


# --------------------------------------------------------------------------
# Screen 3: Konami (boot_konami).

## boot_konami: plane A the green line (tiles 4 and 5 on rows 0-1,
## tile $10 below) and plane B the logo (boot_konami_logo_map's map
## pieces) in the tiles of boot_res3; the dark palettes (data3 on lines
## 0-2, data4 on line 3) faded in by brightness; a spark runs along the
## line (_9) as plane A scrolls (boot_scroll_object), the line's colours
## brighten (_1), the line travels down the screen (_11, plane A up 2 px
## a frame for 112 frames); then the jingle (song 1), the logo's colours
## wiped in (_5, lines 1-2 from boot_konami_palettes), its backdrop (_7, line
## 0), the background to white (_3), 240 frames, the fade out. A button
## press skips to the end.
func boot_konami() -> void:
	boot_objects_init()
	boot_sprites_reset()
	boot_vdp_registers()
	boot_planes_clear()
	boot_scroll_clear()
	for line in 3:
		_copy_rom(rom("boot_konami_dark_palette"), PAL_TARGET + line * 0x20, 16)
	_copy_rom(rom("boot_konami_line_palette"), PAL_TARGET + 0x60, 16)
	_unpack_res(3, 0)
	dma_queue_add(DMA_VRAM, 0x0000, 0xFF0000 | UNPACK, 0xD20)
	dma_flush()
	ISSRam.clear(UNPACK, 0x1000)
	for i in 32:
		set_w(UNPACK + 0x40 + 2 * i, 0xE004)
		set_w(UNPACK + 0xC0 + 2 * i, 0xE005)
	for i in 0x700:
		set_w(UNPACK + 0x100 + 2 * i, 0xE010)
	dma_queue_add(DMA_VRAM, 0xA000, 0xFF0000 | UNPACK, 0x800)
	dma_flush()
	ISSRam.clear(UNPACK, 0x1000)
	var a := rom("boot_konami_logo_map")
	while true:
		var n := ISSRom.u16(a)
		a += 2
		if n == 0:
			break
		var dst := ISSRom.u32(a) & 0xFFFF
		a += 4
		for i in n:
			set_w(dst + 2 * i, ISSRom.u16(a + 2 * i))
		a += 2 * n
	dma_queue_add(DMA_VRAM, 0xE000, 0xFF0000 | UNPACK, 0x800)
	dma_flush()
	frame_cb = boot_konami_vblank
	boot_display_on()
	boot_fade_in_bright(0, 0, 0, 0x3F)
	await boot_wait(0x18)
	boot_konami_spark()
	if sb(PAL) < 0:
		boot_scroll_object(0x00250007, 0x1C, 0, 0)
	else:
		boot_scroll_object(0x002B0006, 0x1C, 0, 0)
	while b(F_ANIM) != 0:
		await vblank
	if sb(PRESSED) >= 0:
		boot_konami_line_colours()
		while b(F_ANIM) != 0:
			await vblank
		boot_konami_line_down()
		while b(F_ANIM) != 0:
			await vblank
	if sb(PRESSED) >= 0:
		await boot_wait(0x1E)
		set_w(SOUND, 0xFFFF)
		m.play_music(1)
		set_w(SOUND, 1)
		_copy_rom(rom("boot_konami_logo_palette"), PAL_TARGET + 0x20, 32)
		boot_konami_logo_wipe()
		while b(F_ANIM) != 0:
			await vblank
	if sb(PRESSED) >= 0:
		_copy_rom(rom("boot_konami_palettes"), PAL_TARGET, 16)
		boot_konami_back_wipe()
		while b(F_ANIM) != 0:
			await vblank
	if sb(PRESSED) >= 0:
		boot_konami_white()
		await boot_wait(0xF0)
	boot_fade_out()
	while b(F_FADE_OUT) != 0:
		await vblank
	await boot_screen_end()


## boot_konami_line_colours / _2: the line's colours (line 3, colours 2-8) up
## one green level in three stages, 3 frames apart.
func boot_konami_line_colours() -> void:
	var o := obj_alloc(boot_konami_line_colours_1)
	if o == 0:
		return
	set_b(F_ANIM, 0xFF)
	set_w(o + 0x1E, 2)
	set_w(o + 0x32, 0)


func boot_konami_line_colours_1(o: int) -> void:
	add_w(o + 0x1E, -1)
	if w(o + 0x1E) != 0:
		return
	set_w(o + 0x1E, 3)
	var a0 := PAL_TARGET + 0x64
	var offsets := []
	match w(o + 0x32):
		0:
			offsets = [0xC, 0xA, 8]
		1:
			offsets = [0xC, 0xA, 8, 6, 4, 2]
		2:
			offsets = [0xA, 6, 4, 2, 0]
		3:
			offsets = [0xA, 8, 6, 4, 2, 0]
	for k: int in offsets:
		add_w(a0 + k, 0x20)
	dma_queue_add(DMA_CRAM, 0x60, 0xFF0000 | (PAL_TARGET + 0x60), 0x10)
	add_w(o + 0x32, 1)
	if w(o + 0x32) == 3:
		obj_free(o)
		set_b(F_ANIM, 0)


## boot_konami_white / _4: colour 0 up one level a channel seven times,
## every 4 frames (2 on PAL): the background to white.
func boot_konami_white() -> void:
	var o := obj_alloc(boot_konami_white_1)
	if o == 0:
		return
	set_w(o + 0x16, 0)
	set_w(o + 0x1E, 2)
	set_w(o + 0x20, 2 if sb(PAL) < 0 else 4)
	set_b(F_ANIM, 0xFF)


func boot_konami_white_1(o: int) -> void:
	add_w(o + 0x1E, -1)
	if w(o + 0x1E) != 0:
		return
	set_w(o + 0x1E, w(o + 0x20))
	add_w(PAL_TARGET, 0x222)
	dma_queue_add(DMA_CRAM, 0, 0xFF0000 | PAL_TARGET, 0x40)
	add_w(o + 0x16, 1)
	if w(o + 0x16) == 7:
		obj_free(o)
		set_b(F_ANIM, 0)


## boot_konami_logo_wipe / _6: lines 1 and 2 wiped in from their last colour
## back, one more a frame, from boot_konami_palettes + $2C / + $4C.
func boot_konami_logo_wipe() -> void:
	var o := obj_alloc(boot_konami_logo_wipe_1)
	if o == 0:
		return
	set_b(F_ANIM, 0xFF)
	set_w(o + 0x16, 0x1E)


func boot_konami_logo_wipe_1(o: int) -> void:
	var a0 := rom("boot_konami_palettes")
	var d4 := w(o + 0x16)
	var d1 := d4 & 0xFF
	var d0 := 0
	var d3 := ((32 - d1) >> 1) & 0xFF
	for i in d3:
		set_w(PAL_TARGET + 0x20 + d1, ISSRom.u16(a0 + 0x2C + d0))
		set_w(PAL_TARGET + 0x40 + d1, ISSRom.u16(a0 + 0x4C + d0))
		d0 += 2
		d1 += 2
	set_w(o + 0x16, d4 - 2)
	dma_queue_add(DMA_CRAM, 0, 0xFF0000 | PAL_TARGET, 0x40)
	if w(o + 0x16) == 0xA:
		obj_free(o)
		set_b(F_ANIM, 0)


## boot_konami_back_wipe / _8: line 0 wiped in the same way from + $C.
func boot_konami_back_wipe() -> void:
	var o := obj_alloc(boot_konami_back_wipe_1)
	if o == 0:
		return
	set_b(F_ANIM, 0xFF)
	set_w(o + 0x16, 0x1E)


func boot_konami_back_wipe_1(o: int) -> void:
	var a0 := rom("boot_konami_palettes")
	var d4 := w(o + 0x16)
	var d1 := d4 & 0xFF
	var d0 := 0
	var d3 := ((32 - d1) >> 1) & 0xFF
	for i in d3:
		set_w(PAL_TARGET + d1, ISSRom.u16(a0 + 0xC + d0))
		d0 += 2
		d1 += 2
	set_w(o + 0x16, d4 - 2)
	dma_queue_add(DMA_CRAM, 0, 0xFF0000 | PAL_TARGET, 0x40)
	if w(o + 0x16) == 0xA:
		obj_free(o)
		set_b(F_ANIM, 0)


## boot_konami_spark / _10: the spark: a sprite from x $49 along the line
## 6 px a frame (7 on PAL), its four pieces (boot_konami_spark_data) in
## turn, until x $140 or a button press.
func boot_konami_spark() -> void:
	var o := obj_alloc(boot_konami_spark_1)
	if o == 0:
		return
	set_w(o + 0x34, 0)
	set_w(o + 0x32, 0)
	set_w(o + 0xC, 0x49)
	set_w(o + 8, 0x49)
	set_w(o + 0x1E, 1)
	set_w(o + 0x20, 1)
	set_b(F_ANIM, 0xFF)


func boot_konami_spark_1(o: int) -> void:
	var d3 := w(o + 0x34) >> 5
	add_w(o + 8, 7 if sb(PAL) < 0 else 6)
	var piece := rom("boot_konami_spark_data") + w(o + 0x32)
	var a1 := boot_sprite_alloc()
	if a1 >= 0:
		boot_sprite_set(o, a1, piece, d3)
	add_w(o + 0x1E, -1)
	if w(o + 0x1E) == 0:
		set_w(o + 0x1E, w(o + 0x20))
		add_w(o + 0x32, 0xA)
		if w(o + 0x32) == 0x28:
			set_w(o + 0x32, 0)
	if sb(PRESSED) < 0 or w(o + 8) >= 0x140:
		obj_free(o)
		set_b(F_ANIM, 0)


## boot_konami_line_down / _12: VSRAM down 2 a frame for 112 frames (the
## line travels down the screen).
func boot_konami_line_down() -> void:
	var o := obj_alloc(boot_konami_line_down_1)
	if o == 0:
		return
	set_w(o + 0x26, 0xFFFE)
	set_w(o + 0x32, 0)
	set_b(F_ANIM, 0xFF)


func boot_konami_line_down_1(o: int) -> void:
	add_w(VSCROLL, sw(o + 0x26))
	dma_queue_add(DMA_VSRAM, 0, 0xFF0000 | VSCROLL, 2)
	if sb(PRESSED) < 0:
		obj_free(o)
		set_b(F_ANIM, 0)
		return
	add_w(o + 0x32, 1)
	if w(o + 0x32) == 0x70:
		obj_free(o)
		set_b(F_ANIM, 0)


## boot_konami_vblank: the screen's VBlank routine: the objects, the
## sprites.
func boot_konami_vblank() -> void:
	boot_objects_run()
	boot_sprites_flush()


# --------------------------------------------------------------------------
# Screen 2: Factor 5 (boot_factor5).

## boot_factor5: planes of 32 x 32 cells: the burst's tiles (boot_res2
## entry 3 at $19A0, entry 2 at $0000) and maps (entry 5 on plane A with
## palette 1, entry 4 on plane B in front), lines 0-1 from entry 0; the
## ripple from amplitude $8000 with its phase running; 3 frames, a fade in
## of 32 colours (2 frames a step; by brightness on PAL) under 300 frames,
## the fade out.
func boot_factor5() -> void:
	boot_display_off()
	boot_objects_init()
	boot_sprites_reset()
	boot_vdp_registers()
	boot_scroll_clear()
	m.vdp.plane_cols = 32
	m.vdp.plane_rows = 32
	_copy_rom(ISSRom.boot_res(2, 0), PAL_TARGET, 32)
	_unpack_res(2, 3)
	dma_queue_add(DMA_VRAM, 0x19A0, 0xFF0000 | UNPACK, 0x3070)
	dma_flush()
	_unpack_res(2, 5)
	for i in 0x680:
		set_w(UNPACK + 2 * i, (w(UNPACK + 2 * i) + 0xCD) | 0x2000)
	dma_queue_add(DMA_VRAM, 0xA002, 0xFF0000 | UNPACK, 0x340)
	dma_flush()
	_unpack_res(2, 2)
	dma_queue_add(DMA_VRAM, 0x0000, 0xFF0000 | UNPACK, 0xCC0)
	dma_flush()
	_unpack_res(2, 4)
	for i in 0x680:
		set_w(UNPACK + 2 * i, w(UNPACK + 2 * i) | 0x8000)
	dma_queue_add(DMA_VRAM, 0xE002, 0xFF0000 | UNPACK, 0x340)
	dma_flush()
	set_w(0x1002, 0x8000)
	set_w(0x1004, 0)
	boot_display_on()
	frame_cb = boot_raster_vblank
	await boot_wait(3)
	if b(PAL) == 0:
		boot_fade_in(2, 0, 0, 0x20)
	else:
		boot_fade_in_bright(2, 0, 0, 0x20)
	await boot_wait(0x12C)
	await boot_fade_out_end()


# --------------------------------------------------------------------------
# Helpers the intro and the title share.

const UNPACK_SRC := 0xFF0000 | UNPACK
## boot_palette_a / boot_palette_b: two 32-colour palettes ($14A150,
## $14A1B0) the intro's end and the title use.
const PALETTE_A := 0x14A150
const PALETTE_B := 0x14A1B0


static func _s16(v: int) -> int:
	v &= 0xFFFF
	return v - 0x10000 if v >= 0x8000 else v


## n words of the unpack buffer straight into VRAM (the screens' first
## loads, written to the data port).
func _vram_write(dest: int, words: int) -> void:
	m.vdp.dma(dest, ISSRam.m, UNPACK, words * 2)


## Register 16: the planes' size in cells.
func _plane_size(cols: int, rows: int) -> void:
	m.vdp.plane_cols = cols
	m.vdp.plane_rows = rows


## n sprite pieces (10 bytes each) from a4 at object o's position, tiles
## from d3 (the loop every animation object runs).
func _draw_pieces(o: int, a4: int, n: int, d3: int) -> void:
	for i in n:
		var a1 := boot_sprite_alloc()
		if a1 >= 0:
			boot_sprite_set(o, a1, a4, d3)
		a4 += 10


## Song id, $F38 noting it ($FFFF while the driver starts).
func _play_music(id: int) -> void:
	set_w(SOUND, 0xFFFF)
	m.play_music(id)
	set_w(SOUND, id)


## The main thread's wait for the title's HInt counter ($1846) to move.
func _wait_hint() -> void:
	var d1 := w(0x1846)
	while w(0x1846) == d1:
		if hint_on:
			await hint
		else:
			await vblank


## boot_wait_vblank_edges: two edges of the VBlank flag, polled: the next VBlank
## has run when it returns.
func boot_wait_vblank_edges() -> void:
	await vblank


## boot_spawn: an object that queues, next VBlank, a CRAM DMA of d2 colours
## of the target palette from word d1, then goes.
func boot_spawn(d1: int, d2: int) -> void:
	var o := obj_alloc(boot_spawn_1)
	if o == 0:
		return
	set_w(o + 0x16, d1)
	set_w(o + 0x32, d2)


func boot_spawn_1(o: int) -> void:
	dma_queue_add(DMA_CRAM, 0, 0xFF0000 | (PAL_TARGET + w(o + 0x16)), w(o + 0x32))
	obj_free(o)


## boot_palettes_black: both palettes black, sent next VBlank.
func boot_palettes_black() -> void:
	obj_alloc(boot_palettes_black_1)
	ISSRam.clear(PAL_TARGET, 0x80)
	ISSRam.clear(PAL_CURRENT, 0x80)


func boot_palettes_black_1(o: int) -> void:
	dma_queue_add(DMA_CRAM, 0, 0xFF0000 | PAL_TARGET, 0x40)
	obj_free(o)


## boot_fade_out_channels: a fade out by channel: the d4 colours from d3 of the
## target palette become the current one, then every d1 frames, d2 times,
## each loses a level of green, else of red, else of blue; $F34 while it
## runs.
func boot_fade_out_channels(d1: int, d2: int, d3: int, d4: int) -> void:
	var o := obj_alloc(boot_fade_out_channels_1)
	if o == 0:
		return
	set_b(F_FADE_OUT, 0xFF)
	d1 = boot_pal_frames(d1)
	set_w(o + 0x16, d1)
	set_w(o + 0x18, d2)
	set_w(o + 0x1E, d1)
	set_w(o + 0x1A, d3 * 2)
	set_w(o + 0x1C, d4 - 1)
	ISSRam.copy(PAL_CURRENT + d3 * 2, PAL_TARGET + d3 * 2, d4 * 2)


func boot_fade_out_channels_1(o: int) -> void:
	if w(o + 0x1E) != 0:
		add_w(o + 0x1E, -1)
		return
	set_w(o + 0x1E, w(o + 0x16))
	if w(o + 0x18) == 0:
		obj_free(o)
		set_b(F_FADE_OUT, 0)
		return
	add_w(o + 0x18, -1)
	var a1 := PAL_CURRENT + w(o + 0x1A)
	for i in w(o + 0x1C) + 1:
		var c := w(a1)
		var d0 := 0
		if c & 0xE0:
			d0 = -0x20
		elif c & 0xE:
			d0 = -2
		elif c & 0xE00:
			d0 = -0x200
		set_w(a1, c + d0)
		a1 += 2
	dma_queue_add(DMA_CRAM, 0, 0xFF0000 | PAL_CURRENT, 0x40)


## boot_fade_up: a fade up to the current palette: every d1 frames, 16
## times, each of the d4 colours from d3 of the target palette gains a
## level in each channel below the current palette's, and the target is
## shown (the intro's wipe to white); $F30 while it runs.
func boot_fade_up(d1: int, d2: int, d3: int, d4: int) -> void:
	set_b(F_FADE_IN, 0xFF)
	var o := obj_alloc(boot_fade_up_1)
	if o == 0:
		return
	d1 = boot_pal_frames(d1)
	set_w(o + 0x16, d1)
	set_w(o + 0x18, d2)
	set_w(o + 0x1E, d1)
	set_w(o + 0x1A, d3 * 2)
	set_w(o + 0x1C, (d4 & 0x3F) - 1)


func boot_fade_up_1(o: int) -> void:
	if sb(PRESSED) < 0:
		set_b(F_FADE_IN, 0)
		obj_free(o)
		return
	if w(o + 0x1E) != 0:
		add_w(o + 0x1E, -1)
		return
	set_w(o + 0x1E, w(o + 0x16))
	if sw(o + 0x18) >= 0x10:
		set_b(F_FADE_IN, 0)
		obj_free(o)
		return
	add_w(o + 0x18, 1)
	var a0 := PAL_TARGET + w(o + 0x1A)
	var a1 := PAL_CURRENT + w(o + 0x1A)
	for i in w(o + 0x1C) + 1:
		var t := w(a0)
		var c := w(a1)
		var d6 := 0
		if (c & 0xF00) > (t & 0xF00):
			d6 |= 0x200
		if (c & 0xF0) > (t & 0xF0):
			d6 |= 0x20
		if (c & 0xF) > (t & 0xF):
			d6 |= 2
		set_w(a0, t + d6)
		a0 += 2
		a1 += 2
	dma_queue_add(DMA_CRAM, 0, 0xFF0000 | PAL_TARGET, 0x40)


# --------------------------------------------------------------------------
# Screen 0: the intro (boot_intro): a dozen scenes of unpacked
# pictures (boot_res0), animated sprites and palette cycles, each ended by
# a button press (a press skips to the fade out).

## boot_intro: the scenes in turn (_intro), then the common end.
func boot_intro() -> void:
	await _intro()
	await boot_screen_end()


## The intro's main thread: the stadium at night (tiles 0, planes from
## boot_res0 entries 11-13, 27) scrolling diagonally as its colours fade
## in, a ball (boot_intro_ball) and a player (boot_intro_player); the
## grid of faces (boot_intro_faces) under song 2; the circle wipe
## (boot_intro_circle_wipe); the wide picture seen through a sliding window
## (boot_intro_window); the plane B column wipe (boot_intro_column_wipe); the
## colour cycles (boot_intro_cycle_two, boot_intro_cycle_one), the falling pieces
## (boot_intro_falling), the wipe to white (boot_fade_up), the small
## window (boot_intro_small_window), the flicker (boot_intro_flicker) with both
## halves of plane B scrolling apart; the logo (boot_intro_logo) under
## shadow / highlight; a return on a button press.
func _intro() -> void:
	boot_display_off()
	boot_objects_init()
	boot_sprites_reset()
	# boot_intro_registers: the registers of boot_vdp_registers.
	boot_vdp_registers()
	m.vdp.shadow_highlight = false
	_copy_rom(ISSRom.boot_res(0, 0), PAL_TARGET, 32)
	_copy_rom(ISSRom.boot_res(0, 1), PAL_TARGET + 0x40, 16)
	_copy_rom(ISSRom.boot_res(0, 8), PAL_TARGET + 0x60, 16)
	_unpack_res(0, 11)
	_vram_write(0x0000, 0xC80)
	_unpack_res(0, 12)
	_vram_write(0xE000, 0x1000)
	for i in 0x1000:
		ISSRam.or_w(UNPACK + 2 * i, 0x8000)
	_vram_write(0xA000, 0x1000)
	_unpack_res(0, 13)
	_vram_write(0x1900, 0x980)
	_unpack_res(0, 27)
	_vram_write(0x2C00, 0x2800)
	set_w(VSCROLL, 0xBE)
	set_w(VSCROLL + 2, 0xBE)
	frame_cb = boot_objects_vblank
	if sb(PRESSED) < 0:
		return
	boot_fade_in_bright(0, 0, 0, 0x10)
	if sb(PRESSED) < 0:
		return
	_play_music(0x19)
	boot_scroll_object(0x0023FFF7, 0x20, 0xFFF9FFFF, 0)
	boot_fade_in_bright(0, 0, 0x20, 0x20)
	if sb(PRESSED) < 0:
		return
	boot_display_on()
	while b(F_SCROLL) != 0:
		await vblank
	m.play_sfx(124)
	boot_intro_ball()
	boot_intro_player()
	await boot_wait(0x28)
	m.play_sfx(125)
	while b(F_ANIM) != 0:
		await vblank
	if sb(PRESSED) < 0:
		return
	boot_fade_in_bright(1, 0, 0x10, 0x10)
	await boot_wait(0xB4)
	if sw(SOUND) >= 0:
		set_w(SOUND, 0xFFFF)
		m.sound.stop_music()
	if sb(PRESSED) < 0:
		return
	boot_fade_out_channels(0, 0x18, 0, 0x3F)
	while b(F_FADE_OUT) != 0:
		await vblank
	# The faces.
	boot_planes_clear()
	m.vdp.shadow_highlight = false
	_plane_size(64, 32)
	_copy_rom(ISSRom.boot_res(0, 2), PAL_TARGET + 0x60, 16)
	_unpack_res(0, 14)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x0000, UNPACK_SRC, 0x1000)
	await boot_wait(3)
	_unpack_res(0, 16)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x2000, UNPACK_SRC, 0x800)
	await boot_wait(3)
	_unpack_res(0, 15)
	await boot_wait(3)
	for i in 0x700:
		set_w(UNPACK + 2 * i, (w(UNPACK + 2 * i) | 0x8000) + 0x100)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0xA000, UNPACK_SRC, 0x700)
	await boot_wait(3)
	_plane_size(64, 32)
	boot_scroll_clear()
	await boot_wait(3)
	_copy_rom(ISSRom.boot_res(0, 3), PAL_TARGET, 16)
	_play_music(2)
	set_b(0xF35, 0xFF)
	boot_intro_faces()
	boot_fade_in_bright(1, 0, 0, 0x3F)
	await boot_wait(0x85)
	boot_scroll_object(0x00210008, 0x000C0004, 0, 0)
	await boot_wait(0x78)
	boot_fade_in_bright(0, 0, 4, 1)
	while b(F_FADE_IN) != 0:
		await vblank
	await boot_wait(0x5A)
	ISSRam.clear(UNPACK, 0xE00)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0xA000, UNPACK_SRC, 0x700)
	await boot_wait(3)
	_plane_size(32, 32)
	boot_scroll_clear()
	await boot_wait(3)
	if sb(PRESSED) < 0:
		return
	# The circle wipe over the faces.
	set_w(0xFFA, 0)
	boot_intro_circle_wipe()
	_copy_rom(PALETTE_A, PAL_TARGET + 0x60, 16)
	boot_fade_in(2, 0, 0x30, 0x10)
	while b(0xF35) != 0:
		await vblank
	if sb(PRESSED) < 0:
		return
	# The wide picture through a sliding window.
	boot_palettes_black()
	await boot_wait(3)
	boot_scroll_clear()
	boot_planes_clear()
	boot_display_off()
	await boot_wait(3)
	_unpack_res(0, 17)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x0000, UNPACK_SRC, 0x1000)
	await boot_wait(3)
	_copy_rom(ISSRom.boot_res(0, 4), PAL_TARGET, 16)
	_unpack_res(0, 20)
	await boot_wait(3)
	await boot_wait(0x14 if b(PAL) == 0 else 0xA)
	boot_intro_window()
	boot_display_on()
	while b(F_ANIM) != 0:
		await vblank
	if sb(PRESSED) < 0:
		return
	# The column wipe of plane B over a dimmed plane A.
	boot_display_off()
	boot_palettes_black()
	boot_scroll_clear()
	await boot_wait(3)
	if sb(PRESSED) < 0:
		return
	_unpack_res(0, 17)
	await boot_wait(3)
	for i in 0x400:
		set_b(UNPACK + i, b(UNPACK + i) & 0xBB)
	await boot_wait(3)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x0000, UNPACK_SRC, 0x800)
	dma_flush()
	_unpack_res(0, 18)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x1000, UNPACK_SRC, 0x12C0)
	await boot_wait(3)
	_unpack_res(0, 19)
	await boot_wait(3)
	_plane_size(128, 32)
	for i in 0xE00:
		set_w(UNPACK + 2 * i, (w(UNPACK + 2 * i) + 0x80) & 0x7FFF)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0xA000, UNPACK_SRC, 0xE00)
	await boot_wait(3)
	for i in 0xE00:
		set_w(UNPACK + 2 * i, 0xE000)
	dma_queue_add(DMA_VRAM, 0xE000, UNPACK_SRC, 0xE00)
	await boot_wait(3)
	_unpack_res(0, 20)
	boot_display_on()
	boot_intro_column_wipe()
	await boot_wait(3)
	if sb(PRESSED) < 0:
		return
	await boot_wait(3)
	boot_scroll_object(0x0000FFFD, 0x20, 1, 0)
	while b(F_SCROLL) != 0:
		await vblank
	if sb(PRESSED) < 0:
		return
	# Two colours cycling on a wide plane B.
	boot_objects_init()
	boot_palettes_black()
	await boot_wait(3)
	boot_scroll_clear()
	boot_planes_clear()
	boot_display_off()
	await boot_wait(3)
	_plane_size(128, 32)
	_copy_rom(ISSRom.boot_res(0, 4), PAL_TARGET + 0x60, 16)
	_unpack_res(0, 17)
	dma_queue_add(DMA_VRAM, 0x0000, UNPACK_SRC, 0x800)
	await boot_wait(3)
	_unpack_res(0, 21)
	for i in 0xE00:
		ISSRam.or_w(UNPACK + 2 * i, 0xE000)
	dma_queue_add(DMA_VRAM, 0xE000, UNPACK_SRC, 0xE00)
	boot_display_on()
	await boot_wait_vblank_edges()
	boot_intro_cycle_two()
	while b(F_ANIM) != 0:
		await vblank
	if sb(PRESSED) < 0:
		return
	# The falling pieces, then the wipe to white.
	boot_palettes_black()
	await boot_wait(3)
	_plane_size(32, 32)
	boot_scroll_clear()
	await boot_wait(3)
	boot_planes_clear()
	boot_display_off()
	await boot_wait(3)
	if b(PAL) == 0:
		await boot_wait(0x1A)
	_unpack_res(0, 22)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x0000, UNPACK_SRC, 0xC80)
	await boot_wait(3)
	_unpack_res(0, 24)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x1900, UNPACK_SRC, 0x1240)
	await boot_wait(3)
	_unpack_res(0, 23)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0xA000, UNPACK_SRC, 0x380)
	await boot_wait(3)
	_copy_rom(ISSRom.boot_res(0, 6), PAL_TARGET, 64)
	_copy_rom(ISSRom.boot_res(0, 7), PAL_TARGET + 0x40, 16)
	boot_spawn(0, 0x40)
	boot_display_on()
	boot_intro_falling()
	while b(F_ANIM) != 0:
		await vblank
	if sb(PRESSED) < 0:
		return
	set_b(0xF35, 0xFF)
	for i in 96:
		set_w(PAL_CURRENT + 2 * i, 0xEEE)
	await boot_wait(3)
	boot_fade_up(3, 0, 1, 0x3F)
	set_w(0xFFA, 1)
	boot_intro_circle_wipe()
	while b(0xF35) != 0:
		await vblank
	# The small window.
	boot_palettes_black()
	await boot_wait(3)
	boot_planes_clear()
	boot_display_off()
	if b(PAL) == 0:
		await boot_wait(0x28)
	boot_scroll_clear()
	_plane_size(32, 32)
	_unpack_res(0, 17)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x0000, UNPACK_SRC, 0x800)
	dma_flush()
	_unpack_res(0, 25)
	for i in 0xE00:
		ISSRam.or_w(UNPACK + 2 * i, 0x8000)
	boot_display_on()
	boot_intro_small_window()
	while b(F_ANIM) != 0:
		await vblank
	if sb(PRESSED) < 0:
		return
	# Plane B's halves scrolling apart under the flicker.
	await boot_wait(3)
	boot_palettes_black()
	await boot_wait(3)
	boot_scroll_clear()
	boot_display_off()
	await boot_wait(3)
	_unpack_res(0, 18)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x1000, UNPACK_SRC, 0x12C0)
	await boot_wait(3)
	_unpack_res(0, 19)
	await boot_wait(3)
	for i in 0xE00:
		add_w(UNPACK + 2 * i, 0x80)
	dma_queue_add(DMA_VRAM, 0xA000, UNPACK_SRC, 0xE00)
	await boot_wait(3)
	_unpack_res(0, 17)
	await boot_wait(3)
	for i in 0x1001:
		# Of each tile byte only colour 4 stays, as colour 15.
		var v := b(UNPACK + i)
		set_b(UNPACK + i, (0xF if v & 0xF == 4 else 0) | (0xF0 if v & 0xF0 == 0x40 else 0))
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x0000, UNPACK_SRC, 0x800)
	await boot_wait(3)
	_unpack_res(0, 25)
	await boot_wait(3)
	for i in 0xE00:
		ISSRam.or_w(UNPACK + 2 * i, 0x8000)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0xE000, UNPACK_SRC, 0xE00)
	await boot_wait(3)
	_plane_size(128, 32)
	set_b(0xF36, 0xFF)
	boot_display_on()
	boot_intro_flicker()
	boot_scroll_object(0x012CFFFD, 0x10, 1, 0)
	boot_scroll_object(0x012C0003, 0x00100010, 1, 0)
	await boot_wait(3)
	while b(F_SCROLL) != 0:
		await vblank
	if sb(PRESSED) < 0:
		set_b(0xF36, 0)
		return
	boot_scroll_clear()
	boot_scroll_object(0x0001FFFF, 0x20, 6, 0)
	_unpack_res(0, 26)
	await boot_wait(3)
	for i in 0xE00:
		ISSRam.or_w(UNPACK + 2 * i, 0xE000)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0xE000, UNPACK_SRC, 0xE00)
	await boot_wait(3)
	boot_intro_cycle_one()
	while b(F_ANIM) != 0:
		await vblank
	if sb(PRESSED) < 0:
		return
	# The logo, with shadow / highlight.
	boot_palettes_black()
	await boot_wait(3)
	boot_display_off()
	boot_scroll_clear()
	_copy_rom(ISSRom.boot_res(0, 9), PAL_TARGET, 16)
	_copy_rom(ISSRom.boot_res(0, 10), PAL_TARGET + 0x60, 16)
	_plane_size(32, 32)
	m.vdp.shadow_highlight = true
	_unpack_res(0, 28)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x0000, UNPACK_SRC, 0x640)
	dma_flush()
	_unpack_res(0, 31)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x0C80, UNPACK_SRC, 0x39D0)
	dma_flush()
	_unpack_res(0, 32)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x8020, UNPACK_SRC, 0x730)
	dma_flush()
	_unpack_res(0, 29)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0xA000, UNPACK_SRC, 0xE00)
	dma_flush()
	await boot_wait(3)
	_unpack_res(0, 30)
	await boot_wait(3)
	for i in 0xE00:
		ISSRam.or_w(UNPACK + 2 * i, 0x8000)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0xE000, UNPACK_SRC, 0xE00)
	dma_flush()
	await boot_wait(3)
	if b(PAL) == 0:
		boot_scroll_object(0x0064FFFE, 0x00060010, 0, 0)
	else:
		boot_scroll_object(0x0050FFFE, 0x00060010, 0, 0)
	boot_fade_in(1, 0, 0, 0x3F)
	boot_intro_logo()
	boot_display_on()
	while b(F_SCROLL) != 0:
		await vblank
	boot_scroll_object(0x0010FFFF, 0x00060010, 0, 0)
	while b(F_ANIM) != 0:
		await vblank
	ISSRam.copy(PAL_CURRENT, PAL_TARGET, 0x80)
	set_l(PAL_CURRENT + 0x7C, 0)
	_copy_rom(PALETTE_A, PAL_TARGET, 32)
	_copy_rom(PALETTE_A, PAL_TARGET + 0x40, 32)
	m.vdp.set_cram_word(63, 0)
	m.vdp.shadow_highlight = false
	await boot_wait(0x14)
	boot_fade_in(3, 0, 0, 0x20)
	boot_fade_in(3, 0, 0x20, 0x20)
	await boot_wait(0x78)


## boot_intro_ball: the ball: 10 frames of 4 pieces (the lists at
## $14637E) every 6 frames after 31, at ($AA, $8C), tiles from $2C00;
## $F2C while it runs.
func boot_intro_ball() -> void:
	var o := obj_alloc(boot_intro_ball_1)
	if o == 0:
		return
	set_l(o + 0x2A, 0x14637E)
	set_w(o + 0x34, 0x2C00)
	set_w(o + 0x32, 0)
	set_w(o + 0xC, 0x8C)
	set_w(o + 0x8, 0xAA)
	set_w(o + 0x1E, 1)
	set_w(o + 0x20, boot_pal_frames(6))
	set_w(o + 0x16, 0x1E)
	set_b(F_ANIM, 0xFF)


func boot_intro_ball_1(o: int) -> void:
	if sb(PRESSED) < 0:
		set_b(F_ANIM, 0)
		obj_free(o)
		return
	add_w(o + 0x16, -1)
	if sw(o + 0x16) >= 0:
		return
	var a4 := ISSRom.u32(l(o + 0x2A))
	var d3 := w(o + 0x34) >> 5
	add_w(o + 0x1E, -1)
	if w(o + 0x1E) == 0:
		set_w(o + 0x1E, w(o + 0x20))
		set_l(o + 0x2A, l(o + 0x2A) + 4)
		add_w(o + 0x32, 1)
		if w(o + 0x32) == 0xA:
			set_l(o + 0x2A, 0x14637E)
			set_w(o + 0x32, 0)
			set_b(F_ANIM, 0)
			obj_free(o)
			return
	_draw_pieces(o, a4, 4, d3)


## boot_intro_player: the player: five stages (the lists at $146060) of a
## figure moving up and left from ($10, $10) at the stage's speed, 4
## pieces in the first two, 1 after, the next stage once it is above the
## screen; 300 frames; tiles from $1900.
func boot_intro_player() -> void:
	var o := obj_alloc(boot_intro_player_1)
	if o == 0:
		return
	set_l(o + 0x2A, 0x146060)
	set_w(o + 0x34, 0x1900)
	set_w(o + 0x32, 0)
	set_w(o + 0x26, 0xFFFC)
	set_w(o + 0x22, 0xFFFC)
	set_w(o + 0xC, 0x10)
	set_w(o + 0x8, 0x10)
	set_w(o + 0x16, boot_pal_frames(0x12C))
	set_b(F_ANIM, 0xFF)


func boot_intro_player_1(o: int) -> void:
	if sb(PRESSED) < 0:
		obj_free(o)
		return
	add_w(o + 0x16, -1)
	if w(o + 0x16) == 0:
		obj_free(o)
		return
	var a4 := ISSRom.u32(l(o + 0x2A))
	var d3 := w(o + 0x34) >> 5
	add_w(o + 0xC, sw(o + 0x26))
	add_w(o + 0x8, sw(o + 0x22))
	var stage := w(o + 0x32)
	_draw_pieces(o, a4, 4 if stage < 2 else 1, d3)
	if sw(o + 0xC) >= 0:
		return
	match stage:
		0:
			add_w(o + 0x22, -1)
			add_w(o + 0x26, -1)
		4:
			set_w(o + 0x22, 0)
			set_w(o + 0x26, 0)
			return
	add_w(o + 0x32, 1)
	set_l(o + 0x2A, l(o + 0x2A) + 4)
	set_w(o + 0x8, 0x10)
	set_w(o + 0xC, 0x10)


## boot_intro_faces: the faces: a grid of 7 rows of 8 sprites of 32 x 32
## (the piece at $14587E, palette 3), each column's tiles from one of 16
## phases ($F3A, 16 tiles apart) that all step every 3 frames; while $F35
## is set (the circle wipe clears it).
func boot_intro_faces() -> void:
	var o := obj_alloc(boot_intro_faces_1)
	if o == 0:
		return
	set_l(o + 0x2A, 0x14587A)
	set_w(o + 0x34, 0)
	set_w(o + 0x32, 0)
	var d0 := boot_pal_frames(3)
	set_w(o + 0x1E, d0)
	set_w(o + 0x20, d0)
	set_w(o + 0x16, boot_pal_frames(0x1A4))
	for i in 16:
		set_w(0xF3A + 2 * i, 15 - i)


func boot_intro_faces_1(o: int) -> void:
	if b(0xF35) == 0:
		obj_free(o)
		return
	add_w(o + 0x1E, -1)
	if w(o + 0x1E) == 0:
		set_w(o + 0x1E, w(o + 0x20))
		for i in 16:
			set_w(0xF3A + 2 * i, (w(0xF3A + 2 * i) + 1) & 0xF)
	var a4 := ISSRom.u32(l(o + 0x2A))
	var d5 := 0
	for row in 7:
		for col in 8:
			var a1 := boot_sprite_alloc()
			if a1 < 0:
				continue
			var d3 := w(o + 0x34) + (w(0xF3A + 2 * d5) << 4)
			set_w(a1, w(o + 0xC) + ISSRom.u16(a4))
			set_b(a1 + 2, ISSRom.u16(a4 + 2) & 0xFF)
			set_w(a1 + 4, d3 + ISSRom.u16(a4 + 4))
			set_w(a1 + 6, w(o + 8) + ISSRom.u16(a4 + 6))
			add_w(o + 8, 0x20)
			d5 = (d5 + 1) & 0xF
		set_w(o + 8, 0)
		add_w(o + 0xC, 0x20)
	set_w(o + 0xC, 0)


## boot_intro_circle_wipe: the circle wipe: plane B's map (the unpack buffer,
## filled with tile $100 the first time, $FFA 0) gets, row list by row
## list ($1454BE: 12 lists of (word offset, run) pairs), runs of tile $65
## (the second time, $FFA 1, tile $97 of palette 1 over what is there)
## with tile $66 / $98 at both ends of the short ones, and goes to the VDP;
## the rows come every 6 frames (4 the second time) to every frame; $F35
## while it runs.
func boot_intro_circle_wipe() -> void:
	var o := obj_alloc(boot_intro_circle_wipe_1)
	if o == 0:
		return
	set_l(o + 0x2A, 0x1454BE)
	set_w(o + 0x34, 0x2000)
	set_w(o + 0x32, 0)
	set_w(o + 0x1E, 1)
	set_w(o + 0x20, 6 if w(0xFFA) == 0 else 4)
	set_w(o + 0x18, 0)
	if w(0xFFA) == 0:
		for i in 0x380:
			set_w(UNPACK + 2 * i, 0x8100)
	set_b(0xF35, 0xFF)


func boot_intro_circle_wipe_1(o: int) -> void:
	add_w(o + 0x1E, -1)
	if w(o + 0x1E) != 0:
		return
	if w(o + 0x20) > 1:
		add_w(o + 0x20, -1)
	set_w(o + 0x1E, w(o + 0x20))
	var a4 := ISSRom.u32(l(o + 0x2A) + 4 * w(o + 0x32))
	if a4 == 0xFFFFFFFF:
		obj_free(o)
		set_b(0xF35, 0)
		return
	var second := w(0xFFA) != 0
	var end_tile := 0xA098 if second else 0x66
	var run_tile := 0xA097 if second else 0x65
	while true:
		var a0 := UNPACK + ISSRom.u16(a4)
		var d1 := ISSRom.u16(a4 + 2)
		if d1 < 0x20 and d1 > 1:
			set_w(a0 - 2, (w(a0 - 2) & 0xFF00) | end_tile)
			set_w(a0 + 2 * d1 + 2, (w(a0 + 2 * d1 + 2) & 0xFF00) | end_tile)
		for i in d1 + 1:
			set_w(a0, (w(a0) & 0xFF00) | run_tile)
			a0 += 2
		a4 += 4
		if ISSRom.s16(a4) < 0:
			break
	add_w(o + 0x32, 1)
	dma_queue_add(DMA_VRAM, 0xE000, UNPACK_SRC, 0x380)


## boot_intro_window: the sliding window: every 20 frames, colour 4 black
## for 3 frames, then one of six colours (boot_intro_window_data) as the
## 16 middle columns of plane A's 28 rows show the next 16 columns of the
## wide picture unpacked at $8040 (180 words a row); 7 steps; $F2C while
## it runs.
func boot_intro_window() -> void:
	var o := obj_alloc(boot_intro_window_1)
	if o == 0:
		return
	set_l(o + 0x2A, 0xFFFF8040)
	set_w(o + 0x32, 0)
	var d0 := boot_pal_frames(0x14)
	set_w(o + 0x1E, d0)
	set_w(o + 0x16, d0)
	set_w(o + 0x18, 3)
	set_b(F_ANIM, 0xFF)


func boot_intro_window_1(o: int) -> void:
	if sb(PRESSED) < 0 or w(o + 0x32) == 7:
		set_b(F_ANIM, 0)
		obj_free(o)
		return
	add_w(o + 0x1E, -1)
	if w(o + 0x1E) == 0:
		set_w(o + 0x1E, w(o + 0x16))
		add_w(o + 0x32, 1)
		set_l(o + 0x2A, l(o + 0x2A) + 0x20)
		set_w(o + 0x18, 3)
		if w(o + 0x32) == 6:
			set_w(o + 0x1E, 2)
			set_w(o + 0x18, 0)
		return
	add_w(o + 0x18, -1)
	if sw(o + 0x18) >= 0:
		set_w(PAL_TARGET + 8, 0)
		set_w(PAL_CURRENT + 8, 0)
		boot_spawn(0, 16)
		return
	var c := ISSRom.u16(rom("boot_intro_window_data") + 2 * w(o + 0x32))
	set_w(PAL_TARGET + 8, c)
	set_w(PAL_CURRENT + 8, c)
	boot_spawn(0, 16)
	var src := l(o + 0x2A) & 0xFFFF
	for col in 16:
		for row in 28:
			set_w(UNPACK + 0x6010 + 2 * col + 0x40 * row, w(src + 2 * col + 0x168 * row) & 0x9FFF)
	dma_queue_add(DMA_VRAM, 0xA000, 0xFF0000 | (UNPACK + 0x6000), 0x380)


## boot_intro_column_wipe: the column wipe: every 4 frames two palettes alternate
## (boot_flicker_palette0_a / 145D14 on line 0, 145CF4 / 145D34 on line 2) while
## every 2 (3 past column 100) the next column of the picture unpacked at
## $8040 (90 words a row, 56 rows) goes down plane B (a DMA with a row's
## increment); 155 columns; $F2B while it runs.
func boot_intro_column_wipe() -> void:
	var o := obj_alloc(boot_intro_column_wipe_1)
	if o == 0:
		return
	set_b(F_SCROLL, 0xFF)
	set_w(o + 0x32, 0)
	set_w(o + 0x1E, 4)
	set_w(o + 0x16, 1)
	set_b(o + 0x18, 0xFF)
	set_w(o + 0x1A, 0)
	set_w(o + 0x1C, 1)
	_copy_rom(ISSRom.boot_res(0, 5), PAL_TARGET, 32)
	_copy_rom(PALETTE_A, PAL_TARGET + 0x60, 16)
	boot_spawn(0, 0x40)


func boot_intro_column_wipe_1(o: int) -> void:
	if sb(PRESSED) < 0:
		set_b(F_SCROLL, 0)
		obj_free(o)
	add_w(o + 0x1E, -1)
	if w(o + 0x1E) != 0:
		return
	set_w(o + 0x1E, w(o + 0x16))
	if sb(o + 0x18) < 0:
		_copy_rom(rom("boot_flicker_palette0_a"), PAL_TARGET, 16)
		_copy_rom(rom("boot_flicker_palette2_a"), PAL_TARGET + 0x40, 16)
	else:
		_copy_rom(rom("boot_flicker_palette0_b"), PAL_TARGET, 16)
		_copy_rom(rom("boot_flicker_palette2_b"), PAL_TARGET + 0x40, 16)
	boot_spawn(0, 64)
	set_b(o + 0x18, -sb(o + 0x18))
	add_w(o + 0x1C, -1)
	if w(o + 0x1C) == 0:
		set_w(o + 0x1C, 2 if w(o + 0x1A) < 0xC8 else 3)
		boot_intro_column_wipe_2(o)
	if w(o + 0x1A) == 0x136:
		set_b(F_SCROLL, 0)
		obj_free(o)


func boot_intro_column_wipe_2(o: int) -> void:
	var a0 := UNPACK + 0x40 + w(o + 0x1A)
	for i in 56:
		set_w(0xF7A + 2 * i, w(a0) | 0x8000)
		a0 += 0xB4
	dma_queue_add(DMA_VRAM, 0xE040 + w(o + 0x1A), 0xFF0000 | 0xF7A, 0x38, 0x80)
	add_w(o + 0x1A, 2)


## boot_intro_falling: the falling pieces: every 12 frames a new object of a
## kind (0-4, boot_intro_falling_data: 9, 4, 4, 1, 1 pieces) at the x of
## the list at $146244 falls from the top (4 px a frame, faster each
## frame; kind 0 stops at 140 and 60 frames later lets the thread go);
## tiles from $1900; $F2C and $F35 set.
func boot_intro_falling() -> void:
	var o := obj_alloc(boot_intro_falling_1)
	if o == 0:
		return
	set_l(o + 0x2A, 0x146244)
	var d0 := boot_pal_frames(0xC)
	set_w(o + 0x1E, d0)
	set_w(o + 0x20, d0)
	set_b(F_ANIM, 0xFF)
	set_b(0xF35, 0xFF)


func boot_intro_falling_1(o: int) -> void:
	if sb(PRESSED) < 0:
		obj_free(o)
		set_b(F_ANIM, 0)
		return
	add_w(o + 0x1E, -1)
	if w(o + 0x1E) != 0:
		return
	set_w(o + 0x1E, w(o + 0x20))
	var a4 := l(o + 0x2A)
	var d1 := ISSRom.s16(a4)
	var d2 := ISSRom.u16(a4 + 2)
	if d1 < 0:
		obj_free(o)
		return
	set_l(o + 0x2A, a4 + 4)
	add_w(o + 0x32, 1)
	var n := obj_alloc(boot_intro_falling_piece)
	if n == 0:
		return
	set_l(n + 0x26, 0x00040000)
	set_w(n + 0x32, d1)
	set_w(n + 0x8, d2)
	set_l(n + 0xC, 0)
	set_w(n + 0x16, 0)
	set_w(n + 0x34, 0x1900)


func boot_intro_falling_piece(o: int) -> void:
	if sb(PRESSED) < 0:
		obj_free(o)
		set_b(F_ANIM, 0)
		return
	if b(0xF35) == 0:
		obj_free(o)
		return
	if w(o + 0x16) == 0x3C:
		set_b(F_ANIM, 0)
	var kind := w(o + 0x32)
	var a4 := ISSRom.u32(rom("boot_intro_falling_data") + 4 * kind)
	var d3 := w(o + 0x34) >> 5
	if kind != 0:
		set_l(o + 0x26, (l(o + 0x26) + 0x2200) & 0xFFFFFFFF)
	elif w(o + 0xC) > 0x8C:
		set_l(o + 0x26, 0)
		add_w(o + 0x16, 1)
	var counts := [9, 4, 4, 1, 1]
	_draw_pieces(o, a4, counts[kind] if kind < 5 else 1, d3)
	add_w(o + 0xC, sw(o + 0x26))
	if w(o + 0xC) > 0x12C:
		obj_free(o)


## boot_intro_small_window: the small window: every 13 frames (12 on PAL), colour
## 4 black for 5 frames (3), then one of the cycle's colours
## (boot_intro_small_window_data) as a 4 x 8 window of plane A (row 9, column
## 14) shows the next 4 columns of the picture unpacked at $9060 (128
## words a row); 15 steps; $F2C while it runs.
func boot_intro_small_window() -> void:
	var o := obj_alloc(boot_intro_small_window_1)
	if o == 0:
		return
	set_l(o + 0x2A, 0xFFFF9060)
	set_w(o + 0x32, 0)
	var d0 := boot_pal_frames(0xD if b(PAL) == 0 else 0xC)
	set_w(o + 0x1E, d0)
	set_w(o + 0x16, d0)
	set_w(o + 0x18, 5 if b(PAL) == 0 else 3)
	set_b(F_ANIM, 0xFF)


func boot_intro_small_window_1(o: int) -> void:
	if sb(PRESSED) < 0 or w(o + 0x32) == 0x1E:
		obj_free(o)
		set_b(F_ANIM, 0)
		return
	add_w(o + 0x1E, -1)
	if w(o + 0x1E) == 0:
		set_w(o + 0x1E, w(o + 0x16))
		add_w(o + 0x32, 2)
		if w(o + 0x32) == 0xA:
			set_l(o + 0x2A, l(o + 0x2A) + 4)
		if w(o + 0x32) == 0x12:
			set_l(o + 0x2A, l(o + 0x2A) + 4)
		set_l(o + 0x2A, l(o + 0x2A) + 8)
		set_w(o + 0x18, 5 if b(PAL) == 0 else 3)
		return
	add_w(o + 0x18, -1)
	if sw(o + 0x18) >= 0:
		set_w(PAL_TARGET + 8, 0)
		set_w(PAL_CURRENT + 8, 0)
		boot_spawn(0, 64)
		return
	var c := ISSRom.u16(rom("boot_intro_small_window_data") + w(o + 0x32))
	set_w(PAL_TARGET + 8, c)
	set_w(PAL_CURRENT + 8, c)
	boot_spawn(0, 16)
	var src := l(o + 0x2A) & 0xFFFF
	for col in 4:
		for row in 8:
			set_w(UNPACK + 0x625C + 2 * col + 0x40 * row, w(src + 2 * col + 0x100 * row) & 0x9FFF)
	dma_queue_add(DMA_VRAM, 0xA000, 0xFF0000 | (UNPACK + 0x6000), 0x380)


## boot_intro_flicker: the flicker: boot_res0's palette 5 on lines 0-2 and 4
## on line 3, then every frame the two palette pairs of boot_intro_column_wipe
## in turn; while $F36 is set.
func boot_intro_flicker() -> void:
	var o := obj_alloc(boot_intro_flicker_1)
	if o == 0:
		return
	set_w(o + 0x32, 0)
	set_w(o + 0x1E, 2)
	set_w(o + 0x16, 1)
	set_b(o + 0x18, 0xFF)
	_copy_rom(ISSRom.boot_res(0, 5), PAL_TARGET, 48)
	_copy_rom(ISSRom.boot_res(0, 4), PAL_TARGET + 0x60, 16)
	boot_spawn(0, 0x40)


func boot_intro_flicker_1(o: int) -> void:
	if b(0xF36) == 0:
		obj_free(o)
		return
	add_w(o + 0x1E, -1)
	if w(o + 0x1E) != 0:
		return
	set_w(o + 0x1E, w(o + 0x16))
	if sb(o + 0x18) < 0:
		_copy_rom(rom("boot_flicker_palette0_a"), PAL_TARGET, 16)
		_copy_rom(rom("boot_flicker_palette2_a"), PAL_TARGET + 0x40, 16)
	else:
		_copy_rom(rom("boot_flicker_palette0_b"), PAL_TARGET, 16)
		_copy_rom(rom("boot_flicker_palette2_b"), PAL_TARGET + 0x40, 16)
	boot_spawn(0, 64)
	set_b(o + 0x18, -sb(o + 0x18))


## boot_intro_logo: the logo's pieces: 20 frames (boot_intro_logo_frames: each
## a tile offset, a count and the pieces) every 7 frames at ($82, $96),
## tiles from $C80; the last frames repeat from $1466EE; $F2C until the
## last.
func boot_intro_logo() -> void:
	var o := obj_alloc(boot_intro_logo_1)
	if o == 0:
		return
	set_l(o + 0x2A, rom("boot_intro_logo_frames"))
	set_w(o + 0x34, 0xC80)
	set_w(o + 0x32, 0)
	set_w(o + 0xC, 0x96)
	set_w(o + 0x8, 0x82)
	var d0 := boot_pal_frames(7)
	set_w(o + 0x1E, d0)
	set_w(o + 0x20, d0)
	set_b(F_ANIM, 0xFF)


func boot_intro_logo_1(o: int) -> void:
	if sb(PRESSED) < 0:
		set_b(F_ANIM, 0)
	var a4 := ISSRom.u32(l(o + 0x2A))
	var d3 := ((w(o + 0x34) + ISSRom.u16(a4)) & 0xFFFF) >> 5
	a4 += 2
	add_w(o + 0x1E, -1)
	if w(o + 0x1E) == 0:
		if w(o + 0x32) < 0x13:
			add_w(o + 0x32, 1)
			set_l(o + 0x2A, l(o + 0x2A) + 4)
		set_w(o + 0x1E, w(o + 0x20))
	if w(o + 0x32) == 0x13:
		set_b(F_ANIM, 0)
	var d2 := ISSRom.u16(a4)
	a4 += 2
	_draw_pieces(o, a4, d2 + 1, d3)
	if w(o + 0x32) == 0x13:
		set_l(o + 0x2A, 0x1466EE)


## boot_intro_cycle_two: colours 4 and 5 of line 3 cycling through two lists
## of four (boot_intro_cycle_two_data, _data2) every 7 frames (4 on PAL),
## 20 times (15); $F2C while it runs.
func boot_intro_cycle_two() -> void:
	var o := obj_alloc(boot_intro_cycle_two_1)
	if o == 0:
		return
	set_w(o + 0x16, 0x14)
	var d0 := boot_pal_frames(5)
	set_w(o + 0x1E, 1)
	if b(PAL) == 0:
		d0 += 2
	else:
		add_w(o + 0x16, -5)
	set_w(o + 0x20, d0)
	set_w(o + 0x18, 0)
	set_w(o + 0x1A, 0)
	set_b(F_ANIM, 0xFF)


func boot_intro_cycle_two_1(o: int) -> void:
	if sb(PRESSED) >= 0:
		add_w(o + 0x1E, -1)
		if w(o + 0x1E) != 0:
			return
		set_w(o + 0x1E, w(o + 0x20))
		var d0 := w(o + 0x18)
		if d0 == 4:
			d0 = 0
			set_w(o + 0x18, 0)
		set_w(PAL_TARGET + 0x68, ISSRom.u16(rom("boot_intro_cycle_two_data") + 2 * d0))
		add_w(o + 0x18, 1)
		d0 = w(o + 0x1A)
		if d0 == 4:
			d0 = 0
			set_w(o + 0x1A, 0)
		set_w(PAL_TARGET + 0x6A, ISSRom.u16(rom("boot_intro_cycle_two_data2") + 2 * d0))
		add_w(o + 0x1A, 1)
		boot_spawn(0, 0x40)
		add_w(o + 0x16, -1)
		if w(o + 0x16) != 0:
			return
	obj_free(o)
	set_b(F_ANIM, 0)


## boot_intro_cycle_one: colour 15 of line 3 cycling through three
## (boot_intro_cycle_one_data) every 5 frames, 25 times (17 on PAL); $F2C
## while it runs, $F36 cleared at its end.
func boot_intro_cycle_one() -> void:
	var o := obj_alloc(boot_intro_cycle_one_1)
	if o == 0:
		return
	set_w(o + 0x16, 0x19)
	if sb(PAL) < 0:
		add_w(o + 0x16, -8)
	set_w(o + 0x1E, 1)
	set_w(o + 0x20, boot_pal_frames(5))
	set_w(o + 0x18, 0)
	set_w(o + 0x1A, 0)
	set_b(F_ANIM, 0xFF)


func boot_intro_cycle_one_1(o: int) -> void:
	if sb(PRESSED) >= 0:
		add_w(o + 0x1E, -1)
		if w(o + 0x1E) != 0:
			return
		set_w(o + 0x1E, w(o + 0x20))
		var d0 := w(o + 0x18)
		if d0 == 3:
			d0 = 0
			set_w(o + 0x18, 0)
		set_w(PAL_TARGET + 0x7E, ISSRom.u16(rom("boot_intro_cycle_one_data") + 2 * d0))
		add_w(o + 0x18, 1)
		boot_spawn(0, 0x40)
		add_w(o + 0x16, -1)
		if w(o + 0x16) != 0:
			return
	obj_free(o)
	set_b(F_ANIM, 0)
	set_b(0xF36, 0)


# --------------------------------------------------------------------------
# Screen 1: the title (boot_title): the picture from boot_res1 with
# two palettes, the second (boot_palette_b, at $1806) switched in by an
# HInt at line 90 (boot_title_hint); the text written in, the ball, the
# logo sliding in, PRESS START running by four times; Start goes to the
# menus, else the attract demo.

## boot_title: the title's main thread.
func boot_title() -> void:
	boot_objects_init()
	boot_sprites_reset()
	boot_vdp_registers()
	boot_scroll_clear()
	boot_display_on()
	await boot_wait(3)
	_copy_rom(ISSRom.boot_res(1, 1), PAL_TARGET, 32)
	_copy_rom(ISSRom.boot_res(1, 2), PAL_TARGET + 0x40, 16)
	_copy_rom(ISSRom.boot_res(1, 3), PAL_TARGET + 0x60, 16)
	_copy_rom(PALETTE_B, PAL_TARGET + 0x80, 32)
	for i in 32:
		set_w(0x620 + 2 * i, w(0x560 + 2 * i))
		set_w(0x1806 + 2 * i, w(0x560 + 2 * i))
	_unpack_res(1, 8)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x3640, UNPACK_SRC, 0x40)
	dma_flush()
	await boot_wait(3)
	_unpack_res(1, 9)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x3680, UNPACK_SRC, 0xDC0)
	dma_flush()
	await boot_wait(3)
	_unpack_res(1, 12)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x4220, UNPACK_SRC, 0x5D0)
	dma_flush()
	await boot_wait(3)
	_unpack_res(1, 13)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x4DC0, UNPACK_SRC, 0x400)
	await boot_wait(3)
	_unpack_res(1, 4)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x0000, UNPACK_SRC, 0xD80)
	await boot_wait(3)
	_unpack_res(1, 5)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x1B00, UNPACK_SRC, 0xDA0)
	await boot_wait(3)
	_unpack_res(1, 6)
	await boot_wait(3)
	ISSRam.copy(0x1006, UNPACK, 0x380)
	_unpack_res(1, 7)
	await boot_wait(3)
	for i in 0x1C0:
		set_w(0x1406 + 2 * i, (w(UNPACK + 2 * i) + 0xD8) | 0xA000)
	await boot_wait(3)
	_unpack_res(1, 14)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x55C0, UNPACK_SRC, 0x6F0)
	await boot_wait(3)
	_unpack_res(0, 27)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0x63A0, UNPACK_SRC, 0x2100)
	dma_flush()
	await boot_wait(3)
	_copy_rom(ISSRom.boot_res(0, 8), PAL_TARGET + 0x60, 16)
	set_b(F_ANIM, 0xFF)
	if b(PRESSED) == 0:
		_unpack_res(1, 11)
		await boot_wait(3)
		for i in 0x600:
			set_w(UNPACK + 2 * i, ((w(UNPACK + 2 * i) & 0x1FFF) | 0xC000) + 0x1B4)
		await boot_wait(3)
		dma_queue_add(DMA_VRAM, 0xE000, UNPACK_SRC, 0x300)
		dma_flush()
		await boot_wait(3)
	_unpack_res(1, 10)
	await boot_wait(3)
	for i in 0x600:
		set_w(UNPACK + 2 * i, (w(UNPACK + 2 * i) & 0x1FFF) + 0x1B4)
	await boot_wait(3)
	dma_queue_add(DMA_VRAM, 0xA000, UNPACK_SRC, 0x300)
	await boot_wait(3)
	frame_cb = boot_title_vblank
	boot_title_bottom_line()
	boot_display_on()
	boot_fade_in(1, 0, 0, 0x3F)
	while b(F_FADE_IN) != 0:
		await vblank
	_play_music(0xB)
	await boot_wait(3)
	set_w(0xFFE, 0)
	set_b(0xF31, 0xFF)
	await boot_wait(3)
	boot_title_text()
	while b(F_ANIM) != 0:
		await vblank
	set_b(F_ANIM, 0)
	boot_title_ball()
	boot_title_word_scroll()
	boot_scroll_object(0x00590003, 0x00030009, 1, 0)
	while b(0xF2D) != 0:
		await vblank
	if sb(PRESSED) < 0:
		ISSRam.clear(UNPACK, 0xC00)
		dma_queue_add(DMA_VRAM, 0xE000, UNPACK_SRC, 0x300)
		await boot_wait(3)
	boot_title_logo_slide()
	while b(F_SCROLL) != 0:
		await vblank
	await boot_wait(3)
	_copy_rom(ISSRom.boot_res(1, 3), PAL_TARGET + 0x60, 16)
	boot_spawn(0, 0x40)
	await boot_wait(3)
	boot_title_ball_drop()
	if b(PRESSED) == 0:
		await boot_wait(0x3C)
	boot_title_mark()
	set_w(FRAME, 0)
	await boot_wait(3)
	boot_title_press_start()
	while b(0xF2D) != 0:
		await vblank
	if sb(PRESSED) >= 0:
		await boot_fade_out_end()
		return
	boot_title_words()
	if w(0xFFE) < 0x78:
		await boot_wait(3)
		await _wait_hint()
		# sound_play_music_ext: song $19 in the menus' mode.
		_play_music(0x19)
		await _wait_hint()
		m.play_sfx(122)
	await _wait_hint()
	await _wait_hint()
	await _wait_hint()
	m.play_sfx(70)
	boot_title_blink()
	while b(0xF2D) != 0:
		await vblank
	await boot_fade_out_end()


## boot_title_vblank: the title's VBlank routine: once $F31 is set, the
## HInt at line 90 (boot_title_hint); colours 0-31 from the current
## palette while nothing animates; the objects, the sprites; $FFE counts
## the frames.
func boot_title_vblank() -> void:
	if b(0xF31) != 0:
		hint_on = true
		hblank = boot_title_hint
	if b(F_ANIM) == 0:
		for i in 32:
			m.vdp.set_cram_word(i, w(PAL_CURRENT + 2 * i))
	boot_objects_run()
	boot_sprites_flush()
	add_w(0xFFE, 1)


## boot_title_hint: the HInt of line 90: colours 0-31 from $1806, a pair
## a line from line 91 (the write waits for each HBlank); $1846 counts it.
func boot_title_hint() -> void:
	for i in 32:
		m.vdp.set_cram2_word(i, w(0x1806 + 2 * i))
	m.vdp.cram_split = title_split
	add_w(0x1846, 1)


## boot_title_bottom_line: the line at the bottom (8 pieces,
## boot_title_bottom_line_data) at ($51, $DD), tiles from $4220.
func boot_title_bottom_line() -> void:
	var o := obj_alloc(boot_title_bottom_line_1)
	if o == 0:
		return
	set_w(o + 0x34, 0x4220 >> 5)
	set_w(o + 0x32, 0)
	set_w(o + 0xC, 0xDD)
	set_w(o + 0x8, 0x51)


func boot_title_bottom_line_1(o: int) -> void:
	_draw_pieces(o, rom("boot_title_bottom_line_data"), 8, w(o + 0x34))


## boot_title_ball_drop: the ball dropping onto the logo: 4 pieces
## (boot_title_ball_drop_data) at ($EE, $56 + an offset) that starts 100 px
## up with gravity $2C00 a frame (more on PAL); on each landing the speed
## reverses less one, five bounces, then it rests; tiles from $4DC0.
func boot_title_ball_drop() -> void:
	var o := obj_alloc(boot_title_ball_drop_1)
	if o == 0:
		return
	set_w(o + 0x34, 0x4DC0 >> 5)
	set_w(o + 0x32, 0)
	set_l(o + 0x26, 0)
	set_w(o + 0x8, 0xEE)
	set_w(o + 0xC, 0x56)
	set_w(o + 0x16, 0xFF9C)
	set_w(o + 0x18, 0)
	set_w(o + 0x1A, 0)


func boot_title_ball_drop_1(o: int) -> void:
	var y := w(o + 0xC)
	if sb(PRESSED) < 0:
		set_l(o + 0x16, 0)
	else:
		add_w(o + 0xC, sw(o + 0x16))
		var d0 := ISSRam.sl(o + 0x26)
		set_l(o + 0x16, (l(o + 0x16) + d0) & 0xFFFFFFFF)
		var g := 0x2C00 + (0x2300 if sb(PAL) < 0 else 0)
		set_l(o + 0x26, (l(o + 0x26) + g) & 0xFFFFFFFF)
		if w(o + 0x1A) >= 5:
			set_l(o + 0x16, 0)
		elif sw(o + 0x16) >= 0:
			d0 -= 0x10000 + (0x3000 if sb(PAL) < 0 else 0)
			var d1 := _s16(((d0 & 0xFFFFFFFF) >> 1) & 0xFFFF)
			d0 = -(d0 - d1)
			set_l(o + 0x26, d0 & 0xFFFFFFFF)
			add_w(o + 0x1A, 1)
	_draw_pieces(o, rom("boot_title_ball_drop_data"), 4, w(o + 0x34))
	set_w(o + 0xC, y)


## boot_title_mark: one piece (boot_title_mark_data) at ($EC, $8E),
## tiles from $4D80.
func boot_title_mark() -> void:
	var o := obj_alloc(boot_title_mark_1)
	if o == 0:
		return
	set_w(o + 0x34, 0x4D80 >> 5)
	set_w(o + 0xC, 0x8E)
	set_w(o + 0x8, 0xEC)


func boot_title_mark_1(o: int) -> void:
	_draw_pieces(o, rom("boot_title_mark_data"), 1, w(o + 0x34))


## boot_title_press_start: PRESS START (boot_title_press_start_pieces, 3 pieces) comes in
## from the right 4 px a frame to x $98, stays 30 frames, goes off for 5
## and on again for 30, ten times over, then runs on off the left and in
## again, four times; the two words under it (boot_title_word1_pieces, 5 pieces,
## boot_title_word2_pieces, 8), the second sliding to x $FC the first time; $F2D
## while it runs; tiles from $4220.
func boot_title_press_start() -> void:
	var o := obj_alloc(boot_title_press_start_1)
	if o == 0:
		return
	set_w(o + 0x34, 0x4220 >> 5)
	set_w(o + 0x32, 0)
	set_w(o + 0xC, 0xCC)
	set_w(o + 0x8, 0x190)
	set_w(o + 0x22, 0xFFFC)
	var d0 := boot_pal_frames(6)
	set_w(o + 0x1E, d0)
	set_w(o + 0x20, d0)
	set_b(o + 0x16, 5)
	set_w(o + 0x18, 5)
	set_w(o + 0x1A, 0x1E)
	set_b(o + 0x1C, 0)
	set_l(o + 0x26, 0)
	set_b(0xF2D, 0xFF)
	set_b(0xF33, 0)


func boot_title_press_start_1(o: int) -> void:
	if sb(PRESSED) < 0:
		set_b(0xF2D, 0)
		obj_free(o)
	var d3 := w(o + 0x34)
	if sw(o + 0x8) < 0:
		set_w(o + 0x8, 0x154)
		add_w(o + 0x28, 1)
		if w(o + 0x28) == 4:
			set_b(0xF2D, 0)
			obj_free(o)
			return
	if b(o + 0x1C) == 0:
		add_w(o + 0x8, sw(o + 0x22))
	if w(o + 0x8) == 0x98:
		set_b(o + 0x1C, 0xFF)
		add_w(o + 0x1A, -1)
		if sw(o + 0x1A) >= 0:
			_draw_pieces(o, rom("boot_title_press_start_pieces"), 3, d3)
		else:
			add_w(o + 0x18, -1)
			if w(o + 0x18) == 0:
				add_w(o + 0x32, 1)
				set_w(o + 0x1A, 0x1E)
				set_w(o + 0x18, 0xA)
				set_b(o + 0x16, b(o + 0x16) - 1)
				if b(o + 0x16) == 0:
					set_b(o + 0x16, 5)
					set_b(o + 0x1C, 0)
	else:
		_draw_pieces(o, rom("boot_title_press_start_pieces"), 3, d3)
	var x := w(o + 0x8)
	if w(o + 0x32) != 0:
		set_w(o + 0x8, 0x98)
		_draw_pieces(o, rom("boot_title_word1_pieces"), 5, d3)
		set_w(o + 0x8, 0xFC)
		_draw_pieces(o, rom("boot_title_word2_pieces"), 8, d3)
		set_w(o + 0x8, x)
	else:
		if w(o + 0x26) < 0xFC:
			add_w(o + 0x26, 4)
		set_w(o + 0x8, w(o + 0x26))
		_draw_pieces(o, rom("boot_title_word2_pieces"), 8, d3)
		set_w(o + 0x8, x)
		_draw_pieces(o, rom("boot_title_word1_pieces"), 5, d3)


## boot_title_text: the text written in: five lists ($147520) of (row,
## byte column, count) runs of both planes' maps ($1006 for A, $1406 for
## B, 32 words a row, from row 13) written to the VDP every 12 frames (at
## once after a press), a pen of 1 then 4 sprites (boot_title_text_pen_a
## to _data4, tiles from $1B2) meanwhile; $F2C while it runs.
func boot_title_text() -> void:
	set_b(F_ANIM, 0xFF)
	var o := obj_alloc(boot_title_text_1)
	if o == 0:
		return
	set_l(o + 0x2A, 0x147520)
	set_w(o + 0x32, 0)
	set_w(o + 0x1E, 1)
	set_w(o + 0x20, boot_pal_frames(0xC))
	set_w(o + 0x16, 0)


func boot_title_text_1(o: int) -> void:
	if w(o + 0x32) == 5:
		obj_free(o)
		set_b(F_ANIM, 0)
		return
	if sb(PRESSED) < 0:
		set_w(o + 0x1E, 1)
		set_w(o + 0x20, 1)
	add_w(o + 0x1E, -1)
	if w(o + 0x1E) == 0:
		set_w(o + 0x1E, w(o + 0x20))
		var a4 := ISSRom.u32(l(o + 0x2A) + 4 * w(o + 0x32))
		while ISSRom.s16(a4) >= 0:
			var row := ISSRom.u16(a4)
			var col := ISSRom.u16(a4 + 2)
			var n := ISSRom.u16(a4 + 4) + 1
			var src := row * 64 + col
			for i in n:
				m.vdp.set_vram_w(0xA67E + row * 0x80 + col + 2 * i, w(0x1006 + src + 2 * i))
				m.vdp.set_vram_w(0xE67E + row * 0x80 + col + 2 * i, w(0x1406 + src + 2 * i))
			a4 += 6
		add_w(o + 0x32, 1)
	if w(o + 0x32) < 4:
		var a1 := boot_sprite_alloc()
		if a1 >= 0:
			boot_sprite_set(o, a1, rom("boot_title_text_pen_b"), 0x1B2)
	if w(o + 0x32) < 3:
		for nm in ["boot_title_text_pen_a", "boot_title_text_pen_c", "boot_title_text_pen_d"]:
			var a1 := boot_sprite_alloc()
			if a1 >= 0:
				boot_sprite_set(o, a1, rom(nm), 0x1B2)


## boot_title_ball: the ball and its shadow: 7 frames of 4 pieces each
## (the lists at $14637E, the shadow 3 frames behind and $20 to the right)
## every 6 frames, three times round, from ($37, $69) moving 3 px right
## and half a pixel up a frame; tiles from $63A0.
func boot_title_ball() -> void:
	var o := obj_alloc(boot_title_ball_1)
	if o == 0:
		return
	set_l(o + 0x2A, 0x14637E)
	set_w(o + 0x34, 0x63A0 >> 5)
	set_w(o + 0x32, 0)
	set_l(o + 0x18, 0x14638A)
	set_w(o + 0xC, 0x69)
	set_w(o + 0x8, 0x37)
	set_w(o + 0x1E, 1)
	set_w(o + 0x20, boot_pal_frames(6))
	set_w(o + 0x16, 3)
	set_l(o + 0x26, 0x8000)


func boot_title_ball_1(o: int) -> void:
	if sb(PRESSED) < 0:
		obj_free(o)
		return
	var a4 := ISSRom.u32(l(o + 0x2A))
	var d3 := w(o + 0x34)
	add_w(o + 0x1E, -1)
	if w(o + 0x1E) == 0:
		set_w(o + 0x1E, w(o + 0x20))
		set_l(o + 0x2A, l(o + 0x2A) + 4)
		add_w(o + 0x32, 1)
		if w(o + 0x32) == 7:
			set_l(o + 0x2A, 0x14637E)
			set_w(o + 0x32, 0)
			add_w(o + 0x16, -1)
			if w(o + 0x16) == 0:
				obj_free(o)
				return
		set_l(o + 0x18, l(o + 0x18) + 4)
		if l(o + 0x18) == 0x14639A:
			set_l(o + 0x18, 0x14637E)
	_draw_pieces(o, a4, 4, d3)
	var x := w(o + 0x8)
	set_w(o + 0x8, x + 0x20)
	_draw_pieces(o, ISSRom.u32(l(o + 0x18)), 4, d3)
	set_w(o + 0x8, x + 3)
	set_l(o + 0xC, (l(o + 0xC) - l(o + 0x26)) & 0xFFFFFFFF)


## boot_title_word_scroll: the word scrolling into plane B: every 2 frames the
## next 8 words of boot_title_word_tiles (tiles + $1B4, palette 3) down column
## 0 of rows 3-10 (a DMA with a row's increment) as the rows scroll right
## (boot_scroll_object); 90 frames; $F2D while it runs.
func boot_title_word_scroll() -> void:
	var o := obj_alloc(boot_title_word_scroll_1)
	if o == 0:
		return
	set_l(o + 0x2A, rom("boot_title_word_tiles"))
	set_w(o + 0x32, 0)
	set_w(o + 0x1E, 1)
	set_w(o + 0x20, boot_pal_frames(2))
	set_w(o + 0x16, 7)
	set_w(o + 0x18, 0)
	set_b(0xF2D, 0xFF)


func boot_title_word_scroll_1(o: int) -> void:
	if sb(PRESSED) < 0:
		obj_free(o)
		set_b(0xF2D, 0)
		return
	add_w(o + 0x18, 1)
	add_w(o + 0x1E, -1)
	if w(o + 0x1E) != 0:
		return
	set_w(o + 0x1E, w(o + 0x20))
	if w(o + 0x18) > 0x5A:
		obj_free(o)
		set_b(0xF2D, 0)
		return
	boot_title_word_scroll_2(o)


func boot_title_word_scroll_2(o: int) -> void:
	for i in 8:
		set_w(0xF7A + 2 * i, 0)
	if w(o + 0x18) < 0x64:
		for i in w(o + 0x16) + 1:
			var a0 := l(o + 0x2A)
			set_w(0xF7A + 2 * i, (ISSRom.u16(a0) + 0x1B4) | 0xC000)
			set_l(o + 0x2A, a0 + 2)
			if ISSRom.s16(a0 + 2) < 0:
				set_l(o + 0x2A, rom("boot_title_word_tiles"))
	dma_queue_add(DMA_VRAM, 0xE180, 0xFF0000 | 0xF7A, 8, 0x80)


## boot_title_logo_slide: the logo sliding in from the right: 10 pieces
## (boot_title_logo_slide_data) from ($14A, $19), 8 px left and 3 down a
## frame to x $5D (at once after a press); $F2B while it moves; tiles
## from $55C0.
func boot_title_logo_slide() -> void:
	var o := obj_alloc(boot_title_logo_slide_1)
	if o == 0:
		return
	set_w(o + 0x34, 0x55C0 >> 5)
	set_w(o + 0x32, 0)
	set_w(o + 0x8, 0x14A)
	set_w(o + 0xC, 0x19)
	set_b(F_SCROLL, 0xFF)


func boot_title_logo_slide_1(o: int) -> void:
	_draw_pieces(o, rom("boot_title_logo_slide_data"), 10, w(o + 0x34))
	if sb(PRESSED) < 0:
		set_w(o + 0x8, 0x5A)
		set_w(o + 0xC, 0x73)
		set_b(F_SCROLL, 0)
		return
	if w(o + 0x8) > 0x5D:
		add_w(o + 0x8, -8)
		add_w(o + 0xC, 3)
	else:
		set_b(F_SCROLL, 0)


## boot_title_words: the two words under PRESS START, still, after a
## press.
func boot_title_words() -> void:
	var o := obj_alloc(boot_title_words_1)
	if o == 0:
		return
	set_w(o + 0x34, 0x4220 >> 5)
	set_w(o + 0x32, 0)
	set_w(o + 0xC, 0xCC)


func boot_title_words_1(o: int) -> void:
	var d3 := w(o + 0x34)
	set_w(o + 0x8, 0x98)
	_draw_pieces(o, rom("boot_title_word1_pieces"), 5, d3)
	set_w(o + 0x8, 0xFC)
	_draw_pieces(o, rom("boot_title_word2_pieces"), 8, d3)


## boot_title_blink: PRESS START blinking after the press (3 frames on, 2
## off, then 5 and 5) until 10 blinks and 240 frames have passed; $F2D
## while it runs.
func boot_title_blink() -> void:
	var o := obj_alloc(boot_title_blink_1)
	if o == 0:
		return
	set_w(o + 0x34, 0x4220 >> 5)
	set_w(o + 0x32, 0)
	set_w(o + 0xC, 0xCC)
	set_w(o + 0x8, 0x98)
	set_w(o + 0x22, 0xFFFC)
	var d0 := boot_pal_frames(6)
	set_w(o + 0x1E, d0)
	set_w(o + 0x20, d0)
	set_w(o + 0x16, 0)
	set_w(o + 0x18, 2)
	set_w(o + 0x1A, 2)
	set_b(o + 0x1C, 0)
	set_l(o + 0x26, 0)
	set_b(0xF2D, 0xFF)


func boot_title_blink_1(o: int) -> void:
	if w(FRAME) > 0xF0 and w(o + 0x16) >= 0xA:
		set_b(0xF2D, 0)
	var d3 := w(o + 0x34)
	add_w(o + 0x18, -1)
	if sw(o + 0x18) >= 0:
		_draw_pieces(o, rom("boot_title_press_start_pieces"), 3, d3)
		return
	add_w(o + 0x1A, -1)
	if w(o + 0x1A) != 0:
		return
	set_w(o + 0x18, 5)
	set_w(o + 0x1A, 5)
	add_w(o + 0x16, 1)
