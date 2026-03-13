// Package m68k implements a Motorola 68000 disassembler.
// Output is compatible with Clownacy/clownassembler (asm68k clone).
// Based on: https://github.com/Clownacy/clown68000
package m68k

import (
	"fmt"
	"strings"
)

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// FlowKind classifies the control-flow effect of an instruction.
type FlowKind uint8

const (
	FlowNone     FlowKind = iota
	FlowCall               // jsr, bsr — calls a subroutine
	FlowReturn             // rts, rte, rtr — returns from subroutine
	FlowJump               // jmp, bra — unconditional jump (no return)
	FlowBranch             // bcc etc. — conditional branch
	FlowHalt               // illegal, stop — execution stops
)

// Result holds a single disassembled instruction.
type Result struct {
	Addr    uint32
	Bytes   []byte
	Text    string   // formatted instruction text
	IsValid bool
	Flow    FlowKind // control-flow classification
	Target  uint32   // resolved target address for Call/Jump/Branch (0 = indirect/unknown)
}

// Disassembler holds state needed for a disassembly pass.
type Disassembler struct {
	data       []byte
	base       uint32            // ROM base address (usually 0)
	labels     map[uint32]string // address → label name
	pos        int
	lastFlow   FlowKind
	lastTarget uint32
}

// New creates a Disassembler over data starting at baseAddr.
// Genesis hardware register addresses are pre-loaded as symbolic names;
// any entry in labels overrides the built-in defaults.
func New(data []byte, baseAddr uint32, labels map[uint32]string) *Disassembler {
	merged := make(map[uint32]string, len(genesisHWPorts)+len(labels))
	for k, v := range genesisHWPorts {
		merged[k] = v
	}
	for k, v := range labels {
		merged[k] = v
	}
	return &Disassembler{data: data, base: baseAddr, labels: merged}
}

// PC returns the current program counter (base + position).
func (d *Disassembler) PC() uint32 { return d.base + uint32(d.pos) }

// Remaining returns the number of bytes left to disassemble.
func (d *Disassembler) Remaining() int { return len(d.data) - d.pos }

// Next disassembles the instruction at the current position and advances pos.
func (d *Disassembler) Next() Result {
	if d.pos+2 > len(d.data) {
		return Result{Addr: d.PC(), IsValid: false}
	}
	startPos := d.pos
	startPC := d.PC()

	d.lastFlow = FlowNone
	d.lastTarget = 0

	text, ok := d.decode()

	end := d.pos
	if !ok {
		// Emit as DC.W
		d.pos = startPos + 2
		end = d.pos
		word := readU16(d.data, startPos)
		text = fmt.Sprintf("\tdc.w\t$%04X", word)
	}

	return Result{
		Addr:    startPC,
		Bytes:   append([]byte(nil), d.data[startPos:end]...),
		Text:    text,
		IsValid: ok,
		Flow:    d.lastFlow,
		Target:  d.lastTarget,
	}
}

// ---------------------------------------------------------------------------
// Internal decode
// ---------------------------------------------------------------------------

func (d *Disassembler) decode() (string, bool) {
	op := readU16(d.data, d.pos)
	d.pos += 2

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
		return d.decodeSUB(op)
	case 0xA:
		return fmt.Sprintf("\tdc.w\t$%04X\t; A-line trap", op), false
	case 0xB:
		return d.decodeCMP(op)
	case 0xC:
		return d.decodeGroupC(op)
	case 0xD:
		return d.decodeADD(op)
	case 0xE:
		return d.decodeShift(op)
	case 0xF:
		return fmt.Sprintf("\tdc.w\t$%04X\t; F-line trap", op), false
	}
	return "", false
}

