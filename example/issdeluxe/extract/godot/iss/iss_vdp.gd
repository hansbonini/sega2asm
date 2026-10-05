class_name ISSVdp
extends Node2D
## The Mega Drive's picture as the front end builds it: VRAM (tiles, plane B
## at $0000 and plane A at $2000, 64 x 32 cells each), the CRAM and a sprite
## list, drawn by iss_vdp.gdshader at 256 x 224 with the VDP's priority and
## shadow/highlight rules. The front end writes VRAM and CRAM as the game's
## DMA does and adds sprites as sprite_alloc does; the textures are sent to
## the GPU once a frame when something changed.

const PLANE_B := 0x0000
const PLANE_A := 0x2000
## The window plane (register 3), 32 x 32 cells in H32, never scrolled.
const WINDOW := 0x1000
const MAX_SPRITES := 64

var vram := PackedByteArray()
## CRAM words (----bbb-ggg-rrr-).
var cram := PackedInt32Array()
## Sprite table: 8 bytes per sprite (y + 128, size, attr, x + 128), in the
## order they were added (the link order).
var sat := PackedByteArray()
var sprite_count := 0
var scroll_a := Vector2i.ZERO
var scroll_b := Vector2i.ZERO
## Each line's horizontal scroll of planes A and B (register 11's cell or
## line mode, the hardware's own values: positive moves the plane right);
## empty for the full-screen scroll.
var lines_a := PackedInt32Array()
var lines_b := PackedInt32Array()
## Each line's vertical scroll of planes A and B, when a raster routine
## writes VSRAM line by line (the boot screens); empty for the whole-screen
## scroll.
var vlines_a := PackedInt32Array()
var vlines_b := PackedInt32Array()
## Registers 2, 4 and 16: the planes' bases and size in cells (the game's
## 64 x 32 at $2000 / $0000; the boot module's 64 x 64 at $A000 / $E000).
var plane_a := PLANE_A
var plane_b := PLANE_B
var plane_cols := 64
var plane_rows := 32
## Register 1 bit 6: the display (black when off).
var display := true
var backdrop := 0x20
var shadow_highlight := true
## Registers 17 and 18: the window's horizontal and vertical extent (bit 7
## right / down of the cell or row in bits 0-4; 0 for none). Where it is
## the window replaces plane A.
var window_h := 0
var window_v := 0
## The figures drawn over the picture (the match's players, referee and
## ball as ISSMatch draws them) go behind what has priority: with this set
## the planes' priority pixels and the priority sprites are drawn again
## above them (z 1000), as the VDP puts them in front of low-priority
## sprites.
var priority_overlay := false:
	set(v):
		priority_overlay = v
		_high.visible = v

var _vram_img: Image
var _vram_tex: ImageTexture
var _cram_img: Image
var _cram_tex: ImageTexture
var _cram2_img: Image
var _cram2_tex: ImageTexture
var _sat_img: Image
var _sat_tex: ImageTexture
var _mat := ShaderMaterial.new()
var _high := ColorRect.new()
var _high_mat := ShaderMaterial.new()
var _vram_dirty := true
var _cram_dirty := true
var _cram2_dirty := true
## A second set of colours 0-31 (the title's HInt palette): from line
## cram_split, colour c from cram_split + (c >> 1) on (its write takes an
## HBlank a pair); NO_SPLIT for none.
const NO_SPLIT := 1000
var cram2 := PackedInt32Array()
var cram_split := NO_SPLIT


