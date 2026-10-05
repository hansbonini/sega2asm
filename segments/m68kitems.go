package segments

import (
	"sort"

	"sega2asm/disasm/m68k"
	"sega2asm/types"
)

// m68kItem is one emitted element of an m68k segment: either a decoded
// instruction or an inline data hint.
type m68kItem struct {
	Addr uint32
	Size uint32
	Hint *types.Hint
	Res  *m68k.Result
}

// sortedHints returns the segment's hints ordered by offset with overlapping
// or out-of-range hints removed. The second result lists dropped hints.
func sortedHints(seg types.Segment) ([]types.Hint, []types.Hint) {
	size := uint32(seg.End) - uint32(seg.Start)
	hs := append([]types.Hint(nil), seg.Hints...)
	sort.SliceStable(hs, func(i, j int) bool { return hs[i].Offset < hs[j].Offset })
	var out, dropped []types.Hint
	end := uint32(0)
	for _, h := range hs {
		n := uint32(h.Length)
		if h.Length <= 0 {
			n = 1
		}
		if h.Offset < end || h.Offset+n > size {
			dropped = append(dropped, h)
			continue
		}
		out = append(out, h)
		end = h.Offset + n
	}
	return out, dropped
}

// disasmM68KSegment splits seg into code runs and hints and disassembles the
// code runs independently, so hints never desynchronise the instruction
// stream. rom is the whole ROM (mapped at address 0).
func disasmM68KSegment(rom []byte, seg types.Segment, o m68k.BlockOptions) []m68kItem {
	start := uint32(seg.Start)
	end := uint32(seg.End)
	if int(end) > len(rom) {
		end = uint32(len(rom))
	}
	hints, _ := sortedHints(seg)
	var items []m68kItem
	code := func(from, to uint32) {
		if to <= from {
			return
		}
		for _, r := range m68k.DisassembleRange(rom, from, to, o) {
			r := r
			items = append(items, m68kItem{Addr: r.Addr, Size: uint32(len(r.Bytes)), Res: &r})
		}
	}
	cur := start
	for i := range hints {
		h := &hints[i]
		ha := start + h.Offset
		code(cur, ha)
		n := uint32(h.Length)
		if h.Length <= 0 {
			n = 1
		}
		if h.Type == "code" {
			code(ha, ha+n)
		} else {
			items = append(items, m68kItem{Addr: ha, Size: n, Hint: h})
		}
		cur = ha + n
	}
	code(cur, end)
	return items
}

// literalSet returns the segment's literal instruction addresses as a set.
func literalSet(seg types.Segment) map[uint32]bool {
	if len(seg.Literal) == 0 {
		return nil
	}
	m := make(map[uint32]bool, len(seg.Literal))
	for _, a := range seg.Literal {
		m[uint32(a)] = true
	}
	return m
}
