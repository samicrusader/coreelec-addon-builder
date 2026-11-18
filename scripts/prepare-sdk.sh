#!/usr/bin/env bash
# Builds the CoreELEC toolchain and the SDK packages into ${COREELEC_DIR}.
# Runs once, inside `docker build`, as the unprivileged build user.
#
#   prepare-sdk.sh <sdk-dir>
#
# <sdk-dir> holds config.env and patches/*.patch (applied in name order).

set -euo pipefail

readonly SDK_DIR="${1:?usage: prepare-sdk.sh <sdk-dir>}"
readonly COREELEC_DIR="${COREELEC_DIR:-/build/CoreELEC}"
readonly SDK_PRUNE="${SDK_PRUNE:-yes}"

# shellcheck source=/dev/null
. "${SDK_DIR}/config.env"

echo "==> Fetching CoreELEC ${COREELEC_REF}"
mkdir -p "${COREELEC_DIR}"
git -C "${COREELEC_DIR}" init -q
git -C "${COREELEC_DIR}" remote add origin "${COREELEC_REPOSITORY}"
git -C "${COREELEC_DIR}" fetch -q --depth=1 origin "${COREELEC_REF}"
git -C "${COREELEC_DIR}" checkout -q --detach FETCH_HEAD

shopt -s nullglob
for patch in "${SDK_DIR}"/patches/*.patch; do
  echo "==> Applying $(basename "${patch}")"
  git -C "${COREELEC_DIR}" apply "${patch}"
done
shopt -u nullglob

if [ -n "${GNU_MIRROR:-}" ]; then
  gnu_mirror="${GNU_MIRROR%/}"
  echo "==> Rewriting GNU source URLs to ${gnu_mirror}"
  mapfile -t gnu_pkgs < <(
    grep -rlE --include=package.mk 'https?://(ftp|ftpmirror)\.gnu\.org/' \
      "${COREELEC_DIR}/packages" || true
  )
  if [ "${#gnu_pkgs[@]}" -gt 0 ]; then
    sed -i -E \
      -e "s#https?://ftp\.gnu\.org/(pub/)?gnu/#${gnu_mirror}/#g" \
      -e "s#https?://ftpmirror\.gnu\.org/(gnu/)?#${gnu_mirror}/#g" \
      "${gnu_pkgs[@]}"
  fi
fi

# Commit the patched tree so `git status` inside the image shows only what an
# addon build adds (handy when debugging a broken addon package).
git -C "${COREELEC_DIR}" add -A
git -C "${COREELEC_DIR}" -c user.name=sdk -c user.email=sdk@localhost \
  commit -q -m "SDK: host patches and GNU mirror rewrite"

echo "==> Building SDK packages: ${SDK_PACKAGES}"
(
  cd "${COREELEC_DIR}"
  # shellcheck disable=SC2086 # word splitting is the point
  env PROJECT="${PROJECT}" DEVICE="${DEVICE}" ARCH="${ARCH}" \
    ./scripts/build_mt ${SDK_PACKAGES}
)

if [ "${SDK_PRUNE}" = "yes" ]; then
  # Keep the toolchain, sysroot and build stamps; drop everything that can be
  # recreated. The build system decides "already built" from .stamps, so the
  # per-package build trees and downloaded tarballs aren't needed. Top-level
  # dotfiles in each package build dir are kept (some packages hash a
  # .pkg_stamp_var file there into their stamp).
  echo "==> Pruning build trees, sources and ccache"
  for build in "${COREELEC_DIR}"/build.*; do
    if [ -d "${build}/build" ]; then
      find "${build}/build" -mindepth 2 -maxdepth 2 \( -type d -o ! -name '.*' \) \
        -exec rm -rf {} +
    fi
    rm -rf "${build}/.unpack" "${build}/.ccache" "${build}/.ccache-local" \
           "${build}/.threads"
  done
  rm -rf "${COREELEC_DIR}/sources"
fi

du -sh "${COREELEC_DIR}" || true
echo "==> SDK ready"
