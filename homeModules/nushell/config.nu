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
    --pkgs: list<string>
    --python-pkgs: list<string>
    ...command
] {
    # Determine final command (default to SHELL if empty)
    let final_cmd = if ($command | is-empty) {
        [ (if ("SHELL" in $env) { $env.SHELL } else { "bash" }) ]
    } else {
        $command
    }

    if ($python_pkgs | is-empty) {
        if ($pkgs | is-empty) {
             # just enter shell with no extra packages (basically useless but valid)
        }
        
        let nix_args = ($pkgs | each { |it| $"nixpkgs#($it)" })
        print $"(ansi cyan)[nx] Entering System Environment...(ansi reset)"
        nix shell --impure ...$nix_args --command ...$final_cmd

    } else {
        let py_deps = ($python_pkgs | each { |it| $"ps.($it)" } | str join " ")
        let sys_deps = ($pkgs | each { |it| $"pkgs.($it)" } | str join "\n            ")

        let expr = $"
let
  pkgs = import <nixpkgs> { config.allowUnfree = true; };
in
pkgs.mkShell {
  buildInputs = [
    ($sys_deps)
    \(pkgs.python3.withPackages \(ps: [ ($py_deps) ]\)\)
  ];
}
"
        print $"(ansi green)[nx] Entering Python+System Environment...(ansi reset)"
        nix shell --impure --expr $expr --command ...$final_cmd
    }
}

use std/dirs shells-aliases *
