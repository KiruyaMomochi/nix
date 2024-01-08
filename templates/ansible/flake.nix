{
  description = "Ansible environment";

  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.kyaru.url = "github:KiruyaMomochi/nix";

  outputs = { self, nixpkgs, flake-utils, kyaru }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # pkgs = nixpkgs.legacyPackages.${system};
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            kyaru.overlay
          ];
        };

        python3 = pkgs.python3;
      in
      {
        devShells = {
          default = pkgs.mkShell {
            packages = with pkgs; [
              cowsay
              ansible
              ansible-lint
              python3Packages.molecule
              python3Packages.molecule-plugins
              python3Packages.ansible-builder
              python3Packages.ansible-runner
              sshpass
            ];
          };
        };
      });
}

