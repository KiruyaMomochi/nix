{ caddy }:
let
  caddy-naive = caddy.overrideAttrs (oldAttrs: {
    pname = "caddy-naive";
    vendorHash = "sha256-/jykOd5pqT0TYIW9jAI70em4tO7PUcTO0LaOehbIqD0=";

    prePatch = ''
      sed -i -e '\!// plug in Caddy modules here!a _ "github.com/caddyserver/forwardproxy"' ./cmd/caddy/main.go
      cp ${./go.mod} go.mod
      cp ${./go.sum} go.sum
    '';

    # File permission test fails in sandbox due to different umask behavior
    doCheck = false;

    passthru = oldAttrs.passthru // {
      updateScript = ./update.sh;
      withPlugins = oldAttrs.passthru.withPlugins.override { caddy = caddy-naive; };
    };
  });
in
caddy-naive