// ---------------------------------------------------------------------------
// Group 0 – Immediate / bit operations
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeGroup0(op uint16) (string, bool) {
	// Dynamic bit ops: bit 8 set, bits 11-9 = data register (e.g. BTST d0,ea)
	if op&0xF100 == 0x0100 {
		return d.decodeBit(op)
	}
	subop := (op >> 8) & 0x0F
	// Static bit ops (subop=0x8): encoding is opword + bit-number-word + EA-words.
	// decodeBit handles all three in order — do NOT pre-consume EA here.
	if subop == 0x8 {
		return d.decodeBit(op)
	}
	sz := sizeName((op >> 6) & 3)
	ea := d.decodeEA(op&0x3F, sizeBytes((op>>6)&3))

	switch subop {
	case 0x0: // ORI / ORI to CCR / ORI to SR
		if op&0xFF == 0x3C {
			imm := d.readImm(1)
			return fmt.Sprintf("\tori\t#$%02X,ccr", imm), true
		}
		if op&0xFF == 0x7C {
			imm := d.readImm(2)
			return fmt.Sprintf("\tori.w\t#$%04X,sr", imm), true
		}
		imm := d.fmtImm(sz)
		return fmt.Sprintf("\tori.%s\t%s,%s", sz, imm, ea), true
	case 0x2: // ANDI
		imm := d.fmtImm(sz)
		return fmt.Sprintf("\tandi.%s\t%s,%s", sz, imm, ea), true
	case 0x4: // SUBI
		imm := d.fmtImm(sz)
		return fmt.Sprintf("\tsubi.%s\t%s,%s", sz, imm, ea), true
	case 0x6: // ADDI
		imm := d.fmtImm(sz)
		return fmt.Sprintf("\taddi.%s\t%s,%s", sz, imm, ea), true
	case 0xA: // EORI
		imm := d.fmtImm(sz)
		return fmt.Sprintf("\teori.%s\t%s,%s", sz, imm, ea), true
	case 0xC: // CMPI
		imm := d.fmtImm(sz)
		return fmt.Sprintf("\tcmpi.%s\t%s,%s", sz, imm, ea), true
	case 0xE: // MOVES (68010+) – treat as DC
		return fmt.Sprintf("\tdc.w\t$%04X", op), false
	}
	return fmt.Sprintf("\tdc.w\t$%04X", op), false
}

func (d *Disassembler) decodeBit(op uint16) (string, bool) {
	eaReg := op & 0x3F
	bitOp := (op >> 6) & 3
	names := []string{"btst", "bclr", "bset", "bchg"}
	name := names[bitOp]

	var bit string
	if op&0x0100 != 0 {
		// Dynamic: bit number is in a data register (Dn)
		bit = fmt.Sprintf("d%d", (op>>9)&7)
	} else {
		// Static: bit number is in the low byte of the next extension word.
		// Guard against reading past end of segment.
		if d.pos+2 > len(d.data) {
			return fmt.Sprintf("\tdc.w\t$%04X\t; truncated bit-op", op), false
		}
		d.pos += 2
		bit = fmt.Sprintf("#%d", d.data[d.pos-1])
	}
	ea := d.decodeEA(eaReg, 1)
	return fmt.Sprintf("\t%s\t%s,%s", name, bit, ea), true
}

// ---------------------------------------------------------------------------
// MOVE / MOVEA
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeMOVE(op uint16) (string, bool) {
	sizeCode := op >> 12
	var sz string
	var bytes int
	switch sizeCode {
	case 1:
		sz, bytes = "b", 1
	case 3:
		sz, bytes = "w", 2
	case 2:
		sz, bytes = "l", 4
	default:
		return "", false
	}
	src := d.decodeEA(op&0x3F, bytes)
	dstMode := (op >> 6) & 7
	dstReg := (op >> 9) & 7
	dst := d.decodeEAReg(dstMode, dstReg, bytes)

	if dstMode == 1 {
		return fmt.Sprintf("\tmovea.%s\t%s,a%d", sz, src, dstReg), true
	}
	return fmt.Sprintf("\tmove.%s\t%s,%s", sz, src, dst), true
}

