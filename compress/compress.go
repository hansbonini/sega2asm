package compress

import "fmt"

// Decompress decompresses src using the named algorithm.
//
// Compression name strings accepted by the YAML `compression:` field:
//
//   Original:     nemesis  kosinski  kosinskiplus  enigma  segard
//   clownlzss:    saxman  saxman_noheader  comper  rocket  faxman  rage  chameleon
//   py-port:      lznamco  lzstrike  lztechnosoft
//                 lzkonami1  lzkonami2  lzkonami3
//                 lzancient  lztose  lznextech  lzwolfteam  lzsti  rlesc
//   RNC:          rnc  rnc1  rnc2
//   Blizzard:     lzblizzard
//   LucasArts:    lzhlucasarts
//   Climax:       lzclimax  lzclimax2
//   Westone:      lzwestone  lzwestone_block
//   KOEI:         lzkoei
//   Game Arts:    rlegamearts
//   Pass-through: none  (empty)
func Decompress(compression string, src []byte) ([]byte, error) {
	switch compression {
	case "nemesis":
		return DecompressNemesis(src)
	case "kosinski":
		return DecompressKosinski(src)
	case "kosinskiplus":
		return DecompressKosinskiPlus(src)
	case "enigma":
		return DecompressEnigma(src)
	case "segard":
		return DecompressSegaRD(src)
	case "saxman":
		return DecompressSaxman(src)
	case "saxman_noheader":
		return DecompressSaxmanNoHeader(src)
	case "comper":
		return DecompressComper(src)
	case "rocket":
		return DecompressRocket(src)
	case "faxman":
		return DecompressFaxman(src)
	case "rage":
		return DecompressRage(src)
	case "chameleon":
		return DecompressChameleon(src)
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
	case "lztose":
		return DecompressLZTose(src)
	case "lznextech":
		return DecompressLZNextech(src)
	case "lzwolfteam":
		return DecompressLZWolfteam(src)
	case "lzsti":
		return DecompressLZSTI(src)
	case "rlesc":
		return DecompressRLESoftwareCreations(src)
	case "rnc":
		return DecompressRNC(src)
	case "rnc1":
		return DecompressRNC1(src)
	case "rnc2":
		return DecompressRNC2(src)
	case "lzcompile":
		return DecompressLZCompile(src)
	case "itl":
		return DecompressITL(src)
	case "lzfactor5":
		return DecompressLZFactor5(src)
	case "lzbeam":
		return DecompressLZBeam(src)
	case "lztreasure":
		return DecompressLZTreasure(src)
	case "lzblizzard":
		return DecompressLZBlizzard(src)
	case "lzhlucasarts":
		return DecompressLZHLucasArts(src)
	case "lzclimax":
		return DecompressLZClimax(src)
	case "lzclimax2":
		return DecompressLZClimax2(src)
	case "lzwestone":
		return DecompressLZWestone(src)
	case "lzwestone_block":
		return DecompressLZWestoneBlock(src)
	case "lzkoei":
		return DecompressLZKoei(src)
	case "rlegamearts":
		return DecompressRLEGameArts(src)
	case "none", "":
		dst := make([]byte, len(src))
		copy(dst, src)
		return dst, nil
	default:
		return nil, fmt.Errorf("unknown compression %q", compression)
	}
}
