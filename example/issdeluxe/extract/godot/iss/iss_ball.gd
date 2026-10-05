class_name ISSBall
extends RefCounted
## The ball's state and physics, one step per 60 Hz frame, as ball_update
## ($009FA8) and ball_update_high ($00A134):
## - in the air: z += vz, vz -= gravity ($1400, or $2800 after a high kick);
## - landing: vz = -vz / 2 (0 below 1/8), and a hard landing (vz < -3) costs
##   speed >> tbl_ball_bounce_damp[weather] and plays SFX $58;
## - on the ground: speed -= speed >> tbl_ball_friction[weather];
## - then pos += speed along the heading (0 = -y, 16 = +x, 64 per turn).
## While a player owns it the ball sits in front of his feet
## (ball_hold_at_feet) and the physics are off.

signal bounced(hard: bool)

var pos := Vector2.ZERO
var z := 0.0
var vz := 0.0
var speed := 0.0
## 0-64, fractional headings allowed.
var heading := 0.0
var high := false
## Player at whose feet (or in whose hands) the ball is, or null.
var owner: ISSFootballer = null
## Team that touched it last (obj_team of the ball), -1 = nobody yet.
var team := -1
var last_touch: ISSFootballer = null
## Player that kicked it (cannot touch it again for a few frames).
var kicker: ISSFootballer = null
var kick_cooldown := 0
## Spin phase for the sprite.
var spin := 0.0
var weather := 1
## False while the ball is dead (out of play, a goal, before a restart).
var live := true
## Frames since the last kick (for the offside check and the AI).
var since_kick := 0
var launch_pos := Vector2.ZERO


func velocity() -> Vector2:
	return _heading_vector(heading) * speed


static func _heading_vector(h: float) -> Vector2:
	var a := h / 64.0 * TAU
	return Vector2(sin(a), -cos(a))


func is_loose() -> bool:
	return owner == null


func stop() -> void:
	speed = 0.0
	vz = 0.0
	z = 0.0
	high = false


## Launch the ball from player p (or null) along heading h.
func launch(p: ISSFootballer, h: float, new_speed: float, new_vz: float, from_z: float = 0.0) -> void:
	owner = null
	heading = fposmod(h, 64.0)
	speed = new_speed
	vz = new_vz
	z = from_z
	high = false
	kicker = p
	kick_cooldown = 12
	since_kick = 0
	launch_pos = pos
	if p != null:
		team = p.team
		last_touch = p


func step() -> void:
	since_kick += 1
	if kick_cooldown > 0:
		kick_cooldown -= 1
		if kick_cooldown == 0:
			kicker = null
	if owner != null:
		# ball_hold_at_feet: 8 pixels ahead of the owner along his facing.
		var ahead := 8.0 if not owner.holding_in_hands() else 6.0
		pos = owner.pos + ISSProjection.heading_vector(owner.facing) * ahead
		z = 10.0 if owner.holding_in_hands() else 0.0
		heading = owner.facing
		speed = owner.speed
		vz = 0.0
		spin += speed / 4.0
		return
	var c: Dictionary = ISSMatchData.consts["ball"]
	z += vz
	if z < 0.0:
		z = 0.0
		var hard: bool = vz < float(c["bounce_sound_vz"])
		if hard:
			speed -= _shift(speed, int(c["bounce_damp"][weather]))
		vz = -vz / 2.0
		if vz < float(c["bounce_stop"]):
			vz = 0.0
		high = false
		bounced.emit(hard)
	elif z < 1.0:
		# tst.w obj_z: only the integer part counts, so a ball less than a
		# pixel up rolls with friction and no gravity.
		speed -= _shift(speed, int(c["friction_shift"][weather]))
		if speed < 1.0 / 256.0:
			speed = 0.0
		spin += speed / 4.0
	else:
		vz -= float(c["gravity_high"] if high else c["gravity"])
		spin += 0.125
	pos += _heading_vector(heading) * speed


## speed >> n on a 16.16 value.
static func _shift(v: float, n: int) -> float:
	return v / float(1 << n)


## Where the ball will come down (or stop), and after how many frames.
func landing(max_frames: int = 240) -> Array:
	if owner != null:
		return [pos, 0]
	var c: Dictionary = ISSMatchData.consts["ball"]
	var p := pos
	var zz := z
	var v := vz
	var s := speed
	var d := _heading_vector(heading)
	for i in max_frames:
		if zz <= 0.0 and v <= 0.0:
			return [p, i]
		zz += v
		v -= float(c["gravity_high"] if high else c["gravity"])
		p += d * s
	return [p, max_frames]


## Where the ball will be after n frames (ignores bounces; good enough for aiming).
func predict(frames: int) -> Vector2:
	if owner != null:
		return pos
	var c: Dictionary = ISSMatchData.consts["ball"]
	var p := pos
	var s := speed
	var zz := z
	var v := vz
	var d := _heading_vector(heading)
	for i in frames:
		zz += v
		if zz <= 0.0:
			zz = 0.0
			v = 0.0
			s -= _shift(s, int(c["friction_shift"][weather]))
		else:
			v -= float(c["gravity"])
		p += d * s
	return p
