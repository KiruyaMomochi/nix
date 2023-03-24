self: super:

{
  goldendict = (super.goldendict.override {
    qtwebkit = null;
  }).overrideAttrs (oldAttrs: rec {
    version = "23.02.07-alpha.230318.3cb17825";
    src = self.fetchFromGitHub {
      owner = "xiaoyifang";
      repo = "goldendict";
      rev = "v${version}";
      sha256 = "sha256-bcoMnqH9vwrfM4LizGcKCWQsKQhE2MxVcYsiPtJvZ6M=";
    };
    postPatch = "";
    buildInputs = oldAttrs.buildInputs ++ (with super.libsForQt5.qt5; [
      qtwebengine
      qtwebchannel
      qtmultimedia
    ]);
    # buildInputs = super.lib.lists.remove super.qtwebkit oldAttrs.buildInputs;
  });
}
