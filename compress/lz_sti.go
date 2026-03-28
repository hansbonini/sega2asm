package compress

import (
	"encoding/binary"
	"fmt"
	"sega2asm/types"
)

func init() {
	Register(Algorithm{Name: "lzsti", Family: FamilyLZ, Description: "STI LZ compression", Decompress: DecompressLZSTI})
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
