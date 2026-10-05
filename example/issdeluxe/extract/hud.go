package main

import (
	"fmt"
	"image"
	"image/color"
	"os"
	"path/filepath"
	"strings"

	"sega2asm/types"
)

// The match HUD lives in the window plane: res16 entry 3 is its 32x32 map
// over the overlay tiles (res16 entry 5), palette line 2 (colours 0-7 the
// officials' kit, 8-15 res16 entry 9). match_init_hud streams the team flags
// and names into overlay tiles 72-93; the radar is a 10x7-tile bitmap in
// tiles 2-71 redrawn by the hud_update chain; the score and clock are digit
// tiles written into the map.
const (
	entHUDMap       = 3
	entReplayTiles  = 8 // res16, raw: 43 tiles streamed over overlay tiles $11B-$145 while a replay runs
	replayTiles     = 43
	replayFirst     = 0x11B
	stateMatch8Data = 0x1ABA6 // state_match_8_data: the replay HUD's cells
	entHUDPalette   = 9
	entRadarTiles   = 20      // res04: clean radar bitmap, 10 columns of 7 tiles
	grpTeamGfx      = 6       // res06
	entTeamNames    = 0       // 5 tiles per team
	entTeamFlags    = 2       // 6 tiles per team (3 x 2 cells, column-major)
	tblDigits       = 0x1CD00 // 10 digits x (top, bottom) tile words
	tblTimeUp       = 0x1CD50 // 4 cells shown instead of the clock at time up
	tblRadarMaps    = 0x1BBF0 // per stadium: column table, row table
	tblRadarDots    = 0x1BB90 // 6 dot patterns x 16 bytes
	radarFirstTile  = 2
	hudTeams        = 42
	entStrategies   = 5        // res04, raw: 9 blocks of 8 tiles, block s+1 = label of strategy s
	bannerFont      = 0x0195AA // 27 glyphs ('@' = space, A-Z) x 8 window-cell words (2 x 4)
	bannerGlyphs    = 27
)

// bannerMessages are the banner_draw strings (str_banner_*): text and the
// window column the game draws it at (row 23).
var bannerMessages = []struct {
	Name string
	Addr uint32
	Col  int
}{
	{"corner_kick", 0x01711E, 5}, {"offside", 0x0171A0, 5}, {"free_kick", 0x01734A, 5},
	{"goal_kick", 0x0174A8, 5}, {"throw_in", 0x01761A, 4}, {"foul", 0x01789A, 4},
	{"yellow_card", 0x017A44, 5}, {"red_card", 0x017A50, 5}, {"penalty_kick", 0x017B58, 4},
	{"own_goal", 0x017CA4, 4}, {"blank", 0x018142, 5}, {"half_time", 0x01825C, 5},
	{"time_up", 0x018396, 5}, {"match_drawn", 0x018588, 5}, {"you_win", 0x018594, 5},
	{"you_lose", 0x0185A0, 4}, {"team_wins", 0x0185AD, 5},
}

// strategyNames are the team strategies in tm_strategy order (labels in
// res04 entry 5 and on screen $0A).
var strategyNames = []string{"all out attack", "push along centre", "push along wings", "counter attack",
	"all out defence", "press up", "zone press", "offside trap"}

// hudLine2 returns palette line 2 as used in a match.
func hudLine2() []uint16 {
	line := append([]uint16(nil), officialKit(0)...)
	pal := unpack(entry(grpOverlay, entHUDPalette))
	for i := 0; i+1 < len(pal) && len(line) < 16; i += 2 {
		line = append(line, uint16(pal[i])<<8|uint16(pal[i+1]))
	}
	return line
}

// cellsImage draws a w x h block of 8x8 tiles given as nametable words
// (tile relative to tiles) into a CRAM-index image.
func cellsImage(words []uint16, w, h int, tiles []byte) *image.Gray {
	m := make([]byte, 2*len(words))
	for i, v := range words {
		m[2*i], m[2*i+1] = byte(v>>8), byte(v)
	}
	return renderPlane(m, tiles, w, h)
}

