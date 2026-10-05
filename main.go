package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"path/filepath"

	"sega2asm/analysis"
	_ "sega2asm/compress"
	"sega2asm/godot"
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
	cmd.AddCommand(newAnalyzeCmd())
	cmd.AddCommand(newVerifyCmd())
	cmd.AddCommand(newGodotCmd())

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

func newAnalyzeCmd() *cobra.Command {
	var configFile, reportFile string
	cmd := &cobra.Command{
		Use:   "analyze <rom>",
		Short: "Trace 68000 control flow and report code / data regions",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			cmd.SilenceUsage = true
			r, err := types.LoadROM(args[0])
			if err != nil {
				return err
			}
			var opts analysis.Options
			opts.Orphans = true
			if configFile != "" {
				cfg, err := types.LoadConfig(configFile)
				if err != nil {
					return err
				}
				opts = analysis.OptionsFromConfig(cfg.Analysis)
			}
			res := analysis.Trace(r.Data, opts)
			out := os.Stdout
			if reportFile != "" {
				f, err := os.Create(reportFile)
				if err != nil {
					return err
				}
				defer f.Close()
				out = f
			}
			res.WriteReport(out)
			code, data, unk := res.Stats()
			fmt.Fprintf(os.Stderr, "code=%d data=%d unknown=%d functions=%d tables=%d indirect=%d conflicts=%d\n",
				code, data, unk, len(res.Entries), len(res.Tables), len(res.Indirect), len(res.Conflicts))
			return nil
		},
	}
	cmd.Flags().StringVarP(&configFile, "config", "c", "", "Configuration YAML (uses its analysis: block)")
	cmd.Flags().StringVarP(&reportFile, "report", "r", "", "Write the report to this file instead of stdout")
	return cmd
}

func newVerifyCmd() *cobra.Command {
	var assembler string
	cmd := &cobra.Command{
		Use:   "verify <config.yaml>",
		Short: "Assemble the split project and compare the result with the original ROM",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			cmd.SilenceUsage = true
			cfg, err := types.LoadConfig(args[0])
			if err != nil {
				return err
			}
			return splitter.Verify(cfg, assembler)
		},
	}
	def := os.Getenv("CLOWNASSEMBLER")
	if def == "" {
		def = "clownassembler"
	}
	cmd.Flags().StringVarP(&assembler, "assembler", "a", def, "clownassembler executable ($CLOWNASSEMBLER)")
	return cmd
}

func newGodotCmd() *cobra.Command {
	var out, extra string
	cmd := &cobra.Command{
		Use:   "godot <config.yaml>",
		Short: "Export the configured assets as a Godot 4 project",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			cmd.SilenceUsage = true
			cfg, err := types.LoadConfig(args[0])
			if err != nil {
				return err
			}
			if out == "" {
				out = filepath.Join(cfg.Options.BasePath, "godot")
			}
			warn := func(f string, a ...any) { fmt.Printf("[WARN] "+f+"\n", a...) }
			if err := godot.Export(cfg, godot.Options{OutDir: out, ExtraDir: extra}, warn); err != nil {
				return err
			}
			fmt.Printf("[OK] Godot project written to %s\n", out)
			return nil
		},
	}
	cmd.Flags().StringVarP(&out, "out", "o", "", "output directory (default <base_path>/godot)")
	cmd.Flags().StringVar(&extra, "extra", "", "directory copied into the project (game-specific scripts)")
	return cmd
}

func main() {
	if err := newRootCmd().Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "[ERROR] %v\n", err)
		os.Exit(1)
	}
}
