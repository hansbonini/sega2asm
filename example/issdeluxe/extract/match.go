package main

// The match engine's constants, read from the ROM for the Godot port
// (iss/iss_match_data.gd). Speeds are pixels per frame at 60 Hz (the NTSC
// column of each (NTSC, PAL) pair; the PAL values are the same speeds per
// second at 50 Hz).

import (
	"path/filepath"
	"strings"
)

const (
	tblBallFriction     = 0x00BD3C // per weather: rolling friction shift
	tblBallBounceDamp   = 0x00BD36 // per weather: speed lost on a bounce (shift)
	tblKickLofted       = 0x00B986 // per power: speed, vz (NTSC, PAL each)
	tblKickRising       = 0x00BA16
	tblLoftedTravel     = 0x00BAA6 // per power: distance of a lofted ball (16.16)
	tblRisingTravel     = 0x00BACA // per power: distance of a rising kick
	tblKickDrive        = 0x00BC1E
	tblKickPass         = 0x00BC2E
	tblKickSoft         = 0x00BD0E // ball_kick_soft: dribble push
	tblReachDeflect     = 0x00BBF6 // ball_in_reach: faster balls are deflected
	tblTeamLines        = 0x037DC6 // per role: (min, max) from the ball, own ball then theirs
	tblRefereeStrict    = 0x016EA2
	tblPressIntensity   = 0x00D504
	tblKeeperDiving     = 0x00512C
	tblKeeperJumping    = 0x00513C
	tblKnockedOverSpeed = 0x009F20
	tblKnockedOverLift  = 0x009F28
	tblTeamStrength     = 0x03B034     // match_simulate: strength per team
	tblSimGoals         = 0x03B05E     // match_simulate: 8 rows (strength difference / 8) x 8 goal counts
	tblLeagueFixtures   = 0x05B17E     // short league: 15 (home, away) pairs of league slots
	tblCupElimFixtures  = 0x05B994     // International Cup elimination round: 3 pairs
	tblCupGroupFixtures = 0x05BE40     // International Cup group round: 6 pairs
	tblWorldSeries      = 0x05C7B2     // World Series: 630 pairs of team numbers (36 teams, each once)
	tblScenarios        = 0x03AA92     // 12 pointers to scenario records
	tblScenarioTexts    = 0x0529B6     // 12 pointers to 8 $FF-terminated lines
	teamRunSpeed        = 0x01487E + 2 // move.l #$0001E000,$1814(a6)
	keeperDiveSlowBall  = 0x00BC0E     // keeper_dive: full-length dive for balls up to this speed
	tblKeeperSmother    = 0x00514C     // keeper_smother: speed, lift of the dive at the ball
	tblKeeperSideDive   = 0x00516C     // keeper_side_dive: speed, lift of the dive the pad's way
	tblWallSize         = 0x038110     // restart_setup_free_kick: players in the wall by angle / 4
	tblFreeKickAttack   = 0x0380AE     // kicking side's players 5-10 (x16 px from the goal line attacked)
	tblFreeKickDefence  = 0x0380BA     // defenders outside the wall, ball within $1A0 of the middle
	tblFreeKickAttackLo = 0x0380C6     // kicking side, ball $1A0 or more below the middle
	tblFreeKickDefWide  = 0x0380D2     // defenders outside the wall, ball out wide
	tblDrillDefence     = 0x03B02A     // defence drill: attackers 10, 9, 8 (x16 px from the left line / the middle)
	tblDrillKeeper      = 0x03B030     // keeper drill: attackers 10, 9
	tblDrillTexts       = 0x04F772     // screen_training_select: 4 pointers to 4 $FF-terminated lines
	tblFreeKickSpots    = 0x038120     // free kick drill / challenge: 16 (x, y) x16 px from the right line / middle
	tblChallengeFlags   = 0x01486A     // dribble challenge: 5 flags, words x16 px from the middle
	tblBestTime         = 0x03AE98     // challenge records: 6 events x 4 levels x (word, 3 letters, $FF)
	tblBestScore        = 0x03AF28
	tblChallengeTexts   = 0x04E792 // 6 pointers to 7 lines (screen_challenge_select)
	tblModeTexts        = 0x04DDF8 // training mode / challenge mode: 4 lines each
	tblModeTexts2       = 0x04DE54
	tblRecordTexts      = 0x04F454 // your record: fail, average, new record (3 lines each)
	tblNameChars        = 0x04E2E2 // name entry: 40 characters, one per word
	tblButtonLayouts    = 0x014FB2 // 24 layouts x 16 bytes: logical buttons per B/C/A/Z combination
	tblLayoutButtons    = 0x0482D0 // key configuration: 24 x (dash, pass, high ball, shot) buttons, 0 B 1 C 2 A 3 Z
)

