package compress

import (
	"encoding/binary"
	"sega2asm/helpers"
	"fmt"
)

// DecompressLZChameleon decompresses data using the Chameleon (clownlzss) format.
//
// Header:
//
//	[0..1] big-endian word — byte offset from src[2] to the literal data sub-stream
//	[2..]  descriptor/back-reference sub-stream
//	[2+offset..] literal data sub-stream
//
// Control stream: 8-bit descriptor byte, MSB first. For each bit:
//
//	bit=1 → literal: read 1 byte from the literal sub-stream
//	bit=0 → back-reference: read 2 bytes from the descriptor sub-stream
//	          ring index = b0 | ((b1 & 0xF0) << 4)   (12-bit absolute ring buffer index)
//	          length     = (b1 & 0x0F) + 3; ring index == 0 && length == 3 → end of stream
func DecompressLZChameleon(src []byte) ([]byte, error) {
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
				helpers.CopyDist(&out, dist, count)
			}
		}
	}
	return out, nil
}
