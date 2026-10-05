class_name ISSTeam
extends RefCounted
## One side's match state (struct team, g_team_home_info / g_team_away_info)
## and its AI: the three formation lines, the team analysis refreshed in the
## player's AI slot (nearest / second nearest to where the ball will land,
## front, back, cover) and the per-player decisions of player_ai, keeper_ai
## and ai_carrier. Decisions run once every 16 frames per player (g_ai_slot);
## steering toward the chosen target runs every frame.

enum AI { FORMATION, CHASE, PRESS, CARRY, KEEPER, RUSH, SET_PIECE, WAIT, RUN, MARK }

var eng: ISSMatchEngine
var side := 0
var team_id := 0
var name := ""
var players: Array[ISSFootballer] = []
var bench: Array = []
var formation := 1
var layout: Array = []
var kickoff_layout: Array = []
var ratings: Array = [0, 0, 0, 0, 0]
var ai_level := 2
var keeper_skill := 2
var second_kit := false
## Pads controlling this team (0 = CPU).
var pads := 0
var controlled: ISSFootballer = null

## X of the attack, midfield and defence lines (tm_lines).
var lines := [0.0, 0.0, 0.0]
var nearest: ISSFootballer
var second: ISSFootballer
var front: ISSFootballer
var back: ISSFootballer
var cover: ISSFootballer

## tm_strategy (-1 = none) and tm_strategy_run (the run of strategies 1 and
## 2); the four strategies a human assigned to dash, pass, lofted and shoot
## ($184C: Mode + button selects one).
var strategy := -1
var strategy_run := -1
var strategy_slots := [-1, -1, -1, -1]

## Substitutions left (screen_select_squad: up to 3).
var subs_left := 3

## tm_keeper_manual (+$10, key configuration KEEPER): 0 AUTO (the computer
## plays the goalkeeper; a pad only while he holds the ball), 1 SEMI-AUTO
## (Mode + Y gives him to the pad until changed), 2 MANUAL (the same, and
## without a pad he only keeps his place: no rushing out or diving).
var keeper_mode := 0

## Handicap (screen_handicap): tm_condition 0-4 or 5 random, and tm_players
## (players on the pitch - 7, a sending-off takes one off).
var condition := 5
var on_pitch := 11

var score := 0
var stats := {"shots": 0, "fouls": 0, "corners": 0, "free_kicks": 0, "penalties": 0,
	"offsides": 0, "yellow": 0, "red": 0, "goals": 0, "possession": 0}


func setup(engine: ISSMatchEngine, s: int, team: int, level: int, kit2: bool, formation_override := -1) -> void:
	eng = engine
	side = s
	team_id = team
	ai_level = level
	keeper_skill = level
	second_kit = kit2
	var t: Dictionary = ISSMatchData.teams[team]
	name = t["name"]
	ratings = t["ratings"]
	formation = int(t["formation"])
	layout = t["layout"]
	if formation_override >= 0 and formation_override != formation:
		# Another formation from the pre-match menu: the generic layout
		# (tbl_formations) instead of the team's tuned copy.
		formation = formation_override
		layout = ISSMatchData.formations[formation]["layout"]
	kickoff_layout = ISSMatchData.formations[formation]["kickoff"]
	var squad: Array = t["players"]
	var picked: Array = engine.options.get("squads", [[], []])[s]
	if not picked.is_empty():
		squad = _squad_from(squad, picked)
	for i in squad.size():
		var rec: Dictionary = squad[i]
		if i >= 11:
			rec = rec.duplicate()
			if not rec.has("energy"):
				rec["energy"] = condition_energy()
			if not rec.has("ram") and not picked.is_empty():
				rec["ram"] = i
			bench.append(rec)
			continue
		var p := ISSFootballer.new()
		p.eng = engine
		p.team = side
		p.index = i
		p.name = rec["name"]
		p.number = int(rec["number"])
		p.hair = int(rec["hair"])
		p.position = ["forward", "midfielder", "defender", "goalkeeper", "attacking type 4", "defensive type 5"].find(rec["position"])
		p.attr = rec["attributes"]
		p.energy = int(rec["energy"]) if rec.has("energy") else condition_energy()
		# A place from the front end (ISSMatchSetup), else the layout's (the
		# records' own "slot" is their squad index).
		var slot: Dictionary = rec["slot"] if rec.get("slot") is Dictionary else layout[i]
		p.role = ["attack", "midfield", "defence", "goalkeeper"].find(slot["role"])
		p.form = Vector2(int(slot["form_x"]), int(slot["form_y"]))
		p.mark = int(rec.get("mark", -1))
		p.ram_slot = int(rec.get("ram", -1))
		p.record = int(rec.get("index", i))
		p.status = int(rec.get("status", 0))
		p.booked = p.status & 0x80 != 0
		if i == 0:
			p.ai_mode = AI.KEEPER
		players.append(p)


