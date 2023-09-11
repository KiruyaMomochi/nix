{
  description = "A basic flake with a terraform environment";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        terraform = pkgs.terraform.withPlugins (ps: with ps; [ ]);
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ terraform terraform-docs tfupdate ];
        };
      });
}
