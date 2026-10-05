class_name MDPalette
extends RefCounted
## Mega Drive colour helpers.
##
## CRAM words are ----BBB-GGG-RRR-. Exported palettes are available both as a
## 16 x N texture (one row per 16-colour line, used by md_indexed.gdshader) and
## as JSON with the raw CRAM words, so fades and palette swaps can be recomputed
## exactly like the original game does.

const LEVELS := [0, 36, 73, 109, 146, 182, 219, 255]


static func cram_to_color(w: int) -> Color:
	return Color8(LEVELS[(w >> 1) & 7], LEVELS[(w >> 5) & 7], LEVELS[(w >> 9) & 7])


static func color_to_cram(c: Color) -> int:
	var r := int(round(c.r * 7.0))
	var g := int(round(c.g * 7.0))
	var b := int(round(c.b * 7.0))
	return (b << 9) | (g << 5) | (r << 1)


## Load the CRAM words of an exported palette JSON.
static func load_cram(path: String) -> PackedInt32Array:
	var doc = JSON.parse_string(FileAccess.get_file_as_string(path))
	var out := PackedInt32Array()
	for w in doc["cram"]:
		out.append(int(w))
	return out


static func load_colors(path: String) -> PackedColorArray:
	var out := PackedColorArray()
	for w in load_cram(path):
		out.append(cram_to_color(w))
	return out


## Build a 16 x N palette texture (one row per palette line).
static func make_texture(colors: PackedColorArray) -> ImageTexture:
	var lines := maxi((colors.size() + 15) >> 4, 1)
	var img := Image.create(16, lines, false, Image.FORMAT_RGBA8)
	for i in colors.size():
		img.set_pixel(i & 15, i >> 4, colors[i])
	return ImageTexture.create_from_image(img)


## One step of the game's fade towards black (see fade_out_step): every channel
## that is not yet 0 is decremented, blue first, then green, then red.
static func fade_step_to_black(w: int) -> int:
	if w & 0x0E00:
		return w - 0x0200
	if w & 0x00E0:
		return w - 0x0020
	if w & 0x000E:
		return w - 0x0002
	return w
