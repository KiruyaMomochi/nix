{ buildGoModule
, caddy
}:
let
  version = caddy.version;
in
buildGoModule {
  pname = "caddy-naive";
  inherit version;
  inherit (caddy) ldflags nativeBuildInputs postInstall meta;
  src = caddy.src + "/cmd/caddy";

  vendorHash = "sha256-AvpA9xUqYRgvU6/9DOnJx90gKwzTyqZBxR1j5KudAAg=";

  prePatch = ''
    cp ${./go.mod} go.mod
    cp ${./go.sum} go.sum
  '';

  passthru = {
    tests = caddy.passthru.tests;
    updateScript = ./update.sh;
  };
}
