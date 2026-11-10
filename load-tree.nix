{ lib }:
# Keep directory namespaces (including empty ones); optionally lift default.nix.
{ src, defaultOnly ? false, collapseDefaults ? false, loader ? import, transform ? (_: value: value) }:
let
  load = cursor: directory:
    let
      entries = lib.filterAttrs
        (name: type:
          !(lib.hasPrefix "_" name) && (
            type == "directory" ||
            (type == "regular" && lib.hasSuffix ".nix" name &&
              (!defaultOnly || name == "default.nix"))
          ))
        (builtins.readDir directory);
      rawTree = lib.mapAttrs'
        (name: type:
          let
            key = if type == "directory" then name else lib.removeSuffix ".nix" name;
            path = directory + "/${name}";
          in
          lib.nameValuePair key (
            if type == "directory" then load (cursor ++ [ key ]) path else loader path
          ))
        entries;
      tree =
        if builtins.length (builtins.attrNames rawTree) == builtins.length (builtins.attrNames entries)
        then rawTree
        else throw "Conflicting Nix file and directory names in ${toString directory}";
      value = if collapseDefaults && tree ? default then tree.default else tree;
    in
    transform cursor value;
in
load [ ] src
