package compress

import (
	"encoding/binary"
	"fmt"
	"sega2asm/types"
)

func init() {
	types.RegisterAlgorithm(types.Algorithm{Name: "lzbandai", Family: types.FamilyLZ, Description: "Bandai LZ compression", Decompress: DecompressLZBandai})
	types.RegisterSignature(types.CompressSig{
		Name: "lzbandai", WordAligned: true,
		Sig: []byte{
			0x16, 0x30, 0x10, 0x04, 0x18, 0x03, 0x02, 0x44, 0x00, 0x0F, 0xB8, 0x02, 0x67, 0x1E, 0x14, 0x04,
			0x48, 0xE7, 0xF0, 0xC0, 0xD8, 0x44, 0x41, 0xFA, 0x07, 0x3C, 0xD0, 0xC4, 0xD0, 0xD0, 0x43, 0xF9,
			0xFF, 0xFF, 0x20, 0x00, 0x4E, 0xBA, 0xF7, 0x52, 0x4C, 0xDF, 0x03, 0x0F, 0x38, 0x30, 0x10, 0x04,
			0x02, 0x43, 0x00, 0xF0, 0xE6,
		},
	})
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
