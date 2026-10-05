// Package m68k implements a Motorola 68000 disassembler.
// Output is compatible with Clownacy/clownassembler (asm68k clone).
// Based on: https://github.com/Clownacy/clown68000
//
// The decoder is strict: every instruction is validated against the 68000
// effective-address rules and against the canonical encoding an assembler
// would produce. Anything that would not re-assemble to the identical bytes
// (68010+ opcodes, reserved EA modes, garbage bits in extension words,
// ADD/SUB/CMP/AND/OR #imm,Dn forms that assemblers rewrite to ADDI/...) is
// emitted as dc.w so the output always rebuilds bit-for-bit.
package m68k

import (
	"fmt"
	"strings"

	"sega2asm/disasm"
	"sega2asm/types"
)

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// FlowKind classifies the control-flow effect of an instruction.
type FlowKind uint8

const (
	FlowNone   FlowKind = iota
	FlowCall            // jsr, bsr — calls a subroutine
	FlowReturn          // rts, rte, rtr — returns from subroutine
	FlowJump            // jmp, bra — unconditional jump (no return)
	FlowBranch          // bcc, dbcc — conditional branch
	FlowHalt            // illegal, stop — execution stops
)

// RefKind classifies an address referenced by an instruction operand.
type RefKind uint8

const (
	RefCode    RefKind = iota // branch / jsr / jmp destination
	RefData                   // memory operand (absolute or PC-relative)
	RefImm                    // 32-bit immediate value (possible pointer)
	RefIndexed                // base of a PC-indexed operand, e.g. tbl(pc,d0.w)
	RefEffAddr                // address loaded by lea / pea
)

// Ref is an absolute address referenced by an instruction.
type Ref struct {
	Addr uint32
	Kind RefKind
	Size int // operand size in bytes (0 = unknown / not applicable)
}

// Result holds a single disassembled M68K instruction.
type Result struct {
	disasm.BaseResult
	Flow      FlowKind // control-flow classification
	Target    uint32   // resolved target address for Call/Jump/Branch (0 = indirect/unknown)
	HasTarget bool     // true when Target is a static address
	Refs      []Ref    // absolute addresses referenced by operands
	Mnemonic  string   // lower-case mnemonic without size suffix ("" for dc.w)
	Indirect  bool     // jmp/jsr through a register or indexed table
}

// Disassembler holds state needed for a disassembly pass.
type Disassembler struct {
	disasm.Cursor
	// ImmLabels, when non-nil, restricts which labels may replace 32-bit
	// immediate operands (constants that merely coincide with a label
	// address should stay numeric). nil means "use Labels".
	ImmLabels types.LabelMap
	// BaseRegs maps an address register number to the constant address it
	// holds throughout the code (e.g. a6 = $FF0000 for a globals block).
	// d16(An) operands are then printed as (label-base)(An) when a label
	// exists at base+d16.
	BaseRegs map[uint16]uint32
	// StructRegs maps an address register to structure field names by
	// offset: d16(An) is printed as name(An) when the offset is named.
	StructRegs map[uint16]map[int32]string
	// Instances are structures at fixed addresses (see types.StructInstance).
	Instances []types.InstanceInfo
	// Literal lists instructions (by address) whose operands must stay
	// numeric: absolute addresses that name another address space, such as
	// Z80 RAM offsets, and only coincide with ROM labels.
	Literal    map[uint32]bool
	insnPC     uint32
	lastFlow   FlowKind
	lastTarget uint32
	hasTarget  bool
	indirect   bool
	refs       []Ref
	bad        bool
	noncanon   bool // valid on a 68000 but not re-assemblable as written
	opPC       uint32
	immSym     string // symbolised 32-bit immediate in the current insn
	immVal     uint32
}

// literalRefs returns the operand references of the instruction at pc,
// without the data references of a Literal instruction.
func (d *Disassembler) literalRefs(pc uint32) []Ref {
	if !d.Literal[pc] {
		return d.refs
	}
	var out []Ref
	for _, r := range d.refs {
		if r.Kind == RefCode {
			out = append(out, r)
		}
	}
	return out
}

// New creates a Disassembler over data starting at baseAddr.
// Genesis hardware register addresses are pre-loaded as symbolic names;
// any entry in labels overrides the built-in defaults.
func New(data []byte, baseAddr uint32, labels types.LabelMap) *Disassembler {
	merged := make(types.LabelMap, len(genesisHWPorts)+len(labels))
	for k, v := range genesisHWPorts {
		merged[k] = v
	}
	for k, v := range labels {
		merged[k] = v
	}
	return &Disassembler{Cursor: disasm.Cursor{Data: data, Base: baseAddr, Labels: merged}}
}

// Next disassembles the instruction at the current position and advances pos.
func (d *Disassembler) Next() Result {
	if d.Pos+2 > len(d.Data) {
		return Result{BaseResult: disasm.BaseResult{Addr: d.PC(), IsValid: false}}
	}
	startPos := d.Pos
	startPC := d.PC()

	d.lastFlow = FlowNone
	d.lastTarget = 0
	d.hasTarget = false
	d.indirect = false
	d.refs = nil
	d.bad = false
	d.noncanon = false
	d.opPC = startPC
	d.insnPC = startPC
	d.immSym = ""

	text := d.decode()
	ok := !d.bad && text != ""

	if !ok {
		d.Pos = startPos + 2
		word := types.ReadBEU16(d.Data, startPos)
		return Result{BaseResult: disasm.BaseResult{
			Addr:    startPC,
			Bytes:   append([]byte(nil), d.Data[startPos:d.Pos]...),
			Text:    fmt.Sprintf("\tdc.w\t$%04X", word),
			IsValid: false,
		}}
	}

	text = applyImmStrLiterals(text)
	mn := strings.TrimSpace(text)
	if i := strings.IndexAny(mn, "\t ."); i >= 0 {
		mn = mn[:i]
	}
	if d.immSym != "" && d.immVal < 0x10000 && !pointerImmContext(mn, text) {
		// Small values are counters, sizes and offsets far more often than
		// pointers unless they are stored somewhere by a move or compared.
		text = strings.Replace(text, d.immSym, "#"+hexN(d.immVal, 8), 1)
	}
	if d.noncanon {
		// The instruction executes fine on a 68000 but an assembler would
		// encode the mnemonic differently; keep the exact words and show the
		// instruction as a comment.
		var words []string
		for p := startPos; p+1 < d.Pos; p += 2 {
			words = append(words, fmt.Sprintf("$%04X", types.ReadBEU16(d.Data, p)))
		}
		text = fmt.Sprintf("\tdc.w\t%s\t; %s", strings.Join(words, ","), strings.Replace(strings.TrimSpace(text), "\t", " ", 1))
	}
	return Result{
		BaseResult: disasm.BaseResult{
			Addr:    startPC,
			Bytes:   append([]byte(nil), d.Data[startPos:d.Pos]...),
			Text:    text,
			IsValid: true,
		},
		Flow:      d.lastFlow,
		Target:    d.lastTarget,
		HasTarget: d.hasTarget,
		Refs:      d.literalRefs(startPC),
		Mnemonic:  mn,
		Indirect:  d.indirect,
	}
}

