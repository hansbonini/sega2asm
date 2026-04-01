package compress

import (
	"encoding/binary"
	"fmt"
	"sega2asm/types"
)

func init() {
	types.RegisterAlgorithm(types.Algorithm{Name: "lzsti", Family: types.FamilyLZ, Description: "STI LZ compression", Decompress: DecompressLZSTI})
	types.RegisterSignature(types.CompressSig{
		Name: "lzsti", WordAligned: true,
		Sig: []byte{
			0x43, 0xF9, 0xFF, 0xFF, 0x4E, 0x34, 0x40, 0xE7, 0x00, 0x7C, 0x07, 0x00, 0x3A, 0x00, 0x36, 0x41,
			0x3C, 0x18, 0x3E, 0x18, 0x53, 0x46, 0x53, 0x47, 0x61, 0x00, 0xFE, 0x72, 0xE2, 0x4B, 0x53, 0x43,
			0x24, 0x49, 0x78, 0x00, 0x38, 0x05, 0xE5, 0x8C, 0xE4, 0x4C, 0x00, 0x44, 0x40, 0x00, 0x48, 0x44,
			0x28, 0x84, 0x38, 0x06, 0x3F, 0x07, 0x3E,
		},
	})
}

// DecompressLZSTI decompresses data using the LZSTI format (Comix Zone).
//
// Window: 0x400 bytes, cursor at 0x00, fill 0x00.
//
// Header:
//
//	[0..1] big-endian word — uncompressed size
//
// Control stream: bit-packed MSB first (no byte-boundary alignment).
//
//	bit=1 → literal: read 8 bits verbatim
//	bit=0 → back-reference:
//	          offset = next 10 bits   (absolute ring buffer index)
//	          length = next 4 bits + 2
func DecompressLZSTI(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("lzsti: too short")
	}
	uncompSize := int(binary.BigEndian.Uint16(src[0:2]))
	win := types.NewWin(0x400, 0, 0)
	var out []byte
	br := types.NewMSBBitReader(src, 2)
	decoded := 0
	for decoded < uncompSize {
		if br.ReadBit() == 1 {
			b := byte(br.ReadBits(8))
			win.Emit(b, &out)
			decoded++
		} else {
			offset := br.ReadBits(10)
			length := br.ReadBits(4) + 2
			win.CopyFrom(offset, length, &out)
			decoded += length
		}
	}
	if len(out) > uncompSize {
		out = out[:uncompSize]
	}
	return out, nil
}