func fix(a uint32) float64 { return float64(int32(be32(a))) / 65536 }

// pairs reads n (speed, vz) NTSC entries of a per-power kick table laid out as
// speed NTSC, speed PAL, vz NTSC, vz PAL.
func kickTable(a uint32, n int) [][2]float64 {
	var out [][2]float64
	for i := 0; i < n; i++ {
		b := a + uint32(16*i)
		out = append(out, [2]float64{fix(b), fix(b + 8)})
	}
	return out
}

func exportMatch(dir string) {
	type bounds struct {
		Left   int `json:"left"`
		Right  int `json:"right"`
		Top    int `json:"top"`
		Bottom int `json:"bottom"`
	}
	var pitch []bounds
	for s := uint32(0); s < 8; s++ {
		a := tblPitchBounds + 8*s
		pitch = append(pitch, bounds{s16(a), s16(a + 2), s16(a + 4), s16(a + 6)})
	}
	words := func(a uint32, n int) []int {
		var out []int
		for i := 0; i < n; i++ {
			out = append(out, s16(a+uint32(2*i)))
		}
		return out
	}
	longs := func(a uint32, n, stride int) []float64 {
		var out []float64
		for i := 0; i < n; i++ {
			out = append(out, fix(a+uint32(stride*i)))
		}
		return out
	}
	lines := words(tblTeamLines, 12)
	var strict [][]int
	for k := uint32(0); k < 4; k++ {
		var row []int
		for i := uint32(0); i < 4; i++ {
			row = append(row, int(rom[tblRefereeStrict+4*k+i]))
		}
		strict = append(strict, row)
	}
	var press []int
	for i := uint32(0); i < 6; i++ {
		press = append(press, int(rom[tblPressIntensity+i]))
	}
	doc := map[string]any{
		"description": "Match engine constants (NTSC: pixels and frames at 60 Hz). Pitch coordinates: x along the pitch " +
			"(goal lines at left / right), y across it (touchlines at top / bottom), z height; heading 0-63 with " +
			"0 = -y, 16 = +x. See the README's Match engine section for the rules that use them.",
		"frame_rate":   60,
		"pitch_bounds": pitch,
		"goal": map[string]any{
			"post_inner": 92, "post_outer": 100, "bar": 0x3C, "bar_top": 0x40,
			"note": "goal when |y - middle_y| < 92 and z < $3C past the goal line (match_rules_update); posts and bar rebound",
		},
		"penalty_distance": 0x180,
		"restart": map[string]any{
			"throw_in_outside": 24, "throw_in_clamp": 128,
			"goal_kick_x": 128, "goal_kick_y": 192, "corner_inside": 8, "penalty_spot": 256,
		},
		"run_speed": fix(teamRunSpeed),
		"ball": map[string]any{
			"gravity":         float64(0x1400) / 65536,
			"gravity_high":    float64(0x2800) / 65536,
			"friction_shift":  words(tblBallFriction, 3),
			"bounce_damp":     words(tblBallBounceDamp, 3),
			"bounce_sound_vz": -3.0,
			"bounce_stop":     float64(0x2000) / 65536,
			"deflect_speed":   fix(tblReachDeflect),
			"reach_below":     4,
			"reach_above":     0x24,
			"weather_note":    "friction and bounce tables are indexed by weather 0 snow, 1 fine, 2 rain; a ball at a player's feet uses index 1",
		},
		"kick": map[string]any{
			"pass":          []float64{fix(tblKickPass), fix(tblKickPass + 8)},
			"drive":         []float64{fix(tblKickDrive), fix(tblKickDrive + 8)},
			"soft":          fix(tblKickSoft),
			"rising":        kickTable(tblKickRising, 9),
			"lofted":        kickTable(tblKickLofted, 9),
			"lofted_travel": longs(tblLoftedTravel, 9, 4),
			"rising_travel": longs(tblRisingTravel, 9, 4),
			"note":          "[speed, vz] per kick; rising and lofted by power 0-8; *_travel = distance covered, for the landing marker and the AI",
		},
		"team_lines": map[string]any{
			"own_ball":   [][]int{{lines[0], lines[1]}, {lines[2], lines[3]}, {lines[4], lines[5]}},
			"their_ball": [][]int{{lines[6], lines[7]}, {lines[8], lines[9]}, {lines[10], lines[11]}},
			"order":      []int{2, 2, 1, 0},
			"note": "per role (attack, midfield, defence): the line X stays within [target + min, target + max] toward the " +
				"opponents' goal, target = the ball's target X (restart X +- $200 on a dead ball); one role per frame in the " +
				"order given (g_ai_slot & 3), home on slots 0-3, away on 4-7 of each 8",
		},
		"referee_strictness": strict,
		"press_intensity":    press,
		"keeper": map[string]any{
			"line_offset":    32,
			"save_range":     0x50,
			"dive":           []float64{fix(tblKeeperDiving), fix(tblKeeperDiving + 8)},
			"jump":           []float64{fix(tblKeeperJumping), fix(tblKeeperJumping + 8)},
			"dive_gravity":   float64(0x5000) / 65536,
			"hold_frames":    []int{64, 191},
			"dive_note":      "a ball up to dive_slow_ball px/frame gets the full-length dive (action 22), a faster one the jump (21)",
			"dive_slow_ball": fix(keeperDiveSlowBall),
			"side_dive":      []float64{fix(tblKeeperSideDive), fix(tblKeeperSideDive + 8)},
			"smother":        []float64{fix(tblKeeperSmother), fix(tblKeeperSmother + 8)},
			"smother_lead":   8,
			"human_note": "a human keeper (keeper_update_1), with the ball in his half: lofted + direction = side_dive " +
				"that way (keeper_side_dive), lofted alone = keeper_dive, shoot = smother toward where the ball " +
				"will be in smother_lead frames (keeper_smother)",
		},
		"challenge":       challenge(),
		"controls":        controls(),
		"free_kick_spots": signedPairs(tblFreeKickSpots, 16),
		"free_kick": map[string]any{
			"wall_range":    0x280,
			"wall_distance": 0x60 * 256 >> 7,
			"wall_gap":      12,
			"wall_size":     bytesAt(tblWallSize, 16),
			"wide_y":        0x1A0,
			"attack":        signedPairs(tblFreeKickAttack, 6),
			"attack_low":    signedPairs(tblFreeKickAttackLo, 6),
			"defence":       signedPairs(tblFreeKickDefence, 7),
			"defence_wide":  signedPairs(tblFreeKickDefWide, 7),
			"note": "restart_setup_free_kick ($013B76): within wall_range of the goal line the defenders 1..n form a " +
				"wall wall_distance px from the ball toward the goal centre, n = wall_size[heading / 4], wall_gap px " +
				"apart across the line (member k at centre + gap * (k - n / 2)); the other defenders take defence " +
				"(|ball y - middle| < wide_y) or defence_wide, x16 px from their own goal line; the kicking side's " +
				"players 5-10 take attack_low (ball y - middle >= wide_y) or attack, x16 px from the goal line they " +
				"attack; y is mirrored to the ball's side of the pitch",
		},
		"training": map[string]any{
			"team":              0x2A,
			"reset_frames":      0x80,
			"defence_x":         0x180,
			"defence_form":      []int{4, 6},
			"defence_attackers": signedPairs(tblDrillDefence, 3),
			"keeper_attackers":  signedPairs(tblDrillKeeper, 2),
			"texts":             drillTexts(),
			"note": "restart_setup_practice ($01418C), drill g_training_drill: 0 free (the practice team, $2A, stays off; " +
				"kick-off), 1 defence (home role-2 players at left + defence_x + form_x * 4, middle + form_y * 6; " +
				"away players 10, 9, 8 at defence_attackers, x16 px from the left line and the middle, 8 with the " +
				"ball), 2 free kick (home 0-4 and away 7-10 off, a free kick for home where the ball is), 3 keeper " +
				"(home keeper only, under the pad; away 10, 9 at keeper_attackers, 9 with the ball). A drill starts " +
				"again reset_frames after the ball goes out, or the home side has it (1, 3), or the other side (2)",
		},
		"knocked_over": []float64{fix(tblKnockedOverSpeed), fix(tblKnockedOverLift)},
		"contests": map[string]any{
			"base":           tblContests,
			"bytes":          bytesAt(tblContests, contestsLen),
			"slide":          0x3ADA2,
			"charge":         0x3ADE8,
			"keeper":         []int{0x3AD6A, 0x3AD52, 0x3AD4A, 0x3AD42, 0x3AD32},
			"position_bonus": 0x3ADE2,
			"note": "signed bytes read at table + index, past a table's end into whatever follows. slide " +
				"(player_start_sit_after_a_slide_008F16_1, the keeper's too): index = ((position bonus + energy) x 2 + " +
				"intelligence + dribble) / 2 x 4 + random 0-3 of the ball carrier; -1 he rides the tackle (a leap or a " +
				"hop), 0 he loses the ball, 1 he is knocked over, a foul and a card when tackled from behind (facing " +
				"within 9 of the tackler's). charge (player_start_chip_0070AE_1, the crouched run meeting the carrier): " +
				"index = (challenger's intelligence - carrier's + 2, at least 0) x 4 + random 0-3; -1 the challenger " +
				"falls backwards, 0 the carrier loses the ball, 1 the carrier is knocked over as above. keeper " +
				"(ball_check_00A67A, one table per keeper skill 0-4, a lofted ball in flight): index = (kicker's balance " +
				"+ 4 - keeper's energy) x 4 + random 0-3; -1 it gets past him, 0 it bounces back off him at a quarter " +
				"of its speed, 1 he pushes it on his kick direction at half speed, 2 he holds it",
		},
		"simulate": map[string]any{
			"strength": bytesAt(tblTeamStrength, numTeams),
			"goals":    bytesAt(tblSimGoals, 64),
			"note": "match_simulate ($015442), the result of a match between computer teams: d = strength[home] - " +
				"strength[away] clamped to 0-63 for the home side (and the reverse for the away side); goals = " +
				"goals[(d & ~7) + random 0-7]; penalties when needed: 3 + another draw each, one more for the home " +
				"side if level",
		},
		"scenarios":                scenarios(),
		"league_fixtures":          pairsAt(tblLeagueFixtures, 15),
		"cup_elimination_fixtures": pairsAt(tblCupElimFixtures, 3),
		"cup_group_fixtures":       pairsAt(tblCupGroupFixtures, 6),
		"world_series_fixtures":    pairsAt(tblWorldSeries, 630),
		"competitions_note": "short league: 6 slots, 3 points a win, 1 a draw; short tournament: 8, knockout; " +
			"International Cup: elimination round of 3 (the human's side and two of teams 0-23), group round of 4 " +
			"(three of teams 0-35), finals: a 16-team knockout (15 games); World Series: teams 0-35 play each other " +
			"once, every game a knockout match (win / lose table)",
		"ai_slots": 16,
	}
	writeJSON(filepath.Join(dir, "match.json"), doc)
}

