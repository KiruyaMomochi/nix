{ self, super, root, ... }: { inputs, pkgs, ... }:
# TODO: support patching package with only .patch files?
let
  mkCallPackaage = pkgs: set: {
    default = pkgs.callPackage;
    qt5 = pkgs.libsForQt5.callPackage;
  }."${set}";

  # loader = attrs: path: (builtins.trace "path = ${path}" (haumea.lib.loaders.verbatim attrs path));
  # loader = attrs: path: (path);

  loader = attrs: path: (inputs.haumea.lib.loaders.verbatim attrs path);
  matcher = { inherit loader; matches = filename: filename == "default.nix"; };

  # find how to callPackage
  cursorToPackage = pkgs: cursor: package:
    let
      depth = builtins.length cursor;
      set = if depth == 0 then null else if depth == 1 then "default" else (builtins.elemAt cursor 0);
      callPackage = mkCallPackaage pkgs set;
    in
    {
      inherit package set callPackage;
    };

  # transformers
  moduleToPackageSpec = pkgs: cursor: module:
    # builtins.trace "depth = ${builtins.toString depth}, cursor = ${builtins.toString cursor}, set = ${builtins.toString set}"
    if module ? default then (cursorToPackage pkgs cursor module.default) else module;
  callEachPackage = cursor: module:
    if module ? package then (module.callPackage module.package { }) else module;

  mkPackages = pkgs: inputs.haumea.lib.load {
    src = ../../../packages;
    loader = [ matcher ];
    transformer = [ (moduleToPackageSpec pkgs) callEachPackage ];
  };
in
{
  perSystem = {
    packages = mkPackages pkgs;
  };
  flake = rec {
    overlay = overlays.default;
    overlays = {
      default = (final: prev: {
        kyaru = mkPackages final;
        slirp4netns = prev.slirp4netns.overrideAttrs (oldAttrs: {
          patches = (oldAttrs.patches or [ ]) ++ [
            ../../../packages/slirp4netns.patch
          ];
        });
        pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
          (
            python-final: python-prev: { }
          )
        ];
      });
    };
  };
}
