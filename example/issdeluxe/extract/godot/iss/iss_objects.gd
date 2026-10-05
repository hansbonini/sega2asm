class_name ISSObjects
extends RefCounted
## The match's objects as the front end's cinematics drive them (the
## ending, screen $33): the player, keeper, referee and ball objects where
## the game keeps them in RAM (g_team_home_players, g_referee, g_ball),
## linked into the menu's object list and run by their own update routines,
## one method per routine of the original. Only the paths these scenes can
## take are ported: their players have no ball within reach
## (obj_ball_dist $7FFF) and press no buttons (obj_input holds the d-pad
## bits at most), so the branches into kicks, tackles and headers that
## need the match's ball logic report themselves instead.
##
## Positions are 16.16 longs (obj_x, obj_y, obj_z), velocities 16.16
## (obj_vel_x is added to x, obj_vel_y subtracted from y), angles 0-63
## (0 up the pitch, 16 right). The menu draws them at obj_screen_x =
## x - plane B's scroll, obj_screen_y = y / 2 - z - its vertical scroll.

const S := preload("res://iss/iss_sym.gd")

const OWNER := 0x08
const STATE := 0x0C
const VISIBLE := 0x0E
const X := 0x10
const Y := 0x14
const Z := 0x18
const SCREEN_X := 0x1C
const SCREEN_Y := 0x1E
const VEL_X := 0x20
const VEL_Y := 0x24
const TARGET_X := 0x28
const TARGET_Y := 0x2A
## The direction the player's d-pad points (set by the controls).
const STICK := 0x2C
const BALL_DIST := 0x2E
const ATTR := 0x32
const TRAVEL := 0x3C
const KICK_POWER := 0x40
const AIM := 0x42
const HEADING := 0x44
## Set while a crouched run follows the d-pad (the controls).
const CROUCH := 0x46
const INPUT := 0x48
const TEAM := 0x4A
## Long: the object steered to (-1 none).
const FOLLOW := 0x4C
## Byte: 1 while the object moves under its own control.
const MOVING := 0x50
const ENERGY_TIMER := 0x58
const ACTION := 0x6A
const ANIM_FRAME := 0x7A
const TIMER := 0x7C
const SPEED := 0x7E
const VEL_Z := 0x82
const FACING := 0x86
const KICK_DIR := 0x88
const DISTANCE := 0x8A
## Bytes: the keepy-up count and its timer (player_stop_ball).
const JUGGLE := 0x8C

## Gravity a frame (NTSC, PAL) for players and for the ball.
const GRAVITY := [0x5000, 0x7333]
const BALL_GRAVITY := [0x1400, 0x1CCC]


## An object in RAM at base: its fields are the game's.
class Actor extends ISSMenu.Obj:
	var base := 0
	## Its picture: ISSPlayerSprite, ISSKeeperSprite, ISSNPCSprite or
	## ISSBallSprite.
	var node: Node2D = null
	var cram := PackedInt32Array()

	func _init(at: int) -> void:
		base = at & 0xFFFF
		pooled = false

	## The object's address as the game stores it in pointers.
	func ptr() -> int:
		return 0xFF0000 | base

	func b(o: int) -> int:
		return ISSRam.b(base + o)

	func sb(o: int) -> int:
		return ISSRam.sb(base + o)

	func set_b(o: int, v: int) -> void:
		ISSRam.set_b(base + o, v)

	func w(o: int) -> int:
		return ISSRam.w(base + o)

	func sw(o: int) -> int:
		return ISSRam.sw(base + o)

	func set_w(o: int, v: int) -> void:
		ISSRam.set_w(base + o, v)

	func add_w(o: int, v: int) -> void:
		ISSRam.set_w(base + o, ISSRam.w(base + o) + v)

	func l(o: int) -> int:
		return (ISSRam.w(base + o) << 16) | ISSRam.w(base + o + 2)

	func sl(o: int) -> int:
		var v := l(o)
		return v - 0x100000000 if v >= 0x80000000 else v

	func set_l(o: int, v: int) -> void:
		ISSRam.set_w(base + o, (v >> 16) & 0xFFFF)
		ISSRam.set_w(base + o + 2, v & 0xFFFF)

	func add_l(o: int, v: int) -> void:
		set_l(o, (l(o) + v) & 0xFFFFFFFF)


var m: ISSMenu
## The actors by RAM address.
var actors := {}
var ball: Actor
var referee: Actor
## Where the figures go (m.figures, or a clipping Control a screen gives:
## its position is subtracted).
var parent: Node = null
var _reported := {}
var _draw_frame := -1
var _draw_order := 0


func _init(menu: ISSMenu) -> void:
	m = menu


## The actor for the object at RAM address a (made on first use).
func actor(a: int) -> Actor:
	a &= 0xFFFF
	if not actors.has(a):
		actors[a] = Actor.new(a)
	return actors[a]


## Player k (0 the goalkeeper) of the home side.
func player(k: int) -> Actor:
	return actor(S.g_team_home_players + k * ISSModes.PLAYER_SIZE)


## obj_link_active: put the object at the head of the active list.
func link(o: Actor) -> void:
	o.alive = true
	if not m.objs.has(o):
		m.objs.push_front(o)


static func _rand() -> int:
	return ISSModes._rand()


func _pal() -> int:
	return ISSRam.w(S.g_is_pal) & 1


## A long of the (NTSC, PAL) pair at ROM table t.
func _pal_rom(t: String, offset := 0) -> int:
	return ISSRom.u32(ISSRom.addr(t) + offset + _pal() * 4)


## A long of the (NTSC, PAL) pair in RAM at a ($1814 the run speed, $17B4
## the referee's).
func _pal_ram(a: int) -> int:
	return ISSRam.l(a + _pal() * 4)


func _owns_ball(o: Actor) -> bool:
	return ISSRam.l(S.g_ball + OWNER) == o.ptr()


## A branch these scenes never take (it needs the match's ball logic).
func _unported(o: Actor, what: String) -> void:
	if not _reported.has(what):
		_reported[what] = true
		push_error("ISSObjects: %s is not ported (object $%04X)" % [what, o.base])


func _sfx(id: int) -> void:
	m.play_sfx(id)


func _stop(o: Actor) -> void:
	o.set_l(SPEED, 0)
	o.set_l(VEL_X, 0)
	o.set_l(VEL_Y, 0)


## x += vel_x, y -= vel_y.
func _move(o: Actor) -> void:
	o.add_l(X, o.l(VEL_X))
	o.add_l(Y, -o.sl(VEL_Y))


## vel_z -= gravity; z += vel_z; true when it lands (z below 0).
func _fall(o: Actor) -> bool:
	o.add_l(VEL_Z, -GRAVITY[_pal()])
	o.add_l(Z, o.sl(VEL_Z))
	return o.sw(Z) < 0


## Step the animation every n frames from frame 0 to last (then hold or
## wrap); true when it passed last.
func _anim(o: Actor, n: int, last: int, wrap: bool) -> bool:
	o.add_w(TIMER, -1)
	if o.w(TIMER) != 0:
		return false
	o.set_w(TIMER, n)
	o.add_w(ANIM_FRAME, 1)
	if o.sw(ANIM_FRAME) <= last:
		return false
	o.set_w(ANIM_FRAME, 0 if wrap else last)
	return true


## (heading - facing) & 63.
static func _turn(o: Actor) -> int:
	return (o.w(HEADING) - o.w(FACING)) & 0x3F


## A state's start: its update, action, frame 0, timer and standing still.
func _start(o: Actor, update: Callable, action: int, timer: int, moving: int) -> void:
	o.update = update
	o.set_b(MOVING, moving)
	o.set_w(ACTION, action)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, timer)
	_stop(o)


# --------------------------------------------------------------------------
# Movement.

## velocity_from_heading: obj_vel_x / obj_vel_y from obj_speed (8.8 of it)
## and angle d (tbl_direction_x, the y components 64 entries on).
func velocity_from_heading(o: Actor, d: int) -> void:
	var t := ISSRom.addr("tbl_direction_x") + (d & 0x3F) * 2
	var s := ((o.w(SPEED) << 8) | o.b(SPEED + 2)) & 0xFFFF
	if s >= 0x8000:
		s -= 0x10000
	o.set_l(VEL_X, (s * ISSRom.s16(t)) & 0xFFFFFFFF)
	o.set_l(VEL_Y, (s * ISSRom.s16(t + 0x80)) & 0xFFFFFFFF)


## obj_steer_idle: the think of an object going nowhere: heading = facing,
## target = where it stands.
func obj_steer_idle(o: Actor) -> void:
	o.think = obj_steer_idle_1
	obj_steer_idle_1(o)


func obj_steer_idle_1(o: Actor) -> void:
	o.set_w(HEADING, o.w(FACING))
	o.set_w(TARGET_X, o.w(X))
	o.set_w(TARGET_Y, o.w(Y))


## The target obj_travel pixels ahead along obj_facing.
func _target_ahead(o: Actor) -> void:
	var t := ISSRom.addr("tbl_direction_x") + o.w(FACING) * 2
	var travel := o.sw(TRAVEL)
	o.set_w(TARGET_X, ((travel * ISSRom.s16(t)) >> 8) + o.w(X))
	o.set_w(TARGET_Y, -((travel * ISSRom.s16(t + 0x80)) >> 8) + o.w(Y))


