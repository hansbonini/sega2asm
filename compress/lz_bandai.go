package compress

import (
	"encoding/binary"
	"fmt"
	"sega2asm/types"
)

func init() {
	Register(Algorithm{Name: "lzbandai", Family: FamilyLZ, Description: "Bandai LZ compression", Decompress: DecompressLZBandai})
}

// DecompressLZBandai decompresses data using the LZBandai format
// (Dragon Ball Z: Buyuu Retsuden).
//
// Window: 0x2000 bytes, cursor at 0x00, fill 0x00.
//
// Header:
//
//	[0..1] little-endian word — (uncompressed_size - 1) | bit 15 (bit 15 always set)
//
// Control stream: 8-bit descriptor byte, LSB first.
//
//	bit=1 → literal byte
//	bit=0 → back-reference: 2 bytes little-endian (word)
//	          length = (lo & 0x0F) + 3
//	          offset = word >> 4
func DecompressLZBandai(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("lzbandai: too short")
	}
	hdr := binary.LittleEndian.Uint16(src[0:2])
	uncompSize := int(hdr&0x7FFF) + 1
	dr := types.NewLSBDescReader(src, 2)
	win := types.NewWin(0x2000, 0, 0)
	var out []byte
	for len(out) < uncompSize {
		if dr.PopBit() == 1 {
			win.Emit(dr.ReadByte(), &out)
		} else {
			lo := int(dr.ReadByte())
			hi := int(dr.ReadByte())
			length := (lo & 0xF) + 3
			offset := ((hi << 8) | lo) >> 4
			base := (win.Cursor - offset + win.Size) & win.Mask
			win.CopyFrom(base, length, &out)
		}
	}
	if len(out) > uncompSize {
		out = out[:uncompSize]
	}
	return out, nil
}
