{ self, inputs, lib, ... }:
let
  inherit (lib.strings) removeSuffix;
  inherit (lib.modules) mkDefault;
  inherit (lib.attrsets) filterAttrs;
  inherit (lib.kyaru.modules) mapModules;
  inherit (builtins) baseNameOf;

  defaultSystem = inputs.flake-utils.lib.system.x86_64-linux;
in
{
  mkHost = path: attrs @ { system ? defaultSystem, ... }:
    lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; };
      modules = [
        {
          nixpkgs.overlays = [ inputs.self.overlay ];
          networking.hostName = mkDefault (removeSuffix ".nix" (baseNameOf path));
        }
        (filterAttrs (name: value: name != "system") attrs)
        ../hosts/default.nix
        (import path)
      ];
    };
  
  mapHosts = directory: attrs @ { system ? defaultSystem, ... }:
    mapModules directory (hostPath: self.nixos.mkHost hostPath attrs);
}
