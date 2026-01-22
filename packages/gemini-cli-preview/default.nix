{ gemini-cli-bin
, fetchurl
, lib
, ripgrep
}:
gemini-cli-bin.overrideAttrs (finalAttrs: oldAttrs: {
  version = "0.27.0-nightly.20260122.61040d0eb";
  src = fetchurl {
    url = "https://github.com/google-gemini/gemini-cli/releases/download/v${finalAttrs.version}/gemini.js";
    hash = "sha256-74DoQLBPDawMmUv3vFKUAh/qhtbdBA7xhqICcjSyxtQ=";
  };
  installPhase = ''
    runHook preInstall

    install -D "$src" "$out/bin/gemini"

    # ideal method to disable auto-update
    sed -i '/disableautoupdate: {/,/}/ s/default: false/default: true/' "$out/bin/gemini"

    # use `ripgrep` from `nixpkgs`, more dependencies but prevent downloading incompatible binary on NixOS
    # this workaround can be removed once the following upstream issue is resolved:
    # https://github.com/google-gemini/gemini-cli/issues/11438
    substituteInPlace $out/bin/gemini \
      --replace-fail 'const existingPath = await resolveExistingRgPath();' 'const existingPath = "${lib.getExe ripgrep}";'

    runHook postInstall
  '';

})
