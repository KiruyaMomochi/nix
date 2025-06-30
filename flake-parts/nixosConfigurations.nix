{ self, super, root, flake, ... }: { inputs, ... }:
let
  inherit (flake.lib.nixos) mkHost;

  loader = inputs.haumea.lib.loaders.verbatim;
  matcher = { inherit loader; matches = filename: filename == "default.nix"; };
  transformer = cursor: module:
    let
      depth = builtins.length cursor;
    in
    if depth == 0 then module
    else if depth == 1 then (module.default or null)
    else null;
  # hosts.xxx -> nixosConfigurations/xxx/default.nix
  hosts = inputs.haumea.lib.load {
    src = ../nixosConfigurations;
    loader = [ matcher ];
    transformer = [ transformer ];
  };

  # TODO: refactor this to use lib/nixos.nix
  systemOverride = hostname: {
    "lucent-academy" = "aarch64-linux";
  }.${hostname} or "x86_64-linux";
in
{
  flake = {
    nixosConfigurations = builtins.mapAttrs
      (hostname: config: mkHost (systemOverride hostname) hostname config)
      hosts;
  };
}