const (
	tblContests = 0x3AD0A // misc_data_03AD0A: the contest tables and tbl_position_bonus
	contestsLen = 0x120
)

func bytesAt(a uint32, n int) []int {
	var out []int
	for i := 0; i < n; i++ {
		out = append(out, int(rom[a+uint32(i)]))
	}
	return out
}

func signedPairs(a uint32, n int) [][2]int {
	var out [][2]int
	for i := 0; i < n; i++ {
		out = append(out, [2]int{int(int8(rom[a+uint32(2*i)])), int(int8(rom[a+uint32(2*i+1)]))})
	}
	return out
}

func pairsAt(a uint32, n int) [][2]int {
	var out [][2]int
	for i := 0; i < n; i++ {
		out = append(out, [2]int{int(rom[a+uint32(2*i)]), int(rom[a+uint32(2*i+1)])})
	}
	return out
}

// textLines reads n $FF-terminated lines of menu text ('@' is a space).
func textLines(t uint32, n int) []string {
	var lines []string
	for k := 0; k < n; k++ {
		var b []byte
		for rom[t] != 0xFF {
			c := rom[t]
			if c == '@' {
				c = ' '
			}
			b = append(b, c)
			t++
		}
		t++
		lines = append(lines, strings.TrimSpace(string(b)))
	}
	return lines
}

