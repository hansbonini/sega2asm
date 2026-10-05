class_name ISSText
extends RefCounted
## Text in the front end's own fonts (screens/fonts.json): text_draw_large
## (8x16) and text_draw_small (8x8), glyph i = character '-' + i; the
## highlighted variant is palette line 3 (rect_highlight).

const DIR := "res://assets/iss/screens/"

static var _tex := {}


static func _font(large: bool, hi: bool) -> Texture2D:
	var key := ("font_large" if large else "font_small") + ("_hi" if hi else "")
	if not _tex.has(key):
		_tex[key] = load(DIR + key + ".png")
	return _tex[key]


## Draw text at a pixel position; lower case, unknown characters and spaces
## advance without drawing.
static func draw(canvas: CanvasItem, text: String, at: Vector2, large := true, hi := false) -> void:
	var tex := _font(large, hi)
	var h := 16 if large else 8
	for i in text.length():
		var c := text.unicode_at(i)
		var g := c - 0x2D
		if c != 0x20 and c != 0x40 and g >= 0 and g < 0x50:
			canvas.draw_texture_rect_region(tex, Rect2(at + Vector2(i * 8, 0), Vector2(8, h)), Rect2(g * 8, 0, 8, h))


static func width(text: String) -> int:
	return text.length() * 8


## Draw text centred on x.
static func draw_centred(canvas: CanvasItem, text: String, cx: float, y: float, large := true, hi := false) -> void:
	draw(canvas, text, Vector2(roundf(cx - width(text) / 2.0), y), large, hi)