// ---------------------------------------------------------------------------
// Effective-address classes
// ---------------------------------------------------------------------------

const (
	eaDn = 1 << iota
	eaAn
	eaInd
	eaPostInc
	eaPreDec
	eaDisp
	eaIdx
	eaAbsW
	eaAbsL
	eaPCDisp
	eaPCIdx
	eaImm
)

const (
	eaAll       = eaDn | eaAn | eaInd | eaPostInc | eaPreDec | eaDisp | eaIdx | eaAbsW | eaAbsL | eaPCDisp | eaPCIdx | eaImm
	eaData      = eaAll &^ eaAn
	eaMemory    = eaData &^ eaDn
	eaControl   = eaInd | eaDisp | eaIdx | eaAbsW | eaAbsL | eaPCDisp | eaPCIdx
	eaAlterable = eaAll &^ (eaPCDisp | eaPCIdx | eaImm)
	eaDataAlt   = eaData & eaAlterable
	eaMemAlt    = eaMemory & eaAlterable
	eaCtrlAlt   = eaControl & eaAlterable
)

// eaClass returns the class bit of a mode/register pair (0 if reserved).
func eaClass(mode, reg uint16) int {
	switch mode {
	case 0:
		return eaDn
	case 1:
		return eaAn
	case 2:
		return eaInd
	case 3:
		return eaPostInc
	case 4:
		return eaPreDec
	case 5:
		return eaDisp
	case 6:
		return eaIdx
	case 7:
		switch reg {
		case 0:
			return eaAbsW
		case 1:
			return eaAbsL
		case 2:
			return eaPCDisp
		case 3:
			return eaPCIdx
		case 4:
			return eaImm
		}
	}
	return 0
}

// ---------------------------------------------------------------------------
// Low-level readers
// ---------------------------------------------------------------------------

func (d *Disassembler) word() uint16 {
	if d.Pos+2 > len(d.Data) {
		d.bad = true
		d.Pos = len(d.Data)
		return 0
	}
	v := types.ReadBEU16(d.Data, d.Pos)
	d.Pos += 2
	return v
}

func (d *Disassembler) long() uint32 {
	hi := uint32(d.word())
	lo := uint32(d.word())
	return hi<<16 | lo
}

func (d *Disassembler) addRef(addr uint32, kind RefKind, size int) {
	d.refs = append(d.refs, Ref{Addr: addr, Kind: kind, Size: size})
}

// ---------------------------------------------------------------------------
// Operand formatting
// ---------------------------------------------------------------------------

func hexN(v uint32, size int) string {
	switch size {
	case 1:
		return fmt.Sprintf("$%02X", v&0xFF)
	case 2:
		return fmt.Sprintf("$%04X", v&0xFFFF)
	}
	return fmt.Sprintf("$%08X", v)
}

func signedHex(v int32) string {
	if v < 0 {
		return fmt.Sprintf("-$%X", -int64(v))
	}
	return fmt.Sprintf("$%X", v)
}

// addrOperand returns a label for addr if one is known, otherwise a hex
// address literal.
func (d *Disassembler) addrOperand(addr uint32) string {
	if name, ok := d.lookup(addr); ok {
		return name
	}
	return fmt.Sprintf("$%06X", addr)
}

func (d *Disassembler) lookup(addr uint32) (string, bool) {
	if d.Literal[d.insnPC] {
		return "", false
	}
	if name, ok := d.Labels[addr]; ok {
		return name, true
	}
	if len(d.Instances) > 0 {
		if name, ok := types.ResolveInstance(d.Instances, addr); ok {
			return name, true
		}
	}
	return "", false
}

// sizeTag returns the ".b"/".w"/".l" suffix char for a size code (00/01/10).
func sizeTag(sz uint16) (string, int) {
	switch sz {
	case 0:
		return "b", 1
	case 1:
		return "w", 2
	case 2:
		return "l", 4
	}
	return "", 0
}

// ea decodes an effective address. size is the operand size in bytes (used
// for immediates); allowed is the set of legal EA classes.
func (d *Disassembler) ea(mode, reg uint16, size int, allowed int) string {
	cls := eaClass(mode, reg)
	if cls == 0 || cls&allowed == 0 {
		d.bad = true
		return ""
	}
	switch cls {
	case eaDn:
		return fmt.Sprintf("d%d", reg)
	case eaAn:
		return fmt.Sprintf("a%d", reg)
	case eaInd:
		return fmt.Sprintf("(a%d)", reg)
	case eaPostInc:
		return fmt.Sprintf("(a%d)+", reg)
	case eaPreDec:
		return fmt.Sprintf("-(a%d)", reg)
	case eaDisp:
		disp := int16(d.word())
		if base, ok := d.BaseRegs[reg]; ok {
			addr := base + uint32(int32(disp))
			d.addRef(addr, RefData, size)
			if name, ok := d.lookup(addr); ok {
				return fmt.Sprintf("(%s-$%X)(a%d)", name, base, reg)
			}
		}
		if fields, ok := d.StructRegs[reg]; ok {
			if name, ok := fields[int32(disp)]; ok {
				return fmt.Sprintf("%s(a%d)", name, reg)
			}
		}
		return fmt.Sprintf("%s(a%d)", signedHex(int32(disp)), reg)
	case eaIdx:
		ext := d.word()
		idx, ok := briefIndex(ext)
		if !ok {
			d.noncanon = true // bits 10-8 are ignored by the 68000
		}
		disp := int8(ext & 0xFF)
		return fmt.Sprintf("%s(a%d,%s)", signedHex(int32(disp)), reg, idx)
	case eaAbsW:
		addr := uint32(int32(int16(d.word())))
		d.addRef(addr, RefData, size)
		if name, ok := d.lookup(addr); ok {
			return fmt.Sprintf("(%s).w", name)
		}
		if addr&0x80000000 != 0 {
			// RAM symbols are often defined with 24-bit addresses.
			if name, ok := d.lookup(addr & 0x00FFFFFF); ok {
				return fmt.Sprintf("((%s)|$FFFF0000).w", name)
			}
			return fmt.Sprintf("($%08X).w", addr)
		}
		return fmt.Sprintf("($%06X).w", addr)
	case eaAbsL:
		addr := d.long()
		d.addRef(addr, RefData, size)
		if name, ok := d.lookup(addr); ok {
			return fmt.Sprintf("(%s).l", name)
		}
		if addr >= 0x00FF8000 && addr <= 0x00FFFFFF {
			if name, ok := d.lookup(addr | 0xFF000000); ok {
				return fmt.Sprintf("((%s)&$FFFFFF).l", name)
			}
		}
		if addr > 0x00FFFFFF {
			return fmt.Sprintf("($%08X).l", addr)
		}
		return fmt.Sprintf("($%06X).l", addr)
	case eaPCDisp:
		pc := d.PC()
		disp := int16(d.word())
		target := pc + uint32(int32(disp))
		d.addRef(target, RefData, size)
		return fmt.Sprintf("%s(pc)", d.addrOperand(target))
	case eaPCIdx:
		pc := d.PC()
		ext := d.word()
		idx, ok := briefIndex(ext)
		if !ok {
			d.noncanon = true
		}
		target := pc + uint32(int32(int8(ext&0xFF)))
		d.addRef(target, RefIndexed, size)
		return fmt.Sprintf("%s(pc,%s)", d.addrOperand(target), idx)
	case eaImm:
		switch size {
		case 1:
			v := d.word()
			if v&0xFF00 != 0 {
				d.noncanon = true // the 68000 ignores the high byte
			}
			return "#" + hexN(uint32(v), 1)
		case 2:
			return "#" + hexN(uint32(d.word()), 2)
		case 4:
			v := d.long()
			d.addRef(v, RefImm, 4)
			imm := d.ImmLabels
			if imm == nil {
				imm = d.Labels
			}
			if name, ok := imm[v]; ok && v >= 0x200 {
				d.immSym, d.immVal = "#"+name, v
				return "#" + name
			}
			return "#" + hexN(v, 4)
		}
		d.bad = true
		return ""
	}
	d.bad = true
	return ""
}

