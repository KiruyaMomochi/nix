{ self, lib, ... }:
let
  inherit (lib.attrsets) nameValuePair filterAttrs mapAttrs';
  inherit (lib.strings) hasPrefix hasSuffix removeSuffix;
  inherit (self.attrs) filterMapAttrs';
in
{
  /*
    Apply a function to path to each module in a directory,
    returning a new attribute set.

    mapModules ::
      String -> (String -> String) -> { name :: String; value :: String; }
  */
  mapModules =
    # Directory to map over.
    directory:
    # Function to apply to each module. To remove a module, return null.
    fn:
    filterMapAttrs'
      (
        # filename :: String
        # type :: "regular" | "directory" | "symlink" | "unknown"
        filename: type:
        let
          path = "${toString directory}/${filename}";
          module =
            if lib.hasPrefix "_" filename then null
            else if type == "directory" && builtins.pathExists "${path}/default.nix"
            then nameValuePair filename (fn path)
            else if type == "regular" && filename != "default.nix" && hasSuffix ".nix" filename
            then nameValuePair (removeSuffix ".nix" filename) (fn path)
            else null;
        in
        if module == null then null
        else if module.value == null then null
        else module
      )
      (builtins.readDir directory);
}
