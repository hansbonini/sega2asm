class_name ISSInput
extends RefCounted
## Controllers as the Mega Drive's 6-button pad (joypad_read_port packs U D
## L R B C A Start and Z Y X Mode), mapped to the logical buttons through the
## controller's button layout (tbl_button_layouts, chosen on the key
## configuration screen): pass $10, lofted (high ball) $20, dash $40 and
## shoot $100; Y switches player ($200), Mode picks strategies ($800). The
## default layout puts dash on A, pass on B, high ball on C and shot on Z.
## In the menus C confirms and B cancels, as the screens say.
##
##   Player 1: arrows; Z X C = A B C; A S D = X Y Z; Q Mode; Enter Start.
##   Player 2: I J K L; V B N = A B C; F G H = X Y Z; R Mode; Backspace Start.
##   Joypads: X = A, A = B, B = C, LB = X, Y = Y, RB = Z, Back = Mode, Start;
##   the right trigger is A too.

const UP := 0x1
const DOWN := 0x2
const LEFT := 0x4
const RIGHT := 0x8
const B := 0x10
const C := 0x20
const A := 0x40
const START := 0x80
const Z := 0x100
const Y := 0x200
const X := 0x400
const MODE := 0x800

const BITS := {"up": UP, "down": DOWN, "left": LEFT, "right": RIGHT, "b": B, "c": C, "a": A,
	"start": START, "z": Z, "y": Y, "x": X, "mode": MODE}
const KEYS := [
	{"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "a": KEY_Z, "b": KEY_X,
		"c": KEY_C, "x": KEY_A, "y": KEY_S, "z": KEY_D, "mode": KEY_Q, "start": KEY_ENTER},
	{"up": KEY_I, "down": KEY_K, "left": KEY_J, "right": KEY_L, "a": KEY_V, "b": KEY_B,
		"c": KEY_N, "x": KEY_F, "y": KEY_G, "z": KEY_H, "mode": KEY_R, "start": KEY_BACKSPACE},
]
const PAD_BUTTONS := {"a": JOY_BUTTON_X, "b": JOY_BUTTON_A, "c": JOY_BUTTON_B,
	"x": JOY_BUTTON_LEFT_SHOULDER, "y": JOY_BUTTON_Y, "z": JOY_BUTTON_RIGHT_SHOULDER,
	"mode": JOY_BUTTON_BACK, "start": JOY_BUTTON_START,
	"up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN, "left": JOY_BUTTON_DPAD_LEFT,
	"right": JOY_BUTTON_DPAD_RIGHT}

## Each controller's button layout (g_control_slots + $18 / 16), 0-23.
static var layouts := [0, 0, 0, 0, 0, 0, 0, 0]
static var _prev := [0, 0, 0, 0, 0, 0, 0, 0]


static func action(player: int, name: String) -> StringName:
	return StringName("iss_p%d_%s" % [player + 1, name])


## Register the input actions once.
static func ensure_actions() -> void:
	if InputMap.has_action(action(0, "b")):
		return
	for p in 2:
		for name: String in KEYS[p]:
			var act := action(p, name)
			InputMap.add_action(act, 0.4)
			var k := InputEventKey.new()
			k.physical_keycode = KEYS[p][name]
			InputMap.action_add_event(act, k)
			var b := InputEventJoypadButton.new()
			b.device = p
			b.button_index = PAD_BUTTONS[name]
			InputMap.action_add_event(act, b)
		for axis in [["left", JOY_AXIS_LEFT_X, -1.0], ["right", JOY_AXIS_LEFT_X, 1.0],
				["up", JOY_AXIS_LEFT_Y, -1.0], ["down", JOY_AXIS_LEFT_Y, 1.0]]:
			var m := InputEventJoypadMotion.new()
			m.device = p
			m.axis = axis[1]
			m.axis_value = axis[2]
			InputMap.action_add_event(action(p, axis[0]), m)
		var t := InputEventJoypadMotion.new()
		t.device = p
		t.axis = JOY_AXIS_TRIGGER_RIGHT
		t.axis_value = 1.0
		InputMap.action_add_event(action(p, "a"), t)


## The pad's buttons held, as joypad_read_port packs them.
static func raw(player: int) -> int:
	var bits := 0
	for name: String in BITS:
		if Input.is_action_pressed(action(player, name)):
			bits |= BITS[name]
	return bits


## The logical buttons for the B / C / A / Z held (match_players_update).
static func logical(bits: int, layout: int) -> int:
	ISSMatchData.ensure_loaded()
	var combo := (1 if bits & B else 0) | (2 if bits & C else 0) | (4 if bits & A else 0) | (8 if bits & Z else 0)
	var l: Array = ISSMatchData.consts["controls"]["layouts"][clampi(layout, 0, 23)]
	var out := int(l[combo])
	if bits & Y:
		out |= ISSFootballer.SWITCH
	if bits & MODE:
		out |= ISSFootballer.STRATEGY
	return out


## The pad state for the engine: {"dir": -1 or 0-63, "press": logical bits
## newly down, "held": logical bits, "raw": buttons held, "raw_press":
## buttons newly down}. Call once a frame per player.
static func read(player: int) -> Dictionary:
	var bits := raw(player)
	var dir := -1
	var v := Vector2(
		Input.get_action_strength(action(player, "right")) - Input.get_action_strength(action(player, "left")),
		Input.get_action_strength(action(player, "down")) - Input.get_action_strength(action(player, "up")))
	if v.length() > 0.3:
		# 8 directions, 0 = up (-y), 16 = right.
		dir = (roundi(atan2(v.x, -v.y) / TAU * 8.0) * 8) & 63
	var prev: int = _prev[player]
	_prev[player] = bits
	var layout: int = layouts[player]
	var held := logical(bits, layout)
	var before := logical(prev, layout)
	return {"dir": dir, "press": held & ~before, "held": held, "raw": bits, "raw_press": bits & ~prev}


static func start_pressed(player: int) -> bool:
	return Input.is_action_just_pressed(action(player, "start"))
