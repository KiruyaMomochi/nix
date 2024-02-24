{ inputs, lib, ... }:
let
  inherit (lib.attrsets) attrValues filterAttrs;
  inherit (lib.kyaru.modules) mapModules;
in
{
  imports = attrValues (filterAttrs (n: v: n != "all") (mapModules ./. lib.trivial.id));
}
