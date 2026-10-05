class_name ISSCompetition
extends RefCounted
## The competitions, with the ROM's structure and fixture lists (match.json):
## - short league (mode 4): 6 teams, the 15 fixtures of $05B17E, 3 points a
##   win and 1 a draw (screen_league_table);
## - short tournament (mode 5): 8 teams, knockout;
## - International Cup (modes 6-8): an elimination round of 3 (the human's
##   side and two of teams 0-23, fixtures $05B994) that only the winner
##   leaves, a group round of 4 (three of teams 0-35, fixtures $05BE40) whose
##   top two go through, and finals: a 16-team knockout of 15 games;
## - World Series (mode 9): teams 0-35 play each other once in the order of
##   $05C7B2 (630 games), every game with a winner; the table counts wins.
## The first `humans` slots of a stage are played by people; games between
## computer teams are decided by match_simulate ($015442).

var kind := "league"
var humans := 1
## Team numbers of the current stage, by slot.
var teams: Array = []
## International Cup stage: 0 elimination, 1 group, 2 finals.
var stage := 0
## Round-robin fixtures of the stage (slot pairs), empty for a knockout.
var fixtures: Array = []
## Played games of the stage: {home, away, hg, ag, pk: [h, a] or []}.
var games: Array = []
## Knockout: slots still in, in bracket order.
var alive: Array = []
## The human side is out (International Cup).
var eliminated := false
## International Cup: teams already met (not drawn again).
var met: Array = []


static func league(team_ids: Array, human_count: int) -> ISSCompetition:
	var c := ISSCompetition.new()
	c.kind = "league"
	c.teams = team_ids.duplicate()
	c.humans = human_count
	c.fixtures = ISSMatchData.consts["league_fixtures"]
	return c


static func tournament(team_ids: Array, human_count: int) -> ISSCompetition:
	var c := ISSCompetition.new()
	c.kind = "tournament"
	c.teams = team_ids.duplicate()
	c.humans = human_count
	c.alive = range(team_ids.size())
	return c


static func international_cup(team: int) -> ISSCompetition:
	var c := ISSCompetition.new()
	c.kind = "cup"
	c.humans = 1
	c.met = [team]
	c.teams = [team] + c._draw(2, 24)
	c.fixtures = ISSMatchData.consts["cup_elimination_fixtures"]
	return c


static func world_series(team: int) -> ISSCompetition:
	var c := ISSCompetition.new()
	c.kind = "world_series"
	c.humans = 1
	# Slots are team numbers 0-35; the human's side plays as itself.
	c.teams = range(36)
	c.fixtures = ISSMatchData.consts["world_series_fixtures"]
	c.human_team = team
	return c


## World Series: the human's team number (its slot), the season (0, 1) and
## each season's winner ($127E, $1280).
var human_team := -1
var season := 0
var season_winners: Array = []


func _draw(n: int, pool: int) -> Array:
	var out := []
	while out.size() < n:
		var t := randi() % pool
		if not met.has(t) and not out.has(t):
			out.append(t)
	met.append_array(out)
	return out


func is_human(slot: int) -> bool:
	if kind == "world_series":
		return slot == human_team
	return slot < humans


## Every game of this stage needs a winner (extra time and penalties).
func knockout() -> bool:
	return kind == "tournament" or kind == "world_series" or (kind == "cup" and stage == 2)


func in_championship() -> bool:
	return kind == "world_series" and stage == 2


## The next game as [home slot, away slot], or [] when it is over.
func next_game() -> Array:
	if eliminated:
		return []
	if not alive.is_empty() or (kind == "tournament") or (kind == "cup" and stage == 2):
		if alive.size() <= 1:
			return []
		var i := _round_games() * 2
		return [alive[i], alive[i + 1]]
	if games.size() >= fixtures.size() or (kind == "world_series" and stage == 3):
		return []
	var f: Array = fixtures[games.size()]
	# The second World Series season swaps home and away.
	if kind == "world_series" and stage == 0 and season == 1:
		return [int(f[1]), int(f[0])]
	return [int(f[0]), int(f[1])]


