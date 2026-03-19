package compress

import (
	"encoding/binary"
	"fmt"
)

// ── Chameleon (clownlzss) ─────────────────────────────────────────────────────
// Header: BE16 offset from pos+2 to literal stream. Descriptor and data in separate sub-streams.

func DecompressChameleon(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("chameleon: too short")
	}
	offset := int(binary.BigEndian.Uint16(src[0:2]))
	descPos := 2
	dataPos := 2 + offset
	var descByte byte
	descBitsLeft := 0
	readDesc := func() byte {
		if descPos >= len(src) {
			return 0
		}
		b := src[descPos]
		descPos++
		return b
	}
	readData := func() byte {
		if dataPos >= len(src) {
			return 0
		}
		b := src[dataPos]
		dataPos++
		return b
	}
	descPop := func() int {
		if descBitsLeft == 0 {
			descByte = readDesc()
			descBitsLeft = 8
		}
		bit := int((descByte >> 7) & 1)
		descByte <<= 1
		descBitsLeft--
		return bit
	}
	var out []byte
	for {
		if descPop() == 1 {
			out = append(out, readData())
		} else {
			dist := int(readData())
			var count int
			if descPop() == 0 {
				count = 2 + descPop()
			} else {
				if descPop() == 1 {
					dist += 1 << 10
				}
				if descPop() == 1 {
					dist += 1 << 9
				}
				if descPop() == 1 {
					dist += 1 << 8
				}
				if descPop() == 0 {
					if descPop() == 0 {
						count = 3
					} else {
						count = 4
					}
				} else {
					if descPop() == 0 {
						count = 5
					} else {
						count = int(readData())
						if count < 6 {
							break
						}
					}
				}
			}
			if dist > 0 {
				copyDist(&out, dist, count)
			}
		}
	}
	return out, nil
}
