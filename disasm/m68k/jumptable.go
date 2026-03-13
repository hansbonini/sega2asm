package m68k

import "fmt"

// detectJumpTables performs a post-disassembly pass and replaces bytes that
// immediately follow a flow terminator with dc.l entries when those bytes look
// like a table of valid Genesis/Mega Drive code pointers.
//
// Trigger: any result with FlowJump or FlowHalt.
// Entry test: 32-bit value where the high byte is 0x00 (ROM range), the
// address is word-aligned, and >= 0x000200 (past the vector table).
// Minimum 2 consecutive valid entries required to trigger.
//
// After a detected table, disassembly continues as normal code.
func detectJumpTables(results []Result, data []byte, segBase uint32, labels map[uint32]string) []Result {
	if len(results) == 0 {
		return results
	}

	type insertion struct {
		afterIdx int
		entries  []Result
	}

	skip := make([]bool, len(results))
	var inserts []insertion

	for i, res := range results {
		if res.Flow != FlowJump && res.Flow != FlowHalt {
			continue
		}

		// Table candidate starts at the first byte after this instruction.
		tableBase := res.Addr + uint32(len(res.Bytes))
		off := int(tableBase - segBase)

		// Read consecutive valid jump table entries (4-byte long addresses).
		var addrs []uint32
		for off+4 <= len(data) {
			v := uint32(data[off])<<24 | uint32(data[off+1])<<16 |
				uint32(data[off+2])<<8 | uint32(data[off+3])
			if !isJumpTableEntry(v) {
				break
			}
			addrs = append(addrs, v)
			off += 4
		}
		if len(addrs) < 2 {
			continue
		}

		tableEnd := tableBase + uint32(len(addrs)*4)

		// Build dc.l Result entries for the table.
		var dcls []Result
		for k, addr := range addrs {
			entryAddr := tableBase + uint32(k*4)
			rawOff := int(entryAddr - segBase)
			var rawBytes []byte
			if rawOff+4 <= len(data) {
				rawBytes = data[rawOff : rawOff+4]
			}
			name := resolveLabel(addr, labels)
			dcls = append(dcls, Result{
				Addr:    entryAddr,
				Bytes:   rawBytes,
				Text:    fmt.Sprintf("\tdc.l\t%s", name),
				IsValid: true,
				Flow:    FlowNone,
			})
		}

		// Mark results that fall inside the table region for removal.
		for j := i + 1; j < len(results); j++ {
			if results[j].Addr >= tableEnd {
				break
			}
			skip[j] = true
		}

		inserts = append(inserts, insertion{afterIdx: i, entries: dcls})
	}

	if len(inserts) == 0 {
		return results
	}

	// Build a map: resultIndex → dc.l entries to insert after it.
	insertAfter := make(map[int][]Result, len(inserts))
	for _, ins := range inserts {
		insertAfter[ins.afterIdx] = ins.entries
	}

	out := make([]Result, 0, len(results))
	for i, res := range results {
		if skip[i] {
			continue
		}
		out = append(out, res)
		if extra, ok := insertAfter[i]; ok {
			out = append(out, extra...)
		}
	}
	return out
}

// isJumpTableEntry returns true for 32-bit values that look like valid Genesis
// code pointers: high byte must be 0x00 (ROM 0–4 MB range), address must be
// word-aligned and above the vector table ($000200).
func isJumpTableEntry(addr uint32) bool {
	if addr>>24 != 0x00 {
		return false
	}
	lo := addr & 0x00FFFFFF
	return lo >= 0x000200 && lo <= 0x3FFFFF && lo&1 == 0
}

// resolveLabel returns the symbolic name for addr from the labels map, or a
// hex literal if addr is not a known label.
func resolveLabel(addr uint32, labels map[uint32]string) string {
	if name, ok := labels[addr]; ok {
		return name
	}
	return fmt.Sprintf("$%06X", addr&0x00FFFFFF)
}
