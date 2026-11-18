# SPDX-License-Identifier: GPL-2.0-or-later
# Copy to <addon repo>/coreelec/package.mk and fill in the blanks.
# ADDON_SOURCE / ADDON_VERSION / ADDON_SHA256 are set by build-addon.sh.

PKG_NAME="pvr.example"
PKG_VERSION="${ADDON_VERSION:?ADDON_VERSION is not set}"
# file:// sources aren't downloaded or checksummed, but PKG_SHA256 is mandatory.
PKG_SHA256="${ADDON_SHA256:?ADDON_SHA256 is not set}"
PKG_REV="1"
PKG_ARCH="any"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE="https://github.com/samicrusader/pvr.example"
PKG_URL="file://${ADDON_SOURCE:?ADDON_SOURCE is not set}"
# Anything not already in the SDK image (see SDK_PACKAGES) gets built on demand.
PKG_DEPENDS_TARGET="toolchain kodi-platform"
PKG_SECTION=""
PKG_SHORTDESC="Example PVR client"
PKG_LONGDESC="Example PVR client."

PKG_IS_ADDON="yes"
# xbmc.pvrclient, kodi.inputstream, kodi.audiodecoder, kodi.vfs, ...
PKG_ADDON_TYPE="xbmc.pvrclient"
PKG_BUILD_FLAGS="+pic"
PKG_CMAKE_OPTS_TARGET="-DBUILD_TESTING=OFF"
