{ ... }:
{
  /*
    Like `mapAttrs'`, but any null results are removed.

    filterMapAttrs ::
      (String -> Any -> { name :: String; value :: Any; }) -> AttrSet -> AttrSet
  */
  filterMapAttrs' =
    # A function, given an attribute's name and value, returns a new `nameValuePair`.
    f:
    # Attribute set to map over.
    attrs:
      with builtins;
      let
        names = attrNames attrs;
        values = map (attr: f attr attrs.${attr}) names;
        filtered = filter (pair: pair != null) values;
      in
      listToAttrs filtered;
}