// challenge reads the timed challenges of mode 1 (restart_setup_practice_target,
// restart_resume_practice_target, the rules of match_rules_update in mode 1
// and the menus of screens $13-$17).
func challenge() map[string]any {
	counts := func(a uint32) []int { return bytesAt(a, 4) }
	pos := func(i, n int) [][2]int { return signedPairs(0x03AFB8+uint32(2*i), n) }
	records := func(base uint32) [][]map[string]any {
		var out [][]map[string]any
		for ev := uint32(0); ev < 6; ev++ {
			var row []map[string]any
			for lv := uint32(0); lv < 4; lv++ {
				a := base + ev*0x18 + lv*6
				row = append(row, map[string]any{"value": int(be16(a)), "name": string(rom[a+2 : a+5])})
			}
			out = append(out, row)
		}
		return out
	}
	var flags [][2]int
	for i := uint32(0); i < 5; i++ {
		flags = append(flags, [2]int{s16(tblChallengeFlags + 4*i), s16(tblChallengeFlags + 4*i + 2)})
	}
	var texts [][]string
	for i := uint32(0); i < 6; i++ {
		texts = append(texts, textLines(be32(tblChallengeTexts+4*i), 7))
	}
	var chars []string
	for i := uint32(0); i < 40; i++ {
		c := rom[tblNameChars+2*i]
		if c == '@' {
			c = ' '
		}
		chars = append(chars, string(rune(c)))
	}
	return map[string]any{
		"events": []map[string]any{
			{"name": "DRIBBLE", "home_first": 1, "home_counts": counts(0x03AFFA), "home_places": pos(0, 1),
				"away_first": 1, "away_counts": counts(0x03AFFE), "away_places": pos(1, 2), "carrier": []int{0, 1}},
			{"name": "PASS", "home_first": 1, "home_counts": counts(0x03B002), "home_places": pos(3, 10),
				"away_first": 1, "away_counts": counts(0x03B006), "away_places": pos(13, 10), "carrier": []int{0, 6}},
			{"name": "SHOOT", "home_first": 9, "home_counts": counts(0x03B00A), "home_places": pos(23, 2),
				"away_first": 1, "away_counts": counts(0x03B00E), "away_places": pos(25, 3), "carrier": []int{0, 9},
				"keeper_level": 2, "target": true},
			{"name": "DEFENCE", "home_first": 2, "home_counts": counts(0x03B012), "home_places": pos(28, 2),
				"home_middle": 10, "away_first": 8, "away_counts": counts(0x03B016), "away_places": pos(30, 3),
				"carrier": []int{1, 8}},
			{"name": "CORNER KICK", "home_last": 10, "home_counts": counts(0x03B01A), "away_first": 1,
				"away_counts": counts(0x03B01E), "keeper_level": 2, "target": true, "restart": "corner"},
			{"name": "FREE KICK", "home_last": 10, "home_counts": counts(0x03B022), "away_first": 1,
				"away_counts": counts(0x03B026), "keeper_level": 2, "target": true, "restart": "free_kick",
				"spot_by_level": []int{8, 5, 11, 13}},
		},
		"flags":        flags,
		"flag_reach":   0x18,
		"target_y":     0x40,
		"target_reach": 0x20,
		"corner":       []int{-8, -8},
		"time":         []int{3, 0, 0, 0},
		"sixths":       5,
		"bonus_step":   2,
		"banners":      []string{string(rom[0x018A56 : 0x018A56+12]), string(rom[0x018A62 : 0x018A62+12])},
		"best_time":    records(tblBestTime),
		"best_score":   records(tblBestScore),
		"texts":        texts,
		"mode_texts":   [][]string{textLines(tblModeTexts, 4), textLines(tblModeTexts2, 4)},
		"record_texts": [][]string{textLines(tblRecordTexts, 3), textLines(tblRecordTexts+0x22, 3), textLines(tblRecordTexts+0x58, 3)},
		"name_chars":   chars,
		"note": "restart_setup_practice_target ($014364), event g_training_drill, level g_challenge_level: both sides " +
			"are the practice team; the listed players (home_first.. or home_last down, counts by level, places x16 px " +
			"from the middle), the rest off; the carrier [side, player] has the ball; the away keeper plays from " +
			"keeper_level; dribble adds 5 flags, shoot / corner / free kick a target panel on the right goal line " +
			"at middle +- target_y. Time: 4 digits from 30.00, the third wrapping at sixths (60 frames a second); " +
			"success ($13CC = $B): 5 flags, 10 home players touching the ball, the home side winning it (defence) " +
			"or a goal (shoot, corner, free kick); after success in events 0, 1, 3 the bonus counts down " +
			"bonus_step a frame from 30.00 until a goal ($13CE = $B keeps it) or zero; in events 2, 4, 5 the bonus " +
			"is the time left and counts when the goal is within target_reach of the panel. The attempt ends on " +
			"time up, out of play, a goal, or the other side winning the ball. Scores: time taken = 3000 - time " +
			"(digits read as a decimal), time score = its first three digits, bonus score likewise, total = sum",
	}
}

