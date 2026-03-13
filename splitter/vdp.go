package splitter

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// vdpAnnotator holds compiled regexes for a specific VDP ctrl symbol name.
// Build once per segment via newVDPAnnotator.
type vdpAnnotator struct {
	reMoveW *regexp.Regexp
	reMoveL *regexp.Regexp
}

// newVDPAnnotator compiles regexes that match the VDP control port either by
// its raw address ($C00004) or by an optional symbol name (e.g. "VDP_CTRL").
func newVDPAnnotator(ctrlSym string) *vdpAnnotator {
	dest := `(?:\$00)?[Cc]00004(?:\.l)?`
	if ctrlSym != "" {
		dest = dest + `|` + regexp.QuoteMeta(ctrlSym)
	}
	dest = `\s*,\s*\(?(?:` + dest + `)\)?`
	return &vdpAnnotator{
		reMoveW: regexp.MustCompile(`(?i)move\.w\s+#\$([0-9A-F]{1,4})` + dest),
		reMoveL: regexp.MustCompile(`(?i)move\.l\s+#\$([0-9A-F]{1,8})` + dest),
	}
}

// annotate appends a human-readable VDP comment to an instruction line
// when it is an immediate write to the VDP control port ($C00004).
// Returns the line unchanged if no VDP annotation applies.
func (a *vdpAnnotator) annotate(line string) string {
	if m := a.reMoveL.FindStringSubmatch(line); m != nil {
		val, err := strconv.ParseUint(m[1], 16, 32)
		if err == nil {
			if c := vdpLongComment(uint32(val)); c != "" {
				return line + "\t; " + c
			}
		}
	} else if m := a.reMoveW.FindStringSubmatch(line); m != nil {
		val, err := strconv.ParseUint(m[1], 16, 16)
		if err == nil {
			if c := vdpWordComment(uint16(val)); c != "" {
				return line + "\t; " + c
			}
		}
	}
	return line
}

// vdpWordComment decodes a single 16-bit write to VDP_CTRL.
func vdpWordComment(w uint16) string {
	if w>>14 == 2 { // bits 15-14 = 10 → VDP register write
		reg := (w >> 8) & 0x1F
		val := uint8(w & 0xFF)
		return fmt.Sprintf("VDP reg #%d = $%02X (%s)", reg, val, vdpRegDesc(int(reg), val))
	}
	return ""
}

// vdpLongComment decodes a 32-bit write to VDP_CTRL (two consecutive 16-bit commands).
func vdpLongComment(v uint32) string {
	hi := uint16(v >> 16)
	lo := uint16(v)

	// Both words are register writes.
	if hi>>14 == 2 && lo>>14 == 2 {
		return vdpWordComment(hi) + " | " + vdpWordComment(lo)
	}
	if hi>>14 == 2 {
		return vdpWordComment(hi)
	}
	if lo>>14 == 2 {
		return vdpWordComment(lo)
	}

	// Address / DMA command.
	// hi: CD1 CD0 A13..A0
	// lo: 0..0 CD5..CD2 0 0 A15 A14
	cd0_1 := uint8((hi >> 14) & 0x3)
	cd2_5 := uint8((lo >> 4) & 0xF)
	cd := cd0_1 | (cd2_5 << 2)
	addr := (uint32(lo)&0x3)<<14 | uint32(hi&0x3FFF)

	return fmt.Sprintf("VDP %s addr=$%04X", vdpMemType(cd), addr)
}

func vdpMemType(cd uint8) string {
	switch cd {
	case 0x00:
		return "VRAM read"
	case 0x01:
		return "VRAM write"
	case 0x03:
		return "CRAM write"
	case 0x04:
		return "VSRAM read"
	case 0x05:
		return "VSRAM write"
	case 0x08:
		return "CRAM read"
	case 0x20:
		return "DMA fill"
	case 0x21:
		return "VRAM DMA write"
	case 0x23:
		return "CRAM DMA write"
	case 0x25:
		return "VSRAM DMA write"
	case 0x30:
		return "VRAM DMA copy"
	default:
		return fmt.Sprintf("CD=$%02X", cd)
	}
}

