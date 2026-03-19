package splitter

import (
	"fmt"
	"sort"
	"strings"

	"sega2asm/config"
	"sega2asm/disasm/m68k"
	"sega2asm/symbols"
)

// splitSuggestion represents a suggested segment boundary.
type splitSuggestion struct {
	addr    uint32
	reasons []string
}

// suggestM68KSplits analyses disassembly results and returns YAML-ready split
// suggestion lines. A boundary is suggested when an address is:
//
//   - a JSR/BSR target that immediately follows a flow terminator (strong), or
//   - a JSR/BSR target called more than once (medium).
func (s *Splitter) suggestM68KSplits(results []m68k.Result, seg config.Segment, syms *symbols.Table) []string {
	segStart := uint32(seg.Start)
	segEnd := uint32(seg.End)

	// callCount[addr] = number of JSR/BSR instructions targeting addr.
	callCount := map[uint32]int{}
	// afterTerminator[addr] = true if addr immediately follows rts/rte/jmp/bra/illegal.
	afterTerminator := map[uint32]bool{}

	prevTerminator := false
	for i, res := range results {
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
			// Unconditional jmp/bra is also a terminator.
			prevTerminator = true
		}
		_ = i
	}

	// Build suggestion map.
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

	// Keep only strong (called + after terminator) or heavily called (≥2).
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

	if len(suggestions) == 0 {
		return nil
	}

	sort.Slice(suggestions, func(i, j int) bool {
		return suggestions[i].addr < suggestions[j].addr
	})

	var lines []string
	lines = append(lines, fmt.Sprintf("[HINT] Split suggestions for %q ($%06X–$%06X) — %d boundaries:",
		seg.Name, segStart, segEnd, len(suggestions)))

	// Build ordered boundary list: segStart + suggested + segEnd.
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
