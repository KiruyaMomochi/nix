{ self, super, root, ... }: { inputs, ... }:
# TODO: support patching package with only .patch files?
let
  mkCallPackaage = pkgs: set: {
    # default = a: b: (builtins.trace pkgs (pkgs.callPackage a b));
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
    src = ../../packages;
    loader = [ matcher ];
    transformer = [ (moduleToPackageSpec pkgs) callEachPackage ];
  };
in
{
  perSystem = { system, pkgs, ... }: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = [ inputs.self.overlays.default ];
      config = import ../../nixpkgs-config.nix;
    };
    packages = mkPackages pkgs;
  };
  flake = rec {
    overlay = overlays.default;
    overlays = {
      default = (final: prev: {
        kyaru = mkPackages final;
        slirp4netns = prev.slirp4netns.overrideAttrs (oldAttrs: {
          patches = (oldAttrs.patches or [ ]) ++ [
            ../../packages/slirp4netns.patch
          ];
        });
        pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
          (
            python-final: python-prev: {
              # Remove after https://github.com/NixOS/nixpkgs/pull/382920 is merged
              rapidocr-onnxruntime = python-prev.rapidocr-onnxruntime.overridePythonAttrs (old: {
                disabledTests = final.lib.throwIf (builtins.elem "test_ort_dml_warning" old.disabledTests) "test_ort_dml_warning is already in disabledTests, remove the patch!" (old.disabledTests ++ final.lib.optionals final.onnxruntime.cudaSupport [
                  # segfault when built with cuda support but GPU is not availaible in build environment
                  "test_ort_cuda_warning"
                  "test_ort_dml_warning"
                ]);
              });
            }
          )
        ];
      });
    };
  };
}
