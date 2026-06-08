# libcronet-naive Build Notes

Builds the cronet shared library using chromium's `mkChromiumDerivation` with NaiveProxy source overlay.

## Common Upgrade Issues

### 1. LLVM compat patch hunk failures

nixpkgs chromium ships `chromium-*-llvm-22.patch` to fix flags unrecognized by newer LLVM. After NaiveProxy overlay, `build/config/compiler/BUILD.gn` differs from upstream (extra `&& !is_apple` clauses etc.), so hunks fail to apply.

**Fix**: Filter all llvm-22 patches by suffix, don't hardcode version number:
```nix
patches = lib.filter (
  p: !(lib.hasSuffix "llvm-22.patch" (p.name or (toString p)))
) base.patches;
```

### 2. substituteInPlace target missing

Naive upstream may have already removed certain flags (e.g. `-fno-lifetime-dse`), causing our substituteInPlace to fail on match.

**Fix**: Use `--replace-warn` instead of `--replace-fail`:
```nix
substituteInPlace build/config/compiler/BUILD.gn \
  --replace-warn 'cflags += [ "-fno-lifetime-dse" ]' '# stripped for LLVM compat'
```

### 3. Upgrade checklist

On chromium major version bumps (147→148→149...):
1. `nix build` — check if patch phase has any FAILED hunks
2. Verify patch filter still matches (suffix matching avoids this)
3. Check if postPatch substituteInPlace targets still exist in naive's BUILD.gn

## Pitfalls

- chromium's `base.patches` changes every major version — hardcoding patch names will break
- naive's prePatch must run before chromium patches (overlays source first, then chromium patches land on top)
