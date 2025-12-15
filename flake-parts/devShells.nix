{ self, super, root, ... }: { inputs, ... }:
# TODO: support patching package with only .patch files?
{
  perSystem = { system, pkgs, ... }: {
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        sops
        age
        ssh-to-age
        ssh-to-pgp
        jq
        yq
        act
        (inputs.colmena.packages.${system}.colmena)
        yaml-language-server
        nix
        nix-fast-build
        nix-eval-jobs
      ];
    };
  };
  flake = { };
}