func exportHUD(dir string) {
	must(os.MkdirAll(filepath.Join(dir, "flags"), 0755))
	must(os.MkdirAll(filepath.Join(dir, "names"), 0755))
	must(os.MkdirAll(filepath.Join(dir, "strategies"), 0755))
	tiles := append([]byte(nil), unpack(entry(grpOverlay, entOverlayTiles))...)
	radar := unpack(entry(grpMisc, entRadarTiles))
	copy(tiles[radarFirstTile*32:], radar)
	window := unpack(entry(grpOverlay, entHUDMap))

	// Palette texture: line 2 = HUD, line 3 = stadium 0 fine (unused here).
	pimg := image.NewRGBA(image.Rect(0, 0, 16, 4))
	setLine(pimg, 2, hudLine2())
	setLine(pimg, 3, stadiumLine(0, 1))
	must(types.WritePNG(filepath.Join(dir, "hud.pal.png"), pimg))

	must(types.WritePNG(filepath.Join(dir, "window.png"), renderPlane(window, tiles, 32, 32)))
	idx, _ := types.TileSheet(tiles, 16, types.GrayPalette(16), false)
	must(types.WritePNG(filepath.Join(dir, "overlay_tiles.png"), grayIndex(idx)))
	// Replay HUD: while a replay runs match_init_hud streams 43 raw tiles
	// (res16 entry 8) over overlay tiles $11B-$145: the REPLAY logo and the
	// control icons state_match_8 puts in the window's top rows.
	rt := entry(grpOverlay, entReplayTiles)
	ridx, _ := types.TileSheet(rom[rt:rt+replayTiles*32], 16, types.GrayPalette(16), false)
	must(types.WritePNG(filepath.Join(dir, "replay_tiles.png"), grayIndex(ridx)))
	var words []int
	for i := 0; i+1 < len(window); i += 2 {
		words = append(words, int(be16s(window, i)))
	}

	// Team flags (3x2 cells) and names (5x1).
	flags := unpack(entry(grpTeamGfx, entTeamFlags))
	names := unpack(entry(grpTeamGfx, entTeamNames))
	for t := 0; t < hudTeams; t++ {
		fw := make([]uint16, 6)
		for c := 0; c < 3; c++ {
			for r := 0; r < 2; r++ {
				fw[r*3+c] = uint16(2<<13 | (c*2 + r))
			}
		}
		must(types.WritePNG(filepath.Join(dir, "flags", fmt.Sprintf("flag_%02d.png", t)),
			cellsImage(fw, 3, 2, flags[t*6*32:t*6*32+6*32])))
		nw := make([]uint16, 5)
		for c := range nw {
			nw[c] = uint16(2<<13 | c)
		}
		must(types.WritePNG(filepath.Join(dir, "names", fmt.Sprintf("name_%02d.png", t)),
			cellsImage(nw, 5, 1, names[t*5*32:t*5*32+5*32])))
	}

	// Strategy labels: shown in the window while a team's strategy runs
	// (match_players_update streams block s+1 to overlay tile $107 / $10F).
	labels := rom[entry(grpMisc, entStrategies):]
	lw := make([]uint16, 8)
	for c := range lw {
		lw[c] = uint16(2<<13 | c)
	}
	for st := range strategyNames {
		b := (st + 1) * 8 * 32
		must(types.WritePNG(filepath.Join(dir, "strategies", fmt.Sprintf("strategy_%d.png", st)),
			cellsImage(lw, 8, 1, labels[b:b+8*32])))
	}

	// Banner font: glyph g is 2 x 4 cells, words added to the overlay base
	// with priority and palette line 2 ($C000).
	var fw []uint16
	for row := 0; row < 4; row++ {
		for g := 0; g < bannerGlyphs; g++ {
			for c := 0; c < 2; c++ {
				fw = append(fw, uint16(be16(bannerFont+uint32(16*g+4*row+2*c)))+0xC000)
			}
		}
	}
	must(types.WritePNG(filepath.Join(dir, "banner_font.png"), cellsImage(fw, 2*bannerGlyphs, 4, tiles)))
	messages := map[string]any{}
	for _, m := range bannerMessages {
		e := m.Addr
		for rom[e] != 0xFF {
			e++
		}
		messages[m.Name] = map[string]any{"text": strings.ReplaceAll(string(rom[m.Addr:e]), "@", " "), "column": m.Col}
	}

	// Digits 0-9 (8x16 each), and the time-up cells.
	var dw []uint16
	for r := 0; r < 2; r++ {
		for d := uint32(0); d < 10; d++ {
			dw = append(dw, uint16(be16(tblDigits+4*d+2*uint32(r)))|2<<13)
		}
	}
	must(types.WritePNG(filepath.Join(dir, "digits.png"), cellsImage(dw, 10, 2, tiles)))
	var tw []uint16
	for r := 0; r < 2; r++ {
		for d := uint32(0); d < 4; d++ {
			tw = append(tw, uint16(be16(tblTimeUp+4*d+2*uint32(r)))|2<<13)
		}
	}
	must(types.WritePNG(filepath.Join(dir, "time_up.png"), cellsImage(tw, 4, 2, tiles)))

	// Radar: background bitmap and the per-stadium pitch -> radar mapping.
	rimg := image.NewGray(image.Rect(0, 0, 80, 56))
	for col := 0; col < 10; col++ {
		for y := 0; y < 56; y++ {
			for x := 0; x < 8; x++ {
				b := radar[col*0xE0+y*4+x/2]
				v := b >> 4
				if x&1 == 1 {
					v = b & 15
				}
				if v != 0 {
					rimg.SetGray(col*8+x, y, color.Gray{Y: 32 + v})
				}
			}
		}
	}
	must(types.WritePNG(filepath.Join(dir, "radar.png"), rimg))
	type radarMap struct {
		Stadium int   `json:"stadium"`
		X       []int `json:"x"` // radar pixel X for (x - pitch_left) / 16
		Y       []int `json:"y"` // radar pixel Y for (y - pitch_top) / 16
	}
	var maps []radarMap
	for st := 0; st < numStadiums; st++ {
		ct, rt := be32(tblRadarMaps+uint32(8*st)), be32(tblRadarMaps+uint32(8*st)+4)
		b := uint32(tblPitchBounds + 8*st)
		w, h := (s16(b+2)-s16(b))/16, (s16(b+6)-s16(b+4))/16
		rm := radarMap{Stadium: st}
		for i := 0; i < w; i++ {
			rm.X = append(rm.X, int(be16(ct+uint32(4*i)+2)))
		}
		for j := 0; j < h; j++ {
			rm.Y = append(rm.Y, int(be16(rt+uint32(2*j)))/4)
		}
		maps = append(maps, rm)
	}
	var dots [][]int
	for p := uint32(0); p < 6; p++ {
		var d []int
		for i := uint32(0); i < 16; i++ {
			d = append(d, int(rom[tblRadarDots+16*p+i]))
		}
		dots = append(dots, d)
	}
	writeJSON(filepath.Join(dir, "hud.json"), map[string]any{
		"description": "Match HUD (window plane, 32x32 cells, palette line 2 = hud.pal.png row 2). Images are CRAM-index. " +
			"Cells are (column, row) of window.png; each HUD item is drawn over it at the given cells.",
		"window_words": words,
		"items": map[string]any{
			"home_flag":  map[string]any{"cells": []int{2, 1}, "size": []int{3, 2}, "images": "flags/flag_NN.png (team)"},
			"away_flag":  map[string]any{"cells": []int{12, 1}, "size": []int{3, 2}},
			"home_name":  map[string]any{"cells": []int{1, 3}, "size": []int{5, 1}, "images": "names/name_NN.png"},
			"away_name":  map[string]any{"cells": []int{11, 3}, "size": []int{5, 1}},
			"home_score": map[string]any{"cells": []int{6, 1}, "digits": 2, "note": "tens digit blank when 0"},
			"away_score": map[string]any{"cells": []int{9, 1}, "digits": 2},
			"clock":      map[string]any{"cells": []int{27, 1}, "format": "M:SS, minutes at column 27, colon at 28, seconds at 29-30; time_up.png at 27-30 when the clock is 0"},
			"half":       map[string]any{"cells": []int{25, 1}, "tiles": "$6C first half, $64 second half"},
			"radar":      map[string]any{"cells": []int{11, 20}, "size_px": []int{80, 56}},
			"banner": map[string]any{"cells": []int{4, 23}, "size": []int{24, 4}, "window_row": 10, "band": 20,
				"note": "banner_draw: 16x32 letters from banner_font.png ('@' = space, A-Z, 16 px each) at HUD map row 23, " +
					"from the message's column (see banner_messages); the map's rows 22-27 are uploaded to window rows 9-14, " +
					"shown through the band in the middle of the screen (centre line 95) that opens a line a frame each way to 20"},
			"home_strategy": map[string]any{"cells": []int{2, 22}, "size": []int{8, 1},
				"images": "strategies/strategy_N.png (tm_strategy N) while the strategy runs"},
			"away_strategy": map[string]any{"cells": []int{22, 22}, "size": []int{8, 1}},
		},
		"strategy_names": strategyNames,
		"replay": map[string]any{
			"png": "replay_tiles.png", "first_tile": replayFirst, "count": replayTiles,
			"note": "state_match_8: pairs of [HUD map byte offset, cell word] (row = offset / 64, column = offset % 64 / 2; " +
				"tile = word's low 11 bits + the overlay base, bit 11 = flipped). The logo blinks 16 frames on, 16 off; " +
				"the icons show once a button has been pressed (manual mode): A (backward) and C (forward) lit for the direction " +
				"played, B lit while slow, and the START legend.",
			"logo":  cellPairs(stateMatch8Data, 12),
			"a_dim": cellPairs(stateMatch8Data+0x30, 4),
			"b_dim": cellPairs(stateMatch8Data+0x40, 4),
			"c_dim": cellPairs(stateMatch8Data+0x50, 4),
			"a_lit": cellPairs(stateMatch8Data+0x60, 4),
			"b_lit": cellPairs(stateMatch8Data+0x70, 4),
			"c_lit": cellPairs(stateMatch8Data+0x80, 4),
			"start": cellPairs(stateMatch8Data+0x90, 12),
		},
		"pause": map[string]any{
			"note": "The pause objects (matchflow_func_018BD8 for a 3-button pad, matchflow_func_018A7A for a 6-button one): " +
				"a box of blank tiles $73 in the HUD map, shown through a window band centred on line 95 that opens 2 lines " +
				"a frame each way to its height; texts in the 2-row font (top tile $74 + letter, bottom tile + $50), " +
				"the cursor tiles $5E / $5F on the chosen item, $61 (blank) on the others.",
			"three_button": map[string]any{"items": []string{"RESUME", "REPLAY", "STRATEGY", "EDIT SCREEN"},
				"box_cols": []int{9, 22}, "box_rows": []int{12, 21}, "text_col": 11, "cursor_col": 10, "first_item_row": 13,
				"window_row": 7, "band": 36},
			"six_button": map[string]any{"items": []string{"RESUME", "REPLAY"},
				"box_cols": []int{11, 20}, "box_rows": []int{6, 11}, "text_col": 13, "cursor_col": 12, "first_item_row": 7,
				"window_row": 9, "band": 20},
		},
		"banner_font":     map[string]any{"png": "banner_font.png", "chars": "@ABCDEFGHIJKLMNOPQRSTUVWXYZ", "glyph_px": []int{16, 32}},
		"banner_messages": messages,
		"digits":          "digits.png: 10 digits of 8x16 pixels",
		"radar": map[string]any{
			"background": "radar.png (index 32 + colour, line 2)",
			"mapping":    maps,
			"dots": map[string]any{
				"order":       []string{"home", "away", "flagged player", "controlled home", "controlled away", "ball"},
				"patterns":    dots,
				"format":      "raw patterns plotted by sub_01BAD0: 2x2 dots for players (home colour $D, away $A, flagged $C), 4x4 markers with a colour $F outline for the controlled players (home 9, away 8) and the ball (1)",
				"update_rate": "one step of the hud_update chain per frame (clear, home, away, controlled, ball, DMA)",
			},
		},
	})
	fmt.Printf("hud: window, %d flags and names, radar maps for %d stadiums\n", hudTeams, len(maps))
}

// cellPairs reads n [HUD map offset, cell word] pairs at a.
func cellPairs(a uint32, n int) [][]int {
	var out [][]int
	for i := 0; i < n; i++ {
		out = append(out, []int{int(be16(a + uint32(4*i))), int(be16(a + uint32(4*i) + 2))})
	}
	return out
}