func _round_games() -> int:
	var done := games.size()
	var round_size := teams.size() / 2
	while done >= round_size and round_size >= 1:
		done -= round_size
		round_size /= 2
	return done


func round_name() -> String:
	match kind:
		"league":
			return "ROUND %d" % (games.size() / 3 + 1)
		"world_series":
			if stage == 2:
				return "CHAMPIONSHIP"
			return "SEASON %d GAME %d" % [season + 1, games.size() + 1]
		"cup":
			if stage == 0:
				return "ELIMINATION ROUND"
			if stage == 1:
				return "GROUP ROUND"
	match alive.size():
		2:
			return "FINAL"
		4:
			return "SEMI FINAL"
		8:
			return "QUARTER FINAL"
	return "FIRST ROUND"


## Record the result of the next game (from a match or a simulation).
func record(hg: int, ag: int, pk: Array = []) -> void:
	var g := next_game()
	if g.is_empty():
		return
	games.append({"home": g[0], "away": g[1], "hg": hg, "ag": ag, "pk": pk})
	if not alive.is_empty() and _round_games() == 0:
		# The round is over: the winners go on, in bracket order.
		var n := alive.size() / 2
		var winners := []
		for r in games.slice(games.size() - n):
			winners.append(_winner(r))
		alive = winners
		if kind == "cup" and not alive.has(0):
			eliminated = true
	if kind == "cup" and stage < 2 and next_game().is_empty() and not eliminated:
		_next_stage()
	if kind == "world_series" and stage == 0 and games.size() >= fixtures.size():
		_end_season()


## World Series: the season's winner is the table's leader. After the second
## season a human side that won one of them plays the other season's winner
## in the Championship (mode $A, one knockout match); winning neither is the
## end, winning both makes it the champion.
func _end_season() -> void:
	season_winners.append(int(table()[0]["slot"]))
	if season == 0:
		season = 1
		games = []
		return
	var won: Array = season_winners.filter(func(w): return w == human_team)
	if won.size() == 2:
		stage = 3 # champion without a play-off
	elif won.size() == 1:
		var other: int = season_winners[0] if int(season_winners[1]) == human_team else season_winners[1]
		stage = 2
		games = []
		fixtures = [[human_team, other]]
	else:
		eliminated = true


## International Cup: from the elimination round to the group round (only
## the winner) and from the group round to the finals (the top two).
func _next_stage() -> void:
	var t := table()
	var through: int = 1 if stage == 0 else 2
	var ok := false
	for i in through:
		if int(t[i]["slot"]) == 0:
			ok = true
	if not ok:
		eliminated = true
		return
	var me: int = teams[0]
	stage += 1
	games = []
	if stage == 1:
		teams = [me] + _draw(3, 36)
		fixtures = ISSMatchData.consts["cup_group_fixtures"]
	else:
		met = [me]
		teams = [me] + _draw(15, 36)
		# The human's side meets a random first-round opponent.
		teams.shuffle()
		var at := teams.find(me)
		teams[at] = teams[0]
		teams[0] = me
		fixtures = []
		alive = range(16)


static func _winner(r: Dictionary) -> int:
	var h: int = r["hg"]
	var a: int = r["ag"]
	if h == a and not r["pk"].is_empty():
		h = r["pk"][0]
		a = r["pk"][1]
	return r["home"] if h >= a else r["away"]


## Play the computer's games until one involves a human side (or the end).
func simulate_until_human() -> void:
	while true:
		var g := next_game()
		if g.is_empty() or is_human(g[0]) or is_human(g[1]):
			return
		var r := simulate(teams[g[0]], teams[g[1]], knockout())
		record(r[0], r[1], r[2])


