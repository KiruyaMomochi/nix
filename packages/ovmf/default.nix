{ OVMFFull
, edk2
}:
let
  edk2Patched =
    let
      # https://projectacrn.github.io/latest/tutorials/gpu-passthru.html
      # Insert Gop into Components of dsc and FV.DXEFV of fdf
      intelGopPatches = [
        # https://projectacrn.github.io/latest/_static/downloads/Use-the-default-vbt-released-with-GOP-driver.patch
        ./Use-the-default-vbt-released-with-GOP-driver.patch
        # https://projectacrn.github.io/latest/_static/downloads/Integrate-IntelGopDriver-into-OVMF.patch
        ./Integrate-IntelGopDriver-into-OVMF.patch
        # https://wiki.archlinux.org/title/Intel_GVT-g#Using_DMA-BUF_with_UEFI/OVMF
        ./OvmfPkg-add-IgdAssignmentDxe.patch
        # Mainly https://github.com/tianocore/edk2/compare/master...johnmave126:edk2:intel-gop-patch
        ./acrn-edk2-gop.patch
      ];
    in
    edk2.overrideAttrs (oldAttrs: newAttrs: {
      patches = oldAttrs.patches ++ intelGopPatches;
      postPatch = (oldAttrs.postPatch or "") + ''
        # Add Intel EFI
        cp ${./IntelGopDriver.efi} OvmfPkg/IntelGop/IntelGopDriver.efi
        cp ${./Vbt.bin} OvmfPkg/Vbt/Vbt.bin
      '';
    });
in
(OVMFFull.override
{
  edk2 = edk2Patched;
  # Disable systemManagementModeRequired as legacy gvt-d require i440fx
  # However, i440fx does not support SMM
  # This may affect S3 suspend, but it's not a big issue for our virtual environment
  systemManagementModeRequired = false;
})