## obj_steer_ahead: a lofted ball's think: its landing point ahead (again
## on the AI's turn, g_ai_slot $0E), the distance left shrinking by its
## speed; idle once it lands.
func obj_steer_ahead(o: Actor) -> void:
	o.think = match_func_010E0E
	_target_ahead(o)
	_travel(o)


func match_func_010E0E(o: Actor) -> void:
	if ISSRam.w(S.g_ai_slot) & 0xFF == 0x0E:
		_target_ahead(o)
	_travel(o)


func _travel(o: Actor) -> void:
	o.add_l(TRAVEL, -o.l(SPEED))
	if o.w(Z) == 0:
		o.think = obj_steer_idle


# --------------------------------------------------------------------------
# Outfield players (player_update $00534C and the actions it starts).

## player_update: the ready stance (action 1; 52 when tired, energy timer
## 0), a random 32-63 frames before the next look round.
func player_update(o: Actor) -> void:
	o.update = player_running
	o.set_b(MOVING, 1)
	o.set_w(ACTION, 1 if o.w(ENERGY_TIMER) != 0 else 0x34)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 0xF)
	o.set_w(FACING, o.w(FACING) & 0xFFF8)
	o.set_w(DISTANCE, (_rand() & 0x1F) + 0x20)
	_stop(o)
	player_running(o)


## Standing: turn or run as obj_heading and the d-pad say; the stance's
## frames every 15.
func player_running(o: Actor) -> void:
	if o.sw(BALL_DIST) < 0x14:
		_unported(o, "player_running near the ball")
		return
	var d := _turn(o)
	if d < 8 or d > 0x38:
		if o.w(INPUT) & 0xF:
			o.update = player_start_run_005D5C
	elif d < 0x20:
		o.update = player_start_side_step
	else:
		o.update = player_start_turn_step
	if o.w(INPUT) & 0x130:
		_unported(o, "player_running buttons")
		return
	o.add_w(TIMER, -1)
	if o.w(TIMER) != 0:
		return
	o.set_w(TIMER, 0xF)
	if o.w(ACTION) != 0x34:
		o.add_w(ANIM_FRAME, 1)
		if o.sw(ANIM_FRAME) > 3:
			o.set_w(ANIM_FRAME, 0)
	else:
		o.set_w(ANIM_FRAME, 1)
	if o.w(CROUCH) != 0:
		o.update = player_run_crouched
	o.add_w(DISTANCE, -1)
	if o.w(DISTANCE) != 0:
		return
	if o.sb(STATE) < 0 and o.w(TEAM) == ISSRam.w(S.g_ball + TEAM):
		var info := S.g_team_home_info if o.w(TEAM) == 0 else S.g_team_away_info
		if ISSRam.l(info + 0x64) == o.ptr() and ISSRam.sb(S.g_ball + STATE) < 2:
			_unported(o, "player_running_arm_raised")
			return
	o.set_w(DISTANCE, (_rand() & 0x1F) + 0x20)


## player_start_run_005D5C: run (action 6) at the run speed ($1814) along
## obj_facing.
func player_start_run_005D5C(o: Actor) -> void:
	o.update = player_func_005D98
	o.set_b(MOVING, 1)
	o.set_w(ACTION, 6)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 3)
	o.set_w(DISTANCE, 0)
	o.set_l(SPEED, _pal_ram(0x1814))
	velocity_from_heading(o, o.w(FACING))
	player_func_005D98(o)


## player_start_run_005D1A: the same after a leap (six steps before the
## d-pad can stop it).
func player_start_run_005D1A(o: Actor) -> void:
	o.update = player_func_005D98
	o.set_b(MOVING, 1)
	o.set_w(ACTION, 6)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 3)
	o.set_w(DISTANCE, 6)
	o.set_l(SPEED, _pal_ram(0x1814))
	velocity_from_heading(o, o.w(FACING))
	player_func_005D98(o)


## Running: a step every 3 frames (10 frames), turning straight to the
## heading within 8, a side or turn step beyond; standing again when the
## d-pad is let go.
func player_func_005D98(o: Actor) -> void:
	_move(o)
	if o.w(INPUT) & 0x130:
		_unported(o, "running with buttons")
		return
	o.add_w(TIMER, -1)
	if o.w(TIMER) == 0:
		if o.sw(FOLLOW) >= 0:
			_unported(o, "running to an object")
			return
		o.set_w(TIMER, 3)
		o.add_w(ANIM_FRAME, 1)
		if o.sw(ANIM_FRAME) > 9:
			o.set_w(ANIM_FRAME, 0)
		var d := _turn(o)
		if d != 0:
			if d <= 8 or d >= 0x38:
				o.set_w(FACING, (o.w(FACING) + d) & 0x3F)
				velocity_from_heading(o, o.w(FACING))
			elif d <= 0x20:
				o.update = player_start_side_step
			else:
				o.update = player_start_turn_step
		if o.w(INPUT) & 0x40 and o.w(INPUT) & 0xE:
			_unported(o, "player_start_sprint")
		if o.sw(DISTANCE) < 0:
			if o.w(INPUT) & 0xF == 0:
				o.update = player_update
				return
			if o.w(CROUCH) != 0:
				var a := o.sw(HEADING) - o.sw(STICK)
				if a > 0xC or a < -0xC:
					o.update = player_run_crouched
					return
		else:
			o.add_w(DISTANCE, -1)
	if o.sw(BALL_DIST) < 0x14:
		_unported(o, "running near the ball")


## player_start_side_step: turn on the spot clockwise, 2 a frame, until
## within 8 of the heading.
func player_start_side_step(o: Actor) -> void:
	o.update = player_start_side_step_1
	o.set_b(MOVING, 1)
	if _owns_ball(o):
		o.set_w(ACTION, 4)
		o.set_w(ANIM_FRAME, 1)
	else:
		o.set_w(ACTION, 1)
		o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 0)
	o.set_w(FACING, o.w(FACING) & 0xFFF8)
	_stop(o)
	player_start_side_step_1(o)


func player_start_side_step_1(o: Actor) -> void:
	o.set_w(FACING, (o.w(FACING) + 2) & 0x3F)
	_step_turned(o, true)


## player_start_turn_step: turn on the spot anticlockwise.
func player_start_turn_step(o: Actor) -> void:
	o.update = player_start_turn_step_1
	o.set_b(MOVING, 1)
	if _owns_ball(o):
		o.set_w(ACTION, 3)
		o.set_w(ANIM_FRAME, 1)
	else:
		o.set_w(ACTION, 1)
		o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 0)
	o.set_w(FACING, o.w(FACING) & 0xFFF8)
	_stop(o)
	player_start_turn_step_1(o)


func player_start_turn_step_1(o: Actor) -> void:
	o.set_w(FACING, (o.w(FACING) - 2) & 0x3F)
	_step_turned(o, false)


## After a turning step, on each eighth of the circle: run, stand (or keep
## the ball) facing the heading, else turn on.
func _step_turned(o: Actor, side: bool) -> void:
	if o.w(FACING) & 7 == 0:
		var d := _turn(o)
		if (d < 8 if side else d <= 8) or (d > 0x38 if side else d > 0x40):
			if _owns_ball(o):
				o.update = player_start_run if o.w(INPUT) & 0xF else player_stop_ball
			else:
				o.update = player_start_run_005D5C if o.w(INPUT) & 0xF else player_update
		elif d < 0x20:
			o.update = player_start_side_step
		else:
			o.update = player_start_turn_step
	if _owns_ball(o):
		_unported(o, "turning with the ball")
	elif o.sw(BALL_DIST) < 0x14:
		_unported(o, "turning near the ball")


## player_start_run: running with the ball (action 6) at the run speed,
## the ball pushed 8 ahead (ball_kick_soft).
func player_start_run(o: Actor) -> void:
	o.update = player_func_00608E
	o.set_b(MOVING, 1)
	o.set_w(ACTION, 6)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 3)
	o.set_w(DISTANCE, 0)
	o.set_w(JUGGLE, 0)
	o.set_l(SPEED, _pal_ram(0x1814))
	velocity_from_heading(o, o.w(FACING))
	ball_kick_soft(o, 8)
	player_func_00608E(o)


## Dribbling: a step every 3 frames; the ball pushed on at the end of each
## stride and on every turn; stopping with it when the d-pad is let go.
func player_func_00608E(o: Actor) -> void:
	if not _owns_ball(o):
		if ISSRam.sw(S.g_restart_type) >= 0:
			o.update = player_start_run_005D5C
		else:
			_unported(o, "player_start_lose_the_ball_009B70")
		return
	_move(o)
	if o.w(INPUT) & 0x130:
		_unported(o, "dribbling with buttons")
		return
	o.add_w(TIMER, -1)
	if o.w(TIMER) == 0:
		if o.sw(FOLLOW) >= 0:
			_unported(o, "dribbling to an object")
			return
		var push := false
		o.set_w(TIMER, 3)
		o.add_w(ANIM_FRAME, 1)
		if o.sw(ANIM_FRAME) > 9:
			o.set_w(ANIM_FRAME, 0)
			push = true
		var d := _turn(o)
		if d != 0:
			if d <= 8 or d >= 0x38:
				o.set_w(FACING, (o.w(FACING) + d) & 0x3F)
				velocity_from_heading(o, o.w(FACING))
				push = true
			elif d <= 0x20:
				o.update = player_start_side_step
			else:
				o.update = player_start_turn_step
		if push:
			ball_kick_soft(o, 8)
		if o.sw(DISTANCE) < 0:
			if o.w(INPUT) & 0xF == 0:
				o.update = player_stop_ball
				return
		else:
			o.add_w(DISTANCE, -1)
	if o.b(JUGGLE) & 1 == 0:
		if o.w(INPUT) & 0x40:
			_unported(o, "dribbling with the dash button")
	elif o.w(INPUT) & 0x40 == 0:
		o.set_b(JUGGLE + 1, 9)
		o.set_b(JUGGLE, o.b(JUGGLE) + 1)
	if o.b(JUGGLE + 1) != 0:
		o.set_b(JUGGLE + 1, o.b(JUGGLE + 1) - 1)
		if o.b(JUGGLE + 1) == 0:
			o.set_b(JUGGLE, 0)
			if o.w(INPUT) & 0x40:
				_unported(o, "player_start_sprint_00695C")


