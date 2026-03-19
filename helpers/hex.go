// Package helpers provides shared utility functions used across sega2asm.
package helpers

import (
	"fmt"
	"strings"
)

// ParseHex parses an address string in any of these formats:
//
//	$XXXX     — splat/asm68k style
//	0xXXXX    — C-style hex
//	XXXX      — bare hex digits
//	decimal   — plain base-10 integer
func ParseHex(s string) (uint32, error) {
	s = strings.TrimSpace(s)
	if strings.HasPrefix(s, "$") {
		s = "0x" + s[1:]
	}
	var v uint32
	if _, err := fmt.Sscanf(s, "0x%X", &v); err == nil {
		return v, nil
	}
	if _, err := fmt.Sscanf(s, "0X%X", &v); err == nil {
		return v, nil
	}
	if _, err := fmt.Sscanf(s, "%d", &v); err == nil {
		return v, nil
	}
	return 0, fmt.Errorf("not a number: %q", s)
}
