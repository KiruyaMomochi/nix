{ caddy, lib }:
let
  forwardproxy = "github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@v0.0.0-20250118002110-d62c80d3dd2c";

  caddy-naive = (caddy.withPlugins {
    plugins = [ forwardproxy ];
    hash = "sha256-4y62pkDnDFstlejBOyml+ZW0l/fCq7Mok+2TqLC+yZk=";
  }).overrideAttrs (oldAttrs: {
    pname = "caddy-naive";

    passthru = oldAttrs.passthru // {
      updateScript = ./update.sh;
      withPlugins =
        {
          plugins,
          hash ? lib.fakeHash,
          doInstallCheck ? true,
        }:
        caddy.withPlugins {
          plugins = [ forwardproxy ] ++ plugins;
          inherit hash doInstallCheck;
        };
    };
  });
in
caddy-naive
