{ inputs, lib, ... }:
let
  inherit (lib.attrsets) attrValues filterAttrs;
  inherit (inputs.self.lib.kyaru.modules) mapModules;
in
{
  # home modules is not imported because it does not contains default.nix
  imports = attrValues (filterAttrs (n: v: n != "all") (mapModules ./. lib.trivial.id));
}