// eaRaw decodes the EA in the low 6 bits of op.
func (d *Disassembler) eaLow(op uint16, size int, allowed int) string {
	return d.ea((op>>3)&7, op&7, size, allowed)
}

// briefIndex decodes the index register part of a 68000 brief extension word.
// Bits 10-8 must be zero for the encoding to be canonical.
func briefIndex(ext uint16) (string, bool) {
	ok := ext&0x0700 == 0
	kind := "d"
	if ext&0x8000 != 0 {
		kind = "a"
	}
	sz := "w"
	if ext&0x0800 != 0 {
		sz = "l"
	}
	return fmt.Sprintf("%s%d.%s", kind, (ext>>12)&7, sz), ok
}

// ---------------------------------------------------------------------------
// Decoder
// ---------------------------------------------------------------------------

func (d *Disassembler) decode() string {
	op := d.word()
	switch op >> 12 {
	case 0x0:
		return d.decodeGroup0(op)
	case 0x1, 0x2, 0x3:
		return d.decodeMOVE(op)
	case 0x4:
		return d.decodeGroup4(op)
	case 0x5:
		return d.decodeGroup5(op)
	case 0x6:
		return d.decodeBranch(op)
	case 0x7:
		return d.decodeMOVEQ(op)
	case 0x8:
		return d.decodeGroup8(op)
	case 0x9:
		return d.decodeAddSub(op, "sub")
	case 0xB:
		return d.decodeGroupB(op)
	case 0xC:
		return d.decodeGroupC(op)
	case 0xD:
		return d.decodeAddSub(op, "add")
	case 0xE:
		return d.decodeShift(op)
	}
	// Line-A / Line-F emulator traps.
	d.bad = true
	return ""
}

// ---------------------------------------------------------------------------
// Group 0 – immediate ops, bit ops, MOVEP
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeGroup0(op uint16) string {
	if op&0x0100 != 0 {
		if (op>>3)&7 == 1 {
			return d.decodeMOVEP(op)
		}
		return d.decodeBitDynamic(op)
	}
	sub := (op >> 9) & 7
	if sub == 4 {
		return d.decodeBitStatic(op)
	}

	names := [8]string{"ori", "andi", "subi", "addi", "", "eori", "cmpi", ""}
	name := names[sub]
	if name == "" {
		d.bad = true // MOVES (68010) / reserved
		return ""
	}

	// CCR / SR forms.
	if op&0x3F == 0x3C && (sub == 0 || sub == 1 || sub == 5) {
		switch (op >> 6) & 3 {
		case 0:
			v := d.word()
			if v&0xFF00 != 0 {
				d.noncanon = true
			}
			return fmt.Sprintf("\t%s.b\t#%s,ccr", name, hexN(uint32(v), 1))
		case 1:
			v := d.word()
			return fmt.Sprintf("\t%s.w\t#%s,sr", name, hexN(uint32(v), 2))
		}
		d.bad = true
		return ""
	}

	sz, n := sizeTag((op >> 6) & 3)
	if n == 0 {
		d.bad = true
		return ""
	}
	// Immediate comes first, then the destination EA extension words.
	imm := d.ea(7, 4, n, eaImm)
	allowed := eaDataAlt
	ea := d.eaLow(op, n, allowed)
	return fmt.Sprintf("\t%s.%s\t%s,%s", name, sz, imm, ea)
}

var bitNames = [4]string{"btst", "bchg", "bclr", "bset"}

func (d *Disassembler) decodeBitStatic(op uint16) string {
	kind := (op >> 6) & 3
	num := d.word()
	if num&0xFF00 != 0 {
		d.noncanon = true
		num &= 0xFF
	}
	allowed := eaDataAlt
	if kind == 0 {
		allowed = eaData &^ eaImm
	}
	ea := d.eaLow(op, 1, allowed)
	return fmt.Sprintf("\t%s\t#%d,%s", bitNames[kind], num, ea)
}

func (d *Disassembler) decodeBitDynamic(op uint16) string {
	kind := (op >> 6) & 3
	allowed := eaDataAlt
	if kind == 0 {
		allowed = eaData
	}
	ea := d.eaLow(op, 1, allowed)
	return fmt.Sprintf("\t%s\td%d,%s", bitNames[kind], (op>>9)&7, ea)
}

func (d *Disassembler) decodeMOVEP(op uint16) string {
	dn := (op >> 9) & 7
	an := op & 7
	disp := int16(d.word())
	mem := fmt.Sprintf("%s(a%d)", signedHex(int32(disp)), an)
	sz := "w"
	if op&0x0040 != 0 {
		sz = "l"
	}
	if op&0x0080 != 0 {
		return fmt.Sprintf("\tmovep.%s\td%d,%s", sz, dn, mem)
	}
	return fmt.Sprintf("\tmovep.%s\t%s,d%d", sz, mem, dn)
}