// ---------------------------------------------------------------------------
// Group 4 – Misc
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeGroup4(op uint16) (string, bool) {
	// Specific patterns first
	switch op {
	case 0x4AFC:
		d.lastFlow = FlowHalt
		return "\tillegal", true
	case 0x4E70:
		return "\treset", true
	case 0x4E71:
		return "\tnop", true
	case 0x4E72:
		d.lastFlow = FlowHalt
		ext := d.readImmU16()
		return fmt.Sprintf("\tstop\t#$%04X", ext), true
	case 0x4E73:
		d.lastFlow = FlowReturn
		return "\trte", true
	case 0x4E75:
		d.lastFlow = FlowReturn
		return "\trts", true
	case 0x4E76:
		return "\ttrapv", true
	case 0x4E77:
		d.lastFlow = FlowReturn
		return "\trtr", true
	}

	if op&0xFFF0 == 0x4E40 {
		return fmt.Sprintf("\ttrap\t#%d", op&0xF), true
	}
	if op&0xFFF8 == 0x4E50 {
		d16 := int16(d.readImmU16())
		return fmt.Sprintf("\tlink\ta%d,#%d", op&7, d16), true
	}
	if op&0xFFF8 == 0x4E58 {
		return fmt.Sprintf("\tunlk\ta%d", op&7), true
	}
	if op&0xFFF8 == 0x4E60 {
		return fmt.Sprintf("\tmove.l\ta%d,usp", op&7), true
	}
	if op&0xFFF8 == 0x4E68 {
		return fmt.Sprintf("\tmove.l\tusp,a%d", op&7), true
	}
	if op&0xFFC0 == 0x4E80 {
		d.lastFlow = FlowCall
		posBeforeEA := d.pos
		ea := d.decodeEA(op&0x3F, 4)
		d.lastTarget = eaAbsTarget(op&0x3F, d.data, posBeforeEA, d.base)
		return fmt.Sprintf("\tjsr\t%s", ea), true
	}
	if op&0xFFC0 == 0x4EC0 {
		d.lastFlow = FlowJump
		posBeforeEA := d.pos
		ea := d.decodeEA(op&0x3F, 4)
		d.lastTarget = eaAbsTarget(op&0x3F, d.data, posBeforeEA, d.base)
		return fmt.Sprintf("\tjmp\t%s", ea), true
	}
	if op&0xFB80 == 0x4880 {
		// MOVEM
		return d.decodeMOVEM(op)
	}
	if op&0xFF00 == 0x4A00 {
		sz := sizeName((op >> 6) & 3)
		ea := d.decodeEA(op&0x3F, sizeBytes((op>>6)&3))
		return fmt.Sprintf("\ttst.%s\t%s", sz, ea), true
	}
	if op&0xFFC0 == 0x4800 {
		ea := d.decodeEA(op&0x3F, 1)
		return fmt.Sprintf("\tnbcd\t%s", ea), true
	}
	if op&0xFF00 == 0x4200 {
		sz := sizeName((op >> 6) & 3)
		ea := d.decodeEA(op&0x3F, sizeBytes((op>>6)&3))
		return fmt.Sprintf("\tclr.%s\t%s", sz, ea), true
	}
	if op&0xFF00 == 0x4400 {
		sz := sizeName((op >> 6) & 3)
		ea := d.decodeEA(op&0x3F, sizeBytes((op>>6)&3))
		return fmt.Sprintf("\tneg.%s\t%s", sz, ea), true
	}
	if op&0xFF00 == 0x4000 {
		sz := sizeName((op >> 6) & 3)
		ea := d.decodeEA(op&0x3F, sizeBytes((op>>6)&3))
		return fmt.Sprintf("\tnegx.%s\t%s", sz, ea), true
	}
	if op&0xFF00 == 0x4600 {
		sz := sizeName((op >> 6) & 3)
		ea := d.decodeEA(op&0x3F, sizeBytes((op>>6)&3))
		return fmt.Sprintf("\tnot.%s\t%s", sz, ea), true
	}
	if op&0xFFC0 == 0x4840 {
		ea := d.decodeEA(op&0x3F, 4)
		return fmt.Sprintf("\tpea\t%s", ea), true
	}
	if op&0xFFF8 == 0x4840 {
		return fmt.Sprintf("\tswap\td%d", op&7), true
	}
	if op&0xFFC0 == 0x4AC0 {
		ea := d.decodeEA(op&0x3F, 1)
		return fmt.Sprintf("\ttas\t%s", ea), true
	}
	if op&0xF1C0 == 0x41C0 {
		ea := d.decodeEA(op&0x3F, 4)
		return fmt.Sprintf("\tlea\t%s,a%d", ea, (op>>9)&7), true
	}
	if op&0xF1C0 == 0x4180 {
		ea := d.decodeEA(op&0x3F, 2)
		return fmt.Sprintf("\tchk.w\t%s,d%d", ea, (op>>9)&7), true
	}
	if op&0xFFF8 == 0x4880 {
		return fmt.Sprintf("\text.w\td%d", op&7), true
	}
	if op&0xFFF8 == 0x48C0 {
		return fmt.Sprintf("\text.l\td%d", op&7), true
	}
	return fmt.Sprintf("\tdc.w\t$%04X", op), false
}