## The squad as the front end left it in RAM (ISSMatchSetup): the players
## in their order there, each with the record (attributes possibly edited),
## energy and place in the formation it holds.
static func _squad_from(team_players: Array, picked: Array) -> Array:
	var out := []
	for e: Dictionary in picked:
		var rec: Dictionary = team_players[int(e["index"])].duplicate()
		rec["attributes"] = e["attributes"]
		rec["number"] = e["number"]
		rec["hair"] = e["hair"]
		rec["position"] = e["position"]
		rec["energy"] = e["energy"]
		rec["mark"] = e.get("mark", -1)
		rec["slot"] = e.get("slot", rec.get("slot"))
		for k in ["index", "ram", "status", "off"]:
			if e.has(k):
				rec[k] = e[k]
		out.append(rec)
	return out


## Send bench player bench_index on for the player at pitch index i; he
## takes over the place in the formation. False if not allowed.
func substitute(i: int, bench_index: int) -> bool:
	if subs_left <= 0 or bench_index < 0 or bench_index >= bench.size() or i < 0 or i >= players.size():
		return false
	var p := players[i]
	if p.state == ISSFootballer.S.SENT_OFF or eng.ball.owner == p:
		return false
	var rec: Dictionary = bench[bench_index]
	# The two change places (screen_select_squad swaps the objects' records):
	# the player coming off takes the substitute's place on the bench.
	var out := {"name": p.name, "number": p.number, "hair": p.hair, "attributes": p.attr,
		"position": ["forward", "midfielder", "defender", "goalkeeper", "attacking type 4", "defensive type 5"][clampi(p.position, 0, 5)],
		"energy": p.energy, "index": p.record, "status": p.status, "ram": int(rec.get("ram", -1)), "used": true}
	bench[bench_index] = out
	p.record = int(rec.get("index", p.record))
	p.status = int(rec.get("status", 0))
	p.name = rec["name"]
	p.number = int(rec["number"])
	p.hair = int(rec["hair"])
	p.position = ["forward", "midfielder", "defender", "goalkeeper", "attacking type 4", "defensive type 5"].find(rec["position"])
	p.attr = rec["attributes"]
	p.energy = int(rec.get("energy", condition_energy()))
	p.energy_ticks = 256
	p.booked = p.status & 0x80 != 0
	subs_left -= 1
	return true


## rules_func_014D8A: each player's starting energy is the condition, or
## (condition 5, the default) one of 1, 2, 2, 3, 3, 3, 4, 4 at random.
func condition_energy() -> int:
	if condition < 5:
		return condition
	return [1, 2, 2, 3, 3, 3, 4, 4][randi() % 8]


func dir() -> float:
	return eng.attack_dir(side)


func has_ball() -> bool:
	return eng.ball.owner != null and eng.ball.owner.team == side


func opponents() -> ISSTeam:
	return eng.teams[1 - side]


func active() -> Array[ISSFootballer]:
	var out: Array[ISSFootballer] = []
	for p in players:
		if p.state != ISSFootballer.S.SENT_OFF:
			out.append(p)
	return out


