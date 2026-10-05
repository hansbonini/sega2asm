// Package analysis implements a recursive-descent control-flow tracer for
// Mega Drive 68000 ROMs. It separates code from data by following every
// reachable instruction from the interrupt vectors and user-supplied entry
// points, resolves jump/pointer tables with a small per-block register
// tracker, and speculatively validates code pointers found in immediates.
//
// The result is used to generate sega2asm segment maps whose m68k segments
// contain only real instructions and whose data blocks are split out.
package analysis

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"sega2asm/disasm/m68k"
)

// ByteKind classifies a ROM byte.
type ByteKind uint8

const (
	Unknown  ByteKind = iota
	CodeHead          // first byte of an instruction
	CodeTail          // continuation byte of an instruction
	Data              // known data (tables, referenced blobs)
)

// TableKind identifies how a jump/pointer table is encoded.
type TableKind string

const (
	TableLong    TableKind = "long"     // dc.l absolute code pointers
	TableWordRel TableKind = "word_rel" // dc.w offsets relative to Base
	TableBranch  TableKind = "branch"   // sequence of bra.w / bra.s / jmp
)

// Table describes a resolved jump or pointer table.
type Table struct {
	Addr    uint32
	Kind    TableKind
	Base    uint32 // for word_rel
	Count   int
	From    uint32 // instruction that dispatches through the table
	Targets []uint32
	Manual  bool
}

// Size returns the table size in bytes.
func (t *Table) Size() uint32 {
	switch t.Kind {
	case TableLong:
		return uint32(t.Count * 4)
	case TableWordRel:
		return uint32(t.Count * 2)
	}
	return 0 // branch tables are code
}

// EntryKind describes why an address is a code entry.
type EntryKind uint8

const (
	EntryVector EntryKind = iota
	EntryCall
	EntryTable
	EntryPointer // immediate / lea operand validated as code
	EntryUser
	EntryOrphan // recovered from an unreferenced gap
)

// Options configures a trace.
type Options struct {
	Entries  []uint32 // extra entry points (always code)
	NoReturn []uint32 // subroutines that never return to their caller
	Data     []Range  // forced data ranges
	Tables   []Table  // manually specified tables
	CodeEnd  uint32   // ignore code candidates at or above this address (0 = ROM size)
	Verbose  bool
	// Orphans enables recovery of unreferenced functions found in the gaps
	// between traced code (a gap that starts after a terminator, decodes as a
	// plausible instruction stream and ends in a terminator).
	Orphans bool
}

// Range is a half-open address interval [Start, End).
type Range struct {
	Start, End uint32
}

// Result is the output of a trace.
type Result struct {
	ROM       []byte
	Kind      []ByteKind
	Insns     map[uint32]*m68k.Result
	Entries   map[uint32]EntryKind // function entry points
	Branches  map[uint32]bool      // local branch targets
	DataRefs  map[uint32]int       // referenced data addresses -> operand size
	Tables    []*Table
	Conflicts []string
	Indirect  []uint32          // unresolved indirect jmp/jsr sites
	Rejected  map[uint32]string // pointer candidates rejected as code, with reason
	// Xrefs maps every referenced ROM address (code or data) to the
	// addresses of the instructions that reference it.
	Xrefs map[uint32][]Xref
}

// Xref is a single operand reference.
type Xref struct {
	From uint32
	Kind m68k.RefKind
	Size int
}

// Tracer holds the state of an in-progress trace.
type Tracer struct {
	rom      []byte
	opts     Options
	res      *Result
	dis      *m68k.Disassembler
	noReturn map[uint32]bool
	forced   []Range
	tableAt  map[uint32]*Table
	pending  []uint32
	ptrCands map[uint32]bool
	codeEnd  uint32
	why      string
	rejected map[uint32]string
}

