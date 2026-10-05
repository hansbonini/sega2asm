class_name ISSFootballer
extends RefCounted
## One player on the pitch: position, record and the action state machine
## (player_update $00534C, keeper_update $001DF0). Humans and the AI drive it
## the same way, through input_dir and the button bits in press / held,
## like obj_input in the original.

# Logical buttons (obj_input bits).
const PASS := 0x10
const LOFT := 0x20
const DASH := 0x40
const SHOOT := 0x100
const SWITCH := 0x200
## The Mode button of a 6-button pad: strategies.
const STRATEGY := 0x800

enum S { MOVE, KICK, SLIDE, SIT, GET_UP, HEADER, FALL, LIE, TRAP, CELEBRATE, DEJECTED,
	KEEPER_DIVE, KEEPER_HOLD, SET_PIECE, STUMBLE, SENT_OFF }
enum K { PASS, LOFT, SHOT, DRIVE, THROW_IN, KEEPER_THROW, PUNT, KICKOFF }

# Animation actions (players/animations.json action_names).
const A_STAND := 0
const A_READY := 1
const A_RUN := 6
const A_WALK := 7
const A_SPRINT := 9
const A_TRAP := 12
const A_POWER_KICK := 14
const A_PASS := 15
const A_THROW_RELEASE := 17
const A_THROW_WINDUP := 18
const A_HEADER := 19
const A_JUMP_HEADER := 21
const A_DIVING_HEADER := 22
const A_SLIDE := 23
const A_SIT := 24
const A_GET_UP := 25
const A_DEJECTED := 27
const A_THROWN := 35
const A_FALL_BACK := 36
const A_BEND_DOWN := 37
const A_LOSE_BALL := 40
const A_STOP_BALL := 44
const A_LEAP := 45
const CELEBRATIONS := [30, 31, 32, 33, 34, 53]

var eng: ISSMatchEngine
var team := 0
## Index on the pitch 0-10 (0 = goalkeeper); also obj_ai_slot.
var index := 0
var name := ""
var number := 1
var hair := 0
var position := 0
var attr := {}
## 0 attack, 1 midfield, 2 defence, 3 goalkeeper.
var role := 1
var form := Vector2.ZERO
## obj_mark: the opponent (pitch index 1-10) this player man-marks
## (screen_man_marking), -1 none.
var mark := -1
## The player object he is in the front end's RAM (0-10 on the pitch,
## 11-19 the bench; -1 without one), his record in the team's squad
## (+$56) and his g_player_status byte (bit 7 booked in this match, bits
## 0-2 the yellow cards so far, 4 = suspended).
var ram_slot := -1
var record := 0
var status := 0

var pos := Vector2.ZERO
var z := 0.0
var vz := 0.0
var speed := 0.0
var facing := 16
var state := S.MOVE
var timer := 0
var action := A_STAND
var anim_frame := 0
var anim_ticks := 0

## obj_energy: the condition (1-4 by default, tm_condition) less a point
## every tbl_stamina_drain[stamina] frames of sprinting; below 2 it costs top
## speed, and it adds to the strength of kicks.
var energy := 3
var energy_ticks := 256
var booked := false

var input_dir := -1
var press := 0
var held := 0
var hold_frames := 0
var human := false

# Kick in progress.
var kick_kind := K.PASS
var kick_power := 0
var kick_heading := 0.0
var kick_target: ISSFootballer = null
var kick_at := 0

# AI (ISSTeamAI).
var ai_target := Vector2.ZERO
var ai_mode := 0
var ai_turns := 0
var ai_dash := false
var ai_wait := 0
var offside := false
var protect := 0
var dive_speed := -1.0
var dive_lift := -1.0


func is_keeper() -> bool:
	return index == 0


func has_ball() -> bool:
	return eng.ball.owner == self


func holding_in_hands() -> bool:
	return state == S.KEEPER_HOLD


func attack_dir() -> float:
	return eng.attack_dir(team)


func a(key: String) -> int:
	return int(attr.get(key, 5))


## Can this player take or touch the ball this frame?
func can_touch_ball() -> bool:
	if eng.ball.kicker == self:
		return false
	return state in [S.MOVE, S.TRAP, S.KEEPER_DIVE, S.SLIDE, S.SET_PIECE]


func busy() -> bool:
	return state not in [S.MOVE, S.SET_PIECE]


func set_state(s: int, act: int, t: int = 0) -> void:
	state = s
	timer = t
	if act != action:
		action = act
		anim_frame = 0
		anim_ticks = 0


