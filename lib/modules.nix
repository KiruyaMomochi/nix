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
      String -> (String -> Any) -> { name :: String; value :: Any; }
  */
  mapModules =
    # Directory to map over.
    directory:
    # Function to apply to each module. To remove a module, return null.
    fn:
    let
      directoryToModule =
        # filename :: String
        # type :: "regular" | "directory" | "symlink" | "unknown"
        filename: type:
        let
          path = "${toString directory}/${filename}";
          module =
            # Remove files begin with _
            if lib.hasPrefix "_" filename then null
            # Add directories with a default.nix
            else if type == "directory" && builtins.pathExists "${path}/default.nix"
            then nameValuePair filename (fn path)
            # Add regular files ending with .nix
            else if type == "regular" && filename != "default.nix" && hasSuffix ".nix" filename
            then nameValuePair (removeSuffix ".nix" filename) (fn path)
            # Ignore everything else
            else null;
        in
        if module == null then null
        else if module.value == null then null
        else module;
    in
    filterMapAttrs' directoryToModule (builtins.readDir directory);

  mapModulesRecursive =
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
            # Remove files begin with _
            if lib.hasPrefix "_" filename then null
            # Add directories with a default.nix
            else if type == "directory" && builtins.pathExists "${path}/default.nix"
            then nameValuePair filename (fn path)
            # Recurse into directories
            else if type == "directory"
            then nameValuePair filename (self.modules.mapModulesRecursive path fn)
            # Add regular files ending with .nix
            else if type == "regular" && filename != "default.nix" && hasSuffix ".nix" filename
            then nameValuePair (removeSuffix ".nix" filename) (fn path)
            # Ignore everything else
            else null;
        in
        if module == null then null
        else if module.value == null then null
        else module
      )
      (builtins.readDir directory);
}