## player_start_fist_pump_00943E: a goal celebration (action 30, frames
## 0-9 every 8).
func player_start_fist_pump_00943E(o: Actor) -> void:
	_start(o, player_start_fist_pump_00943E_1, 0x1E, 8, 0)
	player_start_fist_pump_00943E_1(o)


func player_start_fist_pump_00943E_1(o: Actor) -> void:
	_anim(o, 8, 9, true)


## player_start_arm_up_009506: arm raised (action 32, held on frame 2).
func player_start_arm_up_009506(o: Actor) -> void:
	_start(o, player_start_arm_up_009506_1, 0x20, 8, 0)
	player_start_arm_up_009506_1(o)


func player_start_arm_up_009506_1(o: Actor) -> void:
	_anim(o, 8, 2, false)


## player_start_stand_still_009352: standing still (action 28), facing the
## heading, until the d-pad moves him.
func player_start_stand_still_009352(o: Actor) -> void:
	_start(o, player_start_stand_still_009352_1, 0x1C, 0x20, 0)
	player_start_stand_still_009352_1(o)


func player_start_stand_still_009352_1(o: Actor) -> void:
	if o.sw(BALL_DIST) < 0x14:
		_unported(o, "standing still near the ball")
		return
	o.set_w(FACING, o.w(HEADING))
	var i := o.w(INPUT)
	if i != 0:
		if i & 0x30:
			_unported(o, "player_jump_header")
		else:
			o.update = player_run_crouched
	if ISSRam.sw(S.g_restart_type) < 0:
		o.set_b(MOVING, 1)


## player_start_knee_slide_009484: a knee slide (action 31) slowing by
## 1/32 a frame to a stop.
func player_start_knee_slide_009484(o: Actor) -> void:
	o.update = player_start_knee_slide_009484_1
	o.set_b(MOVING, 0)
	o.set_w(ACTION, 0x1F)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 8)
	player_start_knee_slide_009484_1(o)


func player_start_knee_slide_009484_1(o: Actor) -> void:
	_move(o)
	o.add_l(SPEED, -(o.l(SPEED) >> 5))
	if _pal_rom("player_data_009F98") > o.sl(SPEED):
		_stop(o)
	else:
		velocity_from_heading(o, o.w(FACING))
	_anim(o, 8, 8, true)


## player_start_jump_009594: a jump (action 34): crouch two frames, take off
## (player_data_009F28 + $48), then the dance (action 33) once landed.
func player_start_jump_009594(o: Actor) -> void:
	o.update = player_start_jump_009594_2
	o.set_b(MOVING, 0)
	o.set_w(ACTION, 0x22)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 4)
	o.set_w(DISTANCE, 0)
	player_start_jump_009594_2(o)


func player_start_jump_009594_2(o: Actor) -> void:
	_move(o)
	if o.sw(ANIM_FRAME) < 2:
		o.add_w(TIMER, -1)
		if o.w(TIMER) == 0:
			o.set_w(TIMER, 4)
			o.add_w(ANIM_FRAME, 1)
			if o.w(ANIM_FRAME) == 2:
				o.set_l(VEL_Z, _pal_rom("player_data_009F28", 0x48))
		return
	_anim(o, 4, 4, false)
	if _fall(o):
		o.set_w(Z, 0)
		o.update = player_start_jump_009594_dance


func player_start_jump_009594_dance(o: Actor) -> void:
	_start(o, player_start_jump_009594_1, 0x21, 6, 0)
	player_start_jump_009594_1(o)


func player_start_jump_009594_1(o: Actor) -> void:
	_anim(o, 6, 8, true)


## player_start_leap_0098F2: a leap over a tackle (action 45), thrown up
## (player_data_009F20 / 9F28), running on when he lands.
func player_start_leap_0098F2(o: Actor) -> void:
	o.update = player_start_leap_0098F2_1
	o.set_b(MOVING, 0)
	o.set_w(ACTION, 0x2D)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 4)
	o.set_l(SPEED, _pal_rom("player_data_009F20"))
	o.set_l(VEL_Z, _pal_rom("player_data_009F28"))
	velocity_from_heading(o, o.w(FACING))
	player_start_leap_0098F2_1(o)


func player_start_leap_0098F2_1(o: Actor) -> void:
	_move(o)
	_anim(o, 4, 2, false)
	if _fall(o):
		o.set_w(Z, 0)
		o.update = player_start_run_005FF8 if _owns_ball(o) else player_start_run_005D1A
	if _owns_ball(o):
		_unported(o, "leaping with the ball")


func player_start_run_005FF8(o: Actor) -> void:
	_unported(o, "player_start_run_005FF8")


## player_start_sit_after_a_slide_008F16: a sliding tackle (action 24) at
## player_data_009F90, slowing by 1/32 a frame, then getting up; a player
## within 24 pixels it was steered to (obj $4C) is brought down.
func player_start_sit_after_a_slide_008F16(o: Actor) -> void:
	o.update = player_start_sit_after_a_slide_008F16_1
	o.set_b(MOVING, 0)
	o.set_w(ACTION, 0x18)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 4)
	o.set_l(SPEED, _pal_rom("player_data_009F90"))
	o.set_w(JUGGLE, 0)
	var d := absi(o.sw(STICK) - o.sw(FACING))
	if d < 8 or d > 0x38:
		o.set_w(FACING, o.w(STICK))
	_sfx(92)
	o.set_w(INPUT, o.w(INPUT) & 0xFFDF)
	if o.sb(STATE) >= 0:
		_unported(o, "a slide by a controlled player")
	player_start_sit_after_a_slide_008F16_1(o)


func player_start_sit_after_a_slide_008F16_1(o: Actor) -> void:
	_move(o)
	o.add_l(SPEED, -(o.l(SPEED) >> 5))
	if _pal_rom("player_data_009F98") > o.sl(SPEED):
		o.update = player_get_up
	else:
		velocity_from_heading(o, o.w(FACING))
	o.add_w(TIMER, -1)
	if o.w(TIMER) == 0:
		o.set_w(TIMER, 4)
		o.add_w(ANIM_FRAME, 1)
		if o.sw(ANIM_FRAME) > 2:
			o.set_w(ANIM_FRAME, 2)
	if o.w(JUGGLE) == 0 and o.sw(FOLLOW) >= 0:
		_unported(o, "a slide at another player")
	if _owns_ball(o):
		_unported(o, "sliding with the ball")
	elif o.sw(BALL_DIST) < 0x14:
		_unported(o, "sliding near the ball")


## player_get_up: getting up (action 25, frames 0-2 every 4), then a
## crouched run (or with the ball stopping it).
func player_get_up(o: Actor) -> void:
	_start(o, player_get_up_1, 0x19, 4, 0)
	player_get_up_1(o)


func player_get_up_1(o: Actor) -> void:
	if _anim(o, 4, 2, false):
		o.update = player_stop_ball if _owns_ball(o) else player_run_crouched
	if _owns_ball(o):
		ball_hold_at_feet(o, 8)


## player_run_crouched: the crouched run (action 8) the d-pad steers;
## facing turns 4 a frame towards the d-pad's direction; standing again
## when it is let go.
func player_run_crouched(o: Actor) -> void:
	o.update = player_run_crouched_1
	o.set_b(MOVING, 1)
	o.set_w(ACTION, 8)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 4)
	player_run_crouched_1(o)


func player_run_crouched_1(o: Actor) -> void:
	if o.sw(BALL_DIST) < 0x14:
		_unported(o, "crouched near the ball")
		return
	if o.w(INPUT) & 0x130:
		_unported(o, "crouched with buttons")
		return
	var d := (o.w(FACING) - o.w(STICK)) & 0x3F
	if d < 0x20:
		if d > 2:
			o.set_w(FACING, (o.w(FACING) - 4) & 0x3F)
	elif d < 0x3E:
		o.set_w(FACING, (o.w(FACING) + 4) & 0x3F)
	if o.w(INPUT) & 0xF == 0:
		_stop(o)
		o.set_w(ANIM_FRAME, 0)
		if o.w(CROUCH) == 0:
			o.update = player_update
		elif ISSRam.sb(S.g_ball + STATE) < 0 and ISSRam.sw(S.g_ball + Z) > 0x20:
			o.set_w(ANIM_FRAME, 4)
		return
	o.set_l(SPEED, _pal_ram(0x1814))
	velocity_from_heading(o, o.w(HEADING))
	_move(o)
	o.add_w(TIMER, -1)
	if o.w(TIMER) != 0:
		return
	if o.sw(FOLLOW) >= 0:
		_unported(o, "crouched to an object")
		return
	if o.w(CROUCH) == 0:
		o.update = player_update
		return
	var a := o.sw(HEADING) - o.sw(STICK)
	if a < 4 and a > -4:
		o.update = player_start_run_005D5C
		return
	if o.w(INPUT) & 0x40:
		o.update = player_update
		return
	o.set_w(TIMER, 4)
	o.add_w(ANIM_FRAME, 1)
	if o.sw(ANIM_FRAME) > 3:
		o.set_w(ANIM_FRAME, 0)