// ---------------------------------------------------------------------------
// MOVE / MOVEA
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeMOVE(op uint16) string {
	var sz string
	var n int
	switch op >> 12 {
	case 1:
		sz, n = "b", 1
	case 3:
		sz, n = "w", 2
	case 2:
		sz, n = "l", 4
	}
	srcAllowed := eaAll
	if n == 1 {
		srcAllowed = eaAll &^ eaAn
	}
	src := d.eaLow(op, n, srcAllowed)
	dstMode := (op >> 6) & 7
	dstReg := (op >> 9) & 7
	if dstMode == 1 {
		if n == 1 {
			d.bad = true
			return ""
		}
		return fmt.Sprintf("\tmovea.%s\t%s,a%d", sz, src, dstReg)
	}
	dst := d.ea(dstMode, dstReg, n, eaDataAlt)
	return fmt.Sprintf("\tmove.%s\t%s,%s", sz, src, dst)
}

// ---------------------------------------------------------------------------
// Group 4 – miscellaneous
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeGroup4(op uint16) string {
	switch op {
	case 0x4AFC:
		d.lastFlow = FlowHalt
		return "\tillegal"
	case 0x4E70:
		return "\treset"
	case 0x4E71:
		return "\tnop"
	case 0x4E72:
		d.lastFlow = FlowHalt
		return fmt.Sprintf("\tstop\t#%s", hexN(uint32(d.word()), 2))
	case 0x4E73:
		d.lastFlow = FlowReturn
		return "\trte"
	case 0x4E75:
		d.lastFlow = FlowReturn
		return "\trts"
	case 0x4E76:
		return "\ttrapv"
	case 0x4E77:
		d.lastFlow = FlowReturn
		return "\trtr"
	}

	switch op & 0xFFF0 {
	case 0x4E40:
		return fmt.Sprintf("\ttrap\t#%d", op&0xF)
	case 0x4E50:
		if op&8 == 0 {
			disp := int16(d.word())
			return fmt.Sprintf("\tlink\ta%d,#%d", op&7, disp)
		}
		return fmt.Sprintf("\tunlk\ta%d", op&7)
	case 0x4E60:
		if op&8 == 0 {
			return fmt.Sprintf("\tmove.l\ta%d,usp", op&7)
		}
		return fmt.Sprintf("\tmove.l\tusp,a%d", op&7)
	}

	switch op & 0xFFC0 {
	case 0x4E80: // JSR
		d.lastFlow = FlowCall
		return "\tjsr\t" + d.controlTarget(op)
	case 0x4EC0: // JMP
		d.lastFlow = FlowJump
		return "\tjmp\t" + d.controlTarget(op)
	case 0x40C0:
		return "\tmove.w\tsr," + d.eaLow(op, 2, eaDataAlt)
	case 0x44C0:
		return "\tmove.w\t" + d.eaLow(op, 2, eaData) + ",ccr"
	case 0x46C0:
		return "\tmove.w\t" + d.eaLow(op, 2, eaData) + ",sr"
	case 0x4800:
		return "\tnbcd\t" + d.eaLow(op, 1, eaDataAlt)
	case 0x4840:
		if (op>>3)&7 == 0 {
			return fmt.Sprintf("\tswap\td%d", op&7)
		}
		ea := d.eaLow(op, 4, eaControl)
		d.markEffAddr()
		return "\tpea\t" + ea
	case 0x4880, 0x48C0:
		if (op>>3)&7 == 0 {
			if op&0x40 != 0 {
				return fmt.Sprintf("\text.l\td%d", op&7)
			}
			return fmt.Sprintf("\text.w\td%d", op&7)
		}
		return d.decodeMOVEM(op)
	case 0x4C80, 0x4CC0:
		return d.decodeMOVEM(op)
	case 0x4AC0:
		return "\ttas\t" + d.eaLow(op, 1, eaDataAlt)
	}

	if op&0xF1C0 == 0x41C0 { // LEA
		ea := d.eaLow(op, 4, eaControl)
		d.markEffAddr()
		return fmt.Sprintf("\tlea\t%s,a%d", ea, (op>>9)&7)
	}
	if op&0xF1C0 == 0x4180 { // CHK.W
		ea := d.eaLow(op, 2, eaData)
		return fmt.Sprintf("\tchk.w\t%s,d%d", ea, (op>>9)&7)
	}

	var name string
	switch op & 0xFF00 {
	case 0x4000:
		name = "negx"
	case 0x4200:
		name = "clr"
	case 0x4400:
		name = "neg"
	case 0x4600:
		name = "not"
	case 0x4A00:
		name = "tst"
	default:
		d.bad = true
		return ""
	}
	sz, n := sizeTag((op >> 6) & 3)
	if n == 0 {
		d.bad = true
		return ""
	}
	return fmt.Sprintf("\t%s.%s\t%s", name, sz, d.eaLow(op, n, eaDataAlt))
}

// markEffAddr re-tags the last data reference as an effective-address load
// (lea / pea), which the tracer treats as a strong pointer.
func (d *Disassembler) markEffAddr() {
	if n := len(d.refs); n > 0 && d.refs[n-1].Kind == RefData {
		d.refs[n-1].Kind = RefEffAddr
	}
}

// controlTarget decodes the control EA of jsr/jmp and records the target.
func (d *Disassembler) controlTarget(op uint16) string {
	mode := (op >> 3) & 7
	reg := op & 7
	cls := eaClass(mode, reg)
	if cls&eaControl == 0 {
		d.bad = true
		return ""
	}
	switch cls {
	case eaAbsW:
		addr := uint32(int32(int16(d.word())))
		d.setTarget(addr)
		if name, ok := d.lookup(addr); ok {
			return fmt.Sprintf("(%s).w", name)
		}
		if addr&0x80000000 != 0 {
			return fmt.Sprintf("($%08X).w", addr)
		}
		return fmt.Sprintf("($%06X).w", addr)
	case eaAbsL:
		addr := d.long()
		d.setTarget(addr)
		if name, ok := d.lookup(addr); ok {
			return fmt.Sprintf("(%s).l", name)
		}
		return fmt.Sprintf("($%06X).l", addr)
	case eaPCDisp:
		pc := d.PC()
		disp := int16(d.word())
		target := pc + uint32(int32(disp))
		d.setTarget(target)
		return fmt.Sprintf("%s(pc)", d.addrOperand(target))
	}
	d.indirect = true
	return d.ea(mode, reg, 4, eaControl)
}

func (d *Disassembler) setTarget(addr uint32) {
	d.lastTarget = addr
	d.hasTarget = true
	d.addRef(addr, RefCode, 0)
}

