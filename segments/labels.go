package segments

import (
	"fmt"
	"sort"
	"strings"

	"sega2asm/disasm/m68k"
	"sega2asm/types"
)

// segmentDefinesStart reports whether a segment of this type emits a label
// at its start address in the ROM address space.
func segmentDefinesStart(seg types.Segment) bool {
	switch strings.ToLower(seg.Type) {
	case "header":
		return false
	case "z80":
		// Only the dc.b form is assembled in the 68000 address space.
		return strings.EqualFold(seg.Format, "bytes")
	}
	return true
}

// CollectLabels performs the global label pass. It decodes every m68k
// segment once, records every address that will be defined in the output
// (instruction and hint boundaries, segment starts), gathers all operand
// references and assigns names:
//
//	symbols file > hint label > segment name > sub_ > loc_ > dat_
//
// Addresses outside the ROM keep only the names from the symbols file; they
// are emitted as equates.
func CollectLabels(cfg *types.Config, rom *types.ROM, syms *types.SymbolTable, warn func(string, ...any)) *types.Labels {
	l := types.NewLabels()
	romSize := uint32(len(rom.Data))
	definable := map[uint32]bool{}
	insnStart := map[uint32]bool{}

	var refs []labelRef

	for _, seg := range cfg.Segments {
		start := uint32(seg.Start)
		if segmentDefinesStart(seg) {
			definable[start] = true
		}
		switch strings.ToLower(seg.Type) {
		case "m68k":
			items := disasmM68KSegment(rom.Data, seg, m68k.BlockOptions{
				Heuristics: cfg.HeuristicsEnabled(seg),
				Literal:    literalSet(seg),
			})
			for _, it := range items {
				definable[it.Addr] = true
				if it.Hint != nil {
					refs = append(refs, hintRefs(rom.Data, it)...)
					if interiorLabels(it.Hint.Type) {
						for a := it.Addr; a < it.Addr+it.Size; a++ {
							definable[a] = true
						}
					}
					continue
				}
				if !it.Res.IsValid {
					continue
				}
				insnStart[it.Addr] = true
				r := it.Res
				for _, rf := range r.Refs {
					switch rf.Kind {
					case m68k.RefCode:
						k := types.LabelLoc
						if r.Flow == m68k.FlowCall || r.Mnemonic == "jmp" {
							k = types.LabelSub
						}
						refs = append(refs, labelRef{addr: rf.Addr, kind: k})
					case m68k.RefImm:
						refs = append(refs, labelRef{addr: rf.Addr, kind: types.LabelSub, imm: true})
					default:
						refs = append(refs, labelRef{addr: rf.Addr, kind: types.LabelData})
					}
				}
			}
		case "data", "text":
			for a := start; a < uint32(seg.End) && a < romSize; a++ {
				definable[a] = true
			}
		case "table":
			for _, t := range tableTargets(rom.Data, seg) {
				refs = append(refs, labelRef{addr: t, kind: types.LabelData})
			}
		case "header":
			for i := 1; i < 64; i++ {
				v := be32(rom.Data, uint32(i*4))
				refs = append(refs, labelRef{addr: v, kind: types.LabelSub})
			}
		}
	}

	// 1. Symbols file.
	for _, s := range syms.Ordered {
		if s.Addr < romSize {
			if !definable[s.Addr] {
				warn("symbol %s = $%06X is not on an instruction/segment boundary; not emitted", s.Name, s.Addr)
				continue
			}
		}
		if l.Set(s.Addr, s.Name, types.LabelUser) && s.Comment != "" {
			l.Comments[s.Addr] = s.Comment
		}
	}
	// 2. Hint labels.
	for _, seg := range cfg.Segments {
		hs, dropped := sortedHints(seg)
		for _, h := range dropped {
			warn("segment %s: hint at +$%X overlaps a previous hint or the segment end; ignored", seg.Name, h.Offset)
		}
		for _, h := range hs {
			if h.Label != "" {
				l.Set(uint32(seg.Start)+h.Offset, h.Label, types.LabelHint)
			}
		}
	}
	// 3. Segment names.
	for _, seg := range cfg.Segments {
		if seg.Name != "" && segmentDefinesStart(seg) {
			if !l.Set(uint32(seg.Start), seg.Name, types.LabelSegment) {
				if other, ok := l.ByName[seg.Name]; ok && other != uint32(seg.Start) {
					warn("segment name %s is already used for $%06X", seg.Name, other)
				}
			}
		}
	}
	// 4. Automatic names for referenced ROM addresses.
	sort.SliceStable(refs, func(i, j int) bool { return refs[i].kind < refs[j].kind })
	for _, r := range refs {
		if r.addr >= romSize || !definable[r.addr] {
			continue
		}
		if r.imm {
			// Only name immediates that point at code (callbacks, state
			// pointers); constants are left alone.
			if !insnStart[r.addr] || r.addr&0xFFF == 0 || r.addr < 0x200 {
				continue
			}
		}
		prefix := "dat"
		switch r.kind {
		case types.LabelSub:
			prefix = "sub"
		case types.LabelLoc:
			prefix = "loc"
		}
		if r.kind == types.LabelData && insnStart[r.addr] {
			prefix = "loc"
		}
		l.Set(r.addr, fmt.Sprintf("%s_%06X", prefix, r.addr), r.kind)
	}

	// Immediate-eligible subset.
	for a, n := range l.ByAddr {
		switch l.Kind[a] {
		case types.LabelUser, types.LabelHint, types.LabelSegment:
			l.Imm[a] = n
		case types.LabelSub:
			if a&0xFFF != 0 {
				l.Imm[a] = n
			}
		}
	}
	return l
}

// interiorLabels reports whether a hint type can carry labels at any address
// inside it (it is emitted with WriteData).
func interiorLabels(typ string) bool {
	switch typ {
	case "data_byte", "data_word", "data_long", "text", "skip", "":
		return true
	}
	return false
}

// labelRef is an address referenced from code or data.
type labelRef struct {
	addr uint32
	kind types.LabelKind
	imm  bool
}

// hintRefs returns the addresses referenced by pointer-table hints.
func hintRefs(rom []byte, it m68kItem) []labelRef {
	var out []labelRef
	h := it.Hint
	end := it.Addr + it.Size
	switch h.Type {
	case "ptr_table":
		for a := it.Addr; a+4 <= end; a += 4 {
			out = append(out, labelRef{be32(rom, a), types.LabelSub, false})
		}
	case "ptr_table_rel":
		base := uint32(h.Base)
		for a := it.Addr; a+2 <= end; a += 2 {
			t := uint32(int32(base) + int32(int16(be16(rom, a))))
			out = append(out, labelRef{t, types.LabelSub, false})
		}
	}
	return out
}

func be16(b []byte, a uint32) uint16 {
	if int(a)+2 > len(b) {
		return 0
	}
	return uint16(b[a])<<8 | uint16(b[a+1])
}

func be32(b []byte, a uint32) uint32 {
	if int(a)+4 > len(b) {
		return 0
	}
	return uint32(b[a])<<24 | uint32(b[a+1])<<16 | uint32(b[a+2])<<8 | uint32(b[a+3])
}
