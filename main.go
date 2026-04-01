package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	_ "sega2asm/compress"
	"sega2asm/splitter"
	"sega2asm/types"
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

func newRootCmd() *cobra.Command {
	var configFile string
	var symbolsFile string
	var charmapFile string
	var verbose bool
	var dryRun bool

	cmd := &cobra.Command{
		Use:     "sega2asm [config.yaml]",
		Short:   "Sega Mega Drive / Genesis ROM disassembler & splitter",
		Version: version,
		Args:    cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Print(banner)

			if configFile == "" {
				if len(args) > 0 {
					configFile = args[0]
				} else {
					return cmd.Usage()
				}
			}

			// Silence usage for runtime errors (past argument validation)
			cmd.SilenceUsage = true

			cfg, err := types.LoadConfig(configFile)
			if err != nil {
				return fmt.Errorf("loading config: %w", err)
			}

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
				return err
			}

			fmt.Println("\n[OK] sega2asm: Completed successfully!")
			return nil
		},
	}

	cmd.Flags().StringVarP(&configFile, "config", "c", "", "Configuration YAML file")
	cmd.Flags().StringVarP(&symbolsFile, "symbols", "s", "", "Symbols file (overrides config)")
	cmd.Flags().StringVarP(&charmapFile, "charmap", "t", "", "Charmap TBL file (overrides config)")
	cmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "Verbose output")
	cmd.Flags().BoolVar(&dryRun, "dry-run", false, "Parse config and symbols without writing files")

	cmd.SetVersionTemplate("sega2asm v{{.Version}}\n")

	cmd.AddCommand(newDetectCmd())

	return cmd
}

func newDetectCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "detect <rom>",
		Short: "Scan a ROM for known compression routine signatures",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			data, err := os.ReadFile(args[0])
			if err != nil {
				return err
			}
			matches := types.Detect(data)
			if len(matches) == 0 {
				fmt.Println("No known compression signatures found.")
				return nil
			}
			for _, m := range matches {
				fmt.Printf("$%06X  %s\n", m.Offset, m.Name)
			}
			return nil
		},
	}
}

func main() {
	if err := newRootCmd().Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "[ERROR] %v\n", err)
		os.Exit(1)
	}
}
