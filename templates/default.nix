builtins.listToAttrs (builtins.filter
  (x: x != null)
  (builtins.attrValues
    (builtins.mapAttrs
      (
        name: value:
        if value == "directory" then
          {
            name = name;
            value = {
              path = ./. + "/${name}";
              description = (import ./${name}/flake.nix).description;
            };
          }
        else null
      )
      (builtins.readDir ./.)
    )))
