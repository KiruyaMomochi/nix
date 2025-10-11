{ buildGoModule
, caddy
}:
caddy.override {
  buildGo125Module = args: buildGoModule (args // {
    pname = "caddy-naive";
    vendorHash = "sha256-NLnPeGw1gsCYvP3e0yL8hMH3NE3084/+8Am6mv56MRo=";

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
