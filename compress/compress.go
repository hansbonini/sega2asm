package compress

import "fmt"

// Decompress decompresses src using the named algorithm.
//
// Compression name strings accepted by the YAML `compression:` field:
//
//   Original:     huffnemesis  lzkosinski  lzkosinskiplus  mixedenigma  rlesegard
//   clownlzss:    lzsssaxman  lzsssaxman_noheader  lzcomper  lzrocket  lzssfaxman  lzrage  lzchameleon
//   py-port:      lznamco  lzstrike  lztechnosoft
//                 lzkonami1  lzkonami2  lzkonami3
//                 lzancient  lzbandai  lznextech  lzwolfteam  lzsti  rlesc
//   RNC:          lzhrnc  lzhrnc1  lzhrnc2
//   Blizzard:     lzssblizzard
//   LucasArts:    lzhlucasarts
//   Climax:       lz77climax  expgolombclimax  lzclimax
//   Westone:      lzhwestone  mixedwestone
//   KOEI:         lzsskoei
//   Game Arts:    rlegamearts
//   PowerPacker:  lzpowerpack20
//   Bahamut:      rlebahamut
//   Samsung:      huffsamsung
//   Pass-through: none  (empty)
func Decompress(compression string, src []byte) ([]byte, error) {
	switch compression {
	case "huffnemesis":
		return DecompressHuffNemesis(src)
	case "lzkosinski":
		return DecompressLZKosinski(src)
	case "lzkosinskiplus":
		return DecompressLZKosinskiPlus(src)
	case "mixedenigma":
		return DecompressMixedEnigma(src)
	case "rlesegard":
		return DecompressRLESegard(src)
	case "lzsssaxman":
		return DecompressLZSSSaxman(src)
	case "lzsssaxman_noheader":
		return DecompressLZSSSaxmanNoHeader(src)
	case "lzcomper":
		return DecompressLZComper(src)
	case "lzrocket":
		return DecompressLZRocket(src)
	case "lzssfaxman":
		return DecompressLZSSFaxman(src)
	case "lzrage":
		return DecompressLZRage(src)
	case "lzchameleon":
		return DecompressLZChameleon(src)
	case "lznamco":
		return DecompressLZNamco(src)
	case "lzstrike":
		return DecompressLZStrike(src)
	case "lztechnosoft":
		return DecompressLZTechnosoft(src)
	case "lzkonami1":
		return DecompressLZKonami1(src)
	case "lzkonami2":
		return DecompressLZKonami2(src)
	case "lzkonami3":
		return DecompressLZKonami3(src)
	case "lzancient":
		return DecompressLZAncient(src)
	case "lzbandai":
		return DecompressLZBandai(src)
	case "lznextech":
		return DecompressLZNextech(src)
	case "lzwolfteam":
		return DecompressLZWolfteam(src)
	case "lzsti":
		return DecompressLZSTI(src)
	case "rlesc":
		return DecompressRLESC(src)
	case "lzhrnc":
		return DecompressLZHRNC(src)
	case "lzhrnc1":
		return DecompressLZHRNC1(src)
	case "lzhrnc2":
		return DecompressLZHRNC2(src)
	case "lzcompile":
		return DecompressLZCompile(src)
	case "mixeditl":
		return DecompressMixedITL(src)
	case "lzfactor5":
		return DecompressLZFactor5(src)
	case "lzbeam":
		return DecompressLZBeam(src)
	case "lztreasure":
		return DecompressLZTreasure(src)
	case "lzssblizzard":
		return DecompressLZSSBlizzard(src)
	case "lzhlucasarts":
		return DecompressLZHLucasArts(src)
	case "lz77climax":
		return DecompressLZ77Climax(src)
	case "expgolombclimax":
		return DecompressExpGolombClimax(src)
	case "lzclimax":
		return DecompressLZClimax(src)
	case "lzhwestone":
		return DecompressLZHWestone(src)
	case "mixedwestone":
		return DecompressMixedWestone(src)
	case "lzsskoei":
		return DecompressLZSSKoei(src)
	case "rlegamearts":
		return DecompressRLEGameArts(src)
	case "lzpowerpack20":
		return DecompressLZPowerPack20(src)
	case "rlebahamut":
		return DecompressRLEBahamut(src)
	case "huffsamsung":
		return DecompressHuffSamsung(src)
	case "none", "":
		dst := make([]byte, len(src))
		copy(dst, src)
		return dst, nil
	default:
		return nil, fmt.Errorf("unknown compression %q", compression)
	}
}