// Trace runs the analysis over rom.
func Trace(rom []byte, opts Options) *Result {
	t := &Tracer{
		rom:      rom,
		opts:     opts,
		dis:      m68k.New(rom, 0, nil),
		noReturn: map[uint32]bool{},
		tableAt:  map[uint32]*Table{},
		ptrCands: map[uint32]bool{},
		codeEnd:  opts.CodeEnd,
		rejected: map[uint32]string{},
	}
	if t.codeEnd == 0 || t.codeEnd > uint32(len(rom)) {
		t.codeEnd = uint32(len(rom))
	}
	t.res = &Result{
		ROM:      rom,
		Kind:     make([]ByteKind, len(rom)),
		Insns:    map[uint32]*m68k.Result{},
		Entries:  map[uint32]EntryKind{},
		Branches: map[uint32]bool{},
		DataRefs: map[uint32]int{},
		Rejected: map[uint32]string{},
		Xrefs:    map[uint32][]Xref{},
	}
	for _, a := range opts.NoReturn {
		t.noReturn[a] = true
	}
	for _, r := range opts.Data {
		t.forced = append(t.forced, r)
		t.markData(r.Start, r.End)
	}
	// Header and vector table are data.
	t.markData(0, 0x200)

	// Vectors: reset PC and every exception vector that points into ROM.
	for i := 1; i < 64; i++ {
		v := be32(rom, uint32(i*4))
		if v >= 0x200 && v < uint32(len(rom)) && v&1 == 0 {
			t.addEntry(v, EntryVector)
		}
	}
	for _, e := range opts.Entries {
		t.addEntry(e, EntryUser)
	}
	for i := range opts.Tables {
		tb := opts.Tables[i]
		tb.Manual = true
		t.applyTable(&tb)
	}

	t.run()

	// Validate pointer candidates speculatively until nothing changes.
	for {
		n := t.resolvePointers()
		if n == 0 {
			break
		}
		t.run()
	}

	if opts.Orphans {
		for t.recoverOrphans() > 0 {
			t.run()
			for t.resolvePointers() > 0 {
				t.run()
			}
		}
	}

	sort.Slice(t.res.Tables, func(i, j int) bool { return t.res.Tables[i].Addr < t.res.Tables[j].Addr })
	sort.Slice(t.res.Indirect, func(i, j int) bool { return t.res.Indirect[i] < t.res.Indirect[j] })
	return t.res
}

func be32(b []byte, a uint32) uint32 {
	if int(a)+4 > len(b) {
		return 0
	}
	return uint32(b[a])<<24 | uint32(b[a+1])<<16 | uint32(b[a+2])<<8 | uint32(b[a+3])
}

func be16(b []byte, a uint32) uint16 {
	if int(a)+2 > len(b) {
		return 0
	}
	return uint16(b[a])<<8 | uint16(b[a+1])
}

func (t *Tracer) inROM(a uint32) bool { return a >= 0x200 && a < uint32(len(t.rom)) }

func (t *Tracer) isForcedData(a uint32) bool {
	for _, r := range t.forced {
		if a >= r.Start && a < r.End {
			return true
		}
	}
	return false
}

func (t *Tracer) markData(start, end uint32) {
	if end > uint32(len(t.rom)) {
		end = uint32(len(t.rom))
	}
	for a := start; a < end; a++ {
		if t.res.Kind[a] == Unknown {
			t.res.Kind[a] = Data
		}
	}
}

func (t *Tracer) addEntry(a uint32, k EntryKind) {
	if _, ok := t.res.Entries[a]; !ok || k < t.res.Entries[a] {
		t.res.Entries[a] = k
	}
	t.pending = append(t.pending, a)
}

func (t *Tracer) conflict(format string, args ...any) {
	t.res.Conflicts = append(t.res.Conflicts, fmt.Sprintf(format, args...))
}

func (t *Tracer) decode(a uint32) *m68k.Result {
	if r, ok := t.res.Insns[a]; ok {
		return r
	}
	t.dis.Pos = int(a)
	r := t.dis.Next()
	return &r
}

// run drains the pending worklist, committing code unconditionally.
func (t *Tracer) run() {
	for len(t.pending) > 0 {
		a := t.pending[len(t.pending)-1]
		t.pending = t.pending[:len(t.pending)-1]
		t.traceBlock(a)
	}
}

