package compress

import "sega2asm/types"

func init() {
	types.RegisterAlgorithm(types.Algorithm{Name: "lzssblizzard", Family: types.FamilyLZSS, Description: "Okumura 1989 LZSS; 4096-byte ring buffer", Decompress: DecompressLZSSBlizzard})
	types.RegisterSignature(types.CompressSig{
		Name: "lzssblizzard", WordAligned: true,
		Sig: []byte{0x12, 0x18, 0x14, 0xC1, 0xE1, 0x46, 0x1C, 0x01, 0xE3},
	})
}

// DecompressLZSSBlizzard decompresses data using the Blizzard LZSS format
// (Rock N Roll Racing). Based on Haruhiko Okumura's LZSS (1989).
//
// Parameters:
//
//	N         = 4096  ring buffer size
//	F         = 18    max match length
//	THRESHOLD = 2
//
// Control stream: 1 byte encodes 8 flags (LSB first).
//
//	bit=1 → literal byte
//	bit=0 → back-reference: 2 bytes
//	          offset = byte0 | ((byte1 & 0x0F) << 8)  — absolute ring-buffer index
//	          length = ((byte1 & 0xF0) >> 4) + THRESHOLD  — copies length+1 bytes
func DecompressLZSSBlizzard(src []byte) ([]byte, error) {
	const threshold = 2

	win := types.NewWin(4096, 0, 0)
	dr := types.NewLSBDescReader(src, 0)
	var out []byte

	for dr.Pos() < len(src) {
		if dr.PopBit() == 1 {
			win.Emit(dr.ReadByte(), &out)
		} else {
			b0 := dr.ReadByte()
			b1 := dr.ReadByte()
			offset := int(b0) | ((int(b1) & 0x0F) << 8)
			length := ((int(b1) & 0xF0) >> 4) + threshold + 1
			win.CopyFrom(offset, length, &out)
		}
	}

	return out, nil
}
