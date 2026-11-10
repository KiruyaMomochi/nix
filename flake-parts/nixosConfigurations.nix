{ self, inputs, ... }:
let
  inherit (self.lib.nixos) mkHost loadHosts systemOverride;

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
