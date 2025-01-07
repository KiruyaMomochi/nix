{ self, super, root, ... }: { inputs, flake, ... }:
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
  hosts = inputs.haumea.lib.load {
    src = ../../nixosConfigurations;
    loader = [ matcher ];
    transformer = [ transformer ];
  };
  mkSystem = hostname: defaultConfig: inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
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
