package compress

import "fmt"

// ── RLESoftwareCreations — Maximum Carnage, Venom, The Tick, Cutthroat Island ──
// src[0] = escape byte. Whenever escape appears twice → (value, count) follows.

func DecompressRLESoftwareCreations(src []byte) ([]byte, error) {
	if len(src) < 1 {
		return nil, fmt.Errorf("rlesc: too short")
	}
	escape := src[0]
	pos := 1
	remaining := len(src) - 1
	var out []byte
	for remaining > 0 && pos < len(src) {
		b := src[pos]
		pos++
		if b == escape {
			if pos+1 >= len(src) {
				break
			}
			val := src[pos]
			pos++
			length := int(src[pos])
			pos++
			for i := 0; i < length; i++ {
				out = append(out, val)
			}
			remaining -= 3
		} else {
			out = append(out, b)
			remaining--
		}
	}
	return out, nil
}
