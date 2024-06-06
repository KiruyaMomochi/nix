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
            };
          }
        else null
      )
      (builtins.readDir ./.)
    )))
