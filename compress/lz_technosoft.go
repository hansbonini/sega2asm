package compress

import "sega2asm/types"

func init() {
	Register(Algorithm{Name: "lztechnosoft", Family: FamilyLZ, Description: "Technosoft LZ variant; no size header", Decompress: DecompressLZTechnosoft})
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