# ---------------------------------------------------------------------------
# Team analysis (match_players_update, in each player's slot).

func analyse() -> void:
	var target: Vector2 = eng.ball_target()
	var best := INF
	var best2 := INF
	nearest = null
	second = null
	front = null
	back = null
	cover = null
	var d := dir()
	for p in active():
		if p.is_keeper():
			continue
		var dist := (p.pos - target).length()
		if p.busy() and p.state != ISSFootballer.S.KICK:
			dist += 200.0
		if dist < best:
			best2 = best
			second = nearest
			best = dist
			nearest = p
		elif dist < best2:
			best2 = dist
			second = p
		if front == null or (p.pos.x - front.pos.x) * d > 0.0:
			front = p
		if back == null or (p.pos.x - back.pos.x) * d < 0.0:
			back = p
		# Covering: goal-side of the ball, closest to the line ball -> own goal.
		if (target.x - p.pos.x) * d > 0.0:
			if cover == null or absf(p.pos.y - target.y) < absf(cover.pos.y - target.y):
				cover = p


## One formation line per call, in the order of g_ai_slot & 3 (2, 2, 1, 0).
func update_line(role: int) -> void:
	var c: Dictionary = ISSMatchData.consts["team_lines"]
	var own := eng.ball.team == side
	var r: Array = (c["own_ball"] if own else c["their_ball"])[role]
	var rect := eng.rect
	var mid_x := rect.get_center().x
	var ball_x := eng.ball.pos.x
	var t := eng.ball_target().x
	if not eng.ball.live or eng.restart_type != ISSMatchEngine.R.NONE:
		t = eng.restart_pos.x + (512.0 if eng.left_goal_team == eng.ball.team else -512.0)
	var d := dir()
	var old: float = lines[role]
	var v: float = old
	if d > 0.0:
		v = clampf(v, t + r[0], t + r[1])
		match role:
			2:
				var lim := minf(rect.position.x + 384.0, ball_x)
				if lim > v:
					v = lim
					if not own and v > old:
						v = old
				v = clampf(v, rect.position.x + 64.0, mid_x - 128.0)
			1:
				v = minf(v, lines[0] - 384.0)
				v = maxf(v, lines[2] + 384.0)
			0:
				v = maxf(v, mid_x)
				var lim := maxf(rect.end.x - 384.0, ball_x) - 32.0
				if v > lim:
					v = maxf(lim, old)
				v = clampf(v, mid_x, rect.end.x - 64.0)
	else:
		v = clampf(v, t - r[1], t - r[0])
		match role:
			2:
				var lim := maxf(rect.end.x - 384.0, ball_x)
				if lim < v:
					v = lim
					if not own and v < old:
						v = old
				v = clampf(v, mid_x + 128.0, rect.end.x - 64.0)
			1:
				v = maxf(v, lines[0] + 384.0)
				v = minf(v, lines[2] - 384.0)
			0:
				v = minf(v, mid_x)
				var lim := minf(rect.position.x + 384.0, ball_x) + 32.0
				if v < lim:
					v = minf(lim, old)
				v = clampf(v, rect.position.x + 64.0, mid_x)
	lines[role] = v


## tbl_team_strategies: strategies 0, 3, 4, 5 and 7 set the lines from the
## ball each frame, 1 and 2 send a player on a run, 6 (zone press) changes
## how close the pressing players go.
func apply_strategy() -> void:
	if strategy < 0:
		return
	var r := eng.rect
	var bx := eng.ball.pos.x
	var own := eng.ball.team == side
	var d := dir()
	var mx := r.get_center().x
	# Positions measured from the goal this side attacks (+1) or defends.
	var far := maxf(r.end.x - 384.0, bx) if d > 0.0 else minf(r.position.x + 384.0, bx)
	var near := minf(r.position.x + 384.0, bx) if d > 0.0 else maxf(r.end.x - 384.0, bx)
	match strategy:
		0: # all out attack
			lines[0] = far
			lines[1] = far - 256.0 * d
			if own:
				lines[2] = far - 512.0 * d
		3: # counter attack
			lines[0] = far
			lines[1] = far - 256.0 * d
			lines[2] = (r.position.x + 384.0) if d > 0.0 else (r.end.x - 384.0)
		4: # all out defence
			lines[2] = near
			lines[1] = near + 256.0 * d
			if not own:
				lines[0] = near + 512.0 * d
		5: # press up: the defence no further back than the ball
			lines[2] = maxf(lines[2], near) if d > 0.0 else minf(lines[2], near)
		7: # offside trap: everybody up to the halfway line
			if not own:
				lines[0] = mx + 192.0 * d
				lines[1] = mx
				lines[2] = mx - 192.0 * d
		1, 2: # push along the centre / the wings: one player runs forward
			if own and strategy_run < 0:
				_start_run(strategy)


