package compress

import "sega2asm/helpers"

// LZTechnosoft — Elemental Master. Same encoding but NO size header; consumes all src.
func DecompressLZTechnosoft(src []byte) ([]byte, error) {
	pos := 0
	win := helpers.NewWin(0x1000, 0xFEE, 0)
	var out []byte
	read := func() byte {
		if pos >= len(src) {
			return 0
		}
		b := src[pos]
		pos++
		return b
	}
	consumed := 0
	for consumed < len(src) {
		ctrl := read()
		consumed++
		for bit := 0; bit < 8 && consumed < len(src); bit++ {
			if (ctrl>>uint(bit))&1 == 1 {
				b := read()
				consumed++
				win.Emit(b, &out)
			} else {
				hi := int(read())
				lo := int(read())
				consumed += 2
				length := (lo & 0xF) + 3
				offset := ((lo & 0xF0) << 4) | hi
				win.CopyFrom(offset, length, &out)
			}
		}
	}
	return out, nil
}
