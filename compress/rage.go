package compress

import (
	"encoding/binary"
	"sega2asm/helpers"
	"fmt"
)

// ── Rage (clownlzss) — Streets of Rage ───────────────────────────────────────
// Header: LE16 compressed size. Command byte bits7:5 encode action.

func DecompressRage(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("rage: too short")
	}
	compSize := int(binary.LittleEndian.Uint16(src[0:2]))
	pos := 2
	end := 2 + compSize
	if end > len(src) {
		end = len(src)
	}
	var out []byte
	lastDist := 0
	read := func() byte {
		if pos >= end {
			return 0
		}
		b := src[pos]
		pos++
		return b
	}
	for pos < end {
		first := int(read())
		switch first >> 5 {
		case 0:
			for i := 0; i < first&0x1F; i++ {
				out = append(out, read())
			}
		case 1:
			count := ((first & 0x1F) << 8) | int(read())
			for i := 0; i < count; i++ {
				out = append(out, read())
			}
		case 2:
			var count int
			if first&0x10 != 0 {
				count = 4 + (((first & 0xF) << 8) | int(read()))
			} else {
				count = 4 + (first & 0xF)
			}
			val := read()
			for i := 0; i < count; i++ {
				out = append(out, val)
			}
		case 3:
			count := first & 0x1F
			if lastDist > 0 {
				helpers.CopyDist(&out, lastDist, count)
			}
		default:
			second := int(read())
			count := ((first >> 5) & 3) + 4
			lastDist = ((first << 8) & 0x1F00) | second
			if lastDist > 0 {
				helpers.CopyDist(&out, lastDist, count)
			}
		}
	}
	return out, nil
}