## player_knocked_over: brought down: moving, thrown full length (action
## 35), standing, falling backwards (36); in the air until he lands, then a
## while on the ground before lying injured.
func player_knocked_over(o: Actor) -> void:
	o.update = player_knocked_over_1
	o.set_b(MOVING, 0)
	var d := o.w(FACING)
	if o.w(SPEED) != 0:
		o.set_w(ACTION, 0x23)
	else:
		o.set_w(ACTION, 0x24)
		d = (d - 0x20) & 0x3F
	o.set_w(ANIM_FRAME, 0)
	o.set_l(SPEED, _pal_rom("player_data_009F20"))
	o.set_l(VEL_Z, _pal_rom("player_data_009F28"))
	velocity_from_heading(o, d)
	ball_func_00AA94(o)
	if ISSRam.w(S.g_training) == 0:
		_sfx(74)
	player_knocked_over_1(o)


func player_knocked_over_1(o: Actor) -> void:
	if o.sw(ANIM_FRAME) >= 2:
		o.add_w(TIMER, -1)
		if o.w(TIMER) == 0:
			o.update = player_knocked_over_lying_injured
		return
	_move(o)
	o.add_l(VEL_Z, -GRAVITY[_pal()])
	if o.sl(VEL_Z) < 0:
		o.set_w(ANIM_FRAME, 1)
	o.add_l(Z, o.sl(VEL_Z))
	if o.sw(Z) < 0:
		_stop(o)
		o.set_w(Z, 0)
		o.set_w(ANIM_FRAME, 2)
		o.set_w(TIMER, 0x20)


## player_knocked_over_lying_injured: lying hurt (action 39) for 128-255
## frames (unless he is the foul's victim), then getting up.
func player_knocked_over_lying_injured(o: Actor) -> void:
	o.update = player_knocked_over_2
	o.set_b(MOVING, 0)
	o.set_w(ACTION, 0x27)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 8)
	o.set_w(DISTANCE, (_rand() & 0x7F) + 0x80)
	_stop(o)
	player_knocked_over_2(o)


func player_knocked_over_2(o: Actor) -> void:
	_anim(o, 8, 5, true)
	if ISSRam.l(S.g_foul_victim) != o.ptr():
		o.add_w(DISTANCE, -1)
		if o.w(DISTANCE) == 0:
			o.update = player_get_up


## player_start_walk_arms_out_009B1A: walking with arms out (action 51,
## frames 0-4 every 16), then standing.
func player_start_walk_arms_out_009B1A(o: Actor) -> void:
	_start(o, player_start_walk_arms_out_009B1A_1, 0x33, 0x10, 0)
	o.set_w(FACING, o.w(HEADING))
	player_start_walk_arms_out_009B1A_1(o)


func player_start_walk_arms_out_009B1A_1(o: Actor) -> void:
	if _anim(o, 0x10, 4, false):
		o.update = player_update


## player_stop_ball: standing with the ball at his feet (action 1); with
## the loft button and the ball on the ground he pokes it up, a high ball
## coming down he heads (keepy-ups).
func player_stop_ball(o: Actor) -> void:
	o.update = player_stop_ball_1
	o.set_b(MOVING, 1)
	o.set_w(ACTION, 1)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 0xF)
	o.set_w(DISTANCE, 8)
	o.set_w(JUGGLE, 0)
	o.set_w(FACING, o.w(FACING) & 0xFFF8)
	_stop(o)
	player_stop_ball_1(o)


func player_stop_ball_1(o: Actor) -> void:
	var bz := ISSRam.sw(S.g_ball + Z)
	if not _owns_ball(o):
		if ISSRam.sw(S.g_restart_type) < 0:
			_unported(o, "player_start_lose_the_ball_009B70")
			return
		o.update = player_update
		return
	if bz == 0:
		ball_hold_at_feet(o, 8)
	elif o.sw(BALL_DIST) > 0x18:
		ball_func_00AA94(o)
		o.update = player_update
		return
	if bz < 0x18:
		if o.b(JUGGLE) & 1 == 0:
			if o.w(INPUT) & 0x40:
				_unported(o, "player_start_flick_up_006D48")
				return
		elif o.w(INPUT) & 0x40 == 0:
			o.set_b(JUGGLE + 1, 9)
			o.set_b(JUGGLE, o.b(JUGGLE) + 1)
		if o.b(JUGGLE + 1) != 0:
			o.set_b(JUGGLE + 1, o.b(JUGGLE + 1) - 1)
			if o.b(JUGGLE + 1) == 0:
				o.set_b(JUGGLE, 0)
	elif bz < 0x20 and ISSRam.sw(S.g_ball + VEL_Z) < 0:
		_unported(o, "player_turn_with_ball")
		return
	var d := _turn(o)
	if d != 0 and (d >= 8 and d <= 0x38):
		_unported(o, "turning with the ball")
	elif o.w(INPUT) & 0xF:
		_unported(o, "running with the ball")
	var i := o.w(INPUT)
	if i & 0x130:
		if i & 0x100 or i & 0xF:
			_unported(o, "shots and passes")
			return
		if i & 0x20:
			if bz > 0x20:
				if ISSRam.sw(S.g_ball + VEL_Z) < 0:
					o.update = player_stop_ball_standing_header
					return
			elif bz > 0x10:
				if ISSRam.sw(S.g_ball + VEL_Z) < 0:
					_unported(o, "player_stop_ball_knee_trap")
					return
			else:
				o.update = player_start_short_poke_00739A
				return
		if i & 0x10:
			_unported(o, "player_start_short_poke_00741C")
			return
	o.add_w(TIMER, -1)
	if o.w(TIMER) != 0:
		return
	o.set_w(TIMER, 0xF)
	o.add_w(ANIM_FRAME, 1)
	if o.sw(ANIM_FRAME) > 3:
		o.set_w(ANIM_FRAME, 0)
	o.add_w(DISTANCE, -1)
	if o.w(DISTANCE) == 0:
		_unported(o, "keeper_start_jog_on_the_spot_005222")


## player_start_short_poke_00739A: a poke of the ball (action 13); on frame
## 1 it goes up from his foot (ball_sound_00B8DC, 8 high, 8 ahead).
func player_start_short_poke_00739A(o: Actor) -> void:
	_start(o, player_start_short_poke_00739A_1, 0xD, 4, 1)
	player_start_short_poke_00739A_1(o)


func player_start_short_poke_00739A_1(o: Actor) -> void:
	o.add_w(TIMER, -1)
	if o.w(TIMER) != 0:
		return
	o.set_w(TIMER, 4)
	o.add_w(ANIM_FRAME, 1)
	if o.w(ANIM_FRAME) == 1:
		o.set_w(DISTANCE, 8)
		if _owns_ball(o):
			ball_sound_00B8DC(o, 8, 8)
	if o.sw(ANIM_FRAME) > 2:
		o.set_w(ANIM_FRAME, 2)
		o.update = player_stop_ball if _owns_ball(o) else player_update


## player_stop_ball_standing_header: a header (action 19) as the ball
## comes down to $28; on frame 2 it goes up again ($28 high).
func player_stop_ball_standing_header(o: Actor) -> void:
	_start(o, player_stop_ball_overhead_kick, 0x13, 3, 1)
	player_stop_ball_overhead_kick(o)


func player_stop_ball_overhead_kick(o: Actor) -> void:
	if o.w(ANIM_FRAME) == 0:
		if ISSRam.sw(S.g_ball + Z) < 0x28:
			o.set_w(ANIM_FRAME, 1)
		return
	o.add_w(TIMER, -1)
	if o.w(TIMER) != 0:
		return
	o.set_w(TIMER, 3)
	o.add_w(ANIM_FRAME, 1)
	if o.w(ANIM_FRAME) == 2:
		o.set_w(DISTANCE, 8)
		if _owns_ball(o):
			ball_sound_00B8DC(o, 0x28, 8)
	if o.sw(ANIM_FRAME) > 4:
		o.set_w(ANIM_FRAME, 4)
		o.update = player_stop_ball


## keeper_start_stand_0051B4: standing (action 0, frames 0-3 every 32).
func keeper_start_stand_0051B4(o: Actor) -> void:
	_start(o, keeper_start_stand_0051B4_1, 0, 0x20, 0)
	keeper_start_stand_0051B4_1(o)


func keeper_start_stand_0051B4_1(o: Actor) -> void:
	_anim(o, 0x20, 3, true)
	if o.sw(BALL_DIST) < 0x14:
		_unported(o, "standing near the ball")


# --------------------------------------------------------------------------
# The goalkeeper (keeper_update $001DF0).

## keeper_update: the keeper's stance (action 0, frames 0-3 every 15).
func keeper_update(o: Actor) -> void:
	_start(o, keeper_update_1, 0, 0xF, 1)
	keeper_update_1(o)


