{ self, super, root, flake, ... }: { inputs, ... }:
let
  inherit (inputs.nixpkgs.lib) mkDefault filterAttrs;

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
    src = ../../nixosConfigurations;
    loader = [ matcher ];
    transformer = [ transformer ];
  };

  # TODO: refactor this to use src/lib/nixos.nix
  systemOverride = {
    "lucent-academy" = "aarch64-linux";
  };
  mkSystem = hostname: defaultConfig: inputs.nixpkgs.lib.nixosSystem {
    system = systemOverride.${hostname} or "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules = [
      {
        nixpkgs.overlays = [ inputs.self.overlay ];
        networking.hostName = mkDefault hostname;
      }
      defaultConfig
      # maybe import all flake.nixosModules here, but currently manually importing with default.nix
      ../../nixosModules/kyaru/default.nix
    ];
  };
in
{
  flake = {
    nixosConfigurations = builtins.mapAttrs mkSystem hosts;
  };
}