func _start_run(kind: int) -> void:
	var order := []
	if kind == 1 and second != null:
		order.append(second)
	for i in range(10, 0, -1):
		order.append(players[i])
	for p: ISSFootballer in order:
		if p.human or p.busy() or p.state == ISSFootballer.S.SENT_OFF or eng.ball.owner == p:
			continue
		var goal := their_goal()
		var mid_y := eng.rect.get_center().y
		if kind == 1:
			p.ai_target = Vector2(goal.x - dir() * 200.0, mid_y + (p.pos.y - mid_y) * 0.3)
		else:
			p.ai_target = Vector2(goal.x - dir() * 160.0, mid_y + (360.0 if p.pos.y > mid_y else -360.0))
		p.ai_mode = AI.RUN
		strategy_run = kind
		return


func reset_lines() -> void:
	var mid_x := eng.rect.get_center().x
	var d := dir()
	lines = [mid_x + d * 32.0, mid_x - d * 256.0, mid_x - d * 544.0]


## The player's place in the formation (player_ai step 4).
func home_position(p: ISSFootballer) -> Vector2:
	var rect := eng.rect
	var mid := rect.get_center()
	var d := dir()
	var in_possession := has_ball()
	var x: float = lines[clampi(p.role, 0, 2)] + p.form.x * 8.0 * d
	var y := mid.y + p.form.y * (10.0 if in_possession else 8.0)
	# Nobody runs past the opponents' last defender minus 32 px.
	var ob := opponents().back
	if ob != null:
		var limit := ob.pos.x - 32.0 * d
		if (x - limit) * d > 0.0 and (eng.ball.pos.x - limit) * d < 0.0:
			x = limit
	return Vector2(clampf(x, rect.position.x + 32.0, rect.end.x - 32.0), clampf(y, rect.position.y + 24.0, rect.end.y - 24.0))


func own_goal() -> Vector2:
	return eng.goal_center(side)


func their_goal() -> Vector2:
	return eng.goal_center(1 - side)


static func chance(mask: int) -> bool:
	return (randi() & mask) == 0


# ---------------------------------------------------------------------------
# Decisions (every 16 frames per player).

func think(p: ISSFootballer) -> void:
	if p.busy():
		return
	if p.is_keeper():
		_keeper_think(p)
		return
	var b := eng.ball
	if b.owner == p:
		p.ai_mode = AI.CARRY
		_carrier_think(p)
		return
	if not b.live or eng.restart_type != ISSMatchEngine.R.NONE:
		p.ai_mode = AI.FORMATION
		return
	if p.ai_mode == AI.RUN and has_ball() and b.owner != p:
		return # still on the strategy's run
	if p.ai_mode == AI.MARK and b.is_loose():
		# player_ai_mark: a loose ball sends the marker after it.
		p.ai_mode = AI.CHASE
		return
	if b.is_loose() and p == nearest:
		p.ai_mode = AI.CHASE
	elif b.owner != null and b.owner.team != side and (p == nearest or (p == second and (p != cover or strategy == 6))):
		p.ai_mode = AI.PRESS
	else:
		p.ai_mode = AI.FORMATION
	# Man-marking overrides pressing while anyone has the ball, unless the
	# opponent he marks is off the pitch.
	if b.owner != null and p.mark > 0 and p.mark < opponents().players.size():
		var o := opponents().players[p.mark]
		if o.state != ISSFootballer.S.SENT_OFF:
			p.ai_mode = AI.MARK
			_mark_target(p, o)


