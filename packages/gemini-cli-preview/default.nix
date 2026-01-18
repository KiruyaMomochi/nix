{ gemini-cli-bin
, fetchurl
}:
gemini-cli-bin.overrideAttrs (finalAttrs: oldAttrs: {
  version = "0.25.0-preview.0";
  src = fetchurl {
    url = "https://github.com/google-gemini/gemini-cli/releases/download/v${finalAttrs.version}/gemini.js";
    hash = "sha256-tvUt31bTPkLQCOba1eWP1QGml/G9cQQnzmFn44QSK2k=";
  };
})
