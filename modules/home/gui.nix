{ config, pkgs, ... }:
let
  msedge-override = { channel, version, sha256 }:
    with pkgs; let
      baseName = "microsoft-edge";
      revision = "1";
      shortName =
        if channel == "stable"
        then "msedge"
        else "msedge-" + channel;
      longName =
        if channel == "stable"
        then baseName
        else baseName + "-" + channel;
      iconSuffix =
        if channel == "stable"
        then ""
        else "_${channel}";
      desktopSuffix =
        if channel == "stable"
        then ""
        else "-${channel}";
    in
    {
      src = fetchurl {
        url = "https://packages.microsoft.com/repos/edge/pool/main/m/${baseName}-${channel}/${baseName}-${channel}_${version}-${revision}_amd64.deb";
        inherit sha256;
      };
      buildPhase =
        let
          libPath = {
            msedge = lib.makeLibraryPath [
              glibc
              glib
              nss
              nspr
              atk
              at-spi2-atk
              xorg.libX11
              xorg.libxcb
              cups.lib
              dbus.lib
              expat
              libdrm
              xorg.libXcomposite
              xorg.libXdamage
              xorg.libXext
              xorg.libXfixes
              xorg.libXrandr
              libxkbcommon
              gtk3
              pango
              cairo
              gdk-pixbuf
              mesa
              alsa-lib
              at-spi2-core
              xorg.libxshmfence
              systemd
              wayland
            ];
            naclHelper = lib.makeLibraryPath [
              glib
              nspr
              atk
              libdrm
              xorg.libxcb
              mesa
              xorg.libX11
              xorg.libXext
              dbus.lib
              libxkbcommon
            ];
            libwidevinecdm = lib.makeLibraryPath [
              glib
              nss
              nspr
            ];
            libGLESv2 = lib.makeLibraryPath [
              xorg.libX11
              xorg.libXext
              xorg.libxcb
              wayland
            ];
            libsmartscreen = lib.makeLibraryPath [
              libuuid
              stdenv.cc.cc.lib
            ];
            libsmartscreenn = lib.makeLibraryPath [
              libuuid
            ];
            liboneauth = lib.makeLibraryPath [
              libuuid
              xorg.libX11
            ];
          };
        in
        ''
          patchelf \
            --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
            --set-rpath "${libPath.msedge}" \
            opt/microsoft/${shortName}/msedge
  
          patchelf \
            --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
            opt/microsoft/${shortName}/msedge-sandbox
  
          patchelf \
            --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
            opt/microsoft/${shortName}/msedge_crashpad_handler
  
          patchelf \
            --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
            --set-rpath "${libPath.naclHelper}" \
            opt/microsoft/${shortName}/nacl_helper
  
          patchelf \
            --set-rpath "${libPath.libwidevinecdm}" \
            opt/microsoft/${shortName}/WidevineCdm/_platform_specific/linux_x64/libwidevinecdm.so
  
          patchelf \
            --set-rpath "${libPath.libGLESv2}" \
            opt/microsoft/${shortName}/libGLESv2.so
  
          # patchelf \
          #   --set-rpath "${libPath.libsmartscreen}" \
          #   opt/microsoft/${shortName}/libsmartscreen.so
  
          patchelf \
            --set-rpath "${libPath.libsmartscreenn}" \
            opt/microsoft/${shortName}/libsmartscreenn.so
  
          patchelf \
            --set-rpath "${libPath.liboneauth}" \
            opt/microsoft/${shortName}/liboneauth.so
        '';
    };
in
{
  nixpkgs.overlays = [
    (import ../../overlays/goldendict.nix)
  ];
  home.packages = with pkgs; [
    zotero
    (microsoft-edge.overrideAttrs (oldAttrs: msedge-override {
      channel = "stable";
      version = "110.0.1587.63";
      sha256 = "sha256-gMTKBmCA1nD48y4igdKoeuebfndfS9U13s/EHv7SdFk=";
    }))
    cascadia-code
    slack
    rustdesk
    libreoffice-qt
    hunspell
    filelight
    keepassxc
    (google-chrome.override {
      commandLineArgs = "--enable-features=WebUIDarkMode --force-dark-mode";
    })
    goldendict
  ];

  programs.vscode =
    let
      # generated = import ./vscode-extensions.nix;
      # extensions = pkgs.vscode-utils.extensionsFromVscodeMarketplace generated.extensions;
      # package = pkgs.vscode-with-extensions.override {
      #  vscodeExtensions = extensions;
      # };
      package = pkgs.vscode.fhs;
    in
    {
      inherit package;
      enable = true;
    };
}
