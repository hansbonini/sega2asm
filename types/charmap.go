package types

import (
	"bufio"
	"encoding/hex"
	"fmt"
	"os"
	"strings"
)

// CharMap translates ROM byte sequences to readable strings.
// Format: standard THINGY/WindHex .tbl files.
type CharMap struct {
	entries map[string]string
	maxLen  int
}

// LoadCharmap reads a .tbl file. Returns an empty map if path is empty/missing.
func LoadCharmap(path string) (*CharMap, error) {
	m := &CharMap{entries: make(map[string]string)}
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

// Lookup attempts to decode bytes starting at data[pos].
// Returns the decoded string and number of bytes consumed, or ("", 0) on no match.
func (m *CharMap) Lookup(data []byte, pos int) (string, int) {
	if len(m.entries) == 0 {
		return "", 0
	}
	maxLen := m.maxLen
	if maxLen > len(data)-pos {
		maxLen = len(data) - pos
	}
	for l := maxLen; l >= 1; l-- {
		key := strings.ToUpper(hex.EncodeToString(data[pos : pos+l]))
		if ch, ok := m.entries[key]; ok {
			return ch, l
		}
	}
	return "", 0
}

// DecodeString decodes bytes using the charmap, stopping at terminator (default 0x00).
func (m *CharMap) DecodeString(data []byte, terminator byte) string {
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
func (m *CharMap) Empty() bool { return len(m.entries) == 0 }