func (d *Disassembler) decodeMOVEM(op uint16) string {
	toMem := op&0x0400 == 0
	sz, n := "w", 2
	if op&0x0040 != 0 {
		sz, n = "l", 4
	}
	mask := d.word()
	if mask == 0 {
		d.bad = true // an empty register list cannot be expressed
		return ""
	}
	mode := (op >> 3) & 7
	if toMem {
		ea := d.eaLow(op, n, eaCtrlAlt|eaPreDec)
		return fmt.Sprintf("\tmovem.%s\t%s,%s", sz, regList(mask, mode == 4), ea)
	}
	ea := d.eaLow(op, n, eaControl|eaPostInc)
	return fmt.Sprintf("\tmovem.%s\t%s,%s", sz, ea, regList(mask, false))
}

// regList formats a MOVEM register mask as asm68k ranges ("d0-d3/a0/a6").
func regList(mask uint16, predecrement bool) string {
	var bits [16]bool // index 0..7 = d0..d7, 8..15 = a0..a7
	for i := 0; i < 16; i++ {
		if predecrement {
			bits[i] = mask&(1<<uint(15-i)) != 0
		} else {
			bits[i] = mask&(1<<uint(i)) != 0
		}
	}
	name := func(i int) string {
		if i < 8 {
			return fmt.Sprintf("d%d", i)
		}
		return fmt.Sprintf("a%d", i-8)
	}
	var parts []string
	for bank := 0; bank < 16; bank += 8 {
		for i := bank; i < bank+8; i++ {
			if !bits[i] {
				continue
			}
			j := i
			for j+1 < bank+8 && bits[j+1] {
				j++
			}
			if j == i {
				parts = append(parts, name(i))
			} else {
				parts = append(parts, name(i)+"-"+name(j))
			}
			i = j
		}
	}
	return strings.Join(parts, "/")
}

// ---------------------------------------------------------------------------
// Group 5 – ADDQ / SUBQ / Scc / DBcc
// ---------------------------------------------------------------------------

var condNames = [16]string{"t", "f", "hi", "ls", "cc", "cs", "ne", "eq", "vc", "vs", "pl", "mi", "ge", "lt", "gt", "le"}

func (d *Disassembler) decodeGroup5(op uint16) string {
	cond := (op >> 8) & 0xF
	if (op>>6)&3 == 3 {
		if (op>>3)&7 == 1 {
			pc := d.PC()
			disp := int16(d.word())
			target := pc + uint32(int32(disp))
			d.lastFlow = FlowBranch
			d.setTarget(target)
			return fmt.Sprintf("\tdb%s\td%d,%s", condNames[cond], op&7, d.addrOperand(target))
		}
		return fmt.Sprintf("\ts%s\t%s", condNames[cond], d.eaLow(op, 1, eaDataAlt))
	}
	sz, n := sizeTag((op >> 6) & 3)
	imm := (op >> 9) & 7
	if imm == 0 {
		imm = 8
	}
	allowed := eaAlterable
	if n == 1 {
		allowed = eaDataAlt
	}
	ea := d.eaLow(op, n, allowed)
	if op&0x0100 != 0 {
		return fmt.Sprintf("\tsubq.%s\t#%d,%s", sz, imm, ea)
	}
	return fmt.Sprintf("\taddq.%s\t#%d,%s", sz, imm, ea)
}

// ---------------------------------------------------------------------------
// Branches
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeBranch(op uint16) string {
	cond := (op >> 8) & 0xF
	disp8 := int8(op & 0xFF)
	pc := d.PC()
	var target uint32
	var size string
	switch disp8 {
	case 0:
		disp16 := int16(d.word())
		target = pc + uint32(int32(disp16))
		size = "w"
	case -1:
		// $FF selects a 32-bit displacement on 68020+; on the 68000 it is a
		// branch to an odd address. Neither can be re-assembled faithfully.
		d.bad = true
		return ""
	default:
		target = pc + uint32(int32(disp8))
		size = "s"
	}
	d.setTarget(target)
	label := d.addrOperand(target)
	switch cond {
	case 0:
		d.lastFlow = FlowJump
		return fmt.Sprintf("\tbra.%s\t%s", size, label)
	case 1:
		d.lastFlow = FlowCall
		return fmt.Sprintf("\tbsr.%s\t%s", size, label)
	}
	d.lastFlow = FlowBranch
	return fmt.Sprintf("\tb%s.%s\t%s", condNames[cond], size, label)
}

// ---------------------------------------------------------------------------
// MOVEQ
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeMOVEQ(op uint16) string {
	if op&0x0100 != 0 {
		d.bad = true
		return ""
	}
	return fmt.Sprintf("\tmoveq\t#%d,d%d", int8(op&0xFF), (op>>9)&7)
}

// ---------------------------------------------------------------------------
// Group 8 – OR / DIVU / DIVS / SBCD
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeGroup8(op uint16) string {
	dn := (op >> 9) & 7
	opmode := (op >> 6) & 7
	mode := (op >> 3) & 7
	switch opmode {
	case 3:
		return fmt.Sprintf("\tdivu.w\t%s,d%d", d.eaLow(op, 2, eaData), dn)
	case 7:
		return fmt.Sprintf("\tdivs.w\t%s,d%d", d.eaLow(op, 2, eaData), dn)
	case 4:
		if mode == 0 {
			return fmt.Sprintf("\tsbcd\td%d,d%d", op&7, dn)
		}
		if mode == 1 {
			return fmt.Sprintf("\tsbcd\t-(a%d),-(a%d)", op&7, dn)
		}
	}
	return d.logicOp(op, "or")
}

// logicOp decodes AND/OR <ea>,Dn and Dn,<ea>.
func (d *Disassembler) logicOp(op uint16, name string) string {
	dn := (op >> 9) & 7
	opmode := (op >> 6) & 7
	sz, n := sizeTag(opmode & 3)
	if n == 0 {
		d.bad = true
		return ""
	}
	if opmode&4 != 0 {
		ea := d.eaLow(op, n, eaMemAlt)
		return fmt.Sprintf("\t%s.%s\td%d,%s", name, sz, dn, ea)
	}
	ea := d.eaLow(op, n, eaData)
	if (op>>3)&7 == 7 && op&7 == 4 {
		// OR/AND #imm,Dn: assemblers always emit ORI/ANDI instead, so use
		// the macro that reproduces the <ea>,Dn encoding.
		name += "_ea"
	}
	return fmt.Sprintf("\t%s.%s\t%s,d%d", name, sz, ea, dn)
}

