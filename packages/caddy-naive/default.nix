{ buildGoModule
, caddy
}:
caddy.override {
  buildGoModule = args: buildGoModule (args // {
    pname = "caddy-naive";
    vendorHash = "sha256-OoS8M1ywug+O1auat6RHBKf5UXAbwzURSHnR2SInrfM=";

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
