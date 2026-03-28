package compress

import (
	"encoding/binary"
	"fmt"
	"sega2asm/types"
)

func init() {
	Register(Algorithm{Name: "lzssfaxman", Family: FamilyLZSS, Description: "Modified Saxman for SMPS music data", Decompress: DecompressLZSSFaxman})
}

// DecompressLZSSFaxman decompresses data using the Faxman (clownlzss) format.
//
// Header:
//
//	[0..1] little-endian word — total descriptor bit count
//	[2..]  payload
//
// Control stream: 8-bit descriptor byte, LSB first.
//
//	bit=1 → literal byte
//	bit=0 → back-reference: 2 bytes little-endian
//	          ring index = (b0 | ((b1 & 0xF0) << 4)) + 18   (12-bit absolute ring buffer index)
//	          length     = (b1 & 0x0F) + 3
//
// Out-of-bounds back-references emit zero bytes.
func DecompressLZSSFaxman(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("faxman: too short")
	}
	remaining := int(binary.LittleEndian.Uint16(src[0:2]))
	dr := types.NewLSBDescReader(src, 2)
	var out []byte
	startLen := 0
	zeroOrCopy := func(distance, count int) {
		if distance > len(out)-startLen {
			for i := 0; i < count; i++ {
				out = append(out, 0)
			}
		} else {
			types.CopyDist(&out, distance, count)
		}
	}
	for remaining > 0 {
		remaining--
		if dr.PopBit() == 1 {
			out = append(out, dr.ReadByte())
		} else {
			remaining--
			if dr.PopBit() == 1 {
				b1 := int(dr.ReadByte())
				b2 := int(dr.ReadByte())
				zeroOrCopy((b1|((b2<<3)&0x700))+1, (b2&0x1F)+3)
			} else {
				dist := 0x100 - int(dr.ReadByte())
				count := 2
				remaining--
				if dr.PopBit() == 1 {
					count += 2
				}
				remaining--
				if dr.PopBit() == 1 {
					count++
				}
				zeroOrCopy(dist, count)
			}
		}
	}
	return out, nil
}
