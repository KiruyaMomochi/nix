{ sops, fetchFromGitHub, buildGoModule }:
let
  attrs = {
    version = "v3.8.0-lookupconfig-20231003";
    src = fetchFromGitHub {
      rev = "path";
      owner = "KiruyaMomochi";
      repo = "sops";
      sha256 = "sha256-1XmvHSrmtalyk15NkcAsiENZKF8blBSz7GZKxVDffbA=";
    };
    vendorHash = "sha256-/fh6pQ7u1icIYGM4gJHXyDNQlAbLnVluw5icovBMZ5k=";
  };
in
sops.override {
  buildGoModule = super: buildGoModule (super // attrs);
}

