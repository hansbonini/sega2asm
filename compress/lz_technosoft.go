package compress

import "sega2asm/types"

func init() {
	types.RegisterAlgorithm(types.Algorithm{Name: "lztechnosoft", Family: types.FamilyLZ, Description: "Technosoft LZ variant; no size header", Decompress: DecompressLZTechnosoft})
	types.RegisterSignature(types.CompressSig{
		Name: "lztechnosoft", WordAligned: true,
		Sig: []byte{0x55, 0x87, 0x12, 0x18, 0x10, 0x18, 0x2A, 0x00, 0xC0, 0x7C, 0x00, 0xF0, 0xE9, 0x40, 0x80, 0x41},
	})
}

// DecompressLZTechnosoft decompresses data using the LZTechnosoft format
// (Elemental Master). Same encoding as LZNamco (window 0x1000, cursor 0xFEE, fill 0x00)
// but with no size header; the decompressor consumes all input bytes.
func DecompressLZTechnosoft(src []byte) ([]byte, error) {
	dr := types.NewLSBDescReader(src, 0)
	win := types.NewWin(0x1000, 0xFEE, 0)
	var out []byte
	for dr.Pos() < len(src) {
		if dr.PopBit() == 1 {
			win.Emit(dr.ReadByte(), &out)
		} else {
			hi := int(dr.ReadByte())
			lo := int(dr.ReadByte())
			length := (lo & 0xF) + 3
			offset := ((lo & 0xF0) << 4) | hi
			win.CopyFrom(offset, length, &out)
		}
	}
	return out, nil
}
