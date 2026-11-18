#!/usr/bin/env bash
# Builds one Kodi binary addon against the prebuilt CoreELEC SDK in this image.
# This is the image's entrypoint.
#
#   build-addon.sh [addon-dir] [package-dir]
#
#   addon-dir    addon source checkout (default: /addon, mount it read-only)
#   package-dir  directory holding the CoreELEC package.mk, relative to
#                addon-dir (default: coreelec). Optional patches/ and sources/
#                next to package.mk are used the way CoreELEC normally does.
#
# The installable ZIP(s) are copied to ${OUTPUT_DIR:-/out}.
#
# package.mk receives these environment variables:
#   ADDON_SOURCE   absolute path of addon-dir  -> PKG_URL="file://${ADDON_SOURCE}"
#   ADDON_VERSION  git commit (+ "-dirty"), or "local" outside a git checkout
#   ADDON_SHA256   sha256 of ADDON_VERSION (PKG_SHA256 is mandatory metadata)

set -euo pipefail

ADDON_DIR="$(cd "${1:-/addon}" && pwd)"
readonly ADDON_DIR
readonly PACKAGE_SRC="${ADDON_DIR}/${2:-coreelec}"
readonly OUTPUT_DIR="${OUTPUT_DIR:-/out}"
readonly COREELEC_DIR="${COREELEC_DIR:-/build/CoreELEC}"
readonly SDK_DIR="${SDK_DIR:-/opt/sdk/current}"

# shellcheck source=/dev/null
. "${SDK_DIR}/config.env"

die() { echo "ERROR: $*" >&2; exit 1; }

[ -f "${PACKAGE_SRC}/package.mk" ] || die "no package.mk in ${PACKAGE_SRC}"

addon_name="$(sed -nE 's/^PKG_NAME="?([^"]+)"?\s*$/\1/p' "${PACKAGE_SRC}/package.mk" | head -n1)"
[ -n "${addon_name}" ] || die "could not read PKG_NAME from ${PACKAGE_SRC}/package.mk"

# The mount is owned by another uid; tell git that's fine.
git_cmd=(git -c safe.directory='*' -C "${ADDON_DIR}")
if "${git_cmd[@]}" rev-parse --git-dir >/dev/null 2>&1; then
  addon_version="$("${git_cmd[@]}" rev-parse HEAD)"
  if ! "${git_cmd[@]}" diff --quiet --ignore-submodules -- 2>/dev/null || \
     ! "${git_cmd[@]}" diff --cached --quiet --ignore-submodules -- 2>/dev/null; then
    addon_version="${addon_version}-dirty"
  fi
else
  addon_version="local"
fi

export ADDON_SOURCE="${ADDON_DIR}"
export ADDON_VERSION="${addon_version}"
ADDON_SHA256="$(printf '%s' "${addon_version}" | sha256sum | cut -d' ' -f1)"
export ADDON_SHA256

# Install the package definition. Its own directory keeps it apart from
# CoreELEC's packages, and a rebuild in the same container replaces it cleanly.
pkg_dir="${COREELEC_DIR}/packages/local-addons/${addon_name}"
rm -rf "${pkg_dir}"
mkdir -p "${pkg_dir}"
cp "${PACKAGE_SRC}/package.mk" "${pkg_dir}/"
for extra in patches sources source; do
  [ -d "${PACKAGE_SRC}/${extra}" ] && cp -R "${PACKAGE_SRC}/${extra}" "${pkg_dir}/"
done

echo "==> Building ${addon_name} ${ADDON_VERSION} for CoreELEC ${DEVICE}.${ARCH}"
(
  cd "${COREELEC_DIR}"
  env PROJECT="${PROJECT}" DEVICE="${DEVICE}" ARCH="${ARCH}" \
    ./scripts/create_addon "${addon_name}"
)

mkdir -p "${OUTPUT_DIR}"
mapfile -t zips < <(
  find "${COREELEC_DIR}/target/addons" -type f \
    -path "*/${addon_name}/${addon_name}-*.zip" -newer "${pkg_dir}/package.mk"
)
[ "${#zips[@]}" -gt 0 ] || die "create_addon finished without producing a ${addon_name} ZIP"

for zip in "${zips[@]}"; do
  cp -f "${zip}" "${OUTPUT_DIR}/"
  echo "==> ${OUTPUT_DIR}/$(basename "${zip}")"
done