func keeper_update_1(o: Actor) -> void:
	if o.sw(BALL_DIST) < 0x14:
		_unported(o, "keeper_update near the ball")
		return
	var d := _turn(o)
	if d < 8 or d > 0x38:
		if o.w(INPUT) & 0xF:
			_unported(o, "keeper_start_shuffle_step_002850")
	else:
		_unported(o, "the keeper turning")
	if o.w(INPUT) & 0x130:
		_unported(o, "keeper_update buttons")
		return
	o.add_w(TIMER, -1)
	if o.w(TIMER) != 0:
		return
	o.set_w(TIMER, 0xF)
	o.add_w(ANIM_FRAME, 1)
	if o.sw(ANIM_FRAME) > 3:
		o.set_w(ANIM_FRAME, 0)
	if o.w(CROUCH) != 0:
		_unported(o, "keeper_run")


## keeper_hold_catch: holding the ball after a catch (action 1), facing up
## the pitch away from his goal; a punt or a roll after 64-191 frames.
func keeper_hold_catch(o: Actor) -> void:
	_start(o, keeper_hold_update, 1, 0x20, 1)
	o.set_w(DISTANCE, (_rand() & 0x7F) + 0x40)
	o.set_w(FACING, 0x10 if ISSRam.w(S.g_left_goal_team) == o.w(TEAM) else 0x30)
	keeper_hold_update(o)


## keeper_hold: the same after a punt was called off.
func keeper_hold(o: Actor) -> void:
	_start(o, keeper_hold_update, 1, 0x10, 1)
	o.set_w(DISTANCE, (_rand() & 0x7F) + 0x40)
	o.set_w(FACING, o.w(FACING) & 0xFFF8)
	keeper_hold_update(o)


func keeper_hold_update(o: Actor) -> void:
	if o.w(TIMER) != 0:
		o.add_w(TIMER, -1)
	else:
		var d := ((o.w(HEADING) & 0xFFF8) - o.w(FACING)) & 0x3F
		if d != 0:
			o.add_w(FACING, 8 if d < 0x20 else -8)
			o.set_w(TIMER, 8)
	var f := o.sw(FACING)
	if ISSRam.w(S.g_left_goal_team) == o.w(TEAM):
		o.set_w(FACING, clampi(f, 8, 0x18))
	else:
		o.set_w(FACING, clampi(f, 0x28, 0x38))
	if o.w(INPUT) & 0x10:
		_unported(o, "keeper_throw")
	if o.w(INPUT) & 0x120:
		o.update = keeper_punt_run
	o.add_w(DISTANCE, -1)
	if o.w(DISTANCE) == 0:
		if _rand() & 3 == 0:
			o.update = keeper_punt
		else:
			o.update = keeper_roll
	if _owns_ball(o):
		ball_hold_in_front(o, 0x18, 6)
	else:
		_unported(o, "keeper_run")


## keeper_roll: the keeper bounces the ball (action 15): on frame 1 it
## drops from $18 high 8 ahead of him; the hold again after frame 6.
func keeper_roll(o: Actor) -> void:
	_start(o, keeper_roll_1, 0xF, 4, 1)
	keeper_roll_1(o)


func keeper_roll_1(o: Actor) -> void:
	if o.w(INPUT) & 0x130:
		o.update = keeper_hold
	o.add_w(TIMER, -1)
	if o.w(TIMER) != 0:
		return
	o.set_w(TIMER, 4)
	o.add_w(ANIM_FRAME, 1)
	if o.w(ANIM_FRAME) == 1:
		keeper_roll_2(o, 0x18, 8)
	if o.sw(ANIM_FRAME) > 6:
		o.set_w(ANIM_FRAME, 6)
		o.update = keeper_hold


func keeper_roll_2(o: Actor, d4: int, d5: int) -> void:
	if not _owns_ball(o):
		return
	var t := ISSRom.addr("tbl_direction_x") + o.w(FACING) * 2
	ball.set_w(X, ((d5 * ISSRom.s16(t)) >> 8) + o.w(X))
	ball.set_w(Y, -((d5 * ISSRom.s16(t + 0x80)) >> 8) + o.w(Y))
	ball.set_w(Z, d4)
	ball.update = ball_update
	ball.set_w(FACING, o.w(FACING))
	ball.set_w(HEADING, o.w(FACING))
	ball.set_l(VEL_Z, 0xFFFC4000)
	ball.set_l(SPEED, 0)


## keeper_punt: the punt's wind-up (action 14, frames 0-7 every 8) with
## the ball held where keeper_punt_1_data says; the hold again after.
func keeper_punt(o: Actor) -> void:
	_start(o, keeper_punt_1, 0xE, 8, 1)
	o.set_w(KICK_DIR, o.w(FACING))
	keeper_punt_1(o)


func keeper_punt_1(o: Actor) -> void:
	if o.w(INPUT) & 0x13F:
		o.update = keeper_hold
	if _anim(o, 8, 7, false):
		o.update = keeper_hold
	if _owns_ball(o):
		var t := ISSRom.addr("keeper_punt_1_data") + o.w(ANIM_FRAME) * 4
		ball_hold_in_front(o, ISSRom.s16(t), ISSRom.s16(t + 2))


## keeper_punt_run: a short run (action 8, then 7) and the kick from the
## hands: the ball lofted on frame 2, along a direction pulled a quarter of
## the way to straight up the pitch.
func keeper_punt_run(o: Actor) -> void:
	o.update = keeper_punt_run_walk
	o.set_b(MOVING, 1)
	o.set_w(ACTION, 8)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 6)
	o.set_l(SPEED, _pal_rom("keeper_punt_run_data"))
	velocity_from_heading(o, o.w(FACING))
	ball_hold_at_feet(o, 0x10)
	ISSRam.set_b(S.g_ball + STATE, 2)
	var f := o.w(FACING)
	if f < 0x20:
		o.set_w(KICK_DIR, ((f - 0x10) >> 2) + 0x10)
	else:
		o.set_w(KICK_DIR, ((f - 0x30) >> 2) + 0x30)
	keeper_punt_run_walk(o)


func keeper_punt_run_walk(o: Actor) -> void:
	_move(o)
	if o.w(ACTION) == 8:
		o.add_w(TIMER, -1)
		if o.w(TIMER) == 0:
			o.set_w(TIMER, 6)
			o.add_w(ANIM_FRAME, 1)
			if o.sw(ANIM_FRAME) > 2:
				o.set_w(ANIM_FRAME, 0)
				o.set_w(ACTION, 7)
		return
	o.add_w(TIMER, -1)
	if o.w(TIMER) != 0:
		return
	o.set_w(TIMER, 2)
	o.add_w(ANIM_FRAME, 1)
	if o.w(ANIM_FRAME) == 2:
		if _owns_ball(o):
			o.set_w(DISTANCE, 0x10)
			ball_launch_lofted(o, 4)
			ISSRam.set_b(S.g_ball + STATE, 2)
		o.set_w(INPUT, 0)
		if o.sb(STATE) >= 0:
			_unported(o, "a punt by a controlled keeper")
	if o.sw(ANIM_FRAME) > 7:
		o.set_w(ANIM_FRAME, 7)
		if ISSRam.sw(S.g_restart_type) < 0:
			ISSRam.set_b(S.g_ball + STATE, 0xFF)
		o.update = keeper_update


## keeper_start_get_up_0049F2: getting up (action 25, frames 0-1 every 32).
func keeper_start_get_up_0049F2(o: Actor) -> void:
	_start(o, keeper_start_get_up_0049F2_1, 0x19, 0x20, 0)
	keeper_start_get_up_0049F2_1(o)


func keeper_start_get_up_0049F2_1(o: Actor) -> void:
	_anim(o, 0x20, 1, false)


# --------------------------------------------------------------------------
# The referee ($125E set: the other set of actions).

func _ref_action(normal: int, other: int) -> int:
	return other if ISSRam.w(0x125E) != 0 else normal


## obj_start_ready: an official (or, $125E, the dog) standing ready
## (action 1 / 15, frames 0-3 / 0-1 every 15), turning or setting off as
## the heading and the d-pad say.
func obj_start_ready(o: Actor) -> void:
	_start(o, obj_start_ready_1, _ref_action(1, 0xF), 0xF, o.b(MOVING))
	obj_start_ready_1(o)


func obj_start_ready_1(o: Actor) -> void:
	var d := _turn(o)
	if d < 8 or d > 0x38:
		if o.w(INPUT) & 0xF:
			o.update = sys_state_00148C
	elif d < 0x20:
		o.update = sys_state_0013DA
	else:
		o.update = sys_state_001328
	o.add_w(TIMER, -1)
	if o.w(TIMER) != 0:
		return
	o.set_w(TIMER, 0xF)
	o.add_w(ANIM_FRAME, 1)
	if o.sw(ANIM_FRAME) > (1 if ISSRam.w(0x125E) != 0 else 3):
		o.set_w(ANIM_FRAME, 0)


## sys_state_00148C: jogging (action 2; the dog's run, 14) at $17B4.
func sys_state_00148C(o: Actor) -> void:
	o.update = sys_state_00148C_1
	o.set_w(ACTION, _ref_action(2, 0xE))
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 4)
	o.set_l(SPEED, _pal_ram(0x17B4))
	velocity_from_heading(o, o.w(FACING))
	sys_state_00148C_1(o)


