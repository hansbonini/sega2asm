class_name ISSBallSprite
extends Node2D
## The ISS Deluxe ball: a ball sprite lifted `height` pixels above its shadow.
##
## Put the node at the ball's ground position (ISSProjection.to_map(pitch)).
## As in ball_update ($009FA8) the ball's size follows its height,
## action = clamp((z - $20) >> 5, 0, 2); `lofted` selects the lofted-pass
## ball (action 3) and `large` the 16x16 ball of the penalty shoot-out view (state_shootout, action 4).
## `spin` is the rolling phase in frames: the game adds speed / 4 per frame
## on the ground and 1/8 per frame in the air.

const DIR := "res://assets/iss/ball/"
const PALETTE := "res://assets/iss/players/palette_match.pal.png"

static var _anims: Dictionary = {}

@export var height: float = 0.0
@export_range(0, 63) var facing: int = 0
@export var spin: float = 0.0
@export var lofted := false
@export var large := false
## Depth band of the large ball (0-2): the game uses 1 below y $110 and 2
## below y $F0 as it travels away from the camera.
@export_range(0, 2) var large_depth: int = 0

var _ball := Sprite2D.new()
var _shadow := Sprite2D.new()


func _ready() -> void:
	if _anims.is_empty():
		_anims = JSON.parse_string(FileAccess.get_file_as_string(DIR + "animations.json"))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://md/md_indexed.gdshader")
	mat.set_shader_parameter("palette", load(PALETTE))
	mat.set_shader_parameter("shadow_highlight", true) # the shadow is line 3 colour 15
	for s: Sprite2D in [_shadow, _ball]:
		s.centered = false
		s.material = mat
		add_child(s)
	_show()


## The whole palette from 64 CRAM words (the cinematics' own colours).
func set_palette_cram(cram: PackedInt32Array, _line := 3) -> void:
	var img := Image.create(16, 4, false, Image.FORMAT_RGBA8)
	for i in 64:
		img.set_pixel(i & 15, i >> 4, MDPalette.cram_to_color(cram[i]))
	var tex := ImageTexture.create_from_image(img)
	for s: Sprite2D in [_shadow, _ball]:
		if s.material != null:
			(s.material as ShaderMaterial).set_shader_parameter("palette", tex)


func _process(_delta: float) -> void:
	_show()


func action() -> int:
	if large:
		return 4
	if lofted:
		return 3
	return clampi((int(height) - 0x20) >> 5, 0, 2)


func _show() -> void:
	var act := action()
	var seq: Array = _anims["actions"][act]["directions"][ISSProjection.direction(facing)]
	if seq.is_empty():
		return
	var i: int = int(spin) % 3 + 3 * large_depth if large else int(spin) % seq.size()
	var f: Dictionary = _anims["frames"][seq[i]]
	# ball_draw flips on the raw facing, not on the direction index.
	var r: Dictionary = f["left" if facing >= 0x28 else "right"]
	_ball.texture = load(r["png"])
	_ball.offset = Vector2(-int(r["origin_x"]), -int(r["origin_y"]))
	_ball.position = Vector2(0, -height)
	var s: Dictionary = f["shadow"]
	_shadow.texture = load(s["png"])
	_shadow.offset = Vector2(-int(s["origin_x"]), -int(s["origin_y"]))