// controls reads the button layouts of the key configuration (tbl_button_layouts,
// screen_key_config) as the port's logical bits.
func controls() map[string]any {
	var layouts [][]int
	var buttons [][]int
	for i := uint32(0); i < 24; i++ {
		var row []int
		for k := uint32(0); k < 16; k++ {
			v := int(rom[tblButtonLayouts+16*i+k])
			// match_players_update: $10 pass, $20 lofted, $40 dash, $80 -> shoot ($100).
			l := v & 0x70
			if v&0x80 != 0 {
				l |= 0x100
			}
			row = append(row, l)
		}
		layouts = append(layouts, row)
		buttons = append(buttons, bytesAt(tblLayoutButtons+4*i, 4))
	}
	return map[string]any{
		"layouts": layouts,
		"buttons": buttons,
		"names":   []string{"B", "C", "A", "Z"},
		"note": "layouts[n][combo]: the logical buttons (pass $10, lofted $20, dash $40, shoot $100) for each " +
			"combination of B (1), C (2), A (4) and Z (8) held; buttons[n]: the button (0 B, 1 C, 2 A, 3 Z) on " +
			"dash, pass, high ball and shot in layout n (RESET: layout 0 = A, B, C, Z). Y switches player, Mode " +
			"+ a button picks a strategy, Mode + Y takes the goalkeeper (keeper SEMI-AUTO or MANUAL)",
	}
}

// drillTexts reads the four training drills' descriptions (screen_training_select_menu).
func drillTexts() [][]string {
	var out [][]string
	for i := uint32(0); i < 4; i++ {
		out = append(out, textLines(be32(tblDrillTexts+4*i), 4))
	}
	return out
}

// scenarios reads tbl_scenarios and their texts (scenario_setup, $05D4C2).
func scenarios() []map[string]any {
	var out []map[string]any
	for i := uint32(0); i < 12; i++ {
		r := be32(tblScenarios + 4*i)
		clock := int(rom[r])*60 + int(rom[r+1])*10 + int(rom[r+2])
		lines := textLines(be32(tblScenarioTexts+4*i), 8)
		out = append(out, map[string]any{
			"clock_seconds": clock, "home": int(rom[r+4]), "away": int(rom[r+5]),
			"home_score": int(rom[r+6]), "away_score": int(rom[r+7]),
			"stadium": int(rom[r+8]), "referee": int(rom[r+9]),
			"restart": s16(r + 10), "restart_x": s16(r + 12), "restart_y": s16(r + 14),
			"title": lines[:2], "text": lines[2:],
		})
	}
	return out
}
