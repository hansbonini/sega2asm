package main

import (
	"fmt"
	"image"
	"os"
	"path/filepath"
	"sort"

	"sega2asm/types"
)

// Ball and non-player characters (referee, linesmen, medics, stretcher,
// dog). Both use the same [action][direction][frame]
// pointer tables as the players, with simpler frame formats.
const (
	tblBallAnims      = 0x020408 // ball_draw: [action][direction][frame] -> 2 pieces (ball, shadow)
	tblBallAnimsEnd   = 0x020BD4
	tblNPCAnims       = 0x033244 // npc_draw: [action][direction][frame] -> frame descriptor
	tblNPCAnimsEnd    = 0x035916
	grpNPC            = 3  // res03: NPC body tiles, raw (long offsets)
	grpMisc           = 4  // res04: ball tiles, NPC extras, officials' kits, ...
	entBallTiles      = 0  // 52 tiles: 12 spin frames x 4 ball sizes + 3 shadows (match)
	entBallLargeTiles = 1  // 16x16 ball used by action 4 (state_shootout)
	entNPCExtra       = 6  // raw: groups of 4 tiles (flags, cards) streamed into tile 18 of a slot
	entOfficialKits   = 38 // 4 kit variants x 8 CRAM words for palette line 2 colours 0-7
	npcSlotTiles      = 22
)

// animAction is one action of a [action][direction][frame] table.
type animAction struct {
	Index      int        `json:"index"`
	Address    string     `json:"address"`
	Directions [][]string `json:"directions"`
}

// walkAnimTable reads an action -> 8 direction lists -> frame pointer table
// whose pointers all lie in [table,end). Frame lists run until the next
// list, a frame descriptor or the first pointer that fails valid.
func walkAnimTable(table, end uint32, valid func(uint32) bool) ([]animAction, [][][]uint32) {
	in := func(v uint32) bool { return v > table && v < end && v&1 == 0 }
	var acts []uint32
	for a := uint32(table); in(be32(a)); a += 4 {
		if len(acts) > 0 && a >= actions0(acts) {
			break
		}
		acts = append(acts, be32(a))
	}
	starts := map[uint32]bool{}
	for _, ap := range acts {
		starts[ap] = true
		for d := uint32(0); d < 8; d++ {
			starts[be32(ap+4*d)] = true
		}
	}
	var sorted []uint32
	for s := range starts {
		sorted = append(sorted, s)
	}
	sort.Slice(sorted, func(i, j int) bool { return sorted[i] < sorted[j] })
	next := func(d uint32) uint32 {
		for _, s := range sorted {
			if s > d {
				return s
			}
		}
		return d + 0x400
	}
	lists := map[uint32][]uint32{}
	frames := map[uint32]bool{}
	for _, ap := range acts {
		for d := uint32(0); d < 8; d++ {
			dp := be32(ap + 4*d)
			if _, done := lists[dp]; done {
				continue
			}
			var seq []uint32
			for p := dp; p < next(dp); p += 4 {
				f := be32(p)
				if !in(f) || !valid(f) {
					break
				}
				seq = append(seq, f)
				frames[f] = true
			}
			lists[dp] = seq
		}
	}
	// A list also ends where a frame descriptor begins.
	for dp, seq := range lists {
		for i := range seq {
			if frames[dp+uint32(4*i)] {
				lists[dp] = seq[:i]
				break
			}
		}
	}
	var out []animAction
	var seqs [][][]uint32
	for i, ap := range acts {
		ao := animAction{Index: i, Address: fmt.Sprintf("$%06X", ap)}
		var as [][]uint32
		for d := uint32(0); d < 8; d++ {
			seq := lists[be32(ap+4*d)]
			var names []string
			for _, f := range seq {
				names = append(names, fmt.Sprintf("$%06X", f))
			}
			ao.Directions = append(ao.Directions, names)
			as = append(as, seq)
		}
		out = append(out, ao)
		seqs = append(seqs, as)
	}
	return out, seqs
}