static func heading_to(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return fposmod(atan2(d.x, -d.y) / TAU * 64.0, 64.0)


static func angle_diff(a1: float, a2: float) -> float:
	return fposmod(a1 - a2 + 32.0, 64.0) - 32.0


func turn_towards(want: int, rate: int) -> void:
	var d := int(angle_diff(want, facing))
	facing = (facing + clampi(d, -rate, rate)) & 63


func top_speed() -> float:
	return ISSMatchData.speed_max(a("speed") + mini(0, energy - 2))


# ---------------------------------------------------------------------------
# One frame.

func step() -> void:
	match state:
		S.MOVE:
			_move()
		S.SET_PIECE:
			_set_piece()
		S.KICK:
			_kick()
		S.SLIDE:
			_slide()
		S.SIT:
			speed = 0.0
			_count_down(S.GET_UP, A_GET_UP, 16)
		S.GET_UP, S.STUMBLE:
			speed = maxf(0.0, speed - 0.1)
			pos += ISSProjection.heading_vector(facing) * speed
			_count_down(S.MOVE, A_STAND)
		S.TRAP:
			speed = maxf(0.0, speed - 0.2)
			_count_down(S.MOVE, A_STAND)
		S.HEADER:
			_header()
		S.FALL:
			_airborne(ISSMatchData.consts["keeper"]["dive_gravity"])
			if z <= 0.0 and vz <= 0.0:
				speed = 0.0
				set_state(S.LIE, action, 40)
		S.LIE:
			_count_down(S.GET_UP, A_GET_UP, 20)
		S.CELEBRATE, S.DEJECTED:
			speed = maxf(0.0, speed - 0.05)
			pos += ISSProjection.heading_vector(facing) * speed
			if timer > 0:
				timer -= 1
		S.KEEPER_DIVE:
			_keeper_dive()
		S.KEEPER_HOLD:
			_keeper_hold()
		S.SENT_OFF:
			pass
	_animate()
	_stamina()
	if protect > 0:
		protect -= 1
	press = 0


func _count_down(next: int, act: int, t: int = 0) -> void:
	timer -= 1
	if timer <= 0:
		set_state(next, act, t)


func _airborne(gravity: float, heading := -1.0) -> void:
	pos += ISSProjection.heading_vector(facing if heading < 0.0 else heading) * speed
	z += vz
	vz -= gravity
	if z < 0.0:
		z = 0.0
		vz = 0.0


func _stamina() -> void:
	# The sprint states (player_start_sprint_00662E, player_func_0069A6)
	# count obj_energy_timer down; at zero a point goes and it starts again
	# from tbl_stamina_drain[stamina].
	if action != A_SPRINT:
		return
	energy_ticks -= 1
	if energy_ticks < 0:
		energy_ticks = ISSMatchData.stamina_drain(a("stamina"))
		energy = maxi(0, energy - 1)


func _animate() -> void:
	var ticks := 6
	match action:
		A_RUN, A_SPRINT, A_WALK:
			ticks = clampi(int(9.0 - speed * 2.0), 3, 8)
		A_SLIDE, A_POWER_KICK, A_PASS, A_THROW_RELEASE, A_THROW_WINDUP:
			ticks = 4
		A_STAND, A_READY:
			ticks = 12
	anim_ticks += 1
	if anim_ticks >= ticks:
		anim_ticks = 0
		anim_frame += 1


# ---------------------------------------------------------------------------
# Running and dribbling.

func _move() -> void:
	var run: float = ISSMatchData.consts["run_speed"]
	if has_ball() and press & (PASS | LOFT | SHOOT):
		_start_kick_from_press()
		return
	if human and is_keeper() and not has_ball() and press & (LOFT | SHOOT) and eng.ball_zone_team() == team:
		_human_save()
		return
	if not has_ball() and press & LOFT and not is_keeper():
		start_slide()
		return
	if not has_ball() and press & (PASS | SHOOT):
		if try_header():
			return
	if input_dir >= 0:
		turn_towards(input_dir, 3 if has_ball() else 6)
		var top := top_speed()
		if has_ball():
			top -= 0.03 * float(9 - a("dribble"))
		if held & DASH:
			if speed < top:
				speed = minf(top, maxf(speed, run) + ISSMatchData.dash_accel(a("dash")))
		elif speed > run:
			speed = maxf(run, speed - 0.05)
		else:
			speed = minf(run, speed + 0.25)
	else:
		speed = maxf(0.0, speed - 0.25)
		if has_ball() and press & DASH:
			speed = 0.0
	pos += ISSProjection.heading_vector(facing) * speed
	var act := A_STAND
	if speed > run + 0.05:
		act = A_SPRINT
	elif speed > 1.0:
		act = A_RUN
	elif speed > 0.0:
		act = A_WALK
	elif is_keeper() or (eng.ball.pos - pos).length() < 160.0:
		act = A_READY
	if act != action:
		action = act
		anim_frame = 0


func _start_kick_from_press() -> void:
	if press & SHOOT:
		start_kick(K.SHOT, facing)
	elif press & LOFT:
		start_kick(K.LOFT, facing)
	else:
		start_kick(K.PASS, facing)


## Begin a kick of the given kind. The ball leaves the foot on frame
## kick_at; for human LOFT and SHOT the power is how long the button is held.
func start_kick(kind: int, h: float, target: ISSFootballer = null, power: int = -1) -> void:
	kick_kind = kind
	kick_heading = h
	kick_target = target
	kick_power = power
	hold_frames = 0
	match kind:
		K.PASS, K.KICKOFF:
			set_state(S.KICK, A_PASS)
			kick_at = 6
		K.THROW_IN, K.KEEPER_THROW:
			set_state(S.KICK, A_THROW_WINDUP)
			kick_at = 14
		_:
			set_state(S.KICK, A_POWER_KICK)
			kick_at = 10
	speed = minf(speed, 1.0)


func _kick() -> void:
	timer += 1
	pos += ISSProjection.heading_vector(facing) * speed
	speed = maxf(0.0, speed - 0.1)
	# Power: held buttons build it up until the kick (human); the AI sets it.
	if kick_power < 0 and timer < kick_at:
		var b := LOFT if kick_kind == K.LOFT else SHOOT
		if human and held & b and kick_kind in [K.LOFT, K.SHOT, K.DRIVE, K.PUNT]:
			hold_frames += 1
			if hold_frames < 24:
				timer -= 1 # keep winding up while the button is held
	if human and input_dir >= 0 and timer < kick_at:
		kick_heading = input_dir
	if timer == kick_at - 4 and kick_kind in [K.THROW_IN, K.KEEPER_THROW]:
		action = A_THROW_RELEASE
		anim_frame = 0
	if timer == kick_at:
		if kick_power < 0:
			kick_power = clampi(hold_frames / 3, 0, 8)
		eng.kick_ball(self)
	if timer >= kick_at + 14:
		set_state(S.MOVE, A_STAND)


# ---------------------------------------------------------------------------
# Tackles and headers.

func start_slide() -> void:
	set_state(S.SLIDE, A_SLIDE, 0)
	speed = maxf(speed, ISSMatchData.consts["run_speed"]) + 1.0
	eng.emit_sound(0x5C)


func _slide() -> void:
	timer += 1
	pos += ISSProjection.heading_vector(facing) * speed
	speed = maxf(0.0, speed - 0.06)
	if timer >= 2 and timer <= 26:
		eng.slide_contact(self)
	if timer >= 36:
		set_state(S.SIT, A_SIT, 20)


## Head or volley a ball in the air within reach; false if there is none.
func try_header() -> bool:
	var b := eng.ball
	if not b.is_loose() or b.kicker == self:
		return false
	var d := (b.pos - pos).length()
	if b.z < 12.0 or b.z > 64.0 or d > 28.0:
		return false
	kick_kind = K.SHOT if press & SHOOT else K.PASS
	kick_heading = input_dir if input_dir >= 0 else facing
	if kick_kind == K.SHOT:
		kick_heading = eng.goal_heading(self)
	if d > 16.0 and b.z < 36.0:
		set_state(S.HEADER, A_DIVING_HEADER)
		speed = 2.0
		facing = int(heading_to(pos, b.pos)) & 63
	elif b.z > 30.0:
		set_state(S.HEADER, A_JUMP_HEADER)
		vz = 2.5
		speed = 0.5
	else:
		set_state(S.HEADER, A_HEADER)
		speed = 0.0
	return true


func _header() -> void:
	timer += 1
	_airborne(0.25)
	var b := eng.ball
	if b.is_loose() and b.kicker != self and timer < 16:
		var d := (b.pos - pos).length()
		if d < 14.0 and absf(b.z - (z + 24.0)) < 20.0:
			eng.head_ball(self)
	if timer >= 30 and z <= 0.0:
		if action == A_DIVING_HEADER:
			set_state(S.LIE, A_DIVING_HEADER, 12)
		else:
			set_state(S.MOVE, A_STAND)


## Knocked over by a tackle (player_knocked_over): thrown full length when
## moving, falls backwards when standing.
func knock_over(from_heading: float) -> void:
	if eng.ball.owner == self:
		eng.ball.owner = null
		eng.ball.launch(null, from_heading, 1.0, 0.5)
	var k: Array = ISSMatchData.consts["knocked_over"]
	if speed > 0.5:
		set_state(S.FALL, A_THROWN)
		speed = float(k[0])
		vz = float(k[1])
	else:
		set_state(S.FALL, A_FALL_BACK)
		speed = 0.5
		vz = 1.0
		facing = int(from_heading) & 63
	eng.emit_sound(0x4A)


func stumble() -> void:
	set_state(S.STUMBLE, A_LOSE_BALL, 18)


func celebrate() -> void:
	set_state(S.CELEBRATE, CELEBRATIONS[randi() % CELEBRATIONS.size()], 150)


func deject() -> void:
	set_state(S.DEJECTED, A_DEJECTED, 150)
	speed = 0.0


# ---------------------------------------------------------------------------
# Set pieces: the taker holds the ball until a button (or the AI) kicks it.

func start_set_piece(aim: float) -> void:
	set_state(S.SET_PIECE, A_READY)
	speed = 0.0
	facing = int(aim) & 63
	hold_frames = 0


func _set_piece() -> void:
	speed = 0.0
	if not has_ball():
		set_state(S.MOVE, A_STAND)
		return
	if input_dir >= 0 and human:
		facing = input_dir
	if press & (PASS | LOFT | SHOOT):
		var kind := K.PASS
		if eng.restart_type == ISSMatchEngine.R.THROW_IN:
			kind = K.THROW_IN
		elif press & SHOOT:
			kind = K.SHOT if eng.restart_type == ISSMatchEngine.R.PENALTY else K.DRIVE
		elif press & LOFT:
			kind = K.LOFT
		start_kick(kind, facing, kick_target, kick_power if not human else -1)


# ---------------------------------------------------------------------------
# Goalkeeper.

## A human goalkeeper (keeper_update_1) with the ball in his half: lofted
## with a direction dives that way (keeper_side_dive), lofted alone is
## keeper_dive, shoot throws him at where the ball will be 8 frames later
## (keeper_smother).
func _human_save() -> void:
	var k: Dictionary = ISSMatchData.consts["keeper"]
	if press & LOFT:
		if input_dir >= 0:
			var d: Array = k["side_dive"]
			start_dive(input_dir, float(d[0]), float(d[1]))
		else:
			start_dive(facing)
		return
	var b := eng.ball
	var at := b.pos + b.velocity() * float(k["smother_lead"])
	var s: Array = k["smother"]
	start_dive(heading_to(pos, at), float(s[0]), float(s[1]))


## keeper_dive: a slow ball gets the full-length dive (action 22), a fast one
## the jump (action 21); take-off two animation frames later. lateral and
## lift override the dive's speed and lift.
func start_dive(h: float, lateral := -1.0, lift := -1.0) -> void:
	dive_speed = lateral
	dive_lift = lift
	var k: Dictionary = ISSMatchData.consts["keeper"]
	var slow: bool = eng.ball.speed <= float(k["dive_slow_ball"])
	var act := A_DIVING_HEADER if slow else A_JUMP_HEADER
	var side := lateral >= 0.0
	if side:
		# keeper_side_dive / keeper_smother: he keeps his facing and dives
		# to that side of it (action 23 within half a turn clockwise, else 24).
		act = 23 if (int(h) - facing) & 63 < 32 else 24
	set_state(S.KEEPER_DIVE, act, 0)
	eng.event_counts["dives"] = int(eng.event_counts.get("dives", 0)) + 1
	kick_heading = h
	if not side:
		facing = int(h) & 63
	speed = 0.0
	vz = 0.0


func _keeper_dive() -> void:
	var k: Dictionary = ISSMatchData.consts["keeper"]
	timer += 1
	# Take-off on the second animation frame (keeper_diving: frame 2 of 3-frame steps).
	if timer == 4:
		var d: Array = k["dive"] if action == A_DIVING_HEADER else k["jump"]
		speed = dive_speed if dive_speed > 0.0 else float(d[0])
		vz = dive_lift if dive_lift >= 0.0 else float(d[1])
	if timer >= 4:
		_airborne(float(k["dive_gravity"]), kick_heading)
	if eng.ball.owner == self:
		pass
	elif eng.ball.is_loose() and timer < 40:
		eng.keeper_reach(self)
	if timer > 8 and z <= 0.0:
		if eng.ball.owner == self:
			start_hold(true)
		elif timer > 40:
			set_state(S.GET_UP, A_GET_UP, 16)


func start_hold(caught: bool) -> void:
	set_state(S.KEEPER_HOLD, A_READY, 0)
	speed = 0.0
	z = 0.0
	var k: Array = ISSMatchData.consts["keeper"]["hold_frames"]
	ai_wait = int(k[0]) + randi() % (int(k[1]) - int(k[0]) + 1)
	if caught:
		facing = 16 if attack_dir() > 0.0 else 48


func _keeper_hold() -> void:
	if not has_ball():
		set_state(S.MOVE, A_STAND)
		return
	# Turn at most 45 degrees off the line up the pitch.
	var up := 16 if attack_dir() > 0.0 else 48
	if input_dir >= 0:
		turn_towards(input_dir, 1)
	var off := int(angle_diff(facing, up))
	facing = (up + clampi(off, -8, 8)) & 63
	timer += 1
	if press & PASS:
		start_kick(K.KEEPER_THROW, facing)
	elif press & (LOFT | SHOOT):
		start_kick(K.PUNT, facing, null, 7)
