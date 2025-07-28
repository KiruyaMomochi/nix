{ self, super, root, ... }: { inputs, ... }:
# TODO: support patching package with only .patch files?
{
  perSystem = { system, pkgs, deployPkgs, ... }: {
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        sops
        age
        ssh-to-age
        ssh-to-pgp
        jq
        yq
        deployPkgs.deploy-rs.deploy-rs
        act
        yaml-language-server
        nix-fast-build
        nix-eval-jobs
      ];
    };
  };
  flake = { };
}