func sys_state_00148C_1(o: Actor) -> void:
	_move(o)
	if o.w(INPUT) & 0xF == 0:
		o.update = obj_start_ready
	o.add_w(TIMER, -1)
	if o.w(TIMER) != 0:
		return
	o.set_w(TIMER, 4)
	o.add_w(ANIM_FRAME, 1)
	if o.sw(ANIM_FRAME) > (4 if ISSRam.w(0x125E) != 0 else 9):
		o.set_w(ANIM_FRAME, 0)
	if o.w(INPUT) & 0xF == 0:
		return
	var d := _turn(o)
	if d == 0:
		return
	if d <= 8 or d >= 0x38:
		o.set_w(FACING, (o.w(FACING) + d) & 0x3F)
		velocity_from_heading(o, o.w(FACING))
	elif d <= 0x20:
		o.update = sys_state_0013DA
	else:
		o.update = sys_state_001328


## sys_state_001328 / 0013DA: turning on the spot, 2 a frame anticlockwise
## / clockwise, until within 8 of the heading.
func sys_state_001328(o: Actor) -> void:
	o.update = sys_state_001328_1
	o.set_w(ACTION, _ref_action(1, 0xF))
	o.set_w(ANIM_FRAME, 0)
	_stop(o)
	sys_state_001328_1(o)


func sys_state_001328_1(o: Actor) -> void:
	o.set_w(FACING, (o.w(FACING) - 2) & 0x3F)
	_ready_turned(o)


func sys_state_0013DA(o: Actor) -> void:
	o.update = sys_state_0013DA_1
	o.set_w(ACTION, _ref_action(1, 0xF))
	o.set_w(ANIM_FRAME, 0)
	_stop(o)
	sys_state_0013DA_1(o)


func sys_state_0013DA_1(o: Actor) -> void:
	o.set_w(FACING, (o.w(FACING) + 2) & 0x3F)
	_ready_turned(o)


func _ready_turned(o: Actor) -> void:
	if o.w(FACING) & 6 != 0:
		return
	var d := _turn(o)
	if d < 8 or d > 0x38:
		o.update = sys_state_00148C if o.w(INPUT) & 0xF else obj_start_ready
	elif d < 0x20:
		o.update = sys_state_0013DA
	else:
		o.update = sys_state_001328


## sys_state_001670: the referee standing (action 5, frames 0-3 every 15).
func sys_state_001670(o: Actor) -> void:
	_start(o, sys_state_001670_1, _ref_action(5, 0x11), 0xF, o.b(MOVING))
	sys_state_001670_1(o)


func sys_state_001670_1(o: Actor) -> void:
	var d := _turn(o)
	if d < 8 or d > 0x38:
		if o.w(INPUT) & 0xF:
			o.update = sys_state_00188E
	elif d < 0x20:
		o.update = sys_state_0017DC
	else:
		o.update = sys_state_00172A
	o.add_w(TIMER, -1)
	if o.w(TIMER) != 0:
		return
	o.set_w(TIMER, 0xF)
	o.add_w(ANIM_FRAME, 1)
	if o.sw(ANIM_FRAME) > (1 if ISSRam.w(0x125E) != 0 else 3):
		o.set_w(ANIM_FRAME, 0)


## sys_state_00188E: running (action 6, ten frames every 4) at $17B4.
func sys_state_00188E(o: Actor) -> void:
	o.update = sys_state_00188E_1
	o.set_w(ACTION, _ref_action(6, 0x10))
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 4)
	o.set_l(SPEED, _pal_ram(0x17B4))
	velocity_from_heading(o, o.w(FACING))
	sys_state_00188E_1(o)


func sys_state_00188E_1(o: Actor) -> void:
	_move(o)
	if o.w(INPUT) & 0xF == 0:
		o.update = sys_state_001670
	o.add_w(TIMER, -1)
	if o.w(TIMER) != 0:
		return
	o.set_w(TIMER, 4)
	o.add_w(ANIM_FRAME, 1)
	if o.sw(ANIM_FRAME) > (4 if ISSRam.w(0x125E) != 0 else 9):
		o.set_w(ANIM_FRAME, 0)
	if o.w(INPUT) & 0xF == 0:
		return
	var d := _turn(o)
	if d == 0:
		return
	if d <= 8 or d >= 0x38:
		o.set_w(FACING, (o.w(FACING) + d) & 0x3F)
		velocity_from_heading(o, o.w(FACING))
	elif d <= 0x20:
		o.update = sys_state_0017DC
	else:
		o.update = sys_state_00172A


## sys_state_00172A / 0017DC: turning on the spot, 2 a frame anticlockwise
## / clockwise, until within 8 of the heading.
func sys_state_00172A(o: Actor) -> void:
	o.update = sys_state_00172A_1
	o.set_w(ACTION, _ref_action(5, 0x11))
	o.set_w(ANIM_FRAME, 0)
	_stop(o)
	sys_state_00172A_1(o)


func sys_state_00172A_1(o: Actor) -> void:
	o.set_w(FACING, (o.w(FACING) - 2) & 0x3F)
	_ref_turned(o)


func sys_state_0017DC(o: Actor) -> void:
	o.update = sys_state_0017DC_1
	o.set_w(ACTION, _ref_action(5, 0x11))
	o.set_w(ANIM_FRAME, 0)
	o.set_l(SPEED, 0)
	sys_state_0017DC_1(o)


func sys_state_0017DC_1(o: Actor) -> void:
	o.set_w(FACING, (o.w(FACING) + 2) & 0x3F)
	_ref_turned(o)


func _ref_turned(o: Actor) -> void:
	if o.w(FACING) & 6 != 0:
		return
	var d := _turn(o)
	if d < 8 or d > 0x38:
		o.update = sys_state_00188E if o.w(INPUT) & 0xF else sys_state_001670
	elif d < 0x20:
		o.update = sys_state_0017DC
	else:
		o.update = sys_state_00172A


## sys_state_001988: the referee signals the restart (action 7): frame 0
## a kick-off, 1 a free kick, 2 pointing; facing the restart's side (or
## up / down the pitch) for 128 frames.
func sys_state_001988(o: Actor) -> void:
	o.update = sys_state_001988_1
	o.set_w(ACTION, _ref_action(7, 0x12))
	o.set_w(ANIM_FRAME, 2)
	var rt := ISSRam.w(S.g_restart_type)
	if rt == 0:
		o.set_w(ANIM_FRAME, 0)
	if rt == 2:
		o.set_w(ANIM_FRAME, 1)
	var own := ISSRam.w(S.g_restart_team) == ISSRam.w(S.g_left_goal_team)
	var f: int
	if ISSRam.sw(S.g_pitch_middle_y) > o.sw(Y):
		f = 0x20 if o.w(ANIM_FRAME) == 2 else (0x18 if own else 0x28)
	else:
		f = 0 if o.w(ANIM_FRAME) == 2 else (8 if own else 0x38)
	o.set_w(FACING, f)
	o.set_w(DISTANCE, 0x80)
	_stop(o)
	sys_state_001988_1(o)


func sys_state_001988_1(o: Actor) -> void:
	o.add_w(DISTANCE, -1)
	if o.w(DISTANCE) == 0:
		o.update = sys_state_001670


# --------------------------------------------------------------------------
# The ball.

## ball_update: the ball in flight or rolling: gravity, the bounce
## (vz = -vz/2, SFX 88, the weather's damping), rolling friction, the
## spin, its size by height, then moving along obj_heading.
func ball_update(o: Actor) -> void:
	o.update = ball_update_1
	ball_update_1(o)


func ball_update_1(o: Actor) -> void:
	o.add_l(Z, o.sl(VEL_Z))
	var z := o.sw(Z)
	var weather := ISSRam.w(S.g_weather)
	if z < 0:
		o.set_w(Z, 0)
		if o.sw(VEL_Z) < -3:
			_sfx(88)
			var damp := ISSRom.u16(ISSRom.addr("tbl_ball_bounce_damp") + weather * 2)
			o.add_l(SPEED, -(o.sl(SPEED) >> damp))
		var vz := -(o.sl(VEL_Z) >> 1)
		o.set_l(VEL_Z, (vz if vz >= 0x2000 else 0) & 0xFFFFFFFF)
	elif z == 0:
		var f := ISSRom.u16(ISSRom.addr("tbl_ball_friction") + (1 if o.b(STATE) == 1 else weather) * 2)
		o.add_l(SPEED, -(o.sl(SPEED) >> f))
		if o.sl(SPEED) < 0:
			_stop(o)
		o.add_l(ANIM_FRAME, o.l(SPEED) >> 2)
		o.set_w(ANIM_FRAME, o.w(ANIM_FRAME) & 3)
	else:
		o.add_l(VEL_Z, -BALL_GRAVITY[_pal()])
		o.add_l(ANIM_FRAME, 0x2000)
		o.set_w(ANIM_FRAME, o.w(ANIM_FRAME) & 3)
	o.set_w(ACTION, clampi(maxi(0, o.sw(Z) - 0x20) >> 5, 0, 2))
	o.set_w(FACING, o.w(HEADING))
	velocity_from_heading(o, o.w(FACING))
	_move(o)


## ball_func_00AA94: the player loses the ball: loose, the camera on it,
## rolling on.
func ball_func_00AA94(o: Actor) -> void:
	if not _owns_ball(o):
		return
	ISSRam.set_l(S.g_ball + OWNER, 0xFFFFFFFF)
	ISSRam.set_b(S.g_ball + STATE, 0xFF)
	ISSRam.set_l(S.g_camera_focus, 0xFF0000 | S.g_ball)
	ball.update = ball_update
	ball.think = obj_steer_idle


