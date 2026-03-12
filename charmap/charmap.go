// Package charmap loads .tbl charmap files used for text segment disassembly.
// Format (standard THINGY/WindHex .tbl):
//   XX=Character
//   XXYY=Multi-byte-character
package charmap

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// Map translates ROM byte sequences to readable strings.
type Map struct {
	entries map[string]string // hex key → string
	maxLen  int               // maximum key byte length
}

// Load reads a .tbl file. Returns an empty map if path is empty/missing.
func Load(path string) (*Map, error) {
	m := &Map{entries: make(map[string]string)}
	if path == "" {
		return m, nil
	}
	f, err := os.Open(path)
	if os.IsNotExist(err) {
		return m, nil
	}
	if err != nil {
		return nil, fmt.Errorf("opening charmap %q: %w", path, err)
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || line[0] == '/' || line[0] == ';' {
			continue
		}
		eqIdx := strings.IndexByte(line, '=')
		if eqIdx < 0 {
			continue
		}
		hexPart := strings.ToUpper(strings.TrimSpace(line[:eqIdx]))
		charPart := line[eqIdx+1:]
		m.entries[hexPart] = charPart
		if len(hexPart)/2 > m.maxLen {
			m.maxLen = len(hexPart) / 2
		}
	}
	return m, scanner.Err()
}

// Lookup attempts to decode bytes starting at data[pos], returning the
// decoded string and number of bytes consumed. Returns ("", 0) on no match.
func (m *Map) Lookup(data []byte, pos int) (string, int) {
	if len(m.entries) == 0 {
		return "", 0
	}
	maxLen := m.maxLen
	if maxLen > len(data)-pos {
		maxLen = len(data) - pos
	}
	// Try longest match first
	for l := maxLen; l >= 1; l-- {
		key := fmt.Sprintf("%X", data[pos:pos+l])
		if len(key) < l*2 {
			key = strings.Repeat("0", l*2-len(key)) + key
		}
		if ch, ok := m.entries[key]; ok {
			return ch, l
		}
	}
	return "", 0
}

// DecodeString decodes a slice of bytes using the charmap, stopping at
// terminator byte (0x00 by default). Falls back to hex escapes.
func (m *Map) DecodeString(data []byte, terminator byte) string {
	var sb strings.Builder
	i := 0
	for i < len(data) {
		if data[i] == terminator {
			break
		}
		if ch, n := m.Lookup(data, i); n > 0 {
			sb.WriteString(ch)
			i += n
		} else {
			sb.WriteString(fmt.Sprintf("{$%02X}", data[i]))
			i++
		}
	}
	return sb.String()
}

// Empty returns true if no entries are loaded.
func (m *Map) Empty() bool {
	return len(m.entries) == 0
}
