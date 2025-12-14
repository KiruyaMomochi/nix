{ self, super, root, flake, ... }: { withSystem, inputs, ... }:
# TODO: support patching package with only .patch files?
let
  inherit (flake.lib.nixos) loadHosts systemOverride;

  hosts = loadHosts ../nixosConfigurations;
  pkgsOf = system: withSystem system ({ pkgs, ... }: pkgs);
in
{
  flake = {
    colmenaHive = inputs.colmena.lib.makeHive ({
      meta = {
        nixpkgs = pkgsOf "x86_64-linux";
        nodeNixpkgs = builtins.mapAttrs (name: _: pkgsOf (systemOverride name)) hosts;
        specialArgs = { inherit inputs; };
      };

      defaults = { name, config, lib, ... }: {
        networking.hostName = name;

        deployment = {
          targetUser = lib.mkIf (config.kyaru.vps.user ? name) config.kyaru.vps.user.name;
        };
      };
    } // (builtins.mapAttrs
      (name: module: {
        imports = [
          ../nixosModules/kyaru/default.nix
          module
        ];
      })
      hosts));
  };
}
