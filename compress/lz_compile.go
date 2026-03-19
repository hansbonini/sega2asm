package compress

import "fmt"

// ── Compile (Puyo Puyo / Aleste / MUSHA etc.) ─────────────────────────────────
//
// Algorithm: command-byte stream with two modes.
//
//	cmd == 0x00             → end of stream
//	cmd & 0x80 == 0         → literal run: emit (cmd & 0x7F) bytes verbatim
//	cmd & 0x80 != 0         → back-reference: copy (cmd & 0x7F)+2 bytes from
//	                           a 256-byte circular history starting at
//	                           (histHead - offset - 1) & 0xFF
//
// Output is buffered in a 4-byte FIFO; each time the FIFO fills it is flushed
// to the output slice.  Output size is always a multiple of 4.
//
// Reference: https://github.com/Nasina7/PuyoComp/blob/main/src/decompress.rs
func DecompressLZCompile(src []byte) ([]byte, error) {
	if len(src) == 0 {
		return nil, fmt.Errorf("compile: empty input")
	}

	var (
		out     []byte
		arr1    [256]byte // 256-byte circular history
		arr1Ind int
		arr2    [4]byte // 4-byte output accumulator
		arr2Ind int
		ptr     int
	)

	emit := func(b byte) {
		arr2[arr2Ind] = b
		arr2Ind = (arr2Ind + 1) & 0xFF
		if arr2Ind&0x4 != 0 {
			arr2Ind = 0
			out = append(out, arr2[:]...)
		}
		arr1[arr1Ind] = b
		arr1Ind = (arr1Ind + 1) & 0xFF
	}

	for ptr < len(src) {
		cmd := int(src[ptr])
		ptr++

		if cmd == 0 {
			break
		}

		if cmd&0x80 != 0 {
			// Back-reference
			count := (cmd & 0x7F) + 2
			if ptr >= len(src) {
				return nil, fmt.Errorf("compile: truncated at back-reference offset byte")
			}
			offset := int(src[ptr])
			ptr++
			calcInd := (arr1Ind - offset - 1) & 0xFF
			for i := 0; i < count; i++ {
				emit(arr1[calcInd])
				calcInd = (calcInd + 1) & 0xFF
			}
		} else {
			// Literal run
			count := cmd & 0x7F
			for i := 0; i < count; i++ {
				if ptr >= len(src) {
					return nil, fmt.Errorf("compile: truncated at literal byte %d/%d", i+1, count)
				}
				emit(src[ptr])
				ptr++
			}
		}
	}

	return out, nil
}
