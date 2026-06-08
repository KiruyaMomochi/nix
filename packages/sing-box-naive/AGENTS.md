# sing-box-naive Build Notes

Overrides nixpkgs sing-box with `with_naive` build tag, linked against our own `libcronet-naive` shared library.

## cronet-go force-push problem

sagernet/cronet-go gets force-pushed (commits disappear from GitHub). Go module proxy still has cached zips, but GOPROXY's `,direct` fallback tries to validate the commit against GitHub and fails.

**Symptom**:
```
go: github.com/sagernet/cronet-go@v0.0.0-...-HASH: invalid version: unknown revision HASH
```

**Fix**: Strip `,direct` in `preBuild`, append `proxy.golang.org` as fallback:
```nix
proxyVendor = true;

preBuild = ''
  export GOPROXY="''${GOPROXY:-https://proxy.golang.org}"
  GOPROXY="$(echo "$GOPROXY" | sed 's/,direct//g')"
  case "$GOPROXY" in
    *proxy.golang.org*) ;;
    *) GOPROXY="$GOPROXY,https://proxy.golang.org" ;;
  esac
  export GOPROXY
'';
```

**Do NOT touch go.mod**:
- `cronet-go/all`: sing-box source directly imports it
- `cronet-go/lib/linux_amd64`: imported by `cronet-go/all` via build-tagged code
- Removing them passes the FOD phase (download-only) but breaks the main build with `missing go.sum entry`

## buildGoModule FOD attr propagation

Attrs that propagate from `overrideAttrs` into the go-modules FOD:
- `patches` ✓
- `prePatch` ✓
- `preBuild` ✓ (FOD buildPhase has `runHook preBuild`)
- `modPostBuild` ✓

`overrideModAttrs` is a parameter of `buildGoModule()` itself — cannot be set via `overrideAttrs`.

## proxyVendor notes

- `proxyVendor = true` only adds `GOPROXY` to the FOD's `impureEnvVars`
- **Do NOT hardcode GOPROXY in env** — user may have regional mirrors (goproxy.io etc.), overriding breaks connectivity behind GFW
- `,direct` may appear mid-string (`goproxy.io,direct`), use `sed 's/,direct//g'` not shell `${var%,direct}`

## modPostBuild vs preBuild (proxyVendor caveat)

With `proxyVendor = true`, there is NO `vendor/` directory. Source lives in `$GOPATH/pkg/mod/`.
- `modPostBuild` targets `vendor/` — useless under proxyVendor, set to `""`
- Cgo directive patching (delete `.a`, rewrite `-l:libcronet.a` → `-lcronet`) must happen in `preBuild`, targeting `$GOPATH/pkg/mod/github.com/sagernet/cronet-go`
- `preBuild` runs in both FOD and main build — guard mod-cache patching with `if [ -d "$cronet_mod" ]`

## vendorHash update flow

1. Set `vendorHash = lib.fakeHash;`
2. Build once to get correct hash from error output
3. Replace with actual hash

## Misc

- `CRONET_GO_VERSION` in sing-box repo is for CI only (picks prebuilt .a from cronet-go releases), irrelevant to us
- Alternative approach: self-maintained go.mod like `caddy-naive` (more work — sing-box uses build tags, need `go mod tidy` with tags)
- Pseudo-version lookup: `curl -s "https://proxy.golang.org/MODULE/@v/VERSION.info"` — wrong timestamp in version string triggers an error that reveals the correct one
