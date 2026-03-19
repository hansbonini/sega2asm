package compress

import (
	"encoding/binary"
	"fmt"
)

// ── Faxman (clownlzss) ────────────────────────────────────────────────────────
// Header: LE16 descriptor-bit count. BitField 1-byte LE, LSB first.
// Out-of-bounds refs → zero-fill.

func DecompressFaxman(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("faxman: too short")
	}
	remaining := int(binary.LittleEndian.Uint16(src[0:2]))
	pos := 2
	var out []byte
	var descByte byte
	descBitsLeft := 0
	startLen := 0
	read := func() byte {
		if pos >= len(src) {
			return 0
		}
		b := src[pos]
		pos++
		return b
	}
	popBit := func() int {
		if descBitsLeft == 0 {
			descByte = read()
			descBitsLeft = 8
		}
		remaining--
		bit := int(descByte & 1)
		descByte >>= 1
		descBitsLeft--
		return bit
	}
	zeroOrCopy := func(distance, count int) {
		if distance > len(out)-startLen {
			for i := 0; i < count; i++ {
				out = append(out, 0)
			}
		} else {
			copyDist(&out, distance, count)
		}
	}
	for remaining > 0 {
		if popBit() == 1 {
			out = append(out, read())
		} else {
			if popBit() == 1 {
				b1 := int(read())
				b2 := int(read())
				zeroOrCopy((b1|((b2<<3)&0x700))+1, (b2&0x1F)+3)
			} else {
				dist := 0x100 - int(read())
				count := 2
				if popBit() == 1 {
					count += 2
				}
				if popBit() == 1 {
					count++
				}
				zeroOrCopy(dist, count)
			}
		}
	}
	return out, nil
}
