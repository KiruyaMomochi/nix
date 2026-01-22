# Nushell Config File
#
# version = "0.101.0"

$env.config.show_banner = false;
$env.config.history.file_format = "sqlite";
$env.config.history.isolation = true;
$env.config.completions.algorithm = "fuzzy";

const extra_config = $nu.default-config-dir | path join 'config.local.nu'
source $extra_config

def --env set-proxy [$proxy: string] {
    ["http", "https", "all"] | each { $in + "_proxy"} | append ($in | str upcase) | reduce --fold {} {|elm, acc| $acc | insert $elm $proxy} | load-env
}

def --env hide-proxy [] {
    ["http", "https", "all"] | each { $in + "_proxy"} | append ($in | str upcase) | where { $in in $env } | hide-env ...$in
}

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

use std/dirs shells-aliases *
