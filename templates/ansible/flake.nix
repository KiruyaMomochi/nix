{
  description = "Ansible environment";

  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
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

