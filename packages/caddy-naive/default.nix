{ buildGoModule
, caddy
}:
caddy.override {
  buildGoModule = args: buildGoModule (args // {
    pname = "caddy-naive";
    vendorHash = "sha256-kXK5ps8+sfUU+nUH9pJZhawvuJs/7xSJJhy2dh12F24=";

    prePatch = ''
      sed -i -e '\!// plug in Caddy modules here!a _ "github.com/caddyserver/forwardproxy"' ./cmd/caddy/main.go
      cp ${./go.mod} go.mod
      cp ${./go.sum} go.sum
    '';

    passthru = {
      tests = caddy.passthru.tests;
      updateScript = ./update.sh;
    };
  });
}