func _init() -> void:
	vram.resize(0x10000)
	cram.resize(64)
	sat.resize(MAX_SPRITES * 8)
	_vram_img = Image.create_from_data(256, 256, false, Image.FORMAT_R8, vram)
	_vram_tex = ImageTexture.create_from_image(_vram_img)
	_cram_img = Image.create(64, 1, false, Image.FORMAT_RGBA8)
	_cram_tex = ImageTexture.create_from_image(_cram_img)
	cram2.resize(32)
	_cram2_img = Image.create(32, 1, false, Image.FORMAT_RGBA8)
	_cram2_tex = ImageTexture.create_from_image(_cram2_img)
	_sat_img = Image.create_from_data(MAX_SPRITES * 8, 1, false, Image.FORMAT_R8, sat)
	_sat_tex = ImageTexture.create_from_image(_sat_img)
	for mat: ShaderMaterial in [_mat, _high_mat]:
		mat.shader = load("res://iss/iss_vdp.gdshader")
		mat.set_shader_parameter("vram", _vram_tex)
		mat.set_shader_parameter("cram", _cram_tex)
		mat.set_shader_parameter("cram2", _cram2_tex)
		mat.set_shader_parameter("sat", _sat_tex)
	material = _mat
	_high_mat.set_shader_parameter("high_only", true)
	_high.material = _high_mat
	_high.size = Vector2(256, 224)
	_high.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_high.z_as_relative = false
	_high.z_index = 1000
	_high.visible = false
	add_child(_high)


## Copy bytes into VRAM (a DMA).
func dma(addr: int, data: PackedByteArray, offset := 0, length := -1) -> void:
	if length < 0:
		length = data.size() - offset
	for i in length:
		vram[(addr + i) & 0xFFFF] = data[offset + i]
	_vram_dirty = true


func vram_w(addr: int) -> int:
	return (vram[addr & 0xFFFF] << 8) | vram[(addr + 1) & 0xFFFF]


func set_vram_w(addr: int, v: int) -> void:
	vram[addr & 0xFFFF] = (v >> 8) & 0xFF
	vram[(addr + 1) & 0xFFFF] = v & 0xFF
	_vram_dirty = true


## Write a 64 x 32 nametable (2048 words, as the game keeps them in RAM).
func set_plane(base: int, words: PackedInt32Array) -> void:
	for i in mini(words.size(), 2048):
		var v := words[i]
		vram[base + 2 * i] = (v >> 8) & 0xFF
		vram[base + 2 * i + 1] = v & 0xFF
	_vram_dirty = true


func set_cram(words: PackedInt32Array) -> void:
	for i in 64:
		cram[i] = words[i] if i < words.size() else 0
	_cram_dirty = true


func clear_sprites() -> void:
	sprite_count = 0


## Add a sprite (sprite_alloc + the four words): y and x with the VDP's
## +128 offset, size byte (w - 1) << 2 | (h - 1), attribute word. Returns
## false when the 64 are used.
func add_sprite(y: int, size: int, attr: int, x: int) -> bool:
	if sprite_count >= MAX_SPRITES:
		return false
	var o := sprite_count * 8
	sat[o] = (y >> 8) & 0xFF
	sat[o + 1] = y & 0xFF
	sat[o + 2] = size & 0x0F
	sat[o + 3] = 0
	sat[o + 4] = (attr >> 8) & 0xFF
	sat[o + 5] = attr & 0xFF
	sat[o + 6] = (x >> 8) & 0xFF
	sat[o + 7] = x & 0xFF
	sprite_count += 1
	return true


static func md_color(w: int) -> Color:
	const LV := [0, 52, 87, 116, 144, 172, 206, 255]
	return Color8(LV[(w >> 1) & 7], LV[(w >> 5) & 7], LV[(w >> 9) & 7])


func _process(_delta: float) -> void:
	flush()


