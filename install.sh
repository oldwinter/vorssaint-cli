#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# vorssaint installer for macOS.
#
#   curl -fsSL https://raw.githubusercontent.com/oldwinter/vorssaint-cli/master/install.sh | sh
#
# Options:
#   --version <tag>   Install a specific release (default: latest), e.g. v0.1.0
#   --prefix <dir>    Install into <dir> (default: /usr/local/bin if writable,
#                     otherwise ~/.local/bin)
#   -h, --help        Show this help
#
# Environment:
#   VORSSAINT_VERSION           same as --version
#   VORSSAINT_INSTALL_DIR       same as --prefix
#   VORSSAINT_RELEASE_BASE_URL  alternate download base (used by tests)
set -eu

REPO="oldwinter/vorssaint-cli"
VERSION="${VORSSAINT_VERSION:-latest}"
INSTALL_DIR="${VORSSAINT_INSTALL_DIR:-}"
BASE_URL="${VORSSAINT_RELEASE_BASE_URL:-}"

say() { printf '%s\n' "$*"; }
die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
vorssaint installer (macOS)

Usage: install.sh [--version <tag>] [--prefix <dir>]

  --version <tag>   Install a specific release (default: latest), e.g. v0.1.0
  --prefix <dir>    Install into <dir> (default: /usr/local/bin if writable,
                    otherwise ~/.local/bin)
  -h, --help        Show this help

Environment:
  VORSSAINT_VERSION           same as --version
  VORSSAINT_INSTALL_DIR       same as --prefix
  VORSSAINT_RELEASE_BASE_URL  alternate download base (used by tests)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      [ $# -ge 2 ] || die "--version needs a value"
      VERSION="$2"; shift 2 ;;
    --version=*)
      VERSION="${1#*=}"; shift ;;
    --prefix)
      [ $# -ge 2 ] || die "--prefix needs a value"
      INSTALL_DIR="$2"; shift 2 ;;
    --prefix=*)
      INSTALL_DIR="${1#*=}"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "unknown argument: $1 (try --help)" ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || die "vorssaint is macOS-only (found $(uname -s))"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64|x86_64) ;;
  *) die "unsupported architecture: $ARCH (expected arm64 or x86_64)" ;;
esac

case "$VERSION" in
  latest)
    [ -z "$BASE_URL" ] || die "VORSSAINT_RELEASE_BASE_URL needs an explicit --version"
    say "→ resolving the latest release…"
    VERSION="$(curl -fsSL --connect-timeout 15 \
      "https://api.github.com/repos/$REPO/releases/latest" \
      | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    [ -n "$VERSION" ] || die "could not resolve the latest release; pass --version vX.Y.Z"
    ;;
  v*) ;;
  *) VERSION="v$VERSION" ;;
esac

ASSET="vorssaint-${VERSION}-macos-universal.tar.gz"
if [ -n "$BASE_URL" ]; then
  URL="${BASE_URL%/}/$ASSET"
else
  URL="https://github.com/$REPO/releases/download/$VERSION/$ASSET"
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/vorssaint-install.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

say "→ downloading $ASSET"
curl -fsSL --retry 3 --connect-timeout 15 -o "$TMP/$ASSET" "$URL" \
  || die "download failed: $URL"
curl -fsSL --retry 3 --connect-timeout 15 -o "$TMP/$ASSET.sha256" "$URL.sha256" \
  || die "checksum download failed: $URL.sha256"

( cd "$TMP" && shasum -a 256 -c "$ASSET.sha256" >/dev/null 2>&1 ) \
  || die "sha256 verification failed for $ASSET"

tar -xzf "$TMP/$ASSET" -C "$TMP"
[ -f "$TMP/vorssaint" ] || die "archive did not contain a vorssaint binary"

if command -v lipo >/dev/null 2>&1; then
  ARCHS="$(lipo -archs "$TMP/vorssaint" 2>/dev/null || true)"
  case " $ARCHS " in
    *" $ARCH "*) ;;
    *) die "downloaded binary has no $ARCH slice (has: ${ARCHS:-unknown})" ;;
  esac
fi

# Homebrew strips quarantine itself; a curl download carries it.
xattr -d com.apple.quarantine "$TMP/vorssaint" 2>/dev/null || true

if [ -z "$INSTALL_DIR" ]; then
  if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
    INSTALL_DIR=/usr/local/bin
  else
    INSTALL_DIR="$HOME/.local/bin"
  fi
fi
mkdir -p "$INSTALL_DIR" 2>/dev/null || die "cannot create $INSTALL_DIR"
[ -w "$INSTALL_DIR" ] || die "$INSTALL_DIR is not writable; try --prefix \"\$HOME/.local/bin\""
install -m 0755 "$TMP/vorssaint" "$INSTALL_DIR/vorssaint"

"$INSTALL_DIR/vorssaint" --version >/dev/null || die "installed binary failed to run"
"$INSTALL_DIR/vorssaint" --selftest >/dev/null || die "installed binary failed its selftest"

say "✓ installed vorssaint $VERSION → $INSTALL_DIR/vorssaint"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) say "  add it to PATH: export PATH=\"$INSTALL_DIR:\$PATH\"" ;;
esac
