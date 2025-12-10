{ self, super, root, ... }: { withSystem, inputs, ... }:
# TODO: support patching package with only .patch files?
let
  # Copy-paste from nixosConfigurations.nix
  # TODO: Refactor this into a shared library
  loader = inputs.haumea.lib.loaders.verbatim;
  matcher = { inherit loader; matches = filename: filename == "default.nix"; };
  transformer = cursor: module:
    let
      depth = builtins.length cursor;
    in
    if depth == 0 then module
    else if depth == 1 then (module.default or null)
    else null;

  hosts = inputs.haumea.lib.load {
    src = ../nixosConfigurations;
    loader = [ matcher ];
    transformer = [ transformer ];
  };

  pkgsOf = system: withSystem system ({ pkgs, ... }: pkgs);

  systemOverride = hostname: {
    "lucent-academy" = "aarch64-linux";
  }.${hostname} or "x86_64-linux";
in
{
  flake = {
    colmenaHive = inputs.colmena.lib.makeHive ({
      meta = {
        nixpkgs = pkgsOf "x86_64-linux";
        nodeNixpkgs = builtins.mapAttrs (_: pkgsOf) {
          "lucent-academy" = "aarch64-linux";
        };
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
