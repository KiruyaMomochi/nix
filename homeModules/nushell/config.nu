# Nushell Config File
#
# version = "0.101.0"

$env.config.show_banner = false;
$env.config.history.isolation = true;
$env.config.history.file_format = "sqlite";
$env.config.completions.algorithm = "fuzzy";

const extra_config = $nu.default-config-dir | path join 'config.local.nu'
source $extra_config

def --env set-proxy [$proxy: string] {
    ["http", "https", "all"] | each { $in + "_proxy"} | append ($in | str upcase) | reduce --fold {} {|elm, acc| $acc | insert $elm $proxy} | load-env
}

def --env hide-proxy [] {
    ["http", "https", "all"] | each { $in + "_proxy"} | append ($in | str upcase) | filter { $in in $env } | hide-env ...$in
}

use std/dirs shells-aliases *
