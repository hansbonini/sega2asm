package analysis

import (
	"fmt"
	"sort"

	"sega2asm/disasm/m68k"
	"sega2asm/types"
)

// SegOptions controls how a traced address range is turned into segments.
type SegOptions struct {
	Prefix      string // segment name prefix for code (default "code")
	DataPrefix  string // segment name prefix for data (default "data")
	SubDir      string // output sub-directory for all generated segments
	MaxCodeSize uint32 // split code segments close to this size (default $4000)
	MaxHintSize uint32 // data gaps inside code up to this size become hints (default $400)
	MaxDataSize uint32 // larger gaps up to this size become "data" segments, else "bin" (default $2000)
	// IsText reports whether a byte belongs to the game's text encoding
	// (used to type small data gaps as text). nil disables text detection.
	IsText func(b byte) bool
	// TextEnd is the string terminator used for text detection.
	TextEnd byte
}

func (o *SegOptions) defaults() {
	if o.Prefix == "" {
		o.Prefix = "code"
	}
	if o.DataPrefix == "" {
		o.DataPrefix = "data"
	}
	if o.MaxCodeSize == 0 {
		o.MaxCodeSize = 0x4000
	}
	if o.MaxHintSize == 0 {
		o.MaxHintSize = 0x400
	}
	if o.MaxDataSize == 0 {
		o.MaxDataSize = 0x2000
	}
}

type run struct {
	start, end uint32
	code       bool
}

func (r *Result) runs(start, end uint32) []run {
	var out []run
	for a := start; a < end; {
		c := r.Kind[a] == CodeHead || r.Kind[a] == CodeTail
		b := a + 1
		for b < end && (r.Kind[b] == CodeHead || r.Kind[b] == CodeTail) == c {
			b++
		}
		out = append(out, run{a, b, c})
		a = b
	}
	return out
}

// labelPoints returns every address in [a,b) that must start a new data
// piece: cross-referenced addresses, table starts and table targets.
func (r *Result) labelPoints(a, b uint32) []uint32 {
	set := map[uint32]bool{}
	for x := range r.Xrefs {
		if x > a && x < b {
			set[x] = true
		}
	}
	for _, t := range r.Tables {
		if t.Addr > a && t.Addr < b {
			set[t.Addr] = true
		}
		if end := t.Addr + t.Size(); end > a && end < b && t.Size() > 0 {
			set[end] = true
		}
	}
	for x := range r.Entries {
		if x > a && x < b {
			set[x] = true
		}
	}
	out := make([]uint32, 0, len(set))
	for x := range set {
		out = append(out, x)
	}
	sort.Slice(out, func(i, j int) bool { return out[i] < out[j] })
	return out
}

func (r *Result) tableAt(a uint32) *Table {
	for _, t := range r.Tables {
		if t.Addr == a && t.Kind != TableBranch {
			return t
		}
	}
	return nil
}

// dataHints types the data gap [a,b) inside a code segment starting at segStart.
func (r *Result) dataHints(segStart, a, b uint32, o SegOptions) []types.Hint {
	cuts := append([]uint32{a}, r.labelPoints(a, b)...)
	cuts = append(cuts, b)
	var hints []types.Hint
	for i := 0; i+1 < len(cuts); i++ {
		p, q := cuts[i], cuts[i+1]
		if q <= p {
			continue
		}
		h := types.Hint{Offset: p - segStart, Length: int(q - p), Type: r.guessType(p, q, o)}
		if t := r.tableAt(p); t != nil {
			switch t.Kind {
			case TableLong:
				h.Type = "ptr_table"
				if n := int(t.Size()); n < h.Length {
					h.Length = n
				}
			case TableWordRel:
				h.Type = "ptr_table_rel"
				h.Base = types.HexInt(t.Base)
				if n := int(t.Size()); n < h.Length {
					h.Length = n
				}
			}
			if h.Length < int(q-p) {
				hints = append(hints, h)
				rest := types.Hint{Offset: p + uint32(h.Length) - segStart, Length: int(q-p) - h.Length}
				rest.Type = r.guessType(p+uint32(h.Length), q, o)
				hints = append(hints, rest)
				continue
			}
		}
		hints = append(hints, h)
	}
	return hints
}

// guessType picks a hint type for the data range [a,b).
func (r *Result) guessType(a, b uint32, o SegOptions) string {
	n := b - a
	data := r.ROM[a:b]
	if o.IsText != nil && n >= 3 {
		text, ends := 0, 0
		for _, c := range data {
			if o.IsText(c) {
				text++
			} else if c == o.TextEnd {
				ends++
			}
		}
		if ends > 0 && text+ends == int(n) && text >= 2*ends {
			return "text"
		}
	}
	if a&1 == 0 && n%4 == 0 && n >= 8 {
		ptrs := true
		for i := uint32(0); i < n; i += 4 {
			v := be32(r.ROM, a+i)
			if v < 0x200 || v >= uint32(len(r.ROM)) || v&1 != 0 {
				ptrs = false
				break
			}
			// Every entry must point at something the trace knows about.
			_, isEntry := r.Entries[v]
			_, isRef := r.Xrefs[v]
			if !isEntry && !isRef {
				ptrs = false
				break
			}
		}
		if ptrs {
			return "ptr_table"
		}
	}
	if a&1 == 0 && n >= 2 {
		return "data_word"
	}
	return "data_byte"
}

