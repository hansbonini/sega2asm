package splitter

import (
	"fmt"
	"regexp"
	"strconv"
)

// hwPort maps a hardware register address to its canonical name.
type hwPort struct {
	addr uint32
	name string
}

// genesisHWPorts lists all known Sega Genesis / Mega Drive hardware I/O registers.
var genesisHWPorts = []hwPort{
	// VDP
	{0x00C00000, "VDP_DATA"},
	{0x00C00002, "VDP_DATA_W"},
	{0x00C00004, "VDP_CTRL"},
	{0x00C00006, "VDP_CTRL_W"},
	{0x00C00008, "VDP_HVCOUNTER"},
	{0x00C0001C, "VDP_DEBUG"},
	// PSG
	{0x00C00011, "PSG_DATA"},
	// Z80
	{0x00A00000, "Z80_RAM"},
	{0x00A11100, "Z80_BUSREQ"},
	{0x00A11200, "Z80_RESET"},
	// I/O
	{0x00A10001, "IO_PCBVER"},
	{0x00A10003, "IO_DATA_1"},
	{0x00A10005, "IO_DATA_2"},
	{0x00A10007, "IO_DATA_EXP"},
	{0x00A10009, "IO_CTRL_1"},
	{0x00A1000B, "IO_CTRL_2"},
	{0x00A1000D, "IO_CTRL_EXP"},
	{0x00A1000F, "IO_TXDATA_1"},
	{0x00A10011, "IO_RXDATA_1"},
	{0x00A10013, "IO_SCTRL_1"},
	{0x00A10015, "IO_TXDATA_2"},
	{0x00A10017, "IO_RXDATA_2"},
	{0x00A10019, "IO_SCTRL_2"},
	{0x00A1001B, "IO_TXDATA_EXP"},
	{0x00A1001D, "IO_RXDATA_EXP"},
	{0x00A1001F, "IO_SCTRL_EXP"},
	// Memory control
	{0x00A11000, "MEM_MODE"},
	{0x00A13000, "TIME_REG"},
	{0x00A14000, "TMSS_REG"},
	{0x00A14100, "TMSS_VDP"},
}

// hwAnnotator replaces raw hardware register address literals inside
// disassembled instruction text with the corresponding EQU constant name
// from ports.asm (e.g. "$00C00004" → "VDP_CTRL").
// This makes the generated ASM use the symbolic constants rather than
// hard-coded addresses, so the output assembles correctly with ports.asm.
type hwAnnotator struct {
	// reAddr matches a $ hex literal of 6–8 digits, capturing just the digits.
	// The leading $ is part of the full match (index 0); digits are group 1.
	reAddr *regexp.Regexp
	byAddr map[uint32]string // addr → constant name
}

func newHWAnnotator() *hwAnnotator {
	m := make(map[uint32]string, len(genesisHWPorts)*2)
	for _, p := range genesisHWPorts {
		m[p.addr] = p.name
		// Also register the 24-bit form (strip leading 00) so both
		// "$00C00004" and "$C00004" are recognised.
		m[p.addr&0x00FFFFFF] = p.name
	}
	return &hwAnnotator{
		reAddr: regexp.MustCompile(`(?i)\$([0-9A-F]{6,8})\b`),
		byAddr: m,
	}
}

// annotate replaces every hardware register address literal in line with its
// constant name.  The surrounding syntax (parentheses, size suffix) is kept.
//
//	move.w  d0,($00C00004).l   →   move.w  d0,(VDP_CTRL).l
//	move.b  ($00A10003).l,d1   →   move.b  (IO_DATA_1).l,d1
func (a *hwAnnotator) annotate(line string) string {
	return a.reAddr.ReplaceAllStringFunc(line, func(tok string) string {
		// tok is the full match, e.g. "$00C00004"
		hex := tok[1:] // strip leading $
		v, err := strconv.ParseUint(hex, 16, 32)
		if err != nil {
			return tok
		}
		if name, ok := a.byAddr[uint32(v)]; ok {
			return name
		}
		return tok
	})
}

// addrComment returns a short register description for use inside an existing
// comment, e.g. when the VDP annotator has already claimed the comment field.
// Returns "" when the address is not a known hardware port.
func (a *hwAnnotator) addrComment(addr uint32) string {
	if name, ok := a.byAddr[addr]; ok {
		return fmt.Sprintf("→ %s", name)
	}
	return ""
}
