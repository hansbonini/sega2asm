package main

import (
	"flag"
	"fmt"
	"log"
	"os"

	"sega2asm/config"
	"sega2asm/splitter"
)

const version = "1.0.0"

const banner = `
███████╗███████╗ ██████╗  █████╗ ██████╗  █████╗ ███████╗███╗   ███╗
██╔════╝██╔════╝██╔════╝ ██╔══██╗╚════██╗██╔══██╗██╔════╝████╗ ████║
███████╗█████╗  ██║  ███╗███████║ █████╔╝███████║███████╗██╔████╔██║
╚════██║██╔══╝  ██║   ██║██╔══██║██╔═══╝ ██╔══██║╚════██║██║╚██╔╝██║
███████║███████╗╚██████╔╝██║  ██║███████╗██║  ██║███████║██║ ╚═╝ ██║
╚══════╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝
  Sega Mega Drive / Genesis ROM disassembler & splitter  v` + version + `
`

func main() {
	var configFile string
	var symbolsFile string
	var charmapFile string
	var verbose bool
	var showVersion bool
	var dryRun bool

	flag.StringVar(&configFile, "c", "", "Configuration YAML file")
	flag.StringVar(&symbolsFile, "s", "", "Symbols file (overrides config)")
	flag.StringVar(&charmapFile, "t", "", "Charmap TBL file (overrides config)")
	flag.BoolVar(&verbose, "v", false, "Verbose output")
	flag.BoolVar(&showVersion, "version", false, "Show version and exit")
	flag.BoolVar(&dryRun, "dry-run", false, "Parse config and symbols without writing files")
	flag.Parse()

	fmt.Print(banner)

	if showVersion {
		fmt.Printf("sega2asm v%s\n", version)
		os.Exit(0)
	}

	// Allow config file as positional argument
	if configFile == "" {
		if flag.NArg() > 0 {
			configFile = flag.Arg(0)
		} else {
			fmt.Println("Usage: sega2asm [options] <config.yaml>")
			fmt.Println("       sega2asm -c config.yaml [-s symbols.txt] [-t charmap.tbl] [-v]")
			fmt.Println()
			fmt.Println("Options:")
			flag.PrintDefaults()
			fmt.Println()
			fmt.Println("Segment types: m68k, z80, gfx, gfxcomp, pcm, psg, header, bin, text")
			fmt.Println("Compression:   nemesis, kosinski, enigma, none")
			os.Exit(1)
		}
	}

	cfg, err := config.Load(configFile)
	if err != nil {
		log.Fatalf("[ERROR] Loading config: %v", err)
	}

	// Command-line flags override config file paths
	if symbolsFile != "" {
		cfg.Options.SymbolsPath = symbolsFile
	}
	if charmapFile != "" {
		cfg.Options.CharmapPath = charmapFile
	}

	sp := splitter.New(cfg, splitter.Options{
		Verbose: verbose,
		DryRun:  dryRun,
	})

	if err := sp.Run(); err != nil {
		log.Fatalf("[ERROR] %v", err)
	}

	fmt.Println("\n[OK] sega2asm: Completed successfully!")
}