## player_ai_mark_1: 24 px from the marked opponent toward the line from
## the marker to the middle of his own goal line (goal side of him).
func _mark_target(p: ISSFootballer, o: ISSFootballer) -> void:
	var h := int(ISSFootballer.heading_to(p.pos, own_goal())) & 63
	var a := h * TAU / 64.0
	p.ai_target = o.pos + Vector2(sin(a), -cos(a)) * 24.0


## Steering every frame: turns ai_target into input_dir and dash.
func steer(p: ISSFootballer) -> void:
	if eng.shootout:
		# Shoot-out: everybody waits where they were put.
		p.input_dir = -1
		p.held = 0
		return
	if p.busy() and p.state != ISSFootballer.S.KEEPER_HOLD:
		p.input_dir = -1
		p.held = 0
		return
	var b := eng.ball
	if p.is_keeper() and b.owner != p:
		_keeper_steer(p)
		return
	if b.owner == p and p.ai_mode != AI.CARRY and p.state == ISSFootballer.S.MOVE:
		p.ai_mode = AI.CARRY
		_carrier_think(p)
		if p.busy():
			return
	var target := p.ai_target
	var dash := false
	match p.ai_mode:
		AI.FORMATION:
			target = home_position(p)
			if eng.restart_type != ISSMatchEngine.R.NONE:
				target = eng.restart_place(p)
			dash = (target - p.pos).length() > 160.0
		AI.CHASE, AI.RUSH:
			var land: Array = b.landing()
			target = land[0] if b.z > 12.0 else b.predict(4)
			dash = (target - p.pos).length() > 32.0
			# Head or volley a ball arriving at head height.
			if b.is_loose() and b.z > 16.0 and b.z < 60.0 and (b.pos - p.pos).length() < 22.0 and b.kicker != p:
				var near_goal := absf(their_goal().x - p.pos.x) < 360.0
				p.press |= ISSFootballer.SHOOT if near_goal else ISSFootballer.PASS
				p.input_dir = int(ISSFootballer.heading_to(p.pos, their_goal())) & 63
		AI.PRESS:
			if b.owner == null or b.owner.team == side:
				p.ai_mode = AI.FORMATION
				return
			target = b.pos + b.owner.pos.direction_to(b.pos) * 2.0
			var dist := (target - p.pos).length()
			dash = dist > 24.0
			# Tackle: slide in when close and facing the ball.
			if dist < 22.0 and absf(ISSFootballer.angle_diff(ISSFootballer.heading_to(p.pos, b.pos), p.facing)) < 6.0:
				var press_delay: int = ISSMatchData.consts["press_intensity"][clampi(ai_level, 0, 5)]
				# Zone press (strategy 6) closes in harder.
				var odds := 40 + press_delay * 2
				if strategy == 6:
					odds /= 2
				if randi() % odds == 0:
					p.press |= ISSFootballer.LOFT
		AI.MARK:
			# Walk (no dash) and stand once within 16 px (|dx| + |dy|).
			target = p.ai_target
			var off := target - p.pos
			if absf(off.x) + absf(off.y) < 16.0:
				p.input_dir = -1
				p.held = 0
				return
		AI.CARRY:
			if b.owner != p:
				p.ai_mode = AI.FORMATION
				return
			target = p.ai_target
			dash = p.ai_dash
		AI.RUN:
			target = p.ai_target
			dash = true
			if not has_ball() or (target - p.pos).length() < 24.0:
				p.ai_mode = AI.FORMATION
				strategy_run = -1
		AI.KEEPER:
			target = _keeper_spot(p)
			if keeper_mode != 2:
				_keeper_save(p)
		AI.SET_PIECE, AI.WAIT:
			p.input_dir = -1
			p.held = 0
			return
	if p.ai_mode == AI.CARRY:
		target = target.clamp(eng.rect.position + Vector2(40, 40), eng.rect.end - Vector2(40, 40))
	else:
		target = target.clamp(eng.rect.position - Vector2(40, 40), eng.rect.end + Vector2(40, 40))
	var d := target - p.pos
	if d.length() > 4.0:
		p.input_dir = int(roundf(ISSFootballer.heading_to(p.pos, target))) & 63
	else:
		p.input_dir = -1
	p.held = ISSFootballer.DASH if dash else 0


