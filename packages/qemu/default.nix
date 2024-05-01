{ qemu
}:
qemu.overrideAttrs (oldAttrs: {
  patches = oldAttrs.patches ++ [
    # https://listman.redhat.com/archives/vfio-users/2019-February/004819.html
    ./spoof-pci-class-code.patch
    ./disable-igd-vga-check.patch
  ];
})
