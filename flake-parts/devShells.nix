{ self, inputs, ... }:
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
        yaml-language-server
        nix
        nix-fast-build
        nix-eval-jobs
        attic-client
        just
      ];
    };
  };
  flake = { };
}
