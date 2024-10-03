{ self, super, root, ... }: { inputs, ... }: {
  # flake.nixosModules = inputs.haumea.lib.load {
  #   src = ../modules;
  #   loader = args: path: import path;
  #   transformer = [ inputs.haumea.lib.transformers.liftDefault ];
  # };
  flake = {
    nixosModules = inputs.haumea.lib.load {
      src = ../../nixosModules;
      loader = inputs.haumea.lib.loaders.verbatim;
    };
    homeModules = inputs.haumea.lib.load {
      src = ../../homeModules;
      loader = inputs.haumea.lib.loaders.verbatim;
    };
    lib = inputs.haumea.lib.load {
      src = ../lib              ;
      inputs = {
        lib = inputs.nixpkgs.lib;
      };
    };
  };
}
