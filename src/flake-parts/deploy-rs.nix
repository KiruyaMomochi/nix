{ self, super, root, ... }: { withSystem, inputs, ... }:
# TODO: support patching package with only .patch files?
{
  perSystem = { system, pkgs, ... }: {
    _module.args.deployPkgs = import inputs.nixpkgs {
      # https://github.com/serokell/deploy-rs/blob/3867348fa92bc892eba5d9ddb2d7a97b9e127a8a/README.md?plain=1#L102-L107
      inherit system;
      overlays = [
        inputs.deploy-rs.overlay
        (self: super: { deploy-rs = { inherit (pkgs) deploy-rs; lib = super.deploy-rs.lib; }; })
      ];
    };
  };
  flake = {
    deploy.nodes =
      let
        mkDeployConfig = nixos:
          withSystem (nixos.pkgs.system) ({ deployPkgs, ... }:
            {
              hostname = nixos.config.networking.hostName;
              profiles.system = {
                user = "root";
                sshOpts = [ "-A" "-t" ];
                path = deployPkgs.deploy-rs.lib.activate.nixos nixos;
              } // (inputs.nixpkgs.lib.optionalAttrs
                (nixos.config.kyaru.vps.user ? name)
                { profiles.system.sshUser = nixos.config.kyaru.vps.user.name; });
            });
      in
      builtins.mapAttrs (_: mkDeployConfig) self.nixosConfigurations;
  };
}
