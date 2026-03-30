{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.kyaru.carapace;
  inherit (lib)
    types
    mkOption
    mapAttrs'
    nameValuePair
    ;
in
{
  options.programs.kyaru.carapace = {
    choices = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        sed = "sed@bsd";
        tldr = "tldr/tldr-python-client";
      };
      description = "Carapace choices. Attribute name is the command, value is the choice spec.";
    };

    bridges = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        nix = "fish";
        ssh = "fish";
      };
      description = "Carapace bridge choices. Attribute name is the command, value is the bridge to use.";
    };
  };

  config.xdg.configFile =
    # choices: name -> spec as-is
    mapAttrs' (name: spec: nameValuePair "carapace/choices/${name}" { text = spec; }) cfg.choices
    //
      # bridges: name -> {name}/{bridge}@bridge
      mapAttrs' (
        name: bridge: nameValuePair "carapace/choices/${name}" { text = "${name}/${bridge}@bridge"; }
      ) cfg.bridges;
}