// tablePiece decodes a 10-byte piece (+0 y, +2 size, +4 tile word, +6 x
// facing right, +8 x facing left). The tile word carries attribute bits and
// is ORed with the object's attribute word; xor toggles bits afterwards.
func tablePiece(b uint32, left bool, attr, xor uint16) piece {
	w := (uint16(be16(b+4)) | attr) ^ xor
	size := int(rom[b+3])
	x := s16(b + 6)
	if left {
		x = s16(b + 8)
	}
	return piece{
		X: x - 128, Y: s16(b) - 128, W: (size>>2)&3 + 1, H: size&3 + 1,
		Tile: int(w & 0x7FF), Line: int(w>>13) & 3, HFlip: w&0x800 != 0, VFlip: w&0x1000 != 0,
		Priority: w&0x8000 != 0,
	}
}

// piecesOK sanity-checks n pieces at b.
func piecesOK(b uint32, n int) bool {
	if n < 1 || n > 32 || int(b)+10*n > len(rom) {
		return false
	}
	for i := 0; i < n; i++ {
		p := b + uint32(10*i)
		if rom[p+2] != 0 || rom[p+3] > 15 {
			return false
		}
		if y, x := s16(p), s16(p+6); y < 64 || y > 192 || x < 64 || x > 192 {
			return false
		}
	}
	return true
}

// ---------------------------------------------------------------------------
// Ball
// ---------------------------------------------------------------------------

type ballFrame struct {
	Address string  `json:"address"`
	Right   *render `json:"right"`
	Left    *render `json:"left"`
	Shadow  *render `json:"shadow"`
}

// exportBall renders the ball frames of ball_draw ($020322): each frame is
// one ball piece (h-flipped when facing >= $28) and one shadow piece drawn
// obj_z pixels lower, i.e. on the ground under the ball.
func exportBall(dir string) {
	must(os.MkdirAll(filepath.Join(dir, "frames"), 0755))
	sets := [][]byte{unpack(entry(grpMisc, entBallTiles)), unpack(entry(grpMisc, entBallLargeTiles))}
	acts, seqs := walkAnimTable(tblBallAnims, tblBallAnimsEnd, func(f uint32) bool { return piecesOK(f, 2) })
	const attr = 0xE000 // obj_attr in a match: priority, palette line 3
	frames := map[string]*ballFrame{}
	for i, as := range seqs {
		tiles := sets[0]
		if i >= 4 {
			tiles = sets[1]
		}
		for _, seq := range as {
			for _, f := range seq {
				name := fmt.Sprintf("$%06X", f)
				if frames[name] != nil {
					continue
				}
				base := filepath.Join(dir, "frames", fmt.Sprintf("b_%06X", f))
				frames[name] = &ballFrame{
					Address: name,
					Right:   drawPieces([]piece{tablePiece(f, false, attr, 0)}, tiles, base+"_r.png"),
					Left:    drawPieces([]piece{tablePiece(f, true, attr, 0x800)}, tiles, base+"_l.png"),
					Shadow:  drawPieces([]piece{tablePiece(f+10, false, attr, 0)}, tiles, base+"_shadow.png"),
				}
			}
		}
	}
	writeJSON(filepath.Join(dir, "animations.json"), map[string]any{
		"description": "Ball animations: actions[action].directions[d][obj_anim_frame]. Direction d = ((facing + 4) & $38) >> 3; " +
			"the left render is used when facing >= $28 (facing 0-63). Images are CRAM-index (palette line 3, the stadium's line). " +
			"Draw the ball at (screen_x, screen_y - z) and the shadow at (screen_x, screen_y); both origins are the object position.",
		"actions": acts,
		"action_notes": []string{
			"0: z < $40 (action = clamp((z - $20) >> 5, 0, 2) while rolling or bouncing)",
			"1: z $40-$5F",
			"2: z >= $60",
			"3: lofted pass (ball_update_lob)",
			"4: 16x16 ball of the penalty shoot-out view, state_shootout (tiles res04 entry 1): frame = spin 0-2, + 3 when y < $110, + 3 more when y < $F0",
		},
		"spin":   "obj_anim_frame is 16.16: + speed/4 per frame on the ground, + $2000 per frame in the air, modulo 4",
		"frames": frames,
	})
	fmt.Printf("ball: %d actions, %d frames\n", len(acts), len(frames))
}

