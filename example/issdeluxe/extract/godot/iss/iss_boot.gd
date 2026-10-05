class_name ISSBoot
extends RefCounted
## The boot module (boot_main, $144318): the screens before the title, a
## small program of its own with its own objects (19 of $36 bytes at $66A,
## run every VBlank), DMA queue, sprite buffer, palette fades and raster
## effects, run here as the game runs it: main_init calls it for screens
## 4 (SEGA), 3 (Konami), 2 (Factor 5), 0 (the intro) and 1 (the title),
## which says whether a button was pressed (the menus) or not (the attract
## demo). Its RAM is the game's work RAM (ISSRam) at the module's own
## offsets, its picture ISSVdp with the module's registers (planes 64 x 64
## at $A000 and $E000, the scroll table in cell mode). The main thread of
## each screen is a coroutine waiting on the VBlank (boot_wait), as the
## program spins on its frame counter. The routines are the ROM's, under
## their names.

## The VBlank is over: the screen's main thread goes on.
signal vblank

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
func run() -> void:
	for scr in [4, 3, 2, 0, 1]:
		pressed = await boot_main(scr)
	finished = true
	m._boot_done(pressed)


## boot_main / boot_func_14433E: the module's RAM cleared, the VDP set up
## and cleared, the screen run, then the display off; true when a button
## was pressed.
func boot_main(scr: int) -> bool:
	ISSRam.clear(0, 0x184C)
	ISSRam.clear(0x8000, 0x7C00)
	frame_cb = Callable()
	hblank = Callable()
	boot_func_144430()
	set_w(FRAME, 0)
	set_w(SCREEN, scr)
	set_w(SOUND, 0xFFFF)
	match scr:
		4:
			await boot_load_148750()
		3:
			await boot_load_147DC8()
		2:
			await boot_load_147964()
		_:
			pass
	frame_cb = Callable()
	if sw(SOUND) >= 0:
		set_w(SOUND, 0xFFFF)
		m.sound.stop_music()
	m.vdp.backdrop = 0
	boot_func_14452E()
	hint_on = false
	return sb(PRESSED) != 0


## boot_func_144430: NTSC here ($F2A), register 1's bits, the module's
## planes (A $A000, B $E000, sprites $DA00, the scroll table $C800), VRAM
## $0000-$9FFF, the planes and the CRAM cleared.
func boot_func_144430() -> void:
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


## boot_func_14452E: the display off (register 1 without bit 6).
func boot_func_14452E() -> void:
	set_w(REG1, w(REG1) & 0x3F)
	m.vdp.display = false


## boot_func_144516: the display on (register 1 | $64).
func boot_func_144516() -> void:
	set_w(REG1, w(REG1) | 0x64)
	m.vdp.display = true


## boot_func_149A1A: the screens' registers: sprites $DA00, backdrop colour
## 0, plane A $A000, plane B $E000, 64 x 64 cells, no window, the scroll
## table in cell mode at $C800, HInt every line (off until a screen turns
## it on).
func boot_func_149A1A() -> void:
	m.vdp.backdrop = 0
	m.vdp.plane_a = 0xA000
	m.vdp.plane_b = 0xE000
	m.vdp.plane_cols = 64
	m.vdp.plane_rows = 64
	m.vdp.window_h = 0
	m.vdp.window_v = 0
	set_w(LINE, 0)
	hint_on = false


## boot_func_14532E: planes B and A cleared ($1000 words each).
func boot_func_14532E() -> void:
	_clear_vram(0xE000, 0x2000)
	_clear_vram(0xA000, 0x2000)


## boot_load_145280: the scroll table (256 lines) and VSRAM cleared.
func boot_load_145280() -> void:
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
# The VBlank (boot_func_144562) and what the picture shows.

## boot_func_144562_1: the frame counter, the queued DMAs, the pads
## (boot_func_144562_3), a button pressed (_2), the screen's own routine
## ($1E); then the main thread goes on.
func frame() -> void:
	set_w(LINE, 1)
	add_w(FRAME, 1)
	if w(SCREEN) == 1:
		ISSRam.copy(0x1806, 0x620, 0x40)
	dma_flush()
	_pads()
	boot_func_144562_2()
	if frame_cb.is_valid():
		frame_cb.call()
	vblank.emit()