# ---------------------------------------------------------------------------
# With the ball (ai_carrier).

func _carrier_think(p: ISSFootballer) -> void:
	p.ai_turns += 1
	var goal := their_goal()
	var to_goal := absf(goal.x - p.pos.x)
	var mid_y := eng.rect.get_center().y
	var challenged := _challenger(p) != null
	if to_goal < 320.0 and absf(p.pos.y - mid_y) < 170.0:
		_shoot(p)
	elif to_goal < 300.0:
		_cross(p)
	elif challenged:
		if chance(int(ratings[0])) or p.ai_turns > 3:
			if not _pass(p):
				_sidestep(p)
		else:
			_sidestep(p)
	elif p.ai_turns >= 12 or (p.ai_turns > 3 and randi() % 5 == 0):
		if chance(int(ratings[4])):
			if not _long_ball(p):
				_pass(p)
		elif not _pass(p):
			_dribble(p, goal)
	else:
		_dribble(p, goal)


func _challenger(p: ISSFootballer) -> ISSFootballer:
	for o in opponents().active():
		var off := o.pos - p.pos
		if off.length() < 48.0 and absf(ISSFootballer.angle_diff(ISSFootballer.heading_to(p.pos, o.pos), p.facing)) < 14.0:
			return o
	return null


func _dribble(p: ISSFootballer, goal: Vector2) -> void:
	var mid_y := eng.rect.get_center().y
	var aim := goal
	if not chance(int(ratings[3])):
		# Toward the near wing.
		var wing := mid_y + (320.0 if p.pos.y > mid_y else -320.0)
		aim = Vector2(goal.x, clampf(p.pos.y, mid_y - 360.0, mid_y + 360.0))
		aim.y = lerpf(aim.y, wing, 0.5)
	p.ai_target = p.pos + (aim - p.pos).normalized() * 160.0
	p.ai_dash = randi() % 3 != 0


func _sidestep(p: ISSFootballer) -> void:
	var side_step := 12.0 if randi() % 2 == 0 else -12.0
	var h := p.facing + side_step
	p.ai_target = p.pos + ISSProjection.heading_vector(int(h) & 63) * 96.0
	p.ai_dash = chance(int(ratings[2]))


func _shoot(p: ISSFootballer) -> void:
	var goal := their_goal()
	# Aim inside a post; the error grows with the distance and falls with
	# shot power.
	var spread := 50.0 + (goal - p.pos).length() * (0.2 - 0.01 * float(p.a("shot_power")))
	var aim := goal + Vector2(0, (randf() * 2.0 - 1.0) * 70.0 + (randf() * 2.0 - 1.0) * spread)
	p.start_kick(ISSFootballer.K.SHOT, ISSFootballer.heading_to(p.pos, aim), null, 3 + randi() % 5)


func _cross(p: ISSFootballer) -> void:
	var goal := their_goal()
	var spot := Vector2(goal.x - dir() * (96.0 + randf() * 96.0), eng.rect.get_center().y + (randf() * 2.0 - 1.0) * 60.0)
	var mate := _best_mate(p, spot, 999.0)
	if mate != null and randi() % 2 == 0:
		spot = mate.pos + Vector2(dir() * 24.0, 0)
	p.start_kick(ISSFootballer.K.LOFT, ISSFootballer.heading_to(p.pos, spot), mate, _lofted_power((spot - p.pos).length()))


