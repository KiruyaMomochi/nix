{ self, super, root, ... }: { inputs, ... }: {
  # We can also define custom flake attribute here
  # https://flake.parts/define-custom-flake-attribute.html
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
      src = ../lib;
      inputs = {
        inherit inputs;
        lib = inputs.nixpkgs.lib;
      };
    };
    templates = import ../templates;
    checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) inputs.deploy-rs.lib;
  };
  perSystem = (
    # module arguments
    { pkgs, deployPkgs, ... }:
    {
      formatter = pkgs.nixpkgs-fmt;
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          sops
          age
          ssh-to-age
          ssh-to-pgp
          jq
          yq
          deployPkgs.deploy-rs.deploy-rs
        ];
      };
    }
  );

}