func (d *Disassembler) decodeMOVEM(op uint16) (string, bool) {
	toMem := op&0x0400 == 0
	sz := "w"
	bytes := 2
	if op&0x0040 != 0 {
		sz = "l"
		bytes = 4
	}
	mask := d.readImmU16()
	ea := d.decodeEA(op&0x3F, bytes)
	regList := regListStr(mask, toMem && (op&0x38) == 0x20)
	if toMem {
		return fmt.Sprintf("\tmovem.%s\t%s,%s", sz, regList, ea), true
	}
	return fmt.Sprintf("\tmovem.%s\t%s,%s", sz, ea, regList), true
}

// ---------------------------------------------------------------------------
// Group 5 – ADDQ / SUBQ / Scc / DBcc
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeGroup5(op uint16) (string, bool) {
	cond := (op >> 8) & 0xF
	if (op>>6)&3 == 3 {
		// Scc or DBcc
		if (op>>3)&7 == 1 {
			// DBcc
			disp := int16(d.readImmU16())
			target := d.PC() + uint32(disp) - 2
			return fmt.Sprintf("\tdb%s\td%d,%s", condName(cond), op&7, d.labelOrHex(target)), true
		}
		ea := d.decodeEA(op&0x3F, 1)
		return fmt.Sprintf("\ts%s\t%s", condName(cond), ea), true
	}
	sz := sizeName((op >> 6) & 3)
	imm := (op >> 9) & 7
	if imm == 0 {
		imm = 8
	}
	ea := d.decodeEA(op&0x3F, sizeBytes((op>>6)&3))
	if op&0x0100 != 0 {
		return fmt.Sprintf("\tsubq.%s\t#%d,%s", sz, imm, ea), true
	}
	return fmt.Sprintf("\taddq.%s\t#%d,%s", sz, imm, ea), true
}

// ---------------------------------------------------------------------------
// Branch instructions
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeBranch(op uint16) (string, bool) {
	cond := (op >> 8) & 0xF
	disp8 := int8(op & 0xFF)
	var target uint32
	var size string

	if disp8 == 0 {
		disp16 := int16(d.readImmU16())
		target = d.PC() + uint32(disp16) - 2
		size = ".w"
	} else if disp8 == -1 { // 0xFF = long branch (68020)
		disp32 := int32(d.readImmU32())
		target = d.PC() + uint32(disp32) - 4
		size = ".l"
	} else {
		target = d.PC() + uint32(disp8)
		size = ".s"
	}

	d.lastTarget = target
	label := d.labelOrHex(target)
	if cond == 0 {
		d.lastFlow = FlowJump
		return fmt.Sprintf("\tbra%s\t%s", size, label), true
	}
	if cond == 1 {
		d.lastFlow = FlowCall
		return fmt.Sprintf("\tbsr%s\t%s", size, label), true
	}
	d.lastFlow = FlowBranch
	return fmt.Sprintf("\tb%s%s\t%s", condName(cond), size, label), true
}

