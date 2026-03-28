package compress

import (
	"encoding/binary"
	"fmt"
	"sega2asm/types"
)

func init() {
	Register(Algorithm{Name: "lzrocket", Family: FamilyLZ, Description: "Konami Rocket Knight compression", Decompress: DecompressLZRocket})
}

// DecompressLZRocket decompresses data using the Rocket (clownlzss) format.
//
// Header:
//
//	[0..1] big-endian word — uncompressed size
//	[2..3] big-endian word — compressed size
//
// Control stream: 8-bit descriptor byte, LSB first.
//
//	bit=1 → literal byte
//	bit=0 → back-reference: big-endian word
//	          ring index = (word + 0x40) & 0x3FF   (10-bit absolute ring buffer index)
//	          length     = (word >> 10) + 1
func DecompressLZRocket(src []byte) ([]byte, error) {
	if len(src) < 4 {
		return nil, fmt.Errorf("rocket: too short")
	}
	uncompSize := int(binary.BigEndian.Uint16(src[0:2]))
	compSize := int(binary.BigEndian.Uint16(src[2:4]))
	dr := types.NewLSBDescReader(src, 4)
	var out []byte
	inputEnd := 4 + compSize
	for dr.Pos() < inputEnd && len(out) < uncompSize {
		if dr.PopBit() == 1 {
			out = append(out, dr.ReadByte())
		} else {
			hi := int(dr.ReadByte())
			lo := int(dr.ReadByte())
			word := (hi << 8) | lo
			dictIdx := (word + 0x40) & 0x3FF
			count := (word >> 10) + 1
			dist := ((0x400 + len(out) - dictIdx - 1) & 0x3FF) + 1
			types.CopyDist(&out, dist, count)
		}
	}
	if len(out) > uncompSize {
		out = out[:uncompSize]
	}
	return out, nil
}
