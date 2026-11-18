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

# Fetch every source tarball the build will need before compiling anything,
# so a dead or bot-walled download host fails the build in minutes (with a
# list of everything that's missing) instead of halfway through.
#
# When CoreELEC's own download (upstream URL + its mirrors) fails, fall back to
# Gentoo's distfiles mirror, which carries byte-identical upstream release
# tarballs under /distfiles/<first byte of BLAKE2b(filename)>/<filename>.
# The sha256 from package.mk is still enforced.
fetch_fallback() {
  local pkg="$1" info url file sha dest prefix mirror_url
  info="$(bash -c '. config/options "$1" >/dev/null 2>&1
                   printf "%s\n%s\n%s\n" "${PKG_URL}" "${PKG_SOURCE_NAME}" "${PKG_SHA256}"' _ "${pkg}")"
  { read -r url; read -r file; read -r sha; } <<<"${info}"
  [ -n "${GENTOO_DISTFILES:-}" ] && [ -n "${file}" ] && [ -n "${sha}" ] || return 1
  case "${url}" in http://*|https://*|ftp://*) ;; *) return 1 ;; esac

  file="$(basename "${file}")"
  prefix="$(python3 -c 'import hashlib,sys; print(hashlib.blake2b(sys.argv[1].encode()).hexdigest()[:2])' "${file}")"
  mirror_url="${GENTOO_DISTFILES%/}/${prefix}/${file}"
  dest="${COREELEC_DIR}/sources/${pkg}/${file}"
  mkdir -p "$(dirname "${dest}")"

  echo "    trying ${mirror_url}"
  wget -q --timeout=30 --tries=3 -O "${dest}" "${mirror_url}" || { rm -f "${dest}"; return 1; }
  if [ "$(sha256sum "${dest}" | cut -d' ' -f1)" != "${sha}" ]; then
    echo "    checksum mismatch from mirror"
    rm -f "${dest}"
    return 1
  fi
  # Same stamps scripts/get_archive writes, so the build treats it as fetched.
  echo "${url}" > "${dest}.url"
  echo "${sha}" > "${dest}.sha256"
}

echo "==> Fetching sources"
(
  cd "${COREELEC_DIR}"
  export PROJECT DEVICE ARCH
  # shellcheck disable=SC2086 # word splitting is the point
  mapfile -t plan_pkgs < <(
    ./scripts/pkgjson 2>/dev/null \
      | python3 ./scripts/genbuildplan.py --build ${SDK_PACKAGES} \
      | awk '$1 == "build" { sub(/:.*/, "", $2); print $2 }' | sort -u
  )
  [ "${#plan_pkgs[@]}" -gt 0 ] || { echo "ERROR: empty build plan" >&2; exit 1; }

  failed=()
  mkdir -p /tmp/sdk-get
  for pkg in "${plan_pkgs[@]}"; do
    log="/tmp/sdk-get/${pkg}.log"
    if timeout 600 ./scripts/get "${pkg}" >"${log}" 2>&1; then
      continue
    fi
    echo "  ${pkg}: download failed, trying fallback mirror"
    if fetch_fallback "${pkg}" && ./scripts/get "${pkg}" >>"${log}" 2>&1; then
      echo "  ${pkg}: OK from fallback mirror"
    else
      failed+=("${pkg}")
    fi
  done

  if [ "${#failed[@]}" -gt 0 ]; then
    for pkg in "${failed[@]}"; do
      echo "---- ${pkg} ----------------------------------------"
      tail -n 25 "/tmp/sdk-get/${pkg}.log"
    done
    echo "ERROR: could not fetch sources for: ${failed[*]}" >&2
    exit 1
  fi
  echo "    ${#plan_pkgs[@]} packages fetched"
)

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
