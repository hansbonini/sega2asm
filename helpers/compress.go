package helpers

// WinBuf is a sliding-window ring buffer used by LZ-family decompressors.
type WinBuf struct {
	Data   []byte
	Size   int
	Mask   int
	Cursor int
}

// NewWin allocates a WinBuf of the given size, positions the cursor, and fills
// the buffer with fill.
func NewWin(size, cursor, fill int) *WinBuf {
	w := &WinBuf{Data: make([]byte, size), Size: size, Mask: size - 1, Cursor: cursor}
	for i := range w.Data {
		w.Data[i] = byte(fill)
	}
	return w
}

// Emit appends b to out and writes it into the ring buffer at the current cursor.
func (w *WinBuf) Emit(b byte, out *[]byte) {
	*out = append(*out, b)
	w.Data[w.Cursor] = b
	w.Cursor = (w.Cursor + 1) & w.Mask
}

// CopyFrom copies count bytes starting at offset within the ring buffer into out.
func (w *WinBuf) CopyFrom(offset, count int, out *[]byte) {
	for i := 0; i < count; i++ {
		b := w.Data[(offset+i)&w.Mask]
		w.Emit(b, out)
	}
}

// CopyDist copies count bytes from distance bytes behind the current end of out.
func CopyDist(out *[]byte, distance, count int) {
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