// ---------------------------------------------------------------------------
// Non-player characters
// ---------------------------------------------------------------------------

type npcFrame struct {
	Address    string  `json:"address"`
	BodyEntry  int     `json:"body_entry"`
	BodyOffset int     `json:"body_offset"`
	BodyTiles  int     `json:"body_tiles"`
	ExtraTiles int     `json:"extra_tiles"` // -1 or group index in res04 entry 6
	ExtraPhase int     `json:"extra_phase"` // obj_anim_frame & 3 used for the render
	Right      *render `json:"right"`
	Left       *render `json:"left"`
}

// npcActionNames labels the actions of tbl_npc_anims (from the renders).
var npcActionNames = []string{
	"stand", "ready stance", "run", "idle (look around)", "arm raised",
	"linesman: stand with flag", "linesman: run with flag", "linesman: signal (flag out / down / up)",
	"referee: yellow card", "referee: red card", "whistle",
	"medic: walk", "medic: kneel", "stretcher",
	"dog: stand / run", "dog: sit", "dog: run with flag", "dog: sit with flag", "dog: wave flag",
	"dog: yellow card", "dog: red card",
}

// validNPCFrame checks a descriptor: +0 res03 entry * 4, +2 offset,
// +4 byte length, +6 extra tile group or -1, +8 piece count - 1, pieces.
func validNPCFrame(f uint32) bool {
	if f&1 != 0 || int(f)+10 > len(rom) {
		return false
	}
	if be16(f)%4 != 0 || be16(f+4)%32 != 0 || be16(f+4) > npcSlotTiles*32 {
		return false
	}
	return piecesOK(f+10, int(be16(f+8))+1)
}

// exportNPCs renders the frames drawn by npc_draw ($033034):
// body tiles are streamed from res03 into the object's VRAM slot; frames
// with an extra group also stream 4 tiles (group + obj_anim_frame & 3)
// from res04 entry 6 into slot tile 18. Left-facing frames set the h-flip
// bit on every piece and use the left x column.
func exportNPCs(dir string) {
	must(os.MkdirAll(filepath.Join(dir, "frames"), 0755))
	extra := rom[entry(grpMisc, entNPCExtra):]
	acts, seqs := walkAnimTable(tblNPCAnims, tblNPCAnimsEnd, validNPCFrame)
	const attr = 0x4000 // obj_attr: palette line 2
	frames := map[string]*npcFrame{}
	for _, as := range seqs {
		for _, seq := range as {
			for pos, f := range seq {
				name := fmt.Sprintf("$%06X", f)
				if frames[name] != nil {
					continue
				}
				fo := &npcFrame{
					Address:    name,
					BodyEntry:  int(be16(f)) / 4,
					BodyOffset: int(be16(f + 2)),
					BodyTiles:  int(be16(f+4)) / 32,
					ExtraTiles: s16(f + 6),
					ExtraPhase: pos & 3,
				}
				slot := make([]byte, npcSlotTiles*32)
				src := entry(grpNPC, fo.BodyEntry) + uint32(fo.BodyOffset)
				copy(slot, rom[src:src+uint32(fo.BodyTiles*32)])
				if fo.ExtraTiles >= 0 {
					o := (fo.ExtraTiles + fo.ExtraPhase) * 0x80
					copy(slot[18*32:], extra[o:o+0x80])
				} else {
					fo.ExtraPhase = 0
				}
				n := int(be16(f+8)) + 1
				var right, left []piece
				for i := 0; i < n; i++ {
					b := f + 10 + uint32(10*i)
					right = append(right, tablePiece(b, false, attr, 0))
					left = append(left, tablePiece(b, true, attr|0x800, 0))
				}
				base := filepath.Join(dir, "frames", fmt.Sprintf("n_%06X", f))
				fo.Right = drawPieces(right, slot, base+"_r.png")
				fo.Left = drawPieces(left, slot, base+"_l.png")
				frames[name] = fo
			}
		}
	}
	var kits [][]uint16
	for v := 0; v < 4; v++ {
		kits = append(kits, officialKit(v))
	}
	writeJSON(filepath.Join(dir, "animations.json"), map[string]any{
		"description": "Referee, linesman, medic, stretcher and dog animations: actions[action].directions[d][obj_anim_frame], " +
			"d = ((facing + 4) & $38) >> 3; the left render is used when ((facing + 4) & 63) >= $28. " +
			"Images are CRAM-index: line 2 for the body (colours 0-7 = kit), line 3 for the shadow.",
		"actions":      acts,
		"action_names": npcActionNames,
		"frames":       frames,
	})
	writeJSON(filepath.Join(dir, "kits.json"), map[string]any{
		"description": "Officials' kit variants: 8 CRAM words copied to palette line 2 colours 0-7 at kick-off. " +
			"Variant = $FF164A (chosen before the match), or 3 when $FF125E is set.",
		"variants": kits,
	})
	fmt.Printf("npc: %d actions, %d frames\n", len(acts), len(frames))
}

