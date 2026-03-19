// Package symbols parses symbols.txt files for use as labels in disassembly.
// Formats supported:
//   labelname = $XXXXXX
//   $XXXXXX labelname
//   XXXXXX:labelname
//   XXXXXX labelname
package symbols

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"sega2asm/helpers"
	"sega2asm/types"
)

type Table struct {
	ByAddr  map[uint32]string
	ByName  map[string]uint32
	Ordered []Symbol
}

type Symbol struct {
	Addr uint32
	Name string
}

func Load(path string) (*Table, error) {
	t := &Table{
		ByAddr: make(map[uint32]string),
		ByName: make(map[string]uint32),
	}
	if path == "" {
		return t, nil
	}
	f, err := os.Open(path)
	if os.IsNotExist(err) {
		return t, nil
	}
	if err != nil {
		return nil, fmt.Errorf("opening symbols %q: %w", path, err)
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || line[0] == ';' || strings.HasPrefix(line, "//") || line[0] == '#' {
			continue
		}
		sym, err := parseLine(line)
		if err != nil {
			continue
		}
		if _, ok := t.ByAddr[sym.Addr]; !ok {
			t.ByAddr[sym.Addr] = sym.Name
		}
		if _, ok := t.ByName[sym.Name]; !ok {
			t.ByName[sym.Name] = sym.Addr
		}
		t.Ordered = append(t.Ordered, sym)
	}
	return t, scanner.Err()
}

func parseLine(line string) (Symbol, error) {
	// Strip inline comments
	if i := strings.IndexByte(line, ';'); i >= 0 {
		line = strings.TrimSpace(line[:i])
	}
	if i := strings.Index(line, "//"); i >= 0 {
		line = strings.TrimSpace(line[:i])
	}

	// Format: name = $ADDR  or  name = 0xADDR
	if strings.Contains(line, "=") {
		parts := strings.SplitN(line, "=", 2)
		name := strings.TrimSpace(parts[0])
		addr, err := helpers.ParseHex(strings.TrimSpace(parts[1]))
		if err != nil {
			return Symbol{}, err
		}
		return Symbol{Addr: addr, Name: name}, nil
	}

	// Format: ADDR:name
	if strings.Contains(line, ":") {
		parts := strings.SplitN(line, ":", 2)
		addr, err := helpers.ParseHex(strings.TrimSpace(parts[0]))
		if err != nil {
			return Symbol{}, err
		}
		return Symbol{Addr: addr, Name: strings.TrimSpace(parts[1])}, nil
	}

	// Format: $ADDR name  or  ADDR name
	fields := strings.Fields(line)
	if len(fields) == 2 {
		// Try addr first, then name-first
		if addr, err := helpers.ParseHex(fields[0]); err == nil {
			return Symbol{Addr: addr, Name: fields[1]}, nil
		}
		if addr, err := helpers.ParseHex(fields[1]); err == nil {
			return Symbol{Addr: addr, Name: fields[0]}, nil
		}
	}
	return Symbol{}, fmt.Errorf("unrecognised line: %q", line)
}

// Label returns the symbol name for addr, or a generated "loc_XXXXXX" fallback.
func (t *Table) Label(addr uint32) string {
	return types.LookupOrHex(t.ByAddr, addr)
}

// Has returns true if addr has an explicit symbol.
func (t *Table) Has(addr uint32) bool {
	_, ok := t.ByAddr[addr]
	return ok
}