## Pass to the best placed team-mate (ai_pass); false if nobody is free.
func _pass(p: ISSFootballer) -> bool:
	var mate := _best_mate(p, their_goal(), 420.0)
	if mate == null:
		return false
	var lead := mate.pos + ISSProjection.heading_vector(mate.facing) * mate.speed * 12.0
	var dist := (lead - p.pos).length()
	if dist < 230.0:
		p.start_kick(ISSFootballer.K.PASS, ISSFootballer.heading_to(p.pos, lead), mate)
	else:
		p.start_kick(ISSFootballer.K.LOFT, ISSFootballer.heading_to(p.pos, lead), mate, _lofted_power(dist))
	return true


## A long ball ahead of the front player (ai_long_ball).
func _long_ball(p: ISSFootballer) -> bool:
	if front == null or front == p:
		return false
	var spot := front.pos + Vector2(dir() * 96.0, 0)
	var dist := (spot - p.pos).length()
	if dist < 200.0 or dist > 850.0:
		return false
	p.start_kick(ISSFootballer.K.LOFT, ISSFootballer.heading_to(p.pos, spot), front, _lofted_power(dist))
	return true


func _lofted_power(dist: float) -> int:
	var travel: Array = ISSMatchData.kick("lofted_travel")
	for i in travel.size():
		if float(travel[i]) >= dist * 0.8:
			return i
	return travel.size() - 1


func _best_mate(p: ISSFootballer, goal: Vector2, max_dist: float) -> ISSFootballer:
	var best: ISSFootballer = null
	var best_score := -INF
	var d := dir()
	for m in active():
		if m == p or m.is_keeper() or m.busy():
			continue
		var off := m.pos - p.pos
		var dist := off.length()
		if dist < 48.0 or dist > max_dist:
			continue
		var free := INF
		for o in opponents().active():
			free = minf(free, (o.pos - m.pos).length())
			# Opponents close to the passing line.
			var t := clampf((o.pos - p.pos).dot(off) / (dist * dist), 0.0, 1.0)
			if (p.pos + off * t - o.pos).length() < 20.0:
				free = minf(free, 10.0)
		var score := off.x * d * 0.6 + minf(free, 120.0) * 1.5 - dist * 0.25
		if m.offside:
			score -= 400.0
		if score > best_score:
			best_score = score
			best = m
	return best


# ---------------------------------------------------------------------------
# Goalkeeper (keeper_ai, keeper_save, keeper_rush_out).

func _keeper_think(p: ISSFootballer) -> void:
	var b := eng.ball
	if p.state == ISSFootballer.S.KEEPER_HOLD:
		return
	if b.owner == p:
		# At his feet outside the area: clear it to a team-mate.
		if not _pass(p):
			p.start_kick(ISSFootballer.K.LOFT, 16.0 if dir() > 0.0 else 48.0, null, 7)
		return
	p.ai_mode = AI.KEEPER
	# MANUAL: without a pad he only keeps his place.
	if keeper_mode == 2:
		return
	if b.live and eng.restart_type == ISSMatchEngine.R.NONE and b.is_loose():
		var goal := own_goal()
		var land: Vector2 = b.landing()[0]
		if absf(land.x - goal.x) < 240.0 and absf(land.y - goal.y) < 200.0:
			var mine := (land - p.pos).length()
			var closest := true
			for o in opponents().active():
				if (o.pos - land).length() < mine - 16.0:
					closest = false
			if closest and (nearest == null or (nearest.pos - land).length() > mine):
				p.ai_mode = AI.RUSH
				if not eng.said_rush:
					eng.say(0x21)
					eng.said_rush = true