## boot_func_144562_3: the two ports' pads, type 1 (the others $F, nothing
## pressed), their buttons as the game reads them.
func _pads() -> void:
	for i in 8:
		set_w(PAD_TYPES + 2 * i, 1 if i < 2 else 0xF)
		set_w(PAD_STATES + 2 * i, ISSInput.raw(i) if i < 2 else 0)


## boot_func_144562_2: Start on any pad sets $F32 (on the title only
## after 24 frames).
func boot_func_144562_2() -> void:
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
	if hint_on and hblank.is_valid():
		hblank.call()
	else:
		m.vdp.vlines_a = PackedInt32Array()
		m.vdp.vlines_b = PackedInt32Array()


static func _s10(v: int) -> int:
	v &= 0x7FF
	return v - 0x800 if v >= 0x400 else v


# --------------------------------------------------------------------------
# Objects (boot_obj_alloc, boot_obj_free, boot_func_144FCA).

## boot_func_144F78: the 19 objects cleared and chained on the free list.
func boot_func_144F78() -> void:
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
	active.erase(o)
	routines.erase(o)
	free.push_front(o)
	add_w(OBJ_COUNT, -1)


## boot_func_144FCA: every active object's routine, head first.
func boot_func_144FCA() -> void:
	for o in active.duplicate():
		if routines.has(o):
			routines[o].call(o)


## boot_func_144DD6: the sprite buffer empty.
func boot_func_144DD6() -> void:
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


## boot_load_144DE2: the sprite buffer to the VDP (the last entry's link
## ended, or an empty first entry) and empty again.
func boot_load_144DE2() -> void:
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

func dma_queue_add(kind: int, dest: int, src: int, words: int) -> void:
	dma.append([kind, dest, src, words])


func dma_flush() -> void:
	set_b(F_DMA, 0xFF)
	for q: Array in dma:
		var dest: int = q[1]
		var src: int = q[2] & 0xFFFF
		var n: int = q[3]
		match int(q[0]):
			DMA_VRAM:
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

## boot_func_144B5A: a fade in: every d1 frames each colour of the d4 from
## d3 steps one level per channel toward the target palette ($4E0), 16
## steps; $F30 while it runs. A button press ends it (not on the SEGA
## screen).
func boot_func_144B5A(d1: int, d2: int, d3: int, d4: int) -> void:
	set_b(F_FADE_IN, 0xFF)
	var o := obj_alloc(boot_func_144B5A_1)
	if o == 0:
		return
	d1 = boot_pal_frames(d1)
	set_w(o + 0x16, d1)
	set_w(o + 0x18, d2)
	set_w(o + 0x1E, d1)
	set_w(o + 0x1A, d3 * 2)
	set_w(o + 0x1C, (d4 & 0x3F) - 1)


func boot_func_144B5A_1(o: int) -> void:
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


## boot_func_1447E4: a fade in by brightness: every d1 frames, each of
## the d4 colours from d3 whose brightness (its levels added) + the step
## is 24 or more moves one channel (blue, red, then green) one level
## toward the target; 24 steps; $F30 while it runs. A button press ends
## it.
func boot_func_1447E4(d1: int, d2: int, d3: int, d4: int) -> void:
	set_b(F_FADE_IN, 0xFF)
	var o := obj_alloc(boot_func_1447E4_1)
	if o == 0:
		return
	d1 = boot_pal_frames(d1)
	set_w(o + 0x16, d1)
	set_w(o + 0x18, d2)
	set_w(o + 0x1E, d1)
	set_w(o + 0x1A, d3 * 2)
	set_w(o + 0x1C, (d4 & 0x3F) - 1)


func boot_func_1447E4_1(o: int) -> void:
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


## boot_func_144C48: a fade out: every frame each channel of every colour
## (96 on the title, else 64) down one level, in both palettes, until all
## are black; $F34 while it runs.
func boot_func_144C48() -> void:
	var o := obj_alloc(boot_func_144C48_1)
	if o == 0:
		return
	set_b(o + 0x16, 0xFF)
	set_b(F_FADE_OUT, 0xFF)
	set_w(o + 0x1E, 1)


func boot_func_144C48_1(o: int) -> void:
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


