#!/usr/bin/env nu

# --- Core Logic ---
# Can be used directly if sourced
def --wrapped nx [
    --pkgs (-s): list<string>          # System packages
    --python-pkgs (-p): list<string>   # Python packages
    --quiet (-q)                       # Suppress output (for scripts)
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
    let quiet = ($quiet | default false)

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
  pkgs = import <nixpkgs> { config.allowUnfree = true; };
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

    # Print info (unless quiet)
    if not $quiet {
        if not ($python_pkgs | is-empty) {
            print $"(ansi green)[nx] Python packages: ($python_pkgs | uniq | str join ', ')(ansi reset)"
        }
        print $"(ansi cyan)[nx] Packages: ($pkgs | str join ', ')(ansi reset)"
        print $"(ansi yellow)[nx] Expression:(ansi reset)"
        print $expr
    }

    # Run!
    nix shell --impure --expr $expr ...$pkgs --command ...$final_cmd
}

# Parses raw string arguments into lists for the core logic
def --wrapped main [
    --python (-p): string   # Python packages (space separated)
    ...args: string         # System packages and command (separated by --)
] {
    # Separate System Packages vs Command
    mut sys_list = []
    mut cmd_list = []
    mut parsing_cmd = false

    for arg in $args {
        if $parsing_cmd {
            $cmd_list = ($cmd_list | append $arg)
        } else if $arg == "--" {
            $parsing_cmd = true
        } else {
            $sys_list = ($sys_list | append ($arg | split words))
        }
    }

    # Parse Python String to List
    let py_list = if ($python | is-empty) { [] } else {
        $python | split words | each { |it| $it | str trim }
    }

    # Delegate to core logic
    nx --pkgs $sys_list --python-pkgs $py_list ...$cmd_list
}