// ---------------------------------------------------------------------------
// ADD / SUB family
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeAddSub(op uint16, name string) string {
	dn := (op >> 9) & 7
	opmode := (op >> 6) & 7
	mode := (op >> 3) & 7
	switch opmode {
	case 3:
		return fmt.Sprintf("\t%sa.w\t%s,a%d", name, d.eaLow(op, 2, eaAll), dn)
	case 7:
		return fmt.Sprintf("\t%sa.l\t%s,a%d", name, d.eaLow(op, 4, eaAll), dn)
	}
	sz, n := sizeTag(opmode & 3)
	if opmode&4 != 0 {
		if mode == 0 {
			return fmt.Sprintf("\t%sx.%s\td%d,d%d", name, sz, op&7, dn)
		}
		if mode == 1 {
			return fmt.Sprintf("\t%sx.%s\t-(a%d),-(a%d)", name, sz, op&7, dn)
		}
		ea := d.eaLow(op, n, eaMemAlt)
		return fmt.Sprintf("\t%s.%s\td%d,%s", name, sz, dn, ea)
	}
	allowed := eaAll
	if n == 1 {
		allowed = eaAll &^ eaAn
	}
	ea := d.eaLow(op, n, allowed)
	if mode == 7 && op&7 == 4 {
		// ADD/SUB #imm,Dn: assemblers always emit ADDI/SUBI instead.
		name += "_ea"
	}
	return fmt.Sprintf("\t%s.%s\t%s,d%d", name, sz, ea, dn)
}

// ---------------------------------------------------------------------------
// Group B – CMP / CMPA / CMPM / EOR
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeGroupB(op uint16) string {
	dn := (op >> 9) & 7
	opmode := (op >> 6) & 7
	mode := (op >> 3) & 7
	switch opmode {
	case 3:
		return fmt.Sprintf("\tcmpa.w\t%s,a%d", d.eaLow(op, 2, eaAll), dn)
	case 7:
		return fmt.Sprintf("\tcmpa.l\t%s,a%d", d.eaLow(op, 4, eaAll), dn)
	}
	sz, n := sizeTag(opmode & 3)
	if opmode&4 != 0 {
		if mode == 1 {
			return fmt.Sprintf("\tcmpm.%s\t(a%d)+,(a%d)+", sz, op&7, dn)
		}
		ea := d.eaLow(op, n, eaDataAlt)
		return fmt.Sprintf("\teor.%s\td%d,%s", sz, dn, ea)
	}
	allowed := eaAll
	if n == 1 {
		allowed = eaAll &^ eaAn
	}
	ea := d.eaLow(op, n, allowed)
	if mode == 7 && op&7 == 4 {
		// CMP #imm,Dn: assemblers always emit CMPI instead.
		return fmt.Sprintf("\tcmp_ea.%s\t%s,d%d", sz, ea, dn)
	}
	return fmt.Sprintf("\tcmp.%s\t%s,d%d", sz, ea, dn)
}

// ---------------------------------------------------------------------------
// Group C – AND / MULU / MULS / ABCD / EXG
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeGroupC(op uint16) string {
	dn := (op >> 9) & 7
	opmode := (op >> 6) & 7
	mode := (op >> 3) & 7
	switch opmode {
	case 3:
		return fmt.Sprintf("\tmulu.w\t%s,d%d", d.eaLow(op, 2, eaData), dn)
	case 7:
		return fmt.Sprintf("\tmuls.w\t%s,d%d", d.eaLow(op, 2, eaData), dn)
	case 4:
		if mode == 0 {
			return fmt.Sprintf("\tabcd\td%d,d%d", op&7, dn)
		}
		if mode == 1 {
			return fmt.Sprintf("\tabcd\t-(a%d),-(a%d)", op&7, dn)
		}
	case 5:
		if mode == 0 {
			return fmt.Sprintf("\texg\td%d,d%d", dn, op&7)
		}
		if mode == 1 {
			return fmt.Sprintf("\texg\ta%d,a%d", dn, op&7)
		}
	case 6:
		if mode == 1 {
			return fmt.Sprintf("\texg\td%d,a%d", dn, op&7)
		}
	}
	return d.logicOp(op, "and")
}

// ---------------------------------------------------------------------------
// Shifts / Rotates
// ---------------------------------------------------------------------------

var shiftNames = [4]string{"as", "ls", "rox", "ro"}

func (d *Disassembler) decodeShift(op uint16) string {
	dir := "r"
	if op&0x0100 != 0 {
		dir = "l"
	}
	if (op>>6)&3 == 3 {
		if op&0x0800 != 0 {
			d.bad = true // 68020 bit-field instructions
			return ""
		}
		kind := (op >> 9) & 3
		ea := d.eaLow(op, 2, eaMemAlt)
		return fmt.Sprintf("\t%s%s.w\t%s", shiftNames[kind], dir, ea)
	}
	sz, _ := sizeTag((op >> 6) & 3)
	kind := (op >> 3) & 3
	cnt := (op >> 9) & 7
	var count string
	if op&0x0020 != 0 {
		count = fmt.Sprintf("d%d", cnt)
	} else {
		if cnt == 0 {
			cnt = 8
		}
		count = fmt.Sprintf("#%d", cnt)
	}
	return fmt.Sprintf("\t%s%s.%s\t%s,d%d", shiftNames[kind], dir, sz, count, op&7)
}

// pointerImmContext reports whether a 32-bit immediate below $10000 is
// plausibly a code/data pointer: stored by move/movea (not into a data
// register) or compared with cmpi.
func pointerImmContext(mn, text string) bool {
	switch mn {
	case "move", "movea":
		return !dataRegDest(text)
	case "cmpi":
		return true
	}
	return false
}

// dataRegDest reports whether the last operand of text is a data register.
func dataRegDest(text string) bool {
	i := strings.LastIndexByte(text, ',')
	if i < 0 {
		return false
	}
	op := strings.TrimSpace(text[i+1:])
	return len(op) == 2 && op[0] == 'd' && op[1] >= '0' && op[1] <= '7'
}

// ---------------------------------------------------------------------------
// Assembler support macros
// ---------------------------------------------------------------------------