## boot_func_14A140: the fade out to its end, then the display off.
func boot_func_14A140() -> void:
	boot_func_144C48()
	while b(F_FADE_OUT) != 0:
		await vblank
	boot_func_14452E()


## The screens' common end (loc_149954): the fades over, the palette shown
## made the target, a fade out (64 frames at most), the display off after
## 3 frames, the VDP and the scroll tables cleared 3 frames later.
func boot_screen_end() -> void:
	while b(F_FADE_IN) != 0:
		await vblank
	while b(F_FADE_OUT) != 0:
		await vblank
	ISSRam.copy(PAL_TARGET, PAL_CURRENT, 0x80)
	boot_func_144C48()
	var d1 := (w(FRAME) + 0x40) & 0xFFFF
	while true:
		if w(FRAME) == d1:
			set_b(F_FADE_OUT, 0)
		if b(F_FADE_OUT) == 0:
			break
		await vblank
	await boot_wait(3)
	boot_func_14452E()
	await boot_wait(3)
	boot_func_144430()
	boot_load_145280()


# --------------------------------------------------------------------------
# Scrolling (boot_func_145078): an object adding d1 (its low word) to the
# scroll table's rows (d2: the first row in its high word, the count in
# its low) of plane A (d3 0), B (1) or both (2), and d3's high word to
# VSRAM, every frame (every other with d4), for d1's high word frames (0:
# until a button press); $F2B while it runs.

func boot_func_145078(d1: int, d2: int, d3: int, d4: int) -> void:
	var o := obj_alloc(boot_func_145078_1)
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


func boot_func_145078_1(o: int) -> void:
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
# The raster routine of the SEGA and Factor 5 screens (boot_input_147B14).

## boot_input_147B14: the screens' VBlank routine: the HInt on (every line,
## the first 6 skipped), boot_input_147B14_1 on it, the objects; on the
## SEGA screen a button press leaves only the objects (boot_func_149A84).
func boot_input_147B14() -> void:
	set_b(F_DMA, 0xFF)
	set_w(LINE, 6)
	hint_on = true
	hblank = boot_input_147B14_1
	boot_func_144FCA()
	if w(SCREEN) == 4 and b(PRESSED) != 0:
		frame_cb = boot_func_149A84


func boot_func_149A84() -> void:
	boot_func_144FCA()


## boot_input_147B14_1: from the seventh line, 209 lines of vertical
## scroll (both planes) from a sine table (boot_input_147B14_1_data, 208
## words) scaled by the amplitude $1002 (down $100 a frame to 0) from the
## phase $1004 (on 4 a frame): the picture ripples, each line showing the
## row |line + wave|, folded back from 207 (the ROM compares the whole
## long after divu/swap, so a quotient above 0 takes the mirrored branch),
## 9 rows up; -9 for the rest.
func boot_input_147B14_1() -> void:
	var amp := w(0x1002)
	if amp != 0:
		amp = maxi(0, amp - 0x100)
		set_w(0x1002, amp)
	var d7 := amp >> 8
	var d3 := w(0x1004)
	if d3 >= 0x1A0:
		d3 = 0
	var table := rom("boot_input_147B14_1_data")
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
# Screen 4: SEGA (boot_load_148750).

## boot_load_148750: the logo's tiles (boot_res4 entry 0) and map (entry 1,
## plane B) and its palette (boot_data_1488AE), the ripple from amplitude
## $4100; 3 frames, the fade in (2 frames a step), 20 frames (25 more on
## PAL), the colours cycled (boot_load_148750_1), 120 frames, the fade out.
func boot_load_148750() -> void:
	boot_func_14452E()
	boot_func_144F78()
	boot_func_144DD6()
	boot_func_149A1A()
	boot_func_14532E()
	boot_load_145280()
	_copy_rom(rom("boot_data_1488AE"), PAL_TARGET, 16)
	_unpack_res(4, 0)
	dma_queue_add(DMA_VRAM, 0x0000, 0xFF0000 | UNPACK, 0x2E0)
	dma_flush()
	_unpack_res(4, 1)
	dma_queue_add(DMA_VRAM, 0xE000, 0xFF0000 | UNPACK, 0x800)
	dma_flush()
	set_w(0x1002, 0x4100)
	set_w(0x1004, 0x7000)
	frame_cb = boot_input_147B14
	boot_func_144516()
	await boot_wait(3)
	boot_func_144B5A(2, 0, 0, 0x10)
	while b(F_FADE_IN) != 0:
		await vblank
	await boot_wait(0x14)
	if sb(PAL) < 0:
		await boot_wait(0x19)
	await boot_load_148750_1()
	await boot_wait(0x78)
	await boot_func_14A140()