// traceBlock decodes a straight-line sequence starting at a and commits it.
func (t *Tracer) traceBlock(a uint32) {
	var regs regState
	for {
		if !t.inROM(a) || a&1 != 0 {
			t.conflict("$%06X: code outside ROM or odd address", a)
			return
		}
		switch t.res.Kind[a] {
		case CodeHead:
			return // already traced
		case CodeTail:
			t.conflict("$%06X: jump into the middle of an instruction", a)
			return
		}
		if t.isForcedData(a) {
			t.conflict("$%06X: code flows into forced data", a)
			return
		}
		r := t.decode(a)
		if !r.IsValid {
			t.conflict("$%06X: invalid instruction %s", a, strings.TrimSpace(r.Text))
			return
		}
		n := uint32(len(r.Bytes))
		for i := uint32(1); i < n; i++ {
			if k := t.res.Kind[a+i]; k == CodeHead || k == CodeTail {
				t.conflict("$%06X: instruction overlaps code at $%06X", a, a+i)
				return
			}
		}
		if t.res.Kind[a] == Data {
			t.conflict("$%06X: code overlaps data", a)
		}
		t.res.Insns[a] = r
		t.res.Kind[a] = CodeHead
		for i := uint32(1); i < n; i++ {
			t.res.Kind[a+i] = CodeTail
		}
		t.noteRefs(r)

		next := a + n
		switch r.Flow {
		case m68k.FlowReturn, m68k.FlowHalt:
			return
		case m68k.FlowJump:
			if r.HasTarget {
				t.branchTo(r.Target, r.Mnemonic == "jmp")
			} else {
				t.dispatch(r, &regs, false)
			}
			return
		case m68k.FlowBranch:
			if r.HasTarget {
				t.branchTo(r.Target, false)
			}
		case m68k.FlowCall:
			if r.HasTarget {
				t.addEntry(r.Target, EntryCall)
				if t.noReturn[r.Target] {
					return
				}
			} else {
				t.dispatch(r, &regs, true)
			}
			regs.clobber()
		}
		regs.step(r, t)
		a = next
	}
}

func (t *Tracer) branchTo(a uint32, far bool) {
	if far {
		t.addEntry(a, EntryCall)
		return
	}
	t.res.Branches[a] = true
	t.pending = append(t.pending, a)
}