// ---------------------------------------------------------------------------
// MOVEQ
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeMOVEQ(op uint16) (string, bool) {
	if op&0x0100 != 0 {
		return fmt.Sprintf("\tdc.w\t$%04X", op), false
	}
	imm := int8(op & 0xFF)
	dn := (op >> 9) & 7
	return fmt.Sprintf("\tmoveq\t#%d,d%d", imm, dn), true
}

// ---------------------------------------------------------------------------
// Group 8 – OR / DIVU / DIVS / SBCD
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeGroup8(op uint16) (string, bool) {
	dn := (op >> 9) & 7
	opmode := (op >> 6) & 7

	if opmode == 3 {
		ea := d.decodeEA(op&0x3F, 2)
		return fmt.Sprintf("\tdivu.w\t%s,d%d", ea, dn), true
	}
	if opmode == 7 {
		ea := d.decodeEA(op&0x3F, 2)
		return fmt.Sprintf("\tdivs.w\t%s,d%d", ea, dn), true
	}
	if opmode == 4 && (op>>3)&7 == 0 {
		return fmt.Sprintf("\tsbcd\td%d,d%d", op&7, dn), true
	}
	if opmode == 4 && (op>>3)&7 == 1 {
		return fmt.Sprintf("\tsbcd\t-(a%d),-(a%d)", op&7, dn), true
	}
	sz := sizeName(opmode & 3)
	ea := d.decodeEA(op&0x3F, sizeBytes(uint16(opmode&3)))
	if opmode&4 != 0 {
		return fmt.Sprintf("\tor.%s\td%d,%s", sz, dn, ea), true
	}
	return fmt.Sprintf("\tor.%s\t%s,d%d", sz, ea, dn), true
}

// ---------------------------------------------------------------------------
// SUB
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeSUB(op uint16) (string, bool) {
	dn := (op >> 9) & 7
	opmode := (op >> 6) & 7
	if opmode == 3 {
		ea := d.decodeEA(op&0x3F, 2)
		return fmt.Sprintf("\tsuba.w\t%s,a%d", ea, dn), true
	}
	if opmode == 7 {
		ea := d.decodeEA(op&0x3F, 4)
		return fmt.Sprintf("\tsuba.l\t%s,a%d", ea, dn), true
	}
	sz := sizeName(uint16(opmode & 3))
	ea := d.decodeEA(op&0x3F, sizeBytes(uint16(opmode&3)))
	if opmode&4 != 0 {
		return fmt.Sprintf("\tsub.%s\td%d,%s", sz, dn, ea), true
	}
	return fmt.Sprintf("\tsub.%s\t%s,d%d", sz, ea, dn), true
}

// ---------------------------------------------------------------------------
// CMP / EOR
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeCMP(op uint16) (string, bool) {
	dn := (op >> 9) & 7
	opmode := (op >> 6) & 7
	if opmode == 3 {
		ea := d.decodeEA(op&0x3F, 2)
		return fmt.Sprintf("\tcmpa.w\t%s,a%d", ea, dn), true
	}
	if opmode == 7 {
		ea := d.decodeEA(op&0x3F, 4)
		return fmt.Sprintf("\tcmpa.l\t%s,a%d", ea, dn), true
	}
	sz := sizeName(uint16(opmode & 3))
	ea := d.decodeEA(op&0x3F, sizeBytes(uint16(opmode&3)))
	if opmode&4 != 0 {
		// EOR (only dn→ea)
		return fmt.Sprintf("\teor.%s\td%d,%s", sz, dn, ea), true
	}
	// CMPM check
	if (op>>3)&7 == 1 && opmode < 3 {
		return fmt.Sprintf("\tcmpm.%s\t(a%d)+,(a%d)+", sz, op&7, dn), true
	}
	return fmt.Sprintf("\tcmp.%s\t%s,d%d", sz, ea, dn), true
}

