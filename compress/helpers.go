// Package compress implements decompressors used in Sega Mega Drive ROMs.
// References: clownnemesis, clownlzss (Clownacy), RNC spec.
package compress

// ── Ring-buffer helper ─────────────────────────────────────────────────────────

type winBuf struct {
	data   []byte
	size   int
	mask   int
	cursor int
}

func newWin(size, cursor, fill int) *winBuf {
	w := &winBuf{data: make([]byte, size), size: size, mask: size - 1, cursor: cursor}
	for i := range w.data {
		w.data[i] = byte(fill)
	}
	return w
}

func (w *winBuf) emit(b byte, out *[]byte) {
	*out = append(*out, b)
	w.data[w.cursor] = b
	w.cursor = (w.cursor + 1) & w.mask
}

func (w *winBuf) copyFrom(offset, count int, out *[]byte) {
	for i := 0; i < count; i++ {
		b := w.data[(offset+i)&w.mask]
		w.emit(b, out)
	}
}

// copyDist copies count bytes from distance bytes behind the current end of out.
func copyDist(out *[]byte, distance, count int) {
	base := len(*out) - distance
	for i := 0; i < count; i++ {
		idx := base + i
		if idx < 0 {
			*out = append(*out, 0)
		} else {
			*out = append(*out, (*out)[idx])
		}
	}
}
