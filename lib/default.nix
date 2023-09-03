{ inputs, lib, ... }:
let
  inherit (lib.fixedPoints) makeExtensible;
  inherit (modules) mapModules;

  # manually import modules.nix to avoid infinite recursion
  modules = import ./modules.nix {
    inherit lib;
    self.attrs = import ./attrs.nix {
      inherit lib; self = { };
    };
  };

  kyaru = makeExtensible
    (self: mapModules
      ./.
      (file: import file { inherit self lib inputs; })
    );
in
kyaru