// ---------------------------------------------------------------------------
// Group C – AND / MUL / ABCD / EXG
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeGroupC(op uint16) (string, bool) {
	dn := (op >> 9) & 7
	opmode := (op >> 6) & 7

	if opmode == 3 {
		ea := d.decodeEA(op&0x3F, 2)
		return fmt.Sprintf("\tmulu.w\t%s,d%d", ea, dn), true
	}
	if opmode == 7 {
		ea := d.decodeEA(op&0x3F, 2)
		return fmt.Sprintf("\tmuls.w\t%s,d%d", ea, dn), true
	}
	if opmode == 4 {
		if (op>>3)&7 == 0 {
			return fmt.Sprintf("\tabcd\td%d,d%d", op&7, dn), true
		}
		if (op>>3)&7 == 1 {
			return fmt.Sprintf("\tabcd\t-(a%d),-(a%d)", op&7, dn), true
		}
		// EXG Dn,Dn
		return fmt.Sprintf("\texg\td%d,d%d", dn, op&7), true
	}
	if opmode == 5 {
		return fmt.Sprintf("\texg\ta%d,a%d", dn, op&7), true
	}
	if opmode == 6 {
		return fmt.Sprintf("\texg\td%d,a%d", dn, op&7), true
	}
	sz := sizeName(uint16(opmode & 3))
	ea := d.decodeEA(op&0x3F, sizeBytes(uint16(opmode&3)))
	if opmode&4 != 0 {
		return fmt.Sprintf("\tand.%s\td%d,%s", sz, dn, ea), true
	}
	return fmt.Sprintf("\tand.%s\t%s,d%d", sz, ea, dn), true
}

// ---------------------------------------------------------------------------
// ADD
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeADD(op uint16) (string, bool) {
	dn := (op >> 9) & 7
	opmode := (op >> 6) & 7
	if opmode == 3 {
		ea := d.decodeEA(op&0x3F, 2)
		return fmt.Sprintf("\tadda.w\t%s,a%d", ea, dn), true
	}
	if opmode == 7 {
		ea := d.decodeEA(op&0x3F, 4)
		return fmt.Sprintf("\tadda.l\t%s,a%d", ea, dn), true
	}
	sz := sizeName(uint16(opmode & 3))
	ea := d.decodeEA(op&0x3F, sizeBytes(uint16(opmode&3)))
	if opmode&4 != 0 {
		return fmt.Sprintf("\tadd.%s\td%d,%s", sz, dn, ea), true
	}
	return fmt.Sprintf("\tadd.%s\t%s,d%d", sz, ea, dn), true
}

// ---------------------------------------------------------------------------
// Shifts / Rotates
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeShift(op uint16) (string, bool) {
	dir := (op >> 8) & 1 // 0=right, 1=left
	mode := (op >> 3) & 7
	kind := (op >> 9) & 3
	names := [4]string{"as", "ls", "rox", "ro"}
	name := names[kind]
	dirStr := "r"
	if dir != 0 {
		dirStr = "l"
	}

	if (op>>6)&3 == 3 {
		// Memory shift
		ea := d.decodeEA(op&0x3F, 2)
		return fmt.Sprintf("\t%s%s.w\t%s", name, dirStr, ea), true
	}

	sz := sizeName((op >> 6) & 3)
	dr := op & 7
	var count string
	if mode&4 != 0 {
		count = fmt.Sprintf("d%d", (op>>9)&7)
	} else {
		c := (op >> 9) & 7
		if c == 0 {
			c = 8
		}
		count = fmt.Sprintf("#%d", c)
	}
	return fmt.Sprintf("\t%s%s.%s\t%s,d%d", name, dirStr, sz, count, dr), true
}