// officialKit returns kit variant v as colours.
func officialKit(v int) []uint16 {
	k := entry(grpMisc, entOfficialKits) + uint32(16*v)
	var out []uint16
	for i := uint32(0); i < 8; i++ {
		out = append(out, uint16(be16(k+2*i)))
	}
	return out
}

// stadiumLine returns palette line 3 of stadium st for g_weather w.
func stadiumLine(st, w int) []uint16 {
	pal := unpack(entry(grpStadium0+st, 6+w))
	var out []uint16
	for i := 0; i < 16; i++ {
		out = append(out, uint16(be16s(pal, 2*i)))
	}
	return out
}

func setLine(img *image.RGBA, line int, words []uint16) {
	for i, w := range words {
		img.SetRGBA(i, line, types.MDColor(w))
	}
}

// ---------------------------------------------------------------------------
// Corner and halfway flags
// ---------------------------------------------------------------------------

const (
	tblFlagAnims = 0x02D56A // flag_draw: [action][frame] -> count-1, pieces
	entFlagTiles = 16       // res04: stadium sprite tiles (flags)
)

// exportFlags renders the six pitch flags drawn by flag_draw ($02D50C).
// load_stadium_tiles places them at the pitch corners and at both ends of
// the halfway line (tbl_pitch_bounds); flag_animate steps the 4 frames
// every 6 video frames.
func exportFlags(dir string) {
	must(os.MkdirAll(dir, 0755))
	tiles := unpack(entry(grpMisc, entFlagTiles))
	var actions [][]*render
	for a := uint32(0); a < 2; a++ {
		ap := be32(tblFlagAnims + 4*a)
		var frames []*render
		for i := uint32(0); i < 4; i++ {
			f := be32(ap + 4*i)
			n := int(be16(f)) + 1
			var ps []piece
			for k := 0; k < n; k++ {
				ps = append(ps, tablePiece(f+2+uint32(10*k), false, 0, 0))
			}
			frames = append(frames, drawPieces(ps, tiles, filepath.Join(dir, fmt.Sprintf("flag_%d_%d.png", a, i))))
		}
		actions = append(actions, frames)
	}
	writeJSON(filepath.Join(dir, "flags.json"), map[string]any{
		"description": "Corner and halfway flags: actions[action][frame], 4 frames advanced every 6 video frames " +
			"(action 0 during a match). Placed at (left, top), (middle, top), (right, top), (middle, bottom), " +
			"(left, bottom), (right, bottom) of the stadium's pitch_bounds, middle = (left + right) / 2. " +
			"CRAM-index images: pole and shadow on line 3 (colour 15 = shadow), cloth on line 2.",
		"frame_ticks": 6,
		"actions":     actions,
	})
	fmt.Printf("flags: %d actions x 4 frames\n", len(actions))
}