// Macros must be included before any disassembled code. They reproduce
// encodings that asm68k-compatible assemblers would otherwise "optimise":
// ADD/SUB/AND/OR/CMP #imm,Dn are always rewritten to ADDI/SUBI/ANDI/ORI/CMPI,
// but some games were built with assemblers that kept the <ea>,Dn form.
const Macros = `; ---------------------------------------------------------------------------
; <op>_ea.<size> #imm,Dn — emit ADD/SUB/AND/OR/CMP with an immediate source
; operand using the "<ea>,Dn" encoding (opcode | Dn<<9 | size<<6 | $3C).
; asm68k-style assemblers silently rewrite these to ADDI/SUBI/ANDI/ORI/CMPI,
; which would change the ROM bytes.
; ---------------------------------------------------------------------------
_ea_imm	macro	base,size,imm,dreg
_eaR	substr	2,2,"\dreg"
_eaI	substr	2,,"\imm"
	if strcmp("\size","b")
	dc.w	\base|(\_eaR<<9)|$003C,(\_eaI)&$FF
	elseif strcmp("\size","w")
	dc.w	\base|(\_eaR<<9)|$007C,\_eaI
	else
	dc.w	\base|(\_eaR<<9)|$00BC
	dc.l	\_eaI
	endif
	endm

or_ea	macro	imm,dreg
	_ea_imm	$8000,\0,\imm,\dreg
	endm
sub_ea	macro	imm,dreg
	_ea_imm	$9000,\0,\imm,\dreg
	endm
cmp_ea	macro	imm,dreg
	_ea_imm	$B000,\0,\imm,\dreg
	endm
and_ea	macro	imm,dreg
	_ea_imm	$C000,\0,\imm,\dreg
	endm
add_ea	macro	imm,dreg
	_ea_imm	$D000,\0,\imm,\dreg
	endm
`

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// applyImmStrLiterals rewrites known immediate values to string literal form
// for specific destination registers where the value is a 4-byte ASCII tag.
func applyImmStrLiterals(text string) string {
	// TMSS unlock: move.l #'SEGA',TMSS_REG
	return strings.ReplaceAll(text, "#$53454741,(TMSS_REG).l", "#'SEGA',(TMSS_REG).l")
}

// DisassembleBlock disassembles data[start:end] treating it as M68K code.
// Returns all Result entries with labels resolved, including automatic
// jump-table detection (dc.l entries replacing garbled post-terminator bytes).
func DisassembleBlock(data []byte, baseAddr, start, end uint32, labels types.LabelMap) []Result {
	return DisassembleBlockOpts(data, baseAddr, start, end, labels, true)
}

// DisassembleBlockOpts is DisassembleBlock with the linear-sweep heuristics
// (jump-table and dead-data detection) optionally disabled. Disable them for
// segments whose boundaries come from a control-flow trace: those segments are
// known to contain only code, and heuristics could hide real instructions.
func DisassembleBlockOpts(data []byte, baseAddr, start, end uint32, labels types.LabelMap, heuristics bool) []Result {
	segData := data[start:end]
	segBase := baseAddr + start
	d := New(segData, segBase, labels)
	var results []Result
	for d.Remaining() >= 2 {
		results = append(results, d.Next())
	}
	if d.Remaining() == 1 {
		results = append(results, Result{BaseResult: disasm.BaseResult{
			Addr:  d.PC(),
			Bytes: []byte{segData[d.Pos]},
			Text:  fmt.Sprintf("\tdc.b\t$%02X", segData[d.Pos]),
		}})
	}
	if heuristics {
		results = detectJumpTables(results, segData, segBase, d.Labels)
		results = convertDeadDataToDCW(results, segData, segBase)
	}
	return results
}

// BlockOptions configures DisassembleRange.
type BlockOptions struct {
	Labels     types.LabelMap    // labels for operands (hardware ports are added)
	ImmLabels  types.LabelMap    // labels allowed for 32-bit immediates (nil = Labels)
	BaseRegs   map[uint16]uint32 // constant address registers
	StructRegs map[uint16]map[int32]string
	Instances  []types.InstanceInfo
	Heuristics bool // enable linear-sweep jump table / dead data heuristics
	Literal    map[uint32]bool
}

// DisassembleRange disassembles rom[start:end] (rom mapped at address 0).
func DisassembleRange(rom []byte, start, end uint32, o BlockOptions) []Result {
	d := New(rom[:end], 0, o.Labels)
	d.ImmLabels = o.ImmLabels
	d.BaseRegs = o.BaseRegs
	d.StructRegs = o.StructRegs
	d.Instances = o.Instances
	d.Literal = o.Literal
	d.Pos = int(start)
	var results []Result
	for d.Remaining() >= 2 {
		results = append(results, d.Next())
	}
	if d.Remaining() == 1 {
		results = append(results, Result{BaseResult: disasm.BaseResult{
			Addr:  d.PC(),
			Bytes: []byte{rom[d.Pos]},
			Text:  fmt.Sprintf("\tdc.b\t$%02X", rom[d.Pos]),
		}})
	}
	if o.Heuristics && len(results) > 0 {
		seg := rom[start:end]
		results = detectJumpTables(results, seg, start, d.Labels)
		results = convertDeadDataToDCW(results, seg, start)
	}
	return results
}

// DecodeAt disassembles a single instruction at absolute address addr of rom
// (which is mapped at address 0). Used by control-flow tracers.
func DecodeAt(rom []byte, addr uint32, labels types.LabelMap) Result {
	d := New(rom, 0, labels)
	d.Pos = int(addr)
	return d.Next()
}

// ---------------------------------------------------------------------------
// Jump table detection
// ---------------------------------------------------------------------------

// detectJumpTables performs a post-disassembly pass and replaces bytes that
// immediately follow a flow terminator with dc.l entries when those bytes look
// like a table of valid Genesis/Mega Drive code pointers.
//
// Trigger: any result with FlowJump or FlowHalt.
// Entry test: 32-bit value where the high byte is 0x00 (ROM range), the
// address is word-aligned, and >= 0x000200 (past the vector table).
// Minimum 2 consecutive valid entries required to trigger.
//
// After a detected table, disassembly continues as normal code.
func detectJumpTables(results []Result, data []byte, segBase uint32, labels types.LabelMap) []Result {
	if len(results) == 0 {
		return results
	}

	type insertion struct {
		afterIdx int
		entries  []Result
	}

	skip := make([]bool, len(results))
	var inserts []insertion

	for i, res := range results {
		if res.Flow != FlowJump && res.Flow != FlowHalt {
			continue
		}

		tableBase := res.Addr + uint32(len(res.Bytes))
		off := int(tableBase - segBase)

		var addrs []uint32
		for off+4 <= len(data) {
			v := uint32(data[off])<<24 | uint32(data[off+1])<<16 |
				uint32(data[off+2])<<8 | uint32(data[off+3])
			if !isJumpTableEntry(v) {
				break
			}
			addrs = append(addrs, v)
			off += 4
		}
		if len(addrs) < 2 {
			continue
		}

		tableEnd := tableBase + uint32(len(addrs)*4)

		// The table must end on an instruction boundary, otherwise the
		// following instruction stream would be desynchronised.
		aligned := false
		for j := i + 1; j < len(results); j++ {
			if results[j].Addr == tableEnd {
				aligned = true
				break
			}
			if results[j].Addr > tableEnd {
				break
			}
		}
		if !aligned && int(tableEnd-segBase) != len(data) {
			continue
		}

		var dcls []Result
		for k, addr := range addrs {
			entryAddr := tableBase + uint32(k*4)
			rawOff := int(entryAddr - segBase)
			dcls = append(dcls, Result{
				BaseResult: disasm.BaseResult{
					Addr:    entryAddr,
					Bytes:   data[rawOff : rawOff+4],
					Text:    fmt.Sprintf("\tdc.l\t%s", resolveLabel(addr, labels)),
					IsValid: true,
				},
				Flow: FlowNone,
				Refs: []Ref{{Addr: addr, Kind: RefImm, Size: 4}},
			})
		}

		for j := i + 1; j < len(results); j++ {
			if results[j].Addr >= tableEnd {
				break
			}
			skip[j] = true
		}

		inserts = append(inserts, insertion{afterIdx: i, entries: dcls})
	}

	if len(inserts) == 0 {
		return results
	}

	insertAfter := make(map[int][]Result, len(inserts))
	for _, ins := range inserts {
		insertAfter[ins.afterIdx] = ins.entries
	}

	out := make([]Result, 0, len(results))
	for i, res := range results {
		if skip[i] {
			continue
		}
		out = append(out, res)
		if extra, ok := insertAfter[i]; ok {
			out = append(out, extra...)
		}
	}
	return out
}