func vdpRegDesc(reg int, val uint8) string {
	switch reg {
	case 0:
		parts := []string{}
		if val&0x04 != 0 {
			parts = append(parts, "HV_stop")
		}
		if val&0x02 != 0 {
			parts = append(parts, "HInt")
		}
		if val&0x01 != 0 {
			parts = append(parts, "ExtInt")
		}
		if len(parts) == 0 {
			return "Mode1: off"
		}
		return "Mode1: " + strings.Join(parts, "|")
	case 1:
		parts := []string{}
		if val&0x40 != 0 {
			parts = append(parts, "DisplayOn")
		} else {
			parts = append(parts, "DisplayOff")
		}
		if val&0x20 != 0 {
			parts = append(parts, "VInt")
		}
		if val&0x10 != 0 {
			parts = append(parts, "DMAEn")
		}
		if val&0x08 != 0 {
			parts = append(parts, "V30")
		} else {
			parts = append(parts, "V28")
		}
		return "Mode2: " + strings.Join(parts, "|")
	case 2:
		return fmt.Sprintf("PlaneA=$%04X", uint32(val&0x38)<<10)
	case 3:
		return fmt.Sprintf("Window=$%04X", uint32(val&0x3E)<<10)
	case 4:
		return fmt.Sprintf("PlaneB=$%04X", uint32(val&0x07)<<13)
	case 5:
		return fmt.Sprintf("Sprites=$%04X", uint32(val&0x7F)<<9)
	case 7:
		pal := (val >> 4) & 0x3
		col := val & 0xF
		return fmt.Sprintf("BgColor=PAL%d[%d]", pal, col)
	case 10:
		return fmt.Sprintf("HInt every %d lines", int(val)+1)
	case 11:
		hscrollModes := [4]string{"FullScreen", "Invalid", "Cell", "Line"}
		ext := ""
		if val&0x04 != 0 {
			ext = "+ExtVScroll"
		}
		return fmt.Sprintf("Mode3: HScroll=%s%s", hscrollModes[val&0x03], ext)
	case 12:
		h40 := (val&0x01 != 0) || (val&0x80 != 0)
		interlace := [4]string{"", " Int2xRes", " Int2x", " IntDouble"}[(val>>1)&0x3]
		shadow := ""
		if val&0x08 != 0 {
			shadow = "+Shadow"
		}
		res := "H32"
		if h40 {
			res = "H40"
		}
		return fmt.Sprintf("Mode4: %s%s%s", res, interlace, shadow)
	case 13:
		return fmt.Sprintf("HScroll=$%04X", uint32(val&0x3F)<<10)
	case 15:
		return fmt.Sprintf("AutoInc=%d", val)
	case 16:
		ws := [4]string{"32", "64", "?", "128"}
		return fmt.Sprintf("ScrollSize=%sx%s cells", ws[val&0x03], ws[(val>>4)&0x03])
	case 17:
		side := "Left"
		if val&0x80 != 0 {
			side = "Right"
		}
		return fmt.Sprintf("WindowH=%s cell=%d", side, val&0x1F)
	case 18:
		side := "Up"
		if val&0x80 != 0 {
			side = "Down"
		}
		return fmt.Sprintf("WindowV=%s cell=%d", side, val&0x1F)
	case 19:
		return fmt.Sprintf("DMALen_lo=%d", val)
	case 20:
		return fmt.Sprintf("DMALen_hi=%d (words=%d)", val, int(val)<<8)
	case 21:
		return fmt.Sprintf("DMASrc_lo=$%02X", val)
	case 22:
		return fmt.Sprintf("DMASrc_mid=$%02X", val)
	case 23:
		switch (val >> 6) & 0x3 {
		case 0, 1:
			return fmt.Sprintf("DMASrc_hi=$%02X (ROM/RAM→VRAM)", val&0x7F)
		case 2:
			return fmt.Sprintf("DMASrc_hi=$%02X (68k→VDP fill)", val&0x3F)
		case 3:
			return "DMA VRAM copy"
		}
	}
	return fmt.Sprintf("reg%d", reg)
}
