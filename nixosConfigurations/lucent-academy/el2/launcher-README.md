# Entry-scoped EL2 launcher

`launcher.nix` builds `lib/efi/lucent-el2-launcher.efi`, an **unsigned AArch64
EFI application**, using native LLVM to emit PE/COFF directly. It works on an
x86_64 build host; no ARM Linux toolchain, emulator or remote builder is needed.
It does not install anything, sign images, or modify the boot configuration.

## Package interface

```nix
pkgs.callPackage ./el2/launcher.nix {
  # GPT partition UUID of XBOOTLDR (/boot), NOT its FAT filesystem UUID.
  bootPartuuid = "11111111-2222-3333-4444-555555555555"; # example only
  ukiPath = "/EFI/nixos/generation-N-specialisation-el2-cxsd.efi";
  # Defaults, override to match the installer's experiment directory:
  qebspilPath = "/EFI/el2/qebspilaa64.efi";
  slbouncePath = "/EFI/el2/slbounceaa64.efi";
}
```

Paths use `/` at the Nix interface and become UEFI `\` paths. They are absolute,
ASCII `.efi` filenames with no empty, `.` or `..` components. Use a unique UKI
filename per generation and compile/sign a new launcher for that generation.
The required arguments deliberately have no machine-specific defaults.

For a standalone **validation-only build** using the private flake's pinned
nixpkgs (run on caon; this does not build or deploy a NixOS system):

```sh
nix build --impure --no-link --print-out-paths --expr '
  let
    secret = builtins.getFlake "/home/kyaru/Projects/nix-kyaru-secret";
    pkgs = import secret.inputs.nix-kyaru.inputs.nixpkgs { system = "x86_64-linux"; };
  in pkgs.callPackage /home/kyaru/Projects/nix/nixosConfigurations/lucent-academy/el2/launcher.nix {
    bootPartuuid = "11111111-2222-3333-4444-555555555555";
    ukiPath = "/EFI/nixos/validation-only-el2.efi";
  }'
```

That example intentionally cannot find the real XBOOTLDR. Integration must pass
the real partition UUID and the exact final specialisation UKI filename. Read
`findmnt -no SOURCE /boot` and `lsblk -o NAME,PARTUUID,MOUNTPOINTS` on the target.
`share/lucent-el2-launcher/routing.json` records the inputs for installer checks;
it is **build metadata only**, never read by the EFI application.

## Firmware sequence and trust boundary

1. Disable the firmware boot watchdog. Require `SecureBoot=1`, `SetupMode=0`.
2. Use our `LoadedImage.DeviceHandle` as the ESP filesystem identity.
3. Enumerate Simple File System handles and find the compiled GPT PARTUUID in
   their hard-drive device-path node. Require one match, distinct from the ESP;
   never choose the first FAT volume, use a label, or assume `/boot` is the ESP.
4. Construct full device paths (volume path + FilePath + End), then call firmware
   `LoadImage(FALSE, parent, path, NULL, 0, ...)` for qebspil, slbounce and the UKI.
   Firmware performs image authentication. Validate each child's filesystem
   identity and image code type. Each image is started before loading the next:
   qebspil first, then slbounce, then the UKI. This preserves the usual
   driver-before-OS allocation/hook order (including slbounce's launch buffers).
5. UKI DT installation happens after both drivers start. There is no EBS call in
   this launcher. A failed UKI load occurs with driver hooks already installed;
   the only supported recovery is a reset, never a return to the menu.
6. Any error, warning or UKI return (even success) prints a status and stops in a
   firmware Stall loop. It does not Exit, return to systemd-boot, unload drivers,
   reboot automatically, or offer another OS in a contaminated EFI session.

Child load options are explicitly cleared. Parent options, loader entry
`options`, external configuration and EFI routing variables are never consulted.
Device paths and successful driver images stay alive for the whole boot.
No `ALWAYS_SWITCH` / `ALWAYS_START` behavior is added.

The final launcher **and both drivers must be signed** with the enrolled db key;
the UKI must also be signed. Signing is an authorized installer operation, not a
Nix build step: private keys must never enter the store. The entry on the ESP
uses `efi /EFI/.../<generation-launcher>.efi` (not `uki` and not a driver). Do not
install either experiment driver in systemd-boot's global `drivers/` directory.
The TCB and firmware still live on that ESP at the locations the drivers expect.

This binds the partition/path, not the contents of all externally loaded files.
Firmware db trust still allows another authorized signed image at a compiled
path; this is not a UKI hash allowlist or rollback protection. DSP firmware/TCB
validation remains the drivers'/platform's responsibility, not this launcher's.
The PARTUUID is an identifier, not cryptographic authentication; duplicate
matching filesystem handles fail closed rather than silently picking one.

## Verification and remaining hardware test

Every build checks the emitted PE machine (`0xaa64`), EFI application subsystem,
entry point, relocations and absence of DLL imports. Compile-time assertions
check 64-bit UINTN, UTF-16 CHAR16 and file-path node layout. GPT nodes are parsed
as their 42-byte wire representation, not gnu-efi's unpacked C structure.
Host-side firmware mocks check successful routing/start order, all three
LoadImage rejection points, both driver failures and UKI failure/return,
missing/duplicate PARTUUID, Secure Boot off, mismatched DeviceHandle, cleared
child options and malformed device-path rejection.

These are not a real UEFI integration test. The unresolved parts are firmware
image authentication/device-path resolution across ESP and XBOOTLDR, qebspil /
slbounce callbacks with the actual signed UKI, and the EL2/EBS transition. A real
launch must wait for an attended experiment with a known-good EL1 fallback.
If stopped, reset the machine before trying a normal OS entry.