// convertDeadDataToDCW converts unreachable instruction sequences whose opcode
// word is in the $0000–$000F range (ori.b/ori.w to any Dn) into dc.w entries.
// These opcodes virtually never appear in real M68K code and are almost always
// embedded data that follows a flow terminator.
//
// Dead mode starts after FlowReturn/FlowJump/FlowHalt and ends when either:
//   - A known intra-segment branch target is reached, or
//   - An opcode outside $0000–$000F is encountered (new function entry).
//
// Already-formatted dc.* entries from detectJumpTables are kept as-is.
func convertDeadDataToDCW(results []Result, data []byte, segBase uint32) []Result {
	if len(results) == 0 {
		return results
	}

	branchTargets := make(map[uint32]bool)
	branchTargets[results[0].Addr] = true
	for _, res := range results {
		if res.HasTarget {
			branchTargets[res.Target] = true
		}
	}

	out := make([]Result, 0, len(results))
	inDead := false

	for _, res := range results {
		addr := res.Addr

		if branchTargets[addr] {
			inDead = false
		}

		if inDead {
			if strings.HasPrefix(res.Text, "\tdc.") {
				out = append(out, res)
				continue
			}

			rawOff := int(addr - segBase)
			if rawOff+2 > len(data) {
				out = append(out, res)
				continue
			}
			opcode := uint16(data[rawOff])<<8 | uint16(data[rawOff+1])
			if opcode <= 0x000F {
				for j := 0; j+1 < len(res.Bytes); j += 2 {
					off := rawOff + j
					w := uint16(data[off])<<8 | uint16(data[off+1])
					out = append(out, Result{
						BaseResult: disasm.BaseResult{
							Addr:    addr + uint32(j),
							Bytes:   data[off : off+2],
							Text:    fmt.Sprintf("\tdc.w\t$%04X", w),
							IsValid: true,
						},
					})
				}
				continue
			}
			inDead = false
		}

		out = append(out, res)

		if res.Flow == FlowReturn || res.Flow == FlowJump || res.Flow == FlowHalt {
			inDead = true
		}
	}
	return out
}

// isJumpTableEntry returns true for 32-bit values that look like valid Genesis
// code pointers: high byte must be 0x00 (ROM 0–4 MB range), address must be
// word-aligned and above the vector table ($000200).
func isJumpTableEntry(addr uint32) bool {
	if addr>>24 != 0x00 {
		return false
	}
	lo := addr & 0x00FFFFFF
	return lo >= 0x000200 && lo <= 0x3FFFFF && lo&1 == 0
}

// resolveLabel returns the symbolic name for addr from the labels map, or a
// hex literal if addr is not a known label.
func resolveLabel(addr uint32, labels types.LabelMap) string {
	if name, ok := labels[addr]; ok {
		return name
	}
	return fmt.Sprintf("$%06X", addr&0x00FFFFFF)
}

// ---------------------------------------------------------------------------
// Genesis hardware ports
// ---------------------------------------------------------------------------

// HWPortName returns the built-in symbolic name for a Genesis hardware
// register address, or "" if the address is not a known hardware port.
func HWPortName(addr uint32) string {
	return genesisHWPorts[addr]
}

// genesisHWPorts maps Sega Genesis / Mega Drive hardware register addresses
// to their canonical symbolic names. They are pre-loaded into the disassembler
// label table so that absolute-long memory references print as symbolic names
// instead of raw hex addresses. User-provided symbols override these defaults.
var genesisHWPorts = map[uint32]string{
	// VDP
	0x00C00000: "VDP_DATA",
	0x00C00002: "VDP_DATA_W",
	0x00C00004: "VDP_CTRL",
	0x00C00006: "VDP_CTRL_W",
	0x00C00008: "VDP_HVCOUNTER",
	0x00C0001C: "VDP_DEBUG",
	// PSG
	0x00C00011: "PSG_DATA",
	// Z80 / YM2612 (as seen from the 68000 while it owns the Z80 bus)
	0x00A00000: "Z80_RAM",
	0x00A04000: "YM2612_A0",
	0x00A04001: "YM2612_D0",
	0x00A04002: "YM2612_A1",
	0x00A04003: "YM2612_D1",
	0x00A11100: "Z80_BUSREQ",
	0x00A11200: "Z80_RESET",
	// I/O
	0x00A10001: "IO_PCBVER",
	0x00A10003: "IO_DATA_1",
	0x00A10005: "IO_DATA_2",
	0x00A10008: "IO_CTRL_12_W",
	0x00A10007: "IO_DATA_EXP",
	0x00A10009: "IO_CTRL_1",
	0x00A1000B: "IO_CTRL_2",
	0x00A1000C: "IO_CTRL_EXP_W",
	0x00A1000D: "IO_CTRL_EXP",
	0x00A1000F: "IO_TXDATA_1",
	0x00A10011: "IO_RXDATA_1",
	0x00A10013: "IO_SCTRL_1",
	0x00A10015: "IO_TXDATA_2",
	0x00A10017: "IO_RXDATA_2",
	0x00A10019: "IO_SCTRL_2",
	0x00A1001B: "IO_TXDATA_EXP",
	0x00A1001D: "IO_RXDATA_EXP",
	0x00A1001F: "IO_SCTRL_EXP",
	// Memory control
	0x00A11000: "MEM_MODE",
	0x00A13000: "TIME_REG",
	0x00A14000: "TMSS_REG",
	0x00A14100: "TMSS_VDP",
}