## ball_hold_in_front: the ball held (state 2) d5 ahead of the holder and
## d4 above his feet, still.
func ball_hold_in_front(o: Actor, d4: int, d5: int) -> void:
	if not _owns_ball(o):
		return
	var t := ISSRom.addr("tbl_direction_x") + o.w(FACING) * 2
	ball.set_w(X, ((d5 * ISSRom.s16(t)) >> 8) + o.w(X))
	ball.set_w(Y, -((d5 * ISSRom.s16(t + 0x80)) >> 8) + o.w(Y))
	ball.set_w(Z, d4 + o.w(Z))
	ball.think = obj_steer_idle
	ball.update = ball_hold_in_front_1
	ball.set_w(FACING, o.w(FACING))
	ball.set_w(HEADING, o.w(FACING))
	ball.set_l(VEL_Z, 0)
	ball.set_l(SPEED, 0)
	ISSRam.set_w(0x1A3C, 0)
	ball.set_b(STATE, 2)


func ball_hold_in_front_1(o: Actor) -> void:
	o.update = ball_hold_in_front_2
	o.set_w(ANIM_FRAME, 0)
	o.set_w(ACTION, 0)


func ball_hold_in_front_2(_o: Actor) -> void:
	pass


## ball_hold_at_feet: the ball at the player's feet (state 1) d5 ahead,
## rolling with him.
func ball_hold_at_feet(o: Actor, d5: int) -> void:
	if not _owns_ball(o):
		return
	var t := ISSRom.addr("tbl_direction_x") + o.w(FACING) * 2
	ball.set_w(X, ((d5 * ISSRom.s16(t)) >> 8) + o.w(X))
	ball.set_w(Y, -((d5 * ISSRom.s16(t + 0x80)) >> 8) + o.w(Y))
	if ball.sw(VEL_Z) >= 0:
		ball.set_l(VEL_Z, 0)
	ball.think = obj_steer_idle
	ball.update = ball_update
	ball.set_w(FACING, o.w(FACING))
	ball.set_w(HEADING, o.w(FACING))
	ball.set_l(SPEED, o.l(SPEED))
	ball.set_b(STATE, 1)


## ball_kick_soft: the ball pushed on along the dribbler's facing: his
## speed plus ball_kick_soft_data, on the ground (state 1) d5 ahead.
func ball_kick_soft(o: Actor, d5: int) -> void:
	if not _owns_ball(o):
		return
	ISSRam.set_w(S.g_offside_pending, 0xFFFF)
	ball.set_w(FACING, o.w(FACING))
	ball.set_w(HEADING, o.w(FACING))
	ball.set_l(SPEED, (_pal_rom("ball_kick_soft_data") + o.l(SPEED)) & 0xFFFFFFFF)
	ball.set_l(VEL_Z, 0)
	ball.set_w(Z, 0)
	ball.set_b(STATE, 1)
	ball.update = ball_update
	ball.think = obj_steer_idle
	var t := ISSRom.addr("tbl_direction_x") + o.w(FACING) * 2
	ball.set_w(X, ((d5 * ISSRom.s16(t)) >> 8) + o.w(X))
	ball.set_w(Y, -((d5 * ISSRom.s16(t + 0x80)) >> 8) + o.w(Y))


## ball_sound_00B8DC: the ball played up from the player's foot: speed and
## lift from ball_sound_00B8DC_data by obj_distance, d4 high, d5 ahead
## (state 0 beyond 10 pixels, else 1); SFX 88.
func ball_sound_00B8DC(o: Actor, d4: int, d5: int) -> void:
	if not _owns_ball(o):
		return
	ISSRam.set_w(S.g_offside_pending, 0xFFFF)
	ball.set_w(FACING, o.w(FACING))
	ball.set_w(HEADING, o.w(FACING))
	var k := ((o.w(DISTANCE) & 0xFFFC) + _pal()) * 4
	var t := ISSRom.addr("ball_sound_00B8DC_data") + k
	ball.set_l(SPEED, ISSRom.u32(t))
	ball.set_l(VEL_Z, ISSRom.u32(t + 8))
	ball.set_w(Z, d4)
	ball.set_b(STATE, 0 if d5 > 10 else 1)
	ball.update = ball_update
	ball.think = obj_steer_idle
	var d := ISSRom.addr("tbl_direction_x") + o.w(FACING) * 2
	ball.set_w(X, ((d5 * ISSRom.s16(d)) >> 8) + o.w(X))
	ball.set_w(Y, -((d5 * ISSRom.s16(d + 0x80)) >> 8) + o.w(Y))
	_sfx(88)


## ball_launch_lofted: a lofted kick along obj_kick_dir: loose, speed and
## lift from tbl_kick_lofted and the distance to the landing point from
## ball_data_00BAA6 by obj_distance, d4 high; the landing marker; SFX 84.
func ball_launch_lofted(o: Actor, d4: int) -> void:
	if not _owns_ball(o):
		return
	ISSRam.set_w(S.g_offside_pending, 0)
	ISSRam.set_l(S.g_ball + OWNER, 0xFFFFFFFF)
	ball.set_b(STATE, 0xFF)
	ball.update = ball_update
	ball.think = obj_steer_ahead
	ISSRam.set_l(S.g_camera_focus, 0xFF0000 | S.g_ball)
	ball.set_w(TARGET_X, 0xFFC0)
	ball.set_w(TARGET_Y, 0xFFC0)
	var keep := m.a5
	var marker := m.obj_alloc()
	m.a5 = keep
	if marker != null:
		landing_marker_start(marker)
	ball.set_w(FACING, o.w(KICK_DIR))
	ball.set_w(HEADING, o.w(KICK_DIR))
	var k := (((o.w(DISTANCE) * 2) & 0xFFFC) + _pal()) * 4
	var t := ISSRom.addr("tbl_kick_lofted") + k
	ball.set_l(SPEED, ISSRom.u32(t))
	ball.set_l(VEL_Z, ISSRom.u32(t + 8))
	ball.set_w(Z, d4)
	ball.set_l(TRAVEL, ISSRom.u32(ISSRom.addr("ball_data_00BAA6") + ((o.w(DISTANCE) * 2) & 0xFFFC)))
	if o.sl(OWNER) >= 0:
		_unported(o, "match_func_010E64 (a controlled kick's aftertouch)")
	_sfx(84)


## landing_marker_start: the marker where the lofted ball will land (its
## target), gone when the ball gets within 8 pixels of it or someone else
## touches it.
func landing_marker_start(o: ISSMenu.Obj) -> void:
	o.think = Callable()
	o.update = landing_marker_update
	o.draw = landing_marker_draw
	o.set_w(ACTION, 0)
	o.set_l(SPEED, 0)
	o.set_l(OWNER, ISSRam.l(S.g_last_touch))
	landing_marker_update(o)


func landing_marker_update(o: ISSMenu.Obj) -> void:
	var dx := ISSRam.sw(S.g_ball + X) - ISSRam.sw(S.g_ball + TARGET_X)
	var dy := ISSRam.sw(S.g_ball + Y) - ISSRam.sw(S.g_ball + TARGET_Y)
	if (dx > -8 and dx < 8 and dy > -8 and dy < 8) or ISSRam.l(S.g_last_touch) != o.l(OWNER):
		_free_marker(o)
		return
	o.set_w(X, ISSRam.w(S.g_ball + TARGET_X))
	o.set_w(Y, ISSRam.w(S.g_ball + TARGET_Y))


var _marker: Sprite2D


func landing_marker_draw(o: ISSMenu.Obj) -> void:
	if _marker == null:
		_marker = Sprite2D.new()
		_marker.texture = load("res://assets/iss/misc/landing_marker.png")
		_marker.centered = true
		m.figures.add_child(_marker)
	_marker.visible = o.b(VISIBLE) != 0xFF
	_marker.position = Vector2(o.sw(SCREEN_X), o.sw(SCREEN_Y))


func _free_marker(o: ISSMenu.Obj) -> void:
	m.obj_free(o)
	if _marker != null:
		_marker.visible = false


# --------------------------------------------------------------------------
# The presentations' objects (state_screen): the two players and the
# referee standing on the big screen, the coin, the crowd's flags and the
# confetti.

## player_think_idle: a player who just stands (no input, heading = facing).
func player_think_idle(o: Actor) -> void:
	o.think = player_think_idle_1
	o.set_w(CROUCH, 0)
	o.set_w(INPUT, 0)
	o.set_w(HEADING, o.w(FACING))


func player_think_idle_1(_o: Actor) -> void:
	pass


## referee_think_idle: the referee's think when he only stands.
func referee_think_idle(o: Actor) -> void:
	o.think = referee_think_idle_1
	referee_think_idle_1(o)


func referee_think_idle_1(o: Actor) -> void:
	o.set_w(INPUT, 0)
	o.set_w(HEADING, o.w(FACING))


## referee_stand: the referee stands (action 0, frames 0-3 every
## 32 frames).
func referee_stand(o: Actor) -> void:
	o.update = referee_stand_1
	o.set_w(ACTION, 0)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 0x20)
	_stop(o)
	referee_stand_1(o)


