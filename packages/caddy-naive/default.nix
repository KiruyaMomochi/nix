{ buildGoModule
, caddy
}:
let
  version = caddy.version;
in
buildGoModule {
  pname = "caddy-naive";
  inherit version;
  # warning: `-buildid=` is set by default as ldflag by buildGoModule
  inherit (caddy) ldflags nativeBuildInputs postInstall meta;
  src = caddy.src + "/cmd/caddy";

  vendorHash = "sha256-20o120C4ukRbjK2RxhrukdcNJ20kJ6/BQSHYneiqp8o=";

  prePatch = ''
    sed -i -e '\!// plug in Caddy modules here!a _ "github.com/caddyserver/forwardproxy"' ./main.go
    cp ${./go.mod} go.mod
    cp ${./go.sum} go.sum
  '';

  passthru = {
    tests = caddy.passthru.tests;
    updateScript = ./update.sh;
  };
}
