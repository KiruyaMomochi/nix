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
# With -s/--pkgs, every positional argument is part of the command. Without it,
# positional arguments before -- are package names.
def --wrapped main [
    --pkgs (-s): string     # System packages (space separated)
    --python (-p): string   # Python packages (space separated)
    --verbose (-v)          # Print resolved packages and the Nix expression
    --help (-h)             # Show usage
    ...args: string
] {
    if $help {
        print "Usage:
  nx \"<system packages>\" [--python \"<python packages>\"] -- <command...>
  nx --pkgs \"<system packages>\" [--python \"<python packages>\"] <command...>

Options:
  -s, --pkgs       System packages, space separated
  -p, --python     Python packages, space separated
  -v, --verbose    Print the generated Nix expression
  -h, --help       Show this help"
        return
    }

    mut sys_list = (split_words $pkgs)
    mut cmd_list = []

    if ($sys_list | is-not-empty) {
        # An explicit package flag removes the package/command ambiguity. Keep a
        # separator optional, but discard it when callers include one for clarity.
        $cmd_list = if (($args | first | default "") == "--") {
            $args | skip 1
        } else {
            $args
        }
    } else {
        mut parsing_cmd = false
        for arg in $args {
            if $parsing_cmd {
                $cmd_list = ($cmd_list | append $arg)
            } else if $arg == "--" {
                $parsing_cmd = true
            } else {
                $sys_list = ($sys_list | append (split_words $arg))
            }
        }
    }

    nx --pkgs $sys_list --python-pkgs (split_words $python) --verbose=$verbose ...$cmd_list
}
