package segments

import (
	"fmt"
	"sort"
	"strings"

	"sega2asm/config"
	"sega2asm/disasm/m68k"
	"sega2asm/symbols"
)

type splitSuggestion struct {
	addr    uint32
	reasons []string
}

// suggestM68KSplits analyses disassembly results and returns YAML-ready split
// suggestion lines and boundary-health warnings.
func suggestM68KSplits(results []m68k.Result, seg config.Segment, syms *symbols.Table, rom []byte) []string {
	segStart := uint32(seg.Start)
	segEnd := uint32(seg.End)

	callCount := map[uint32]int{}
	afterTerminator := map[uint32]bool{}

	var boundaryWarnings []string

	prevTerminator := false
	for _, res := range results {
		if prevTerminator && res.Addr > segStart && res.Addr < segEnd {
			afterTerminator[res.Addr] = true
		}
		prevTerminator = false

		switch res.Flow {
		case m68k.FlowCall:
			t := res.Target
			if t > segStart && t < segEnd {
				callCount[t]++
			}
		case m68k.FlowReturn, m68k.FlowHalt:
			prevTerminator = true
		case m68k.FlowJump:
			prevTerminator = true
		}
	}

	// Check: segment ends mid-function.
	lastCodeFlow := m68k.FlowNone
	lastCodeAddr := uint32(0)
	for i := len(results) - 1; i >= 0; i-- {
		res := results[i]
		if strings.HasPrefix(res.Text, "\tdc.") {
			continue
		}
		lastCodeFlow = res.Flow
		lastCodeAddr = res.Addr
		break
	}
	isTerminated := lastCodeFlow == m68k.FlowReturn ||
		lastCodeFlow == m68k.FlowJump ||
		lastCodeFlow == m68k.FlowHalt
	if lastCodeAddr != 0 && !isTerminated {
		boundaryWarnings = append(boundaryWarnings,
			fmt.Sprintf("  [WARN] segment %q ends mid-function at $%06X (last insn has no flow terminator) — end boundary may be too early",
				seg.Name, lastCodeAddr))

		newEnd := "0x??????"
		segEndOff := int(seg.End)
		for off := segEndOff; off+1 < len(rom); off += 2 {
			if rom[off] == 0x4E && (rom[off+1] == 0x75 || rom[off+1] == 0x73) {
				newEnd = fmt.Sprintf("0x%06X", off+2)
				break
			}
		}

		boundaryWarnings = append(boundaryWarnings, "  Suggested fix (extend end to include the missing rts):")
		boundaryWarnings = append(boundaryWarnings, fmt.Sprintf("    - name: %s", seg.Name))
		boundaryWarnings = append(boundaryWarnings, fmt.Sprintf("      type: %s", seg.Type))
		boundaryWarnings = append(boundaryWarnings, fmt.Sprintf("      start: 0x%06X", uint32(seg.Start)))
		boundaryWarnings = append(boundaryWarnings, fmt.Sprintf("      end:   %s", newEnd))
	}

	hints := map[uint32]*splitSuggestion{}
	add := func(addr uint32, reason string) {
		h, ok := hints[addr]
		if !ok {
			h = &splitSuggestion{addr: addr}
			hints[addr] = h
		}
		h.reasons = append(h.reasons, reason)
	}

	for addr, n := range callCount {
		r := "jsr_target"
		if n > 1 {
			r = fmt.Sprintf("jsr_target×%d", n)
		}
		add(addr, r)
	}
	for addr := range afterTerminator {
		add(addr, "after_terminator")
	}

	var suggestions []splitSuggestion
	for addr, h := range hints {
		hasCall := false
		hasTerm := false
		for _, r := range h.reasons {
			if strings.HasPrefix(r, "jsr_target") {
				hasCall = true
			}
			if r == "after_terminator" {
				hasTerm = true
			}
		}
		if (hasCall && hasTerm) || callCount[addr] >= 2 {
			suggestions = append(suggestions, *h)
		}
	}

	if len(suggestions) == 0 && len(boundaryWarnings) == 0 {
		return nil
	}

	sort.Slice(suggestions, func(i, j int) bool {
		return suggestions[i].addr < suggestions[j].addr
	})

	var lines []string
	lines = append(lines, boundaryWarnings...)

	if len(suggestions) == 0 {
		return lines
	}

	lines = append(lines, fmt.Sprintf("[HINT] Split suggestions for %q ($%06X–$%06X) — %d boundaries:",
		seg.Name, segStart, segEnd, len(suggestions)))

	boundaries := make([]uint32, 0, len(suggestions)+2)
	boundaries = append(boundaries, segStart)
	for _, sg := range suggestions {
		boundaries = append(boundaries, sg.addr)
	}
	boundaries = append(boundaries, segEnd)

	for i := 0; i < len(boundaries)-1; i++ {
		start := boundaries[i]
		end := boundaries[i+1]
		name := syms.Label(start)
		if name == "" {
			name = fmt.Sprintf("sub_%06X", start)
		}

		comment := ""
		if h, ok := hints[start]; ok {
			comment = "  # " + strings.Join(h.reasons, ", ")
		}

		lines = append(lines, fmt.Sprintf("  - name: %s%s", name, comment))
		lines = append(lines, "    type: m68k")
		lines = append(lines, fmt.Sprintf("    start: 0x%06X", start))
		lines = append(lines, fmt.Sprintf("    end:   0x%06X", end))
	}
	return lines
}
