{ self, super, root, flake, ... }: { inputs, ... }:
let
  inherit (flake.lib.nixos) mkHost loadHosts systemOverride;

  # hosts.xxx -> nixosConfigurations/xxx/default.nix
  hosts = loadHosts ../nixosConfigurations;
in
{
  flake = {
    nixosConfigurations = builtins.mapAttrs
      (hostname: config: mkHost (systemOverride hostname) hostname config)
      hosts;
  };
}
