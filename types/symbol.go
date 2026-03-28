package types

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// Symbol is a named ROM address.
type Symbol struct {
	Addr uint32
	Name string
}

// SymbolTable manages symbol lookups by address and name.
type SymbolTable struct {
	ByAddr  map[uint32]string
	ByName  map[string]uint32
	Ordered []Symbol
}

// NewSymbolTable creates an empty symbol table.
func NewSymbolTable() *SymbolTable {
	return &SymbolTable{
		ByAddr: make(map[uint32]string),
		ByName: make(map[string]uint32),
	}
}

// LoadSymbols reads a symbols file and returns a populated SymbolTable.
// Formats supported:
//
//	labelname = $XXXXXX
//	$XXXXXX labelname
//	XXXXXX:labelname
//	XXXXXX labelname
func LoadSymbols(path string) (*SymbolTable, error) {
	t := NewSymbolTable()
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
		sym, err := parseSymbolLine(line)
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

func parseSymbolLine(line string) (Symbol, error) {
	if i := strings.IndexByte(line, ';'); i >= 0 {
		line = strings.TrimSpace(line[:i])
	}
	if i := strings.Index(line, "//"); i >= 0 {
		line = strings.TrimSpace(line[:i])
	}

	if strings.Contains(line, "=") {
		parts := strings.SplitN(line, "=", 2)
		name := strings.TrimSpace(parts[0])
		addr, err := ParseHex(strings.TrimSpace(parts[1]))
		if err != nil {
			return Symbol{}, err
		}
		return Symbol{Addr: addr, Name: name}, nil
	}

	if strings.Contains(line, ":") {
		parts := strings.SplitN(line, ":", 2)
		addr, err := ParseHex(strings.TrimSpace(parts[0]))
		if err != nil {
			return Symbol{}, err
		}
		return Symbol{Addr: addr, Name: strings.TrimSpace(parts[1])}, nil
	}

	fields := strings.Fields(line)
	if len(fields) == 2 {
		if addr, err := ParseHex(fields[0]); err == nil {
			return Symbol{Addr: addr, Name: fields[1]}, nil
		}
		if addr, err := ParseHex(fields[1]); err == nil {
			return Symbol{Addr: addr, Name: fields[0]}, nil
		}
	}
	return Symbol{}, fmt.Errorf("unrecognised line: %q", line)
}

// Label returns the symbol name for addr, or a generated "loc_XXXXXX" fallback.
func (t *SymbolTable) Label(addr uint32) string {
	return LookupOrHex(t.ByAddr, addr)
}

// Has returns true if addr has an explicit symbol.
func (t *SymbolTable) Has(addr uint32) bool {
	_, ok := t.ByAddr[addr]
	return ok
}

// Add inserts a symbol only if neither the address nor the name is already
// present, so explicit symbols-file entries always take priority.
func (t *SymbolTable) Add(addr uint32, name string) {
	if _, exists := t.ByAddr[addr]; exists {
		return
	}
	if _, exists := t.ByName[name]; exists {
		return
	}
	t.ByAddr[addr] = name
	t.ByName[name] = addr
	t.Ordered = append(t.Ordered, Symbol{Addr: addr, Name: name})
}