// Small sprites: weather and celebration particles (particle_draw, one piece
// per frame), the lofted ball's landing-point marker and the practice goal
// target.
const (
	tblParticleAnims   = 0x02D946 // 7 actions -> frames -> one 8-byte piece
	tblGoalTarget      = 0x02D6F2 // 2 actions x 7 pieces of 10 bytes
	pieceLandingMarker = 0x02D502 // one piece, tiles of the ball (res04 entry 0)
	entGoalTargetTiles = 18
)

var particleFrames = []uint32{1, 3, 3, 3, 2, 2, 4}

func exportMisc(dir string) {
	must(os.MkdirAll(dir, 0755))
	sets := []struct {
		name    string
		entry   int
		actions []uint32
		note    string
	}{
		{"rain", 12, []uint32{0, 1}, "12 drops in rain: action 0 falls, then action 1 splashes (3 frames)"},
		{"snow", 11, []uint32{2, 3}, "12 flakes in snow: action 2, then action 3"},
		{"confetti", 13, []uint32{4, 5}, "presentation scenes: 14 pieces spinning (2 frames each)"},
		{"sparkle", 14, []uint32{6}, "presentation scene: above the referee (4 frames)"},
	}
	particles := map[string]any{}
	for _, st := range sets {
		tiles := unpack(entry(grpMisc, st.entry))
		acts := map[string][]*render{}
		for _, a := range st.actions {
			ap := be32(tblParticleAnims + 4*a)
			var frames []*render
			for f := uint32(0); f < particleFrames[a]; f++ {
				p := tablePiece(be32(ap+4*f), false, 0, 0)
				frames = append(frames, drawPieces([]piece{p}, tiles,
					filepath.Join(dir, fmt.Sprintf("%s_%d_%d.png", st.name, a, f))))
			}
			acts[fmt.Sprint(a)] = frames
		}
		particles[st.name] = map[string]any{"tiles": fmt.Sprintf("res04 entry %d", st.entry), "use": st.note, "actions": acts}
	}

	marker := drawPieces([]piece{tablePiece(pieceLandingMarker, false, 0, 0)},
		unpack(entry(grpMisc, entBallTiles)), filepath.Join(dir, "landing_marker.png"))

	tiles := unpack(entry(grpMisc, entGoalTargetTiles))
	var target []*render
	for a := uint32(0); a < 2; a++ {
		ap := be32(tblGoalTarget + 4*a)
		var ps []piece
		for k := uint32(0); k < 7; k++ {
			ps = append(ps, tablePiece(ap+10*k, false, 0, 0))
		}
		target = append(target, drawPieces(ps, tiles, filepath.Join(dir, fmt.Sprintf("goal_target_%d.png", a))))
	}

	writeJSON(filepath.Join(dir, "misc.json"), map[string]any{
		"description": "Small sprites (CRAM-index images, origin = object position). particles: particle_draw frames " +
			"per tile set; landing_marker: shown at the ball's target after a lofted kick until the ball arrives " +
			"within 8 px or another player touches it; goal_target: practice panel over one half of the goal, drawn " +
			"every other frame (see-through), action 1 once a goal is scored through it.",
		"particles":      particles,
		"landing_marker": marker,
		"goal_target":    target,
	})
	fmt.Printf("misc: particles (rain, snow, confetti, sparkle), landing marker, goal target\n")
}
