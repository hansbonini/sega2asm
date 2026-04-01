package compress

import (
	"encoding/binary"
	"sega2asm/types"
	"fmt"
)

func init() {
	types.RegisterAlgorithm(types.Algorithm{Name: "lzrage", Family: types.FamilyLZ, Description: "Bit-stream LZ compressor", Decompress: DecompressLZRage})
}

// DecompressLZRage decompresses data using the Rage (clownlzss) format
// (Streets of Rage series).
//
// Header:
//
//	[0..1] little-endian word — compressed size
//
// Command byte stream; bits 7:5 select the operation:
//
//	0b000 → literal run:       emit (cmd & 0x1F) bytes verbatim
//	0b001 → extended run:      emit ((cmd & 0x1F) << 8 | next) bytes verbatim
//	0b010 → RLE:               repeat next byte (count + 4) times
//	                             count = (cmd & 0x10) ? (cmd & 0xF) << 8 | next : cmd & 0xF
//	0b011 → repeat last dist:  copy (cmd & 0x1F) bytes using the previous back-reference distance
//	0b1xx → back-reference:    length = ((cmd >> 5) & 3) + 4; distance = (cmd & 0x1F) << 8 | next
func DecompressLZRage(src []byte) ([]byte, error) {
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
				types.CopyDist(&out, lastDist, count)
			}
		default:
			second := int(read())
			count := ((first >> 5) & 3) + 4
			lastDist = ((first << 8) & 0x1F00) | second
			if lastDist > 0 {
				types.CopyDist(&out, lastDist, count)
			}
		}
	}
	return out, nil
}
