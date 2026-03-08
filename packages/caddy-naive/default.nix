{ caddy }:
let
  caddy-naive = caddy.overrideAttrs (oldAttrs: {
    pname = "caddy-naive";
    vendorHash = "sha256-zjVy3+sd4z9Jcq7kusLIF8opC7/hBR5q0alZdrwZCHg=";

    prePatch = ''
      sed -i -e '\!// plug in Caddy modules here!a _ "github.com/caddyserver/forwardproxy"' ./cmd/caddy/main.go
      cp ${./go.mod} go.mod
      cp ${./go.sum} go.sum
    '';

    passthru = oldAttrs.passthru // {
      updateScript = ./update.sh;
      withPlugins = oldAttrs.passthru.withPlugins.override { caddy = caddy-naive; };
    };
  });
in
caddy-naive