// isSplitPoint reports whether a code segment may start at a.
func (r *Result) isSplitPoint(a uint32) bool {
	if _, ok := r.Entries[a]; !ok {
		return false
	}
	// Previous instruction must not fall through into a.
	for back := uint32(2); back <= 10 && back <= a; back += 2 {
		if in, ok := r.Insns[a-back]; ok && a-back+uint32(len(in.Bytes)) == a {
			return in.Flow == m68k.FlowReturn || in.Flow == m68k.FlowJump || in.Flow == m68k.FlowHalt
		}
	}
	return true
}

// Segments converts the traced range [start,end) into sega2asm segments:
// m68k segments (with inline data hints for small gaps) and data / bin
// segments for larger data blocks, split at referenced addresses.
func (r *Result) Segments(start, end uint32, o SegOptions) []types.Segment {
	o.defaults()
	runs := r.runs(start, end)
	var segs []types.Segment
	no := false

	// Group code runs with their small gaps into blocks.
	type block struct {
		start, end uint32
		code       bool
	}
	var blocks []block
	for i := 0; i < len(runs); i++ {
		rn := runs[i]
		if !rn.code {
			small := rn.end-rn.start <= o.MaxHintSize
			between := i > 0 && i+1 < len(runs)
			if small && between && len(blocks) > 0 && blocks[len(blocks)-1].code {
				blocks[len(blocks)-1].end = rn.end
				continue
			}
			blocks = append(blocks, block{rn.start, rn.end, false})
			continue
		}
		if len(blocks) > 0 && blocks[len(blocks)-1].code {
			blocks[len(blocks)-1].end = rn.end
		} else {
			blocks = append(blocks, block{rn.start, rn.end, true})
		}
	}
	// A code block must not end with a data gap: move trailing data out.
	for i := range blocks {
		if !blocks[i].code {
			continue
		}
		e := blocks[i].end
		for e > blocks[i].start && !(r.Kind[e-1] == CodeHead || r.Kind[e-1] == CodeTail) {
			e--
		}
		if e < blocks[i].end {
			rest := block{e, blocks[i].end, false}
			blocks[i].end = e
			blocks = append(blocks[:i+1], append([]block{rest}, blocks[i+1:]...)...)
		}
	}

	for _, bl := range blocks {
		if bl.code {
			// Split into files near MaxCodeSize at function boundaries.
			cuts := []uint32{bl.start}
			last := bl.start
			for _, e := range r.SortedEntries() {
				if e <= bl.start || e >= bl.end {
					continue
				}
				if e-last >= o.MaxCodeSize && r.isSplitPoint(e) && (r.Kind[e] == CodeHead) {
					cuts = append(cuts, e)
					last = e
				}
			}
			cuts = append(cuts, bl.end)
			for i := 0; i+1 < len(cuts); i++ {
				s := types.Segment{
					Name:       fmt.Sprintf("%s_%06X", o.Prefix, cuts[i]),
					Type:       "m68k",
					Start:      types.HexInt(cuts[i]),
					End:        types.HexInt(cuts[i+1]),
					SubDir:     o.SubDir,
					Heuristics: &no,
				}
				for _, rn := range r.runs(cuts[i], cuts[i+1]) {
					if !rn.code {
						s.Hints = append(s.Hints, r.dataHints(cuts[i], rn.start, rn.end, o)...)
					}
				}
				segs = append(segs, s)
			}
			continue
		}
		// Data block.
		if bl.end-bl.start <= o.MaxDataSize {
			segs = append(segs, types.Segment{
				Name:   fmt.Sprintf("%s_%06X", o.DataPrefix, bl.start),
				Type:   "data",
				Start:  types.HexInt(bl.start),
				End:    types.HexInt(bl.end),
				SubDir: o.SubDir,
			})
			continue
		}
		cuts := append([]uint32{bl.start}, r.labelPoints(bl.start, bl.end)...)
		cuts = append(cuts, bl.end)
		for i := 0; i+1 < len(cuts); i++ {
			segs = append(segs, types.Segment{
				Name:   fmt.Sprintf("%s_%06X", o.DataPrefix, cuts[i]),
				Type:   "bin",
				Start:  types.HexInt(cuts[i]),
				End:    types.HexInt(cuts[i+1]),
				SubDir: o.SubDir,
			})
		}
	}
	return segs
}
