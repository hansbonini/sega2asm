package compress

import (
	"encoding/binary"
	"fmt"
	"sega2asm/types"
)

func init() {
	Register(Algorithm{Name: "lzsssaxman", Family: FamilyLZSS, Description: "Modified Okumura 1989 LZSS with size header", Decompress: DecompressLZSSSaxman})
	Register(Algorithm{Name: "lzsssaxman_noheader", Family: FamilyLZSS, Description: "Saxman LZSS without size header", Decompress: DecompressLZSSSaxmanNoHeader})
}

// DecompressLZSSSaxman decompresses data using the Saxman (clownlzss) format.
//
// Header:
//
//	[0..1] little-endian word — compressed payload size
//	[2..]  payload
//
// Control stream: 8-bit descriptor byte, LSB first.
//
//	bit=1 → literal byte
//	bit=0 → back-reference: 2 bytes
//	          ring index = (b0 | ((b1 & 0xF0) << 4)) + 18   (absolute, mod 0x1000)
//	          length     = (b1 & 0x0F) + 3
func DecompressLZSSSaxman(src []byte) ([]byte, error) { return decompressSaxman(src, true) }

// DecompressLZSSSaxmanNoHeader decompresses Saxman-encoded data with no leading size header.
func DecompressLZSSSaxmanNoHeader(src []byte) ([]byte, error) { return decompressSaxman(src, false) }

func decompressSaxman(src []byte, hasHeader bool) ([]byte, error) {
	var data []byte
	if hasHeader {
		if len(src) < 2 {
			return nil, fmt.Errorf("saxman: too short")
		}
		n := int(binary.LittleEndian.Uint16(src[0:2]))
		end := 2 + n
		if end > len(src) {
			end = len(src)
		}
		data = src[2:end]
	} else {
		data = src
	}
	dr := types.NewLSBDescReader(data, 0)
	var out []byte
	for dr.Pos() < len(data) {
		if dr.PopBit() == 1 {
			out = append(out, dr.ReadByte())
		} else {
			b1 := int(dr.ReadByte())
			b2 := int(dr.ReadByte())
			dictIdx := (b1 | ((b2 << 4) & 0xF00)) + 18
			count := (b2 & 0xF) + 3
			outPos := len(out)
			dist := (outPos - dictIdx%0x1000 + 0x1000) % 0x1000
			if dist == 0 || dist > outPos {
				for i := 0; i < count; i++ {
					out = append(out, 0)
				}
			} else {
				base := outPos - dist
				for i := 0; i < count; i++ {
					out = append(out, out[base+i])
				}
			}
		}
	}
	return out, nil
}