## boot_load_148750_1: the logo's palette again, then 13 times its colours
## 1-13 moved up one place every 2 frames (the shine running along it).
func boot_load_148750_1() -> void:
	_copy_rom(rom("boot_data_1488AE"), PAL_TARGET, 16)
	for k in 13:
		var first := w(PAL_TARGET + 2)
		for i in 12:
			set_w(PAL_TARGET + 2 + 2 * i, w(PAL_TARGET + 4 + 2 * i))
		set_w(PAL_TARGET + 2 + 24, first)
		boot_load_148750_2()
		await boot_wait(2)


func boot_load_148750_2() -> void:
	dma_queue_add(DMA_CRAM, 0, 0xFF0000 | PAL_TARGET, 0x10)


# --------------------------------------------------------------------------
# Screen 3: Konami (boot_load_147DC8).

## boot_load_147DC8: plane A the green line (tiles 4 and 5 on rows 0-1,
## tile $10 below) and plane B the logo (boot_load_147DC8_data's map
## pieces) in the tiles of boot_res3; the dark palettes (data3 on lines
## 0-2, data4 on line 3) faded in by brightness; a spark runs along the
## line (_9) as plane A scrolls (boot_func_145078), the line's colours
## brighten (_1), the line travels down the screen (_11, plane A up 2 px
## a frame for 112 frames); then the jingle (song 1), the logo's colours
## wiped in (_5, lines 1-2 from boot_data_148690), its backdrop (_7, line
## 0), the background to white (_3), 240 frames, the fade out. A button
## press skips to the end.
func boot_load_147DC8() -> void:
	boot_func_144F78()
	boot_func_144DD6()
	boot_func_149A1A()
	boot_func_14532E()
	boot_load_145280()
	for line in 3:
		_copy_rom(rom("boot_load_147DC8_data3"), PAL_TARGET + line * 0x20, 16)
	_copy_rom(rom("boot_load_147DC8_data4"), PAL_TARGET + 0x60, 16)
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
	var a := rom("boot_load_147DC8_data")
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
	frame_cb = boot_load_147DC8_13
	boot_func_144516()
	boot_func_1447E4(0, 0, 0, 0x3F)
	await boot_wait(0x18)
	boot_load_147DC8_9()
	if sb(PAL) < 0:
		boot_func_145078(0x00250007, 0x1C, 0, 0)
	else:
		boot_func_145078(0x002B0006, 0x1C, 0, 0)
	while b(F_ANIM) != 0:
		await vblank
	if sb(PRESSED) >= 0:
		boot_load_147DC8_1()
		while b(F_ANIM) != 0:
			await vblank
		boot_load_147DC8_11()
		while b(F_ANIM) != 0:
			await vblank
	if sb(PRESSED) >= 0:
		await boot_wait(0x1E)
		set_w(SOUND, 0xFFFF)
		m.play_music(1)
		set_w(SOUND, 1)
		_copy_rom(rom("boot_load_147DC8_data2"), PAL_TARGET + 0x20, 32)
		boot_load_147DC8_5()
		while b(F_ANIM) != 0:
			await vblank
	if sb(PRESSED) >= 0:
		_copy_rom(rom("boot_data_148690"), PAL_TARGET, 16)
		boot_load_147DC8_7()
		while b(F_ANIM) != 0:
			await vblank
	if sb(PRESSED) >= 0:
		boot_load_147DC8_3()
		await boot_wait(0xF0)
	boot_func_144C48()
	while b(F_FADE_OUT) != 0:
		await vblank
	await boot_screen_end()


## boot_load_147DC8_1 / _2: the line's colours (line 3, colours 2-8) up
## one green level in three stages, 3 frames apart.
func boot_load_147DC8_1() -> void:
	var o := obj_alloc(boot_load_147DC8_2)
	if o == 0:
		return
	set_b(F_ANIM, 0xFF)
	set_w(o + 0x1E, 2)
	set_w(o + 0x32, 0)


