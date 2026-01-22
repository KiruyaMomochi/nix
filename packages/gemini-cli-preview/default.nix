{ gemini-cli-bin
, fetchurl
}:
gemini-cli-bin.overrideAttrs (finalAttrs: oldAttrs: {
  version = "0.26.0-preview.1";
  src = fetchurl {
    url = "https://github.com/google-gemini/gemini-cli/releases/download/v${finalAttrs.version}/gemini.js";
    hash = "sha256-dgaQQ3N3phS18JYpccVe6V+dtV1FKW/BB0IWOuqItHo=";
  };
})