func referee_stand_1(o: Actor) -> void:
	_anim(o, 0x20, 3, true)


## referee_toss_coin: the referee tosses the coin (action 3,
## facing down, a frame every 6; SFX 93 on frame 6; it holds frame 15).
func referee_toss_coin(o: Actor) -> void:
	o.update = referee_toss_coin_1
	o.set_w(ACTION, 3)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 6)
	o.set_w(FACING, 0x20)
	_stop(o)
	referee_toss_coin_1(o)


func referee_toss_coin_1(o: Actor) -> void:
	o.add_w(TIMER, -1)
	if o.w(TIMER) != 0:
		return
	o.set_w(TIMER, 6)
	o.add_w(ANIM_FRAME, 1)
	if o.w(ANIM_FRAME) == 6:
		_sfx(93)
	if o.sw(ANIM_FRAME) > 0xF:
		o.set_w(ANIM_FRAME, 0xF)


## coin_hold: the coin (g_director) still in the referee's hand.
func coin_hold(o: ISSMenu.Obj) -> void:
	o.update = coin_hold_1
	o.set_l(SPEED, 0)
	o.set_l(VEL_X, 0)
	o.set_l(VEL_Y, 0)


func coin_hold_1(_o: ISSMenu.Obj) -> void:
	pass


## coin_toss: the coin tossed: 32 frames on it flies up (vz
## 2.25, gravity 3/32), spinning a frame every 4, and is gone after 80.
func coin_toss(o: ISSMenu.Obj) -> void:
	o.update = coin_toss_1
	o.set_w(TIMER, 4)
	o.set_w(DISTANCE, 0x50)
	o.set_l(VEL_Z, 0)
	o.set_l(SPEED, 0)
	o.set_l(VEL_X, 0)
	o.set_l(VEL_Y, 0)
	coin_toss_1(o)


func coin_toss_1(o: ISSMenu.Obj) -> void:
	o.set_w(DISTANCE, o.w(DISTANCE) - 1)
	if o.w(DISTANCE) == 0:
		m.obj_free(o)
		return
	if o.w(DISTANCE) == 0x30:
		o.set_w(Y, o.w(Y) + 2)
		o.set_l(VEL_Z, 0x24000)
	if o.sw(DISTANCE) >= 0x30:
		return
	o.set_w(TIMER, o.w(TIMER) - 1)
	if o.w(TIMER) == 0:
		o.set_w(TIMER, 4)
		o.set_w(ANIM_FRAME, (o.w(ANIM_FRAME) + 1) & 3)
	var vz := (o.l(VEL_Z) - 0x1800) & 0xFFFFFFFF
	o.set_l(VEL_Z, vz)
	o.set_l(Z, (o.l(Z) + vz) & 0xFFFFFFFF)


## confetti_fall: a piece of confetti (action 4 or 5 at random)
## turning every 16 frames and falling a quarter pixel a frame.
func confetti_fall(o: ISSMenu.Obj) -> void:
	o.update = confetti_fall_1
	o.set_w(ACTION, (_rand() & 1) + 4)
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, 0x10)
	confetti_fall_1(o)


func confetti_fall_1(o: ISSMenu.Obj) -> void:
	o.set_w(TIMER, o.w(TIMER) - 1)
	if o.w(TIMER) == 0:
		o.set_w(TIMER, 0x10)
		o.set_w(ANIM_FRAME, o.w(ANIM_FRAME) ^ 1)
	o.set_l(Z, (o.l(Z) - 0x4000) & 0xFFFFFFFF)


## The crowd's flags (flag_fans_draw's figures): action 0 stand (8 frames
## every 11), 1 ready (8 frames every 11), 2 and 3 waving (3 frames every
## 9).
func _fans_start(o: ISSMenu.Obj, update: Callable, action: int, timer: int) -> void:
	o.update = update
	o.set_w(ANIM_FRAME, 0)
	o.set_w(TIMER, timer)
	o.set_l(SPEED, 0)
	o.set_l(VEL_Z, 0)
	o.set_w(ACTION, action)
	update.call(o)


func _fans_step(o: ISSMenu.Obj, n: int, last: int) -> void:
	o.set_w(TIMER, o.w(TIMER) + 1)
	if o.sw(TIMER) <= n:
		return
	o.set_w(TIMER, 0)
	o.set_w(ANIM_FRAME, o.w(ANIM_FRAME) + 1)
	if o.sw(ANIM_FRAME) > last:
		o.set_w(ANIM_FRAME, 0)


func flag_fan_hold(o: ISSMenu.Obj) -> void:
	_fans_start(o, flag_fan_hold_1, 0, 0)


func flag_fan_hold_1(o: ISSMenu.Obj) -> void:
	_fans_step(o, 0xA, 7)


func flag_fan_raise(o: ISSMenu.Obj) -> void:
	_fans_start(o, flag_fan_raise_1, 1, 0x20)


func flag_fan_raise_1(o: ISSMenu.Obj) -> void:
	_fans_step(o, 0xA, 7)


func flag_fan_wave(o: ISSMenu.Obj) -> void:
	_fans_start(o, flag_fan_wave_1, 2, 0)


func flag_fan_wave_1(o: ISSMenu.Obj) -> void:
	_fans_step(o, 8, 2)


func flag_fan_wave_2(o: ISSMenu.Obj) -> void:
	_fans_start(o, flag_fan_wave_2_1, 3, 0x20)


func flag_fan_wave_2_1(o: ISSMenu.Obj) -> void:
	_fans_step(o, 8, 2)


## A sprite-list draw (flag_fans_draw, particle_draw): the table's piece
## for obj_action and obj_anim_frame, its tile after obj_vram's, at the
## object's screen position.
func _piece_draw(o: ISSMenu.Obj, table: String) -> void:
	if o.b(VISIBLE) == 0xFF:
		return
	var t := ISSRom.u32(ISSRom.addr(table) + o.w(ACTION) * 4)
	var p := ISSRom.u32(t + o.w(ANIM_FRAME) * 4)
	var tile := o.w(0x78) >> 5
	m.sprite(o.sw(SCREEN_Y) + ISSRom.s16(p), ISSRom.u16(p + 2), tile + ISSRom.u16(p + 4),
		o.sw(SCREEN_X) + ISSRom.s16(p + 6))


func flag_fans_draw(o: ISSMenu.Obj) -> void:
	_piece_draw(o, "flag_fans_draw_data")


func particle_draw(o: ISSMenu.Obj) -> void:
	_piece_draw(o, "particle_draw_data")


# --------------------------------------------------------------------------
# Drawing (player_draw, obj_set_frame_draw_draw, npc_draw, ball_draw).

## The figure for an actor: kind "player", "keeper", "referee" or "ball"
## (with the team's look for players).
func give_figure(o: Actor, kind: String, team := 0) -> void:
	var n: Node2D
	match kind:
		"player":
			var p := ISSPlayerSprite.new()
			p.team = team
			n = p
			o.draw = _draw_player
		"keeper":
			var k := ISSKeeperSprite.new()
			k.team = team
			n = k
			o.draw = _draw_keeper
		"referee":
			n = ISSNPCSprite.new()
			o.draw = _draw_referee
		_:
			n = ISSBallSprite.new()
			o.draw = _draw_ball
	o.node = n
	n.visible = false
	(parent if parent != null else m.figures).add_child(n)
	if kind == "player":
		(n as ISSPlayerSprite).set_look(team, false, maxi(1, o.b(0x63)), o.b(0x64))


## Depth: objects_draw_menu draws the deepest first, so it is on top.
func _place(o: Actor) -> void:
	var f := ISSRam.w(S.g_frame_counter)
	if f != _draw_frame:
		_draw_frame = f
		_draw_order = 0
	_draw_order += 1
	o.node.z_index = 100 - _draw_order
	o.node.visible = o.b(VISIBLE) != 0xFF
	o.node.position = Vector2(o.sw(SCREEN_X), o.sw(SCREEN_Y))
	if parent is Control:
		o.node.position -= (parent as Control).position
	if o.cram != m.vdp.cram:
		o.cram = m.vdp.cram.duplicate()
		if o.node.has_method("set_palette_cram"):
			var line := (o.w(ATTR) >> 13) & 3
			if o.w(ATTR) & 0x20:
				# tbl_sprite_attr_right's second row: line 0's pieces on line 1.
				line = 1
			o.node.call("set_palette_cram", o.cram, line)


func _draw_player(o: ISSMenu.Obj) -> void:
	var a := o as Actor
	_place(a)
	(a.node as ISSPlayerSprite).set_pose(a.w(ACTION), a.w(ANIM_FRAME), a.w(FACING), true)


func _draw_keeper(o: ISSMenu.Obj) -> void:
	var a := o as Actor
	_place(a)
	(a.node as ISSKeeperSprite).set_pose(a.w(ACTION), a.w(ANIM_FRAME), a.w(FACING), true)


func _draw_referee(o: ISSMenu.Obj) -> void:
	var a := o as Actor
	_place(a)
	(a.node as ISSNPCSprite).set_pose(a.w(ACTION), a.w(ANIM_FRAME), a.w(FACING))


func _draw_ball(o: ISSMenu.Obj) -> void:
	var a := o as Actor
	_place(a)
	var b := a.node as ISSBallSprite
	b.position.y += a.sw(Z)
	b.height = a.sw(Z)
	b.facing = a.w(FACING)
	b.spin = a.w(ANIM_FRAME) & 3
