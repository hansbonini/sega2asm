class_name ISSChallenge
extends RefCounted
## The challenges' scores and records (screen_challenge_record, $04F0FE).
## A result from ISSMatchEngine.challenge_result() holds the time left and
## the bonus as four digits each (from 30.00); a failed attempt scores
## nothing and the bonus only counts when it was kept ($13CE = $B).
##   time taken  = 3000 - the time's digits read as a decimal number
##   time score  = the time's first three digits, bonus score likewise
##   total       = time score + bonus score
## The best time (lowest) and best score (highest) of each event and level
## start as the ROM's ($03AE98, $03AF28) and keep the player's three letters;
## the port saves them (the cartridge forgets them at power off).

const SAVE := "user://iss_challenge.json"

## The player's three letters ($13C0, screen_input_name).
static var player_name := "   "


static func digits_value(d: Array) -> int:
	return int(d[0]) * 1000 + int(d[1]) * 100 + int(d[2]) * 10 + int(d[3])


static func digits_score(d: Array) -> int:
	return int(d[0]) * 100 + int(d[1]) * 10 + int(d[2])


## {time_taken, time_score, bonus_time, bonus_score, total} of a result.
static func score(r: Dictionary) -> Dictionary:
	var time: Array = r["time"] if r["done"] else [0, 0, 0, 0]
	var bonus: Array = r["bonus"] if r["done"] and r["bonus_on"] else [0, 0, 0, 0]
	var ts := digits_score(time)
	var bs := digits_score(bonus)
	return {"time_taken": 3000 - digits_value(time), "time_score": ts,
		"bonus_time": digits_value(bonus), "bonus_score": bs, "total": ts + bs}


## {"best_time": [event][level] {value, name}, "best_score": ...}.
static func records() -> Dictionary:
	if FileAccess.file_exists(SAVE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
		if d is Dictionary and d.has("best_time") and d.has("best_score"):
			return d
	ISSMatchData.ensure_loaded()
	var ch: Dictionary = ISSMatchData.consts["challenge"]
	return {"best_time": ch["best_time"].duplicate(true), "best_score": ch["best_score"].duplicate(true)}


static func save_records(rec: Dictionary) -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(rec))


## Enter a result into rec: {"score": .., "new_time": bool, "new_score": bool}.
static func record(rec: Dictionary, r: Dictionary) -> Dictionary:
	var s := score(r)
	var ev := int(r["event"])
	var lv := int(r["level"])
	var bs: Dictionary = rec["best_score"][ev][lv]
	var bt: Dictionary = rec["best_time"][ev][lv]
	var new_score: bool = int(s["total"]) > int(bs["value"])
	var new_time: bool = int(s["time_taken"]) < int(bt["value"])
	if new_score:
		bs["value"] = s["total"]
		bs["name"] = player_name
	if new_time:
		bt["value"] = s["time_taken"]
		bt["name"] = player_name
	return {"score": s, "new_time": new_time, "new_score": new_score}


## The best record of an event over its levels (menu_state_04E4A6): the
## lowest time and the highest score, with the level they were set at.
static func best_of_event(rec: Dictionary, ev: int) -> Dictionary:
	var bt := 0
	var bs := 0
	for lv in range(1, 4):
		if int(rec["best_time"][ev][lv]["value"]) <= int(rec["best_time"][ev][bt]["value"]):
			bt = lv
		if int(rec["best_score"][ev][lv]["value"]) >= int(rec["best_score"][ev][bs]["value"]):
			bs = lv
	return {"time_level": bt, "score_level": bs}
