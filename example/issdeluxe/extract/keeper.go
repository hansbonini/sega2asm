package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
)

// The goalkeepers have their own frame set, drawn by obj_set_frame_draw_draw
// ($02DA56) for player object 0 of each side (and the shoot-out's and the
// edit screens' keeper): tbl_keeper_anims[action][direction][frame] ->
// descriptor, 16 directions ((facing + 2) & $3C) / 4, the left half drawn
// h-flipped. A descriptor is
//
//	+0 res02 entry * 4, +2 tile offset, +4 tile bytes, +6 piece count - 1,
//	then 10-byte pieces: y, size (byte at +2), attribute word, x (right), x (left)
//
// The tiles are whole (no separate head, kit or hair); the attribute word is
// ORed with obj_attr, which gives the side's palette line (0 home, 1 away),
// so a keeper is coloured by his team's kit palette (colours 1-3).
const (
	keeperFrameTable = 0x02DC2C
	grpKeeper        = 2
)

// keeperActionNames labels the keeper's obj_action values from the routines
// that set them (keeper_update, keeper_hold ... shootout_keeper).
var keeperActionNames = []string{
	"stand", "hold the ball", "jog on the spot", "turn step", "side step", "shuffle step",
	"run", "walk", "run with the ball", "sprint (?)", "pull up", "turn",
	"knee trap", "short poke", "kick from the hands", "roll the ball out", "kick to the left",
	"kick to the right / throw release", "throw wind-up", "(19)", "(20)", "jump", "full-length dive",
	"side dive (smother) left", "side dive (smother) right", "get up", "stumble",
	"shoot-out: wait", "shoot-out: stand still", "(29)", "shoot-out: jump with both arms",
	"shoot-out: crouch", "shoot-out: one-arm reach", "shoot-out: step across", "shoot-out: dive left",
	"shoot-out: dive right", "(36)",
}

func exportKeeperAnimations(dir string) {
	must(os.MkdirAll(filepath.Join(dir, "frames"), 0755))
	var actions []uint32
	for a := uint32(keeperFrameTable); ; a += 4 {
		v := be32(a)
		if v < 0x20000 || v >= 0x40000 || a >= actions0(actions) {
			break
		}
		actions = append(actions, v)
	}
	frames := map[uint32]*render{}
	frameLeft := map[uint32]*render{}
	type actionOut struct {
		Index      int        `json:"index"`
		Name       string     `json:"name"`
		Address    string     `json:"address"`
		Directions [][]string `json:"directions"`
	}
	var out []actionOut
	for i, ap := range actions {
		name := ""
		if i < len(keeperActionNames) {
			name = keeperActionNames[i]
		}
		ao := actionOut{Index: i, Name: name, Address: fmt.Sprintf("$%06X", ap)}
		dirs := make([]uint32, 16)
		for k := range dirs {
			dirs[k] = be32(ap + uint32(4*k))
		}
		ends := boundaries(dirs)
		for _, dp := range dirs {
			var seq []string
			for fa := dp; fa < ends[dp]; fa += 4 {
				f := be32(fa)
				if f < 0x20000 || f >= 0x40000 || !validKeeperFrame(f) {
					break
				}
				seq = append(seq, fmt.Sprintf("$%06X", f))
				if _, ok := frames[f]; !ok {
					frames[f] = renderKeeperFrame(f, false, dir)
					frameLeft[f] = renderKeeperFrame(f, true, dir)
				}
			}
			ao.Directions = append(ao.Directions, seq)
		}
		out = append(out, ao)
	}
	var addrs []uint32
	for a := range frames {
		addrs = append(addrs, a)
	}
	sort.Slice(addrs, func(i, j int) bool { return addrs[i] < addrs[j] })
	fm := map[string]any{}
	for _, a := range addrs {
		fm[fmt.Sprintf("$%06X", a)] = map[string]any{
			"address": fmt.Sprintf("$%06X", a), "tiles_entry": int(be16(a)) / 4,
			"right": frames[a], "left": frameLeft[a],
		}
	}
	writeJSON(filepath.Join(dir, "animations.json"), map[string]any{
		"description": "Goalkeeper animations (tbl_keeper_anims): actions[action].directions[d] lists frame " +
			"addresses, d = ((facing + 2) & $3C) >> 2 with facing 0-63 (16 directions); directions 8-15 use " +
			"the left render (h-flipped, the descriptor's left x). Frames are CRAM-index images on palette " +
			"line 0: colour the keeper with his team's kit palette (the keeper colours are 1-3).",
		"actions": out,
		"frames":  fm,
	})
	fmt.Printf("keepers: %d actions, %d unique frames\n", len(out), len(frames))
}

// validKeeperFrame sanity-checks a keeper frame descriptor.
func validKeeperFrame(f uint32) bool {
	if f&1 != 0 || int(f)+8 > len(rom) {
		return false
	}
	if be16(f)%4 != 0 || int(be16(f))/4 >= groupEntries(grpKeeper) || be16(f+4)%32 != 0 || be16(f+4) > 64*32 {
		return false
	}
	n := be16(f+6) + 1
	if n > 32 {
		return false
	}
	for i := uint32(0); i < n; i++ {
		b := f + 8 + 10*i
		if rom[b+2] > 15 {
			return false
		}
	}
	return true
}

func renderKeeperFrame(f uint32, left bool, dir string) *render {
	e := int(be16(f)) / 4
	tiles := entry(grpKeeper, e) + be16(f+2)
	nb := be16(f + 4)
	slot := make([]byte, 64*32)
	copy(slot, rom[tiles:tiles+nb])
	n := int(be16(f+6)) + 1
	var ps []piece
	for i := 0; i < n; i++ {
		b := f + 8 + uint32(10*i)
		size := int(rom[b+2])
		aw := be16(b + 4)
		x := s16(b + 6)
		hflip := aw&0x800 != 0
		if left {
			x = s16(b + 8)
			hflip = !hflip
		}
		ps = append(ps, piece{
			X: x - 128, Y: s16(b) - 128, W: (size>>2)&3 + 1, H: size&3 + 1,
			Tile: int(aw & 0x7FF), Line: int(aw>>13) & 3, HFlip: hflip, VFlip: aw&0x1000 != 0,
			Priority: aw&0x8000 != 0,
		})
	}
	side := "r"
	if left {
		side = "l"
	}
	return drawPieces(ps, slot, filepath.Join(dir, "frames", fmt.Sprintf("k_%06X_%s.png", f, side)))
}