// ---------------------------------------------------------------------------
// Effective Address decoder
// ---------------------------------------------------------------------------

func (d *Disassembler) decodeEA(ea uint16, bytes int) string {
	mode := (ea >> 3) & 7
	reg := ea & 7
	return d.decodeEAReg(mode, reg, bytes)
}

func (d *Disassembler) decodeEAReg(mode, reg uint16, bytes int) string {
	switch mode {
	case 0:
		return fmt.Sprintf("d%d", reg)
	case 1:
		return fmt.Sprintf("a%d", reg)
	case 2:
		return fmt.Sprintf("(a%d)", reg)
	case 3:
		return fmt.Sprintf("(a%d)+", reg)
	case 4:
		return fmt.Sprintf("-(a%d)", reg)
	case 5:
		disp := int16(d.readImmU16())
		return fmt.Sprintf("(%d,a%d)", disp, reg)
	case 6:
		ext := d.readImmU16()
		disp := int8(ext & 0xFF)
		idxReg := (ext >> 12) & 7
		idxKind := "d"
		if ext&0x8000 != 0 {
			idxKind = "a"
		}
		idxSz := "w"
		if ext&0x0800 != 0 {
			idxSz = "l"
		}
		return fmt.Sprintf("(%d,a%d,%s%d.%s)", disp, reg, idxKind, idxReg, idxSz)
	case 7:
		switch reg {
		case 0:
			addr := uint32(d.readImmU16())
			return d.labelOrHex16(addr)
		case 1:
			addr := d.readImmU32()
			return d.labelOrHex32(addr)
		case 2:
			disp := int16(d.readImmU16())
			target := d.PC() + uint32(disp) - 2
			return fmt.Sprintf("(%s,pc)", d.labelOrHex(target))
		case 3:
			ext := d.readImmU16()
			disp := int8(ext & 0xFF)
			idxReg := (ext >> 12) & 7
			idxKind := "d"
			if ext&0x8000 != 0 {
				idxKind = "a"
			}
			idxSz := "w"
			if ext&0x0800 != 0 {
				idxSz = "l"
			}
			return fmt.Sprintf("(%d,pc,%s%d.%s)", disp, idxKind, idxReg, idxSz)
		case 4:
			switch bytes {
			case 1:
				v := d.readImmU16()
				return fmt.Sprintf("#$%02X", v&0xFF)
			case 2:
				v := d.readImmU16()
				return fmt.Sprintf("#$%04X", v)
			case 4:
				v := d.readImmU32()
				return fmt.Sprintf("#$%08X", v)
			}
		}
	}
	return fmt.Sprintf("?ea(%d,%d)", mode, reg)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func (d *Disassembler) readImmU16() uint16 {
	if d.pos+2 > len(d.data) {
		return 0
	}
	v := readU16(d.data, d.pos)
	d.pos += 2
	return v
}

func (d *Disassembler) readImmU32() uint32 {
	if d.pos+4 > len(d.data) {
		return 0
	}
	v := readU32(d.data, d.pos)
	d.pos += 4
	return v
}

func (d *Disassembler) readImm(n int) uint32 {
	switch n {
	case 1:
		if d.pos+2 > len(d.data) {
			return 0
		}
		v := readU16(d.data, d.pos)
		d.pos += 2
		return uint32(v & 0xFF)
	case 2:
		if d.pos+2 > len(d.data) {
			return 0
		}
		v := readU16(d.data, d.pos)
		d.pos += 2
		return uint32(v)
	case 4:
		if d.pos+4 > len(d.data) {
			return 0
		}
		v := readU32(d.data, d.pos)
		d.pos += 4
		return v
	}
	return 0
}

func (d *Disassembler) fmtImm(sz string) string {
	switch sz {
	case "b":
		return fmt.Sprintf("#$%02X", d.readImm(1))
	case "w":
		return fmt.Sprintf("#$%04X", d.readImm(2))
	case "l":
		return fmt.Sprintf("#$%08X", d.readImm(4))
	}
	return "#?"
}

func (d *Disassembler) labelOrHex(addr uint32) string {
	if name, ok := d.labels[addr]; ok {
		return name
	}
	return fmt.Sprintf("$%06X", addr)
}

func (d *Disassembler) labelOrHex16(addr uint32) string {
	if name, ok := d.labels[addr]; ok {
		return name
	}
	return fmt.Sprintf("$%04X.w", addr)
}

func (d *Disassembler) labelOrHex32(addr uint32) string {
	if name, ok := d.labels[addr]; ok {
		return name
	}
	return fmt.Sprintf("$%06X", addr)
}

// eaAbsTarget extracts the resolved absolute address from a JSR/JMP EA field
// when the EA encodes a static address (absolute long/short or PC-relative).
// posAfterOpword is the index in data right after the instruction opword.
// Returns 0 for indirect/register-based EA modes.
func eaAbsTarget(ea uint16, data []byte, posAfterOpword int, base uint32) uint32 {
	if (ea>>3)&7 != 7 {
		return 0 // not an extended EA mode
	}
	switch ea & 7 {
	case 0: // absolute short (.w)
		if posAfterOpword+2 <= len(data) {
			return uint32(readU16(data, posAfterOpword))
		}
	case 1: // absolute long (.l)
		if posAfterOpword+4 <= len(data) {
			return readU32(data, posAfterOpword)
		}
	case 2: // PC-relative (d16,PC) — PC points past the displacement word
		if posAfterOpword+2 <= len(data) {
			disp := int16(readU16(data, posAfterOpword))
			pc := base + uint32(posAfterOpword+2)
			return uint32(int32(pc) + int32(disp))
		}
	}
	return 0
}

func readU16(data []byte, pos int) uint16 {
	if pos+2 > len(data) {
		return 0
	}
	return uint16(data[pos])<<8 | uint16(data[pos+1])
}

func readU32(data []byte, pos int) uint32 {
	if pos+4 > len(data) {
		return 0
	}
	return uint32(data[pos])<<24 | uint32(data[pos+1])<<16 | uint32(data[pos+2])<<8 | uint32(data[pos+3])
}

func sizeName(sz uint16) string {
	switch sz & 3 {
	case 0:
		return "b"
	case 1:
		return "w"
	case 2:
		return "l"
	}
	return "?"
}

func sizeBytes(sz uint16) int {
	switch sz & 3 {
	case 0:
		return 1
	case 1:
		return 2
	case 2:
		return 4
	}
	return 2
}

func condName(cond uint16) string {
	names := []string{"t", "f", "hi", "ls", "cc", "cs", "ne", "eq", "vc", "vs", "pl", "mi", "ge", "lt", "gt", "le"}
	if int(cond) < len(names) {
		return names[cond]
	}
	return fmt.Sprintf("?%d", cond)
}

func regListStr(mask uint16, predecrement bool) string {
	var parts []string
	regs := [16]string{"d0","d1","d2","d3","d4","d5","d6","d7","a0","a1","a2","a3","a4","a5","a6","a7"}
	if predecrement {
		// Reversed for predecrement addressing
		var rev [16]string
		for i := 0; i < 8; i++ {
			rev[i] = regs[15-i]
			rev[8+i] = regs[7-i]
		}
		regs = rev
	}
	for i, r := range regs {
		if mask&(1<<uint(15-i)) != 0 {
			parts = append(parts, r)
		}
	}
	return strings.Join(parts, "/")
}

// DisassembleBlock disassembles data[start:end] treating it as M68K code.
// Returns all Result entries with labels resolved.
func DisassembleBlock(data []byte, baseAddr, start, end uint32, labels map[uint32]string) []Result {
	segData := data[start:end]
	d := New(segData, baseAddr+start, labels)
	var results []Result
	for d.Remaining() >= 2 {
		results = append(results, d.Next())
	}
	return results
}
