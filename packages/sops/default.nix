{ sops, fetchFromGitHub, buildGoModule }:
let
  attrs = {
    version = "v3.8.0-rc-lookupconfig-20230909";
    src = fetchFromGitHub {
      rev = "path";
      owner = "KiruyaMomochi";
      repo = "sops";
      sha256 = "sha256-i3XlQeZpRm8EoUgrnCKiiPn7Rvs+wIdFtpeAi68YMQ0=";
    };
    vendorSha256 = "sha256-FsmM1zIsB6BXMwMivvjGU/ISayrYyV1M9lU6LUE9dWE=";
  };
in
sops.override {
  buildGoModule = super: buildGoModule (super // attrs);
}