// noteRefs records data references and pointer candidates.
func (t *Tracer) noteRefs(r *m68k.Result) {
	for _, ref := range r.Refs {
		if t.inROM(ref.Addr) || ref.Addr >= 0xFF0000 {
			t.res.Xrefs[ref.Addr] = append(t.res.Xrefs[ref.Addr], Xref{From: r.Addr, Kind: ref.Kind, Size: ref.Size})
		}
		switch ref.Kind {
		case m68k.RefData, m68k.RefIndexed:
			if t.inROM(ref.Addr) && r.Mnemonic != "jmp" && r.Mnemonic != "jsr" {
				if old, ok := t.res.DataRefs[ref.Addr]; !ok || ref.Size > old {
					t.res.DataRefs[ref.Addr] = ref.Size
				}
			}
		case m68k.RefEffAddr, m68k.RefImm:
			if ref.Kind == m68k.RefImm && ref.Addr < 0x10000 {
				mn := r.Mnemonic
				if !((mn == "move" || mn == "movea") && !dataRegDest(r.Text) || mn == "cmpi") {
					continue // counters, sizes and offsets, not pointers
				}
			}
			if t.inROM(ref.Addr) && ref.Addr&1 == 0 {
				t.ptrCands[ref.Addr] = true
			}
			if ref.Kind == m68k.RefEffAddr && t.inROM(ref.Addr) {
				if _, ok := t.res.DataRefs[ref.Addr]; !ok {
					t.res.DataRefs[ref.Addr] = 0
				}
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Register tracking for table dispatch
// ---------------------------------------------------------------------------

type valKind uint8

const (
	vUnknown valKind = iota
	vConst           // register holds a known address
	vLongAt          // register holds a long read from table at addr
	vWordAt          // register holds a word read from table at addr
)

type regVal struct {
	kind valKind
	addr uint32
}

type regState struct {
	d [8]regVal
	a [8]regVal
}

func (s *regState) clobber() { *s = regState{} }

func (s *regState) get(name string) *regVal {
	if len(name) != 2 {
		return nil
	}
	n := int(name[1] - '0')
	if n < 0 || n > 7 {
		return nil
	}
	switch name[0] {
	case 'd':
		return &s.d[n]
	case 'a':
		return &s.a[n]
	}
	if name == "sp" {
		return &s.a[7]
	}
	return nil
}

// splitOperands splits an operand string on commas outside parentheses.
func splitOperands(s string) []string {
	var out []string
	depth := 0
	start := 0
	for i, c := range s {
		switch c {
		case '(':
			depth++
		case ')':
			depth--
		case ',':
			if depth == 0 {
				out = append(out, s[start:i])
				start = i + 1
			}
		}
	}
	return append(out, s[start:])
}

// parseInsn returns mnemonic (with size) and operands of a disassembled line.
func parseInsn(text string) (string, []string) {
	text = strings.TrimSpace(text)
	if i := strings.Index(text, ";"); i >= 0 {
		text = strings.TrimSpace(text[:i])
	}
	parts := strings.SplitN(text, "\t", 2)
	if len(parts) < 2 {
		return parts[0], nil
	}
	return parts[0], splitOperands(parts[1])
}

// indexedOperand parses "X(aN,dM.w)" / "X(pc,dM.w)" into base register, disp
// (or absolute address for pc) and index register.
func indexedOperand(op string) (base string, disp int64, idx string, ok bool) {
	i := strings.Index(op, "(")
	if i < 0 || !strings.HasSuffix(op, ")") {
		return
	}
	inner := strings.Split(op[i+1:len(op)-1], ",")
	if len(inner) != 2 {
		return
	}
	d, err := parseNum(op[:i])
	if err != nil {
		return
	}
	idx = strings.SplitN(inner[1], ".", 2)[0]
	return inner[0], d, idx, true
}

func parseNum(s string) (int64, error) {
	neg := false
	if strings.HasPrefix(s, "-") {
		neg = true
		s = s[1:]
	}
	var v uint64
	var err error
	if strings.HasPrefix(s, "$") {
		v, err = strconv.ParseUint(s[1:], 16, 32)
	} else {
		v, err = strconv.ParseUint(s, 10, 32)
	}
	if neg {
		return -int64(v), err
	}
	return int64(v), err
}

// operandAddr returns the absolute address of an operand of the form
// "$XXXXXX(pc)", "($XXXXXX).l", "($XXXX).w" or "#$XXXXXXXX".
func operandAddr(op string) (uint32, bool) {
	switch {
	case strings.HasSuffix(op, "(pc)"):
		v, err := parseNum(strings.TrimSuffix(op, "(pc)"))
		return uint32(v), err == nil
	case strings.HasPrefix(op, "(") && (strings.HasSuffix(op, ").l") || strings.HasSuffix(op, ").w")):
		v, err := parseNum(op[1 : len(op)-3])
		return uint32(v), err == nil
	case strings.HasPrefix(op, "#$"):
		v, err := parseNum(op[1:])
		return uint32(v), err == nil
	}
	return 0, false
}

// step updates the register state for instruction r.
func (s *regState) step(r *m68k.Result, t *Tracer) {
	mn, ops := parseInsn(r.Text)
	if len(ops) == 0 {
		return
	}
	dst := ops[len(ops)-1]
	// Post-increment / pre-decrement anywhere invalidates that register.
	for _, op := range ops {
		if strings.HasSuffix(op, ")+") || strings.HasPrefix(op, "-(") {
			if i := strings.Index(op, "("); i >= 0 {
				if v := s.get(op[i+1 : i+3]); v != nil {
					*v = regVal{}
				}
			}
		}
	}
	if strings.HasPrefix(mn, "movem") || mn == "exg" {
		s.clobber()
		return
	}
	dv := s.get(dst)
	if dv == nil {
		return
	}
	src := ""
	if len(ops) >= 2 {
		src = ops[0]
	}
	switch {
	case mn == "lea":
		if a, ok := operandAddr(src); ok {
			*dv = regVal{kind: vConst, addr: a}
			return
		}
		if base, disp, _, ok := indexedOperand(src); !ok {
			// d16(aN)
			if i := strings.Index(src, "("); i > 0 {
				if bv := s.get(src[i+1 : len(src)-1]); bv != nil && bv.kind == vConst {
					if d, err := parseNum(src[:i]); err == nil {
						*dv = regVal{kind: vConst, addr: uint32(int64(bv.addr) + d)}
						return
					}
				}
			}
		} else {
			_ = base
			_ = disp
		}
		*dv = regVal{}
	case mn == "movea.l" || mn == "move.l" || mn == "move.w" || mn == "movea.w":
		if a, ok := operandAddr(src); ok && strings.HasPrefix(src, "#") && strings.HasSuffix(mn, ".l") {
			*dv = regVal{kind: vConst, addr: a}
			return
		}
		if base, disp, _, ok := indexedOperand(src); ok {
			var tbl uint32
			found := false
			if base == "pc" {
				tbl, found = uint32(disp), true
			} else if bv := s.get(base); bv != nil && bv.kind == vConst {
				tbl, found = uint32(int64(bv.addr)+disp), true
			}
			if found {
				k := vLongAt
				if strings.HasSuffix(mn, ".w") {
					k = vWordAt
				}
				*dv = regVal{kind: k, addr: tbl}
				return
			}
		}
		if sv := s.get(src); sv != nil {
			*dv = *sv
			return
		}
		// (aN) with aN const: long read from a single pointer
		if strings.HasPrefix(src, "(") && strings.HasSuffix(src, ")") {
			if bv := s.get(src[1 : len(src)-1]); bv != nil && bv.kind == vConst {
				*dv = regVal{kind: vLongAt, addr: bv.addr}
				return
			}
		}
		*dv = regVal{}
	case strings.HasPrefix(mn, "add") || strings.HasPrefix(mn, "lsl") || strings.HasPrefix(mn, "asl"):
		// Scaling an index register keeps table facts about other registers;
		// the index itself becomes an unknown number.
		if dv.kind == vConst && (mn == "adda.w" || mn == "adda.l") {
			*dv = regVal{}
		} else if dv.kind != vConst {
			*dv = regVal{}
		}
	default:
		if !strings.HasPrefix(mn, "cmp") && !strings.HasPrefix(mn, "tst") && !strings.HasPrefix(mn, "btst") {
			*dv = regVal{}
		}
	}
}

// dispatch tries to resolve an indirect jmp/jsr through a table.
func (t *Tracer) dispatch(r *m68k.Result, s *regState, call bool) {
	_, ops := parseInsn(r.Text)
	if len(ops) != 1 {
		t.res.Indirect = append(t.res.Indirect, r.Addr)
		return
	}
	op := ops[0]
	// jmp (aN)
	if strings.HasPrefix(op, "(") && strings.HasSuffix(op, ")") && len(op) == 4 {
		v := s.get(op[1:3])
		if v != nil {
			switch v.kind {
			case vConst:
				t.addEntry(v.addr, EntryPointer)
				return
			case vLongAt:
				t.applyTable(&Table{Addr: v.addr, Kind: TableLong, From: r.Addr})
				return
			}
		}
		t.res.Indirect = append(t.res.Indirect, r.Addr)
		return
	}
	// jmp X(pc,dN) / jmp d(aN,dM)
	if base, disp, idx, ok := indexedOperand(op); ok {
		var tbl uint32
		found := false
		if base == "pc" {
			tbl, found = uint32(disp), true
		} else if bv := s.get(base); bv != nil && bv.kind == vConst {
			tbl, found = uint32(int64(bv.addr)+disp), true
		}
		if found {
			iv := s.get(idx)
			if iv != nil && iv.kind == vWordAt {
				t.applyTable(&Table{Addr: iv.addr, Kind: TableWordRel, Base: tbl, From: r.Addr})
			} else {
				t.applyTable(&Table{Addr: tbl, Kind: TableBranch, From: r.Addr})
			}
			return
		}
	}
	t.res.Indirect = append(t.res.Indirect, r.Addr)
}

// applyTable reads, validates and commits a table.
func (t *Tracer) applyTable(tb *Table) {
	if old, ok := t.tableAt[tb.Addr]; ok {
		if old.Kind == tb.Kind {
			return
		}
	}
	if !t.inROM(tb.Addr) {
		t.conflict("$%06X: table outside ROM (from $%06X)", tb.Addr, tb.From)
		return
	}
	limit := uint32(len(t.rom))
	if tb.Count == 0 {
		tb.Count = 1 << 30
	}
	var targets []uint32
	minTarget := limit
	switch tb.Kind {
	case TableLong:
		for i := 0; i < tb.Count; i++ {
			a := tb.Addr + uint32(i*4)
			if a+4 > limit || a >= minTarget {
				break
			}
			if !tb.Manual && i > 0 && t.stopTableAt(a) {
				break
			}
			v := be32(t.rom, a)
			if !tb.Manual && (!t.inROM(v) || v&1 != 0 || v >= t.codeEnd || !t.plausibleCode(v)) {
				break
			}
			targets = append(targets, v)
			if v > tb.Addr && v < minTarget {
				minTarget = v
			}
		}
	case TableWordRel:
		for i := 0; i < tb.Count; i++ {
			a := tb.Addr + uint32(i*2)
			if a+2 > limit || a >= minTarget {
				break
			}
			if !tb.Manual && i > 0 && t.stopTableAt(a) {
				break
			}
			v := tb.Base + uint32(int32(int16(be16(t.rom, a))))
			if !tb.Manual && (!t.inROM(v) || v&1 != 0 || !t.plausibleCode(v)) {
				break
			}
			targets = append(targets, v)
			if v > tb.Addr && v < minTarget {
				minTarget = v
			}
		}
	case TableBranch:
		a := tb.Addr
		for i := 0; i < tb.Count && a < minTarget; i++ {
			if !tb.Manual && i > 0 && t.stopTableAt(a) {
				break
			}
			r := t.decode(a)
			if !r.IsValid || r.Flow != m68k.FlowJump || !r.HasTarget {
				break
			}
			targets = append(targets, a)
			if r.Target > tb.Addr && r.Target < minTarget {
				minTarget = r.Target
			}
			a += uint32(len(r.Bytes))
		}
	}
	if len(targets) == 0 {
		t.conflict("$%06X: empty %s table (from $%06X)", tb.Addr, tb.Kind, tb.From)
		return
	}
	tb.Count = len(targets)
	tb.Targets = targets
	t.tableAt[tb.Addr] = tb
	t.res.Tables = append(t.res.Tables, tb)
	if tb.Kind != TableBranch {
		t.markData(tb.Addr, tb.Addr+tb.Size())
	}
	for _, v := range targets {
		if tb.Kind == TableBranch {
			t.res.Branches[v] = true
			t.pending = append(t.pending, v)
		} else {
			t.addEntry(v, EntryTable)
		}
	}
}

// stopTableAt reports whether a table scan must stop at address a because
// something else is already known to start there.
func (t *Tracer) stopTableAt(a uint32) bool {
	if k := t.res.Kind[a]; k == CodeHead || k == CodeTail {
		return true
	}
	if _, ok := t.res.Entries[a]; ok {
		return true
	}
	if t.res.Branches[a] {
		return true
	}
	if _, ok := t.tableAt[a]; ok {
		return true
	}
	return false
}

// ---------------------------------------------------------------------------
// Speculative validation
// ---------------------------------------------------------------------------

// suspicious reports instructions that are legal but almost never appear in
// hand-written or compiled game code; they are strong evidence of data.
// strict additionally rejects rarely used forms (used when recovering
// unreferenced code, where the evidence is weaker).
func suspicious(r *m68k.Result, strict bool) bool {
	if strings.HasPrefix(r.Text, "\tdc.") {
		return true // non-canonical encoding
	}
	op := uint16(0)
	if len(r.Bytes) >= 2 {
		op = uint16(r.Bytes[0])<<8 | uint16(r.Bytes[1])
	}
	switch r.Mnemonic {
	case "abcd", "sbcd", "nbcd", "movep", "chk", "trapv", "reset", "stop", "rtr",
		"tas", "illegal", "trap":
		return true
	case "negx", "link", "unlk", "addx", "subx", "rte":
		return strict
	case "ori", "andi", "eori":
		// $0000-$0007: zero words decode as "ori.b #x,dN".
		if op < 8 {
			return true
		}
		if strings.HasSuffix(r.Text, ",sr") || strings.HasSuffix(r.Text, ",ccr") {
			return strict
		}
		if strict && op < 0x0100 {
			return true // ORI: small data words ($00xx) decode as ori
		}
	case "move":
		if strings.Contains(r.Text, "usp") {
			return true
		}
		if strings.HasSuffix(r.Text, ",sr") {
			// move.w #$2x00,sr is the usual interrupt mask update.
			return !strings.Contains(r.Text, "#$2")
		}
		if strings.Contains(r.Text, "\tsr,") {
			return strict
		}
	}
	return false
}

// plausibleCode performs a cheap speculative decode from a to check that a
// candidate code pointer does not start with garbage.
func (t *Tracer) plausibleCode(a uint32) bool {
	if a&1 != 0 || !t.inROM(a) || a >= t.codeEnd {
		return false
	}
	if k := t.res.Kind[a]; k == CodeHead {
		return true
	} else if k == CodeTail || k == Data {
		return false
	}
	if t.isForcedData(a) {
		return false
	}
	ok, _ := t.explore(a, 4000)
	return ok
}

// explore speculatively follows code from a without committing anything.
// It fails on invalid/suspicious instructions, overlaps with existing code or
// data, or flow into forced data. Returns the set of instruction addresses.
func (t *Tracer) explore(start uint32, budget int) (bool, map[uint32]*m68k.Result) {
	return t.exploreMode(start, budget, false)
}

func (t *Tracer) exploreMode(start uint32, budget int, strict bool) (bool, map[uint32]*m68k.Result) {
	t.why = ""
	fail := func(format string, args ...any) (bool, map[uint32]*m68k.Result) {
		t.why = fmt.Sprintf(format, args...)
		return false, nil
	}
	seen := map[uint32]*m68k.Result{}
	work := []uint32{start}
	for len(work) > 0 {
		a := work[len(work)-1]
		work = work[:len(work)-1]
		for {
			if budget--; budget < 0 {
				return true, seen // large, consistent region: accept
			}
			if !t.inROM(a) || a&1 != 0 || a >= t.codeEnd {
				return fail("$%06X: outside code area", a)
			}
			if _, ok := seen[a]; ok {
				break
			}
			switch t.res.Kind[a] {
			case CodeHead:
				goto nextWork
			case CodeTail, Data:
				return fail("$%06X: overlaps %s", a, t.res.Kind[a])
			}
			if t.isForcedData(a) {
				return fail("$%06X: forced data", a)
			}
			r := t.decode(a)
			if !r.IsValid || suspicious(r, strict) {
				return fail("$%06X: bad instruction %s", a, strings.TrimSpace(r.Text))
			}
			n := uint32(len(r.Bytes))
			for i := uint32(1); i < n; i++ {
				if k := t.res.Kind[a+i]; k != Unknown {
					return fail("$%06X: tail overlaps %s", a, k)
				}
			}
			seen[a] = r
			switch r.Flow {
			case m68k.FlowReturn, m68k.FlowHalt:
				goto nextWork
			case m68k.FlowJump:
				if r.HasTarget {
					work = append(work, r.Target)
				}
				goto nextWork
			case m68k.FlowBranch:
				if r.HasTarget {
					work = append(work, r.Target)
				}
			case m68k.FlowCall:
				if r.HasTarget {
					if !t.inROM(r.Target) || r.Target&1 != 0 {
						return fail("$%06X: call to bad target $%06X", a, r.Target)
					}
					if t.noReturn[r.Target] {
						goto nextWork
					}
				}
			}
			a += n
		}
	nextWork:
	}
	return true, seen
}

// resolvePointers validates immediate / lea operands that point into ROM and
// commits the ones that decode as plausible code. Returns the number added.
func (t *Tracer) resolvePointers() int {
	var cands []uint32
	for a := range t.ptrCands {
		cands = append(cands, a)
	}
	sort.Slice(cands, func(i, j int) bool { return cands[i] < cands[j] })
	added := 0
	for _, a := range cands {
		delete(t.ptrCands, a)
		if t.res.Kind[a] != Unknown || a >= t.codeEnd {
			continue
		}
		// Referenced as data by a non-lea operand: not code.
		if sz, ok := t.res.DataRefs[a]; ok && sz > 0 {
			continue
		}
		// Round values ($x000) are usually constants (16.16 fixed point,
		// sizes, VRAM offsets); only accept them right after a terminator.
		if a&0xFFF == 0 {
			if p := t.prevInsn(a); p == nil || !(p.Flow == m68k.FlowReturn || p.Flow == m68k.FlowJump || p.Flow == m68k.FlowHalt) {
				t.res.Rejected[a] = "round constant"
				continue
			}
		}
		if ok, seen := t.explore(a, 20000); ok && len(seen) >= 2 {
			t.addEntry(a, EntryPointer)
			delete(t.res.Rejected, a)
			added++
		} else if !ok {
			t.res.Rejected[a] = t.why
		}
	}
	return added
}

// recoverOrphans looks for unreferenced code in the gaps between traced code:
//   - a gap that decodes linearly into plausible instructions filling it
//     exactly and ending in a terminator or falling into known code (dead
//     "bra" after "rts" emitted by structured-assembly macros, interrupt
//     handlers installed at run time, ...);
//   - a gap that starts after a terminator and explores as a complete
//     function (at least three instructions, ending in a terminator).
func (t *Tracer) recoverOrphans() int {
	added := 0
	n := uint32(len(t.rom))
	for a := uint32(0x200); a < t.codeEnd && a < n; a += 2 {
		if t.res.Kind[a] != Unknown {
			continue
		}
		end := a
		for end < n && t.res.Kind[end] == Unknown {
			end++
		}
		prev := t.prevInsn(a)
		afterTerm := prev != nil && (prev.Flow == m68k.FlowReturn || prev.Flow == m68k.FlowJump || prev.Flow == m68k.FlowHalt)
		if prev != nil && t.gapFill(a, end) {
			t.addEntry(a, EntryOrphan)
			added++
			a = end - 2
			continue
		}
		if !afterTerm {
			a = end - 2 + (end-a)%2
			continue
		}
		if w := be16(t.rom, a); w == 0 || w == 0xFFFF {
			a = end - 2 + (end-a)%2
			continue
		}
		if ok, seen := t.exploreMode(a, 20000, true); ok && len(seen) >= 3 && t.endsCleanly(seen) {
			t.addEntry(a, EntryOrphan)
			added++
		}
		a = end - 2 + (end-a)%2
	}
	return added
}

// gapFill reports whether [a,end) decodes linearly into plausible code that
// exactly fills the gap and either ends in a terminator or falls through
// into already-traced code.
func (t *Tracer) gapFill(a, end uint32) bool {
	if a&1 != 0 || end > t.codeEnd {
		return false
	}
	var last *m68k.Result
	for p := a; p < end; {
		r := t.decode(p)
		if !r.IsValid || suspicious(r, true) {
			return false
		}
		if r.HasTarget && (r.Flow == m68k.FlowBranch || r.Flow == m68k.FlowJump || r.Flow == m68k.FlowCall) {
			tg := r.Target
			if !t.inROM(tg) || tg&1 != 0 {
				return false
			}
			if k := t.res.Kind[tg]; k == CodeTail || k == Data {
				return false
			}
		}
		last = r
		p += uint32(len(r.Bytes))
		if p > end {
			return false
		}
	}
	if last == nil {
		return false
	}
	switch last.Flow {
	case m68k.FlowReturn, m68k.FlowJump, m68k.FlowHalt:
		return true
	}
	return int(end) < len(t.rom) && t.res.Kind[end] == CodeHead
}

// endsCleanly reports whether a speculative region contains at least one
// terminator (so it is a function, not a run of decodable data).
func (t *Tracer) endsCleanly(seen map[uint32]*m68k.Result) bool {
	for _, r := range seen {
		if r.Flow == m68k.FlowReturn || r.Flow == m68k.FlowJump {
			return true
		}
	}
	return false
}

func (t *Tracer) prevInsn(a uint32) *m68k.Result {
	for back := uint32(2); back <= 10 && back <= a; back += 2 {
		if r, ok := t.res.Insns[a-back]; ok && a-back+uint32(len(r.Bytes)) == a {
			return r
		}
	}
	return nil
}

// dataRegDest reports whether the last operand of an instruction is a data
// register.
func dataRegDest(text string) bool {
	i := strings.LastIndexByte(text, ',')
	if i < 0 {
		return false
	}
	op := strings.TrimSpace(text[i+1:])
	return len(op) == 2 && op[0] == 'd' && op[1] >= '0' && op[1] <= '7'
}
