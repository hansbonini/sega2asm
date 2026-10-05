class_name ISSMatchData
extends RefCounted
## The data the match engine runs on, loaded once: assets/iss/match.json
## (constants read from the ROM by the extractor), teams.json (squads,
## player records, ratings, formations) and formations.json.

const DIR := "res://assets/iss/"

static var consts: Dictionary
static var teams: Array
static var formations: Array
static var attributes: Dictionary


static func ensure_loaded() -> void:
	if not consts.is_empty():
		return
	consts = JSON.parse_string(FileAccess.get_file_as_string(DIR + "match.json"))
	var t: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "teams.json"))
	teams = t["teams"]
	attributes = t["attribute_tables"]
	formations = JSON.parse_string(FileAccess.get_file_as_string(DIR + "formations.json"))["formations"]


static func pitch_rect(stadium: int) -> Rect2:
	ensure_loaded()
	var b: Dictionary = consts["pitch_bounds"][stadium]
	return Rect2(b["left"], b["top"], float(b["right"]) - float(b["left"]), float(b["bottom"]) - float(b["top"]))


## Top running speed (px per 60 Hz frame) for a speed attribute 0-9.
static func speed_max(speed: int) -> float:
	return float(attributes["speed_max"][clampi(speed, 0, 9)][0])


## Acceleration per frame while dashing, for a dash attribute 0-9.
static func dash_accel(dash: int) -> float:
	return float(attributes["dash_accel"][clampi(dash, 0, 9)][0])


## Frames of running per energy point, for a stamina attribute 0-9.
static func stamina_drain(stamina: int) -> int:
	return int(attributes["stamina_drain"][clampi(stamina, 0, 9)])


static func position_bonus(position: int) -> int:
	return int(attributes["position_bonus"][clampi(position, 0, 5)])


static func kick(name: String) -> Array:
	return consts["kick"][name]


static func team_count() -> int:
	ensure_loaded()
	return teams.size()


static func team_name(team: int) -> String:
	ensure_loaded()
	return teams[team]["name"]
