{ caddy, lib }:
let
  forwardproxy = "github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@v0.0.0-20261006113151-c096d6a00cb2";

  caddy-naive = (caddy.withPlugins {
    plugins = [ forwardproxy ];
    hash = "sha256-IbcMwA7ignwcgbYealJWERRvGuC3vnbhNjMmcq9s79A=";
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
