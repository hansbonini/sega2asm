package m68k

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
	// Z80
	0x00A00000: "Z80_RAM",
	0x00A11100: "Z80_BUSREQ",
	0x00A11200: "Z80_RESET",
	// I/O
	0x00A10001: "IO_PCBVER",
	0x00A10003: "IO_DATA_1",
	0x00A10005: "IO_DATA_2",
	0x00A10007: "IO_DATA_EXP",
	0x00A10009: "IO_CTRL_1",
	0x00A1000B: "IO_CTRL_2",
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
