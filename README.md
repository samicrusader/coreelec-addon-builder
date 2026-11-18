# coreelec-addon-builder

Prebuilt CoreELEC build environments for compiling Kodi binary addons, so an
addon build takes minutes instead of rebuilding the whole cross toolchain.

Each image is a pinned CoreELEC checkout with the toolchain, sysroot, Kodi
addon headers and common addon dependencies already built. Building an addon
runs CoreELEC's own `scripts/create_addon`, so the result is linked against the
same glibc/libcurl ABI as the box it runs on.

| SDK (`sdk/<dir>`) | Image tag | CoreELEC | Target |
|---|---|---|---|
| `coreelec-21-amlogic-ng-arm` | `21-amlogic-ng-arm` | 21 (Kodi 21.2 Omega) | Amlogic-ng, 32-bit userspace |

Image: `ghcr.io/samicrusader/coreelec-addon-builder:<tag>`. Each build is also
tagged `<tag>-<first 12 chars of COREELEC_REF>`.

## Building an addon

### In GitHub Actions

1. Add `coreelec/package.mk` to the addon repo, starting from
   [`templates/package.mk`](templates/package.mk).
2. Add [`templates/addon-workflow.yml`](templates/addon-workflow.yml) as
   `.github/workflows/coreelec.yml`.

The workflow calls the reusable
[`build-addon.yml`](.github/workflows/build-addon.yml), which builds inside the
SDK image and uploads the installable ZIP as an artifact.

### Locally

```sh
docker run --rm \
  -v /path/to/addon:/addon:ro \
  -v "$PWD/out":/out \
  ghcr.io/samicrusader/coreelec-addon-builder:21-amlogic-ng-arm
```

On Windows (Docker Desktop), from `cmd`:

```bat
docker run --rm -v B:\Source\pvr.dispatcharr:/addon:ro -v %CD%\out:/out ghcr.io/samicrusader/coreelec-addon-builder:21-amlogic-ng-arm
```

Arguments are `[addon-dir] [package-dir]`, defaulting to `/addon` and
`coreelec`. Use a fresh container for every build (`--rm`): the addon's build
stamp doesn't change between commits, so a reused container would treat it as
already built.

### package.mk

Standard CoreELEC package format. `build-addon.sh` sets three variables for it:

| Variable | Value |
|---|---|
| `ADDON_SOURCE` | the mounted addon directory, for `PKG_URL="file://${ADDON_SOURCE}"` |
| `ADDON_VERSION` | git commit, `-dirty` if modified, `local` outside git |
| `ADDON_SHA256` | sha256 of `ADDON_VERSION` (`PKG_SHA256` is mandatory) |

`patches/` and `sources/` next to `package.mk` are copied in too, and behave as
they do for any CoreELEC package.

Dependencies listed in `SDK_PACKAGES` are already built. Anything else in
`PKG_DEPENDS_TARGET` is downloaded and built during the addon build, which
works but is slower; add it to `SDK_PACKAGES` if it's used regularly.

## Building the SDK images

[`sdk.yml`](.github/workflows/sdk.yml) builds every `sdk/*` directory and
pushes to GHCR. It runs on pushes to `master` that touch `docker/`, `scripts/` or
`sdk/`, or by hand from the Actions tab. A cold build is roughly 45-60 minutes.

After the first push, make the package public (Package settings → Change
visibility), or grant each addon repo read access to it under Package settings
→ Manage Actions access.

Locally:

```sh
docker build -f docker/Dockerfile --build-arg SDK=coreelec-21-amlogic-ng-arm -t coreelec-addon-builder .
```

### Adding an SDK

Copy `sdk/coreelec-21-amlogic-ng-arm` to a new directory and edit
`config.env` (`COREELEC_REF`, `PROJECT`/`DEVICE`/`ARCH`, `SDK_TAG`). Patches
in `patches/` are applied to the CoreELEC tree in name order and are specific
to that CoreELEC revision.

### What the CoreELEC 21 patches do

`0001-modern-host.patch` only changes how the build tools are built:

- host-compiler warning fixes so 7-zip and friends build with newer GCC
- dead `ftpmirror.gnu.org` URLs replaced
- `file://` package sources enabled (`GET_HANDLER_SUPPORT="archive file"`)
- `HOST_CFLAGS` uses `-march=x86-64-v2` instead of `-march=native`. The image
  is built on one GitHub runner and used on others with different CPUs, so a
  natively tuned toolchain would die with "Illegal instruction".

Separately, `prepare-sdk.sh` rewrites every GNU download URL to `GNU_MIRROR`
(`mirrors.kernel.org`), because `ftp.gnu.org` regularly times out from GitHub
runners.

### Image size

`prepare-sdk.sh` prunes per-package build trees, downloaded sources and ccache
once the SDK packages are built. CoreELEC decides "already built" from the
stamps in `build.*/.stamps`, which are kept along with the toolchain and
sysroot. Build with `--build-arg SDK_PRUNE=no` to keep everything for
debugging.