func boot_load_147DC8_2(o: int) -> void:
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


## boot_load_147DC8_3 / _4: colour 0 up one level a channel seven times,
## every 4 frames (2 on PAL): the background to white.
func boot_load_147DC8_3() -> void:
	var o := obj_alloc(boot_load_147DC8_4)
	if o == 0:
		return
	set_w(o + 0x16, 0)
	set_w(o + 0x1E, 2)
	set_w(o + 0x20, 2 if sb(PAL) < 0 else 4)
	set_b(F_ANIM, 0xFF)


func boot_load_147DC8_4(o: int) -> void:
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


## boot_load_147DC8_5 / _6: lines 1 and 2 wiped in from their last colour
## back, one more a frame, from boot_data_148690 + $2C / + $4C.
func boot_load_147DC8_5() -> void:
	var o := obj_alloc(boot_load_147DC8_6)
	if o == 0:
		return
	set_b(F_ANIM, 0xFF)
	set_w(o + 0x16, 0x1E)


func boot_load_147DC8_6(o: int) -> void:
	var a0 := rom("boot_data_148690")
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


## boot_load_147DC8_7 / _8: line 0 wiped in the same way from + $C.
func boot_load_147DC8_7() -> void:
	var o := obj_alloc(boot_load_147DC8_8)
	if o == 0:
		return
	set_b(F_ANIM, 0xFF)
	set_w(o + 0x16, 0x1E)


func boot_load_147DC8_8(o: int) -> void:
	var a0 := rom("boot_data_148690")
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


## boot_load_147DC8_9 / _10: the spark: a sprite from x $49 along the line
## 6 px a frame (7 on PAL), its four pieces (boot_load_147DC8_10_data) in
## turn, until x $140 or a button press.
func boot_load_147DC8_9() -> void:
	var o := obj_alloc(boot_load_147DC8_10)
	if o == 0:
		return
	set_w(o + 0x34, 0)
	set_w(o + 0x32, 0)
	set_w(o + 0xC, 0x49)
	set_w(o + 8, 0x49)
	set_w(o + 0x1E, 1)
	set_w(o + 0x20, 1)
	set_b(F_ANIM, 0xFF)


func boot_load_147DC8_10(o: int) -> void:
	var d3 := w(o + 0x34) >> 5
	add_w(o + 8, 7 if sb(PAL) < 0 else 6)
	var piece := rom("boot_load_147DC8_10_data") + w(o + 0x32)
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


## boot_load_147DC8_11 / _12: VSRAM down 2 a frame for 112 frames (the
## line travels down the screen).
func boot_load_147DC8_11() -> void:
	var o := obj_alloc(boot_load_147DC8_12)
	if o == 0:
		return
	set_w(o + 0x26, 0xFFFE)
	set_w(o + 0x32, 0)
	set_b(F_ANIM, 0xFF)


func boot_load_147DC8_12(o: int) -> void:
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


## boot_load_147DC8_13: the screen's VBlank routine: the objects, the
## sprites.
func boot_load_147DC8_13() -> void:
	boot_func_144FCA()
	boot_load_144DE2()


# --------------------------------------------------------------------------
# Screen 2: Factor 5 (boot_load_147964).

## boot_load_147964: planes of 32 x 32 cells: the burst's tiles (boot_res2
## entry 3 at $19A0, entry 2 at $0000) and maps (entry 5 on plane A with
## palette 1, entry 4 on plane B in front), lines 0-1 from entry 0; the
## ripple from amplitude $8000 with its phase running; 3 frames, a fade in
## of 32 colours (2 frames a step; by brightness on PAL) under 300 frames,
## the fade out.
func boot_load_147964() -> void:
	boot_func_14452E()
	boot_func_144F78()
	boot_func_144DD6()
	boot_func_149A1A()
	boot_load_145280()
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
	boot_func_144516()
	frame_cb = boot_input_147B14
	await boot_wait(3)
	if b(PAL) == 0:
		boot_func_144B5A(2, 0, 0, 0x20)
	else:
		boot_func_1447E4(2, 0, 0, 0x20)
	await boot_wait(0x12C)
	await boot_func_14A140()
