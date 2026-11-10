{ inputs, ... }:
let
  lib = inputs.nixpkgs.lib;
  loadTree = import ../load-tree.nix { inherit lib; };
  library = lib.mapAttrs
    (name: path: import path {
      inherit inputs lib;
      self = library.${name};
      super = library;
    })
    (loadTree { src = ../lib; loader = path: path; });
in
{
  flake = {
    nixosModules = loadTree { src = ../nixosModules; };
    homeModules = loadTree { src = ../homeModules; collapseDefaults = true; };
    lib = library;
    templates = import ../templates;
    patches = import ../patches.nix;
  };
  perSystem = { pkgs, ... }: {
    formatter = pkgs.nixpkgs-fmt;
  };
}