## Every frame: stay on the line (or rush out) and dive at shots.
func _keeper_steer(p: ISSFootballer) -> void:
	var b := eng.ball
	if p == eng.scripted_keeper and eng.pk_spot_wait > 0:
		# penalty_spot_keeper_1: still until the dive chosen in the view.
		p.input_dir = -1
		p.held = 0
		return
	var target := _keeper_spot(p)
	var dash := false
	if p.ai_mode == AI.RUSH and b.is_loose() and b.live:
		target = b.landing()[0] if b.z > 12.0 else b.predict(3)
		dash = true
	elif eng.restart_type != ISSMatchEngine.R.NONE:
		target = eng.restart_place(p)
	var shot := _incoming(p) if keeper_mode != 2 else []
	if not shot.is_empty():
		target = Vector2(p.pos.x, clampf(shot[1], own_goal().y - 90.0, own_goal().y + 90.0))
		dash = true
	if keeper_mode != 2:
		_keeper_save(p)
	if p.busy():
		return
	var d := target - p.pos
	p.input_dir = int(roundf(ISSFootballer.heading_to(p.pos, target))) & 63 if d.length() > 3.0 else -1
	p.held = ISSFootballer.DASH if dash or d.length() > 24.0 else 0
	if p.input_dir < 0:
		# Face the ball while waiting.
		p.facing = int(ISSFootballer.heading_to(p.pos, b.pos)) & 63


## 32 px in front of the goal line, on the line from the goal centre to the ball.
func _keeper_spot(p: ISSFootballer) -> Vector2:
	var goal := own_goal()
	var d := dir()
	var b := eng.ball.pos
	var dx := maxf(32.0, absf(b.x - goal.x))
	var y := goal.y + (b.y - goal.y) * 32.0 / dx
	var k: Dictionary = ISSMatchData.consts["keeper"]
	return Vector2(goal.x + d * float(k["line_offset"]), clampf(y, goal.y - 80.0, goal.y + 80.0))


## A shot on its way to goal: [frames until it crosses the keeper's x, the
## y where it crosses], or [] when there is none (keeper_save).
func _incoming(p: ISSFootballer) -> Array:
	var b := eng.ball
	if not b.live or not b.is_loose() or b.speed < 1.5 or b.kicker == p:
		return []
	var goal := own_goal()
	var v := b.velocity()
	if v.x * (goal.x - b.pos.x) <= 0.0 or absf(v.x) < 0.3:
		return []
	var t := (p.pos.x - b.pos.x) / v.x
	if t < 0.0 or t > 90.0:
		return []
	var cross := b.pos.y + v.y * t
	if absf(cross - goal.y) > 120.0:
		return []
	return [t, cross]


## Dive when a shot comes within reach, timed so that he arrives with the ball.
func _keeper_save(p: ISSFootballer) -> void:
	var shot := _incoming(p)
	if shot.is_empty() or p.busy():
		return
	var t: float = shot[0]
	var off: float = shot[1] - p.pos.y
	var range_px: float = ISSMatchData.consts["keeper"]["save_range"]
	if t > 26.0 or (eng.ball.pos - p.pos).length() > range_px + eng.ball.speed * 10.0:
		return # still far: shuffle across (_keeper_steer)
	if absf(off) < 10.0 and eng.ball.z < 30.0:
		return # straight at him: the pickup takes it
	p.start_dive(32.0 if off > 0.0 else 0.0, clampf(absf(off) / maxf(1.0, t - 3.0), 1.0, 4.5))
	eng.stats_shot_on_target(1 - side)


## Distribution while holding the ball (keeper_hold).
func keeper_distribute(p: ISSFootballer) -> void:
	p.ai_wait -= 1
	if p.ai_wait > 0:
		return
	if randi() % 4 == 0:
		p.facing = (16 if dir() > 0.0 else 48) + randi() % 9 - 4
		p.start_kick(ISSFootballer.K.PUNT, p.facing, null, 6 + randi() % 3)
	else:
		var mate := _best_mate(p, their_goal(), 360.0)
		if mate == null:
			p.start_kick(ISSFootballer.K.PUNT, p.facing, null, 7)
		else:
			p.facing = int(ISSFootballer.heading_to(p.pos, mate.pos)) & 63
			p.start_kick(ISSFootballer.K.KEEPER_THROW, p.facing, mate)
