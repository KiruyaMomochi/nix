#!/usr/bin/env nu

# --- Core Logic ---
# Can be used directly if sourced (list arguments use Nushell syntax, e.g. -s [bun jq])
def --wrapped nx [
    --pkgs (-s): list<string>          # System packages
    --python-pkgs (-p): list<string>   # Python packages
    --verbose (-v)                     # Verbose output
    ...command
] {
    # Determine final command (default to SHELL if empty)
    let final_cmd = if ($command | is-empty) {
        [ (if ("SHELL" in $env) { $env.SHELL } else { "bash" }) ]
    } else {
        $command
    }

    # Handle optional parameters
    let pkgs = ($pkgs | default [])
    let verbose = ($verbose | default false)

    let python_pkgs = ($python_pkgs | default [])
    let overrides = [
        (if ($python_pkgs | is-not-empty) {
            let py_pkgs_unique = ($python_pkgs | uniq)
            let py_deps = ($py_pkgs_unique | each { |it| $"ps.($it)" } | str join " ")
            $"  python3 = pkgs.python3.withPackages \(ps: [ ($py_deps) ]\);"
        })
    ] | compact

    # Build expression
    let expr = $"
let
  pkgs = import \(builtins.getFlake \"nixpkgs\"\).outPath { config.allowUnfree = true; };
in
pkgs // {
($overrides | str join "\n")
}
"

    # Build package list
    let pkgs = $pkgs | append (if ($python_pkgs | is-not-empty) {["python3"]}) | compact | uniq

    if ($pkgs | is-empty) {
        error make {
            msg: "Please use -s/--pkgs or -p/--python-pkgs"
        }
    }

    # Print info to stderr if verbose
    if $verbose {
        if not ($python_pkgs | is-empty) {
            print -e $"(ansi green)[nx] Python packages: ($python_pkgs | uniq | str join ', ')(ansi reset)"
        }
        print -e $"(ansi cyan)[nx] Packages: ($pkgs | str join ', ')(ansi reset)"
        print -e $"(ansi yellow)[nx] Expression:(ansi reset)"
        print -e $expr
    }

    # Run!
    nix shell --impure --expr $expr ...$pkgs --command ...$final_cmd
}

def split_words [value?: string] {
    $value
    | default ""
    | split row ' '
    | each { |it| $it | str trim }
    | where { |it| $it != '' }
}

# Executable interface. There are two unambiguous forms:
#   nx "bun jq" -- bash -c '...'
#   nx -s "bun jq" bash -c '...'
#
# Parse flags manually instead of declaring them in main's signature. Nushell parses
# declared short flags before main runs, so a forwarded Go-style option such as
# `-plaintext` collides with nx's `-p` and never reaches ...args.
def --wrapped main [...raw_args: string] {
    mut sys_list = []
    mut python = ""
    mut verbose = false
    mut explicit_pkgs = false
    mut parsing_cmd = false
    mut cmd_list = []
    mut index = 0

    while $index < ($raw_args | length) {
        let arg = ($raw_args | get $index)

        if $parsing_cmd {
            $cmd_list = ($cmd_list | append $arg)
        } else if $arg == "--" {
            $parsing_cmd = true
        } else if $arg in ["-h", "--help"] {
            print "Usage:
  nx \"<system packages>\" [--python \"<python packages>\"] -- <command...>
  nx --pkgs \"<system packages>\" [--python \"<python packages>\"] <command...>

Options:
  -s, --pkgs       System packages, space separated
  -p, --python     Python packages, space separated
  -v, --verbose    Print the generated Nix expression
  -h, --help       Show this help"
            return
        } else if $arg in ["-s", "--pkgs"] {
            $index += 1
            if $index >= ($raw_args | length) {
                error make { msg: $"Missing value for ($arg)" }
            }
            $sys_list = ($sys_list | append (split_words ($raw_args | get $index)))
            $explicit_pkgs = true
        } else if $arg in ["-p", "--python"] {
            $index += 1
            if $index >= ($raw_args | length) {
                error make { msg: $"Missing value for ($arg)" }
            }
            $python = ($raw_args | get $index)
        } else if $arg in ["-v", "--verbose"] {
            $verbose = true
        } else if $explicit_pkgs {
            # The first non-nx argument starts the command. From here on every
            # argument, including strings beginning with '-', is passed unchanged.
            $parsing_cmd = true
            $cmd_list = ($cmd_list | append $arg)
        } else {
            # In positional mode, everything before -- names packages.
            $sys_list = ($sys_list | append (split_words $arg))
        }

        $index += 1
    }

    nx --pkgs $sys_list --python-pkgs (split_words $python) --verbose=$verbose ...$cmd_list
}
