package types

import (
	"fmt"
	"strconv"
	"strings"
)

// ParseHex parses an address string in any of these formats:
//
//	$XXXX     — splat/asm68k style
//	0xXXXX    — C-style hex
//	XXXX      — bare hex digits (A–F accepted)
//	decimal   — plain base-10 integer
func ParseHex(s string) (uint32, error) {
	s = strings.TrimSpace(s)
	if strings.HasPrefix(s, "$") {
		v, err := strconv.ParseUint(s[1:], 16, 32)
		if err != nil {
			return 0, fmt.Errorf("not a number: %q", s)
		}
		return uint32(v), nil
	}
	if strings.HasPrefix(s, "0x") || strings.HasPrefix(s, "0X") {
		v, err := strconv.ParseUint(s[2:], 16, 32)
		if err != nil {
			return 0, fmt.Errorf("not a number: %q", s)
		}
		return uint32(v), nil
	}
	if v, err := strconv.ParseUint(s, 10, 32); err == nil {
		return uint32(v), nil
	}
	if v, err := strconv.ParseUint(s, 16, 32); err == nil {
		return uint32(v), nil
	}
	return 0, fmt.Errorf("not a number: %q", s)
}