## match_simulate ($015442).
static func simulate(home: int, away: int, ko: bool) -> Array:
	ISSMatchData.ensure_loaded()
	var sim: Dictionary = ISSMatchData.consts["simulate"]
	var st: Array = sim["strength"]
	var goals: Array = sim["goals"]
	var d := int(st[home]) - int(st[away])
	var dh := clampi(d, 0, 63) & ~7
	var da := clampi(-d, 0, 63) & ~7
	var hg := int(goals[dh + randi() % 8])
	var ag := int(goals[da + randi() % 8])
	var pk := []
	if ko and hg == ag:
		var ph := 3 + int(goals[dh + randi() % 8])
		var pa := 3 + int(goals[da + randi() % 8])
		if ph == pa:
			ph += 1
		pk = [ph, pa]
	return [hg, ag, pk]


## Standings of a round-robin stage: [{slot, w, d, l, p}] by points (ties keep
## slot order, as the ROM's selection sort does).
func table() -> Array:
	var rows := []
	for i in teams.size():
		rows.append({"slot": i, "w": 0, "d": 0, "l": 0, "p": 0})
	for r: Dictionary in games:
		var h: Dictionary = rows[r["home"]]
		var a: Dictionary = rows[r["away"]]
		var w := -1
		if r["hg"] != r["ag"] or not r["pk"].is_empty():
			w = _winner(r)
		if w < 0:
			h["d"] += 1
			a["d"] += 1
			h["p"] += 1
			a["p"] += 1
		else:
			var win: Dictionary = rows[w]
			var lose: Dictionary = a if w == r["home"] else h
			win["w"] += 1
			win["p"] += 3
			lose["l"] += 1
	var out := []
	var left := rows.duplicate()
	while not left.is_empty():
		var best: Dictionary = left[0]
		for r: Dictionary in left:
			if r["p"] > best["p"]:
				best = r
		out.append(best)
		left.erase(best)
	return out


func finished() -> bool:
	return next_game().is_empty()


## The champion's slot, or -1 (the human side was knocked out of the cup).
func champion() -> int:
	if eliminated:
		return -1
	if not alive.is_empty():
		return alive[0] if alive.size() == 1 else -1
	if kind == "world_series":
		if stage == 3:
			return human_team
		if stage == 2 and not games.is_empty():
			return _winner(games[0])
		return -1
	return table()[0]["slot"]


func team_of(slot: int) -> int:
	return int(teams[slot])


# ---------------------------------------------------------------------------
# Saving (the port's stand-in for the passwords).

const SAVE := "user://iss_competition.json"


func save() -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"kind": kind, "humans": humans, "teams": teams, "stage": stage,
		"fixtures_key": _fixtures_key(), "games": games, "alive": alive, "eliminated": eliminated,
		"met": met, "human_team": human_team, "season": season, "season_winners": season_winners,
		"stage_fixtures": fixtures if kind == "world_series" and stage == 2 else []}))


func _fixtures_key() -> String:
	match kind:
		"league":
			return "league_fixtures"
		"world_series":
			return "world_series_fixtures"
		"cup":
			return ["cup_elimination_fixtures", "cup_group_fixtures", ""][stage]
	return ""


static func load_saved() -> ISSCompetition:
	if not FileAccess.file_exists(SAVE):
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	if d == null:
		return null
	ISSMatchData.ensure_loaded()
	var c := ISSCompetition.new()
	c.kind = d["kind"]
	c.humans = int(d["humans"])
	c.teams = d["teams"].map(func(v): return int(v))
	c.stage = int(d["stage"])
	var key: String = d["fixtures_key"]
	c.fixtures = ISSMatchData.consts[key] if key != "" else []
	c.games = d["games"]
	for g: Dictionary in c.games:
		for k in ["home", "away", "hg", "ag"]:
			g[k] = int(g[k])
		g["pk"] = g["pk"].map(func(v): return int(v))
	c.alive = d["alive"].map(func(v): return int(v))
	c.eliminated = d["eliminated"]
	c.met = d["met"].map(func(v): return int(v))
	c.human_team = int(d["human_team"])
	c.season = int(d.get("season", 0))
	c.season_winners = d.get("season_winners", []).map(func(v): return int(v))
	if c.kind == "world_series" and c.stage == 2:
		c.fixtures = d["stage_fixtures"]
	return c


static func clear_saved() -> void:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
