class_name ISSProjection
extends RefCounted
## Pitch coordinates -> stadium map pixels.
##
## ISS Deluxe draws the pitch with an oblique projection (objects_draw, $00C1DC):
##   screen_x = x + y / 2 - hscroll
##   screen_y = y / 2 - z - vscroll
## where (x, y) is the position on the pitch and z the height above it. The
## stadium map is drawn at scroll (0, 0), so without the scroll terms the result
## is a position on the exported stadium render / ISSPitch layer.


static func to_map(pitch: Vector2, height: float = 0.0) -> Vector2:
	return Vector2(pitch.x + pitch.y * 0.5, pitch.y * 0.5 - height)


static func to_pitch(map_pos: Vector2, height: float = 0.0) -> Vector2:
	var y := (map_pos.y + height) * 2.0
	return Vector2(map_pos.x - y * 0.5, y)


## Direction index used by the animation tables for a 0-63 facing angle.
static func direction(facing: int) -> int:
	return ((facing + 4) & 0x38) >> 3


## Unit movement on the pitch for a 0-63 heading (0 = up the pitch, 16 = right),
## as velocity_from_heading ($00BFA0): x grows with sin, y shrinks with cos.
static func heading_vector(heading: int) -> Vector2:
	var a := heading / 64.0 * TAU
	return Vector2(sin(a), -cos(a))