## Send what changed to the GPU and set the registers.
func flush() -> void:
	if _vram_dirty:
		_vram_img.set_data(256, 256, false, Image.FORMAT_R8, vram)
		_vram_tex.update(_vram_img)
		_vram_dirty = false
	if _cram_dirty:
		for i in 64:
			_cram_img.set_pixel(i, 0, md_color(cram[i]))
		_cram_tex.update(_cram_img)
		_cram_dirty = false
	if _cram2_dirty:
		for i in 32:
			_cram2_img.set_pixel(i, 0, md_color(cram2[i]))
		_cram2_tex.update(_cram2_img)
		_cram2_dirty = false
	_sat_img.set_data(MAX_SPRITES * 8, 1, false, Image.FORMAT_R8, sat)
	_sat_tex.update(_sat_img)
	for mat: ShaderMaterial in [_mat, _high_mat]:
		mat.set_shader_parameter("sprites", sprite_count)
		mat.set_shader_parameter("scroll_ax", scroll_a.x)
		mat.set_shader_parameter("scroll_ay", scroll_a.y)
		mat.set_shader_parameter("scroll_bx", scroll_b.x)
		mat.set_shader_parameter("scroll_by", scroll_b.y)
		mat.set_shader_parameter("line_scroll", not lines_b.is_empty())
		if not lines_b.is_empty():
			mat.set_shader_parameter("lines_a", lines_a)
			mat.set_shader_parameter("lines_b", lines_b)
		mat.set_shader_parameter("backdrop", backdrop)
		mat.set_shader_parameter("shadow_highlight", shadow_highlight)
		mat.set_shader_parameter("window_h", window_h)
		mat.set_shader_parameter("window_v", window_v)
		mat.set_shader_parameter("vline_scroll", not vlines_b.is_empty())
		if not vlines_b.is_empty():
			mat.set_shader_parameter("vlines_a", vlines_a)
			mat.set_shader_parameter("vlines_b", vlines_b)
		mat.set_shader_parameter("plane_a", plane_a)
		mat.set_shader_parameter("plane_b", plane_b)
		mat.set_shader_parameter("plane_cols", plane_cols)
		mat.set_shader_parameter("plane_rows", plane_rows)
		mat.set_shader_parameter("display", display)
		mat.set_shader_parameter("split_line", cram_split)
	queue_redraw()


## The game's registers again (vdp_init_game): planes at $2000 / $0000, 64
## x 32, whole-screen scrolls, the display on.
func reset_registers() -> void:
	plane_a = PLANE_A
	plane_b = PLANE_B
	plane_cols = 64
	plane_rows = 32
	vlines_a = PackedInt32Array()
	vlines_b = PackedInt32Array()
	lines_a = PackedInt32Array()
	lines_b = PackedInt32Array()
	display = true
	window_h = 0
	window_v = 0
	cram_split = NO_SPLIT


## One CRAM word (a CRAM write of the game's own).
func set_cram_word(i: int, v: int) -> void:
	cram[i & 63] = v
	_cram_dirty = true


## One word of the second palette (the HInt's).
func set_cram2_word(i: int, v: int) -> void:
	cram2[i & 31] = v
	_cram2_dirty = true


## The sprite table as a program keeps it in RAM (sprite_alloc's buffer):
## n entries of 8 bytes at addr.
func set_sprites_from_ram(addr: int, n: int) -> void:
	n = clampi(n, 0, MAX_SPRITES)
	for i in n * 8:
		sat[i] = ISSRam.m[(addr + i) & 0xFFFF]
	sprite_count = n


func _draw() -> void:
	draw_rect(Rect2(0, 0, 256, 224), Color.WHITE)


## The scroll table as the VDP reads it (a word for plane A, one for plane
## B per line, at table in RAM, or in VRAM with from_vram): every line its
## own (line mode) or every eighth line's for its row (cell mode).
func set_line_scroll(table: int, cell: bool, from_vram := false) -> void:
	lines_a.resize(224)
	lines_b.resize(224)
	for y in 224:
		var a := table + (y & ~7 if cell else y) * 4
		if from_vram:
			lines_a[y] = vram_w(a) & 0x3FF
			lines_b[y] = vram_w(a + 2) & 0x3FF
		else:
			lines_a[y] = ISSRam.w(a) & 0x3FF
			lines_b[y] = ISSRam.w(a + 2) & 0x3FF
