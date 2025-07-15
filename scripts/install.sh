#!/usr/bin/env sh
# Sprint CLI portable installer
# Installs the requested Sprint release under the given prefix.
# Usage: install.sh [--version vX.Y.Z] [--prefix /usr/local] [--dry-run]

set -e

VERSION=""
PREFIX="/usr/local"
DRY_RUN=0

# Honor GitHub token for private repositories
if [ -n "$GITHUB_TOKEN" ]; then
  CURL_AUTH="-H \"Authorization: token $GITHUB_TOKEN\""
else
  CURL_AUTH=""
fi

usage() {
  cat <<EOF
Sprint CLI installer

Usage: $0 [options]

Options:
  --version, -v <tag>   Install specific version tag (e.g. v0.3.1). Defaults to latest release.
  --prefix,  -p <path>  Installation prefix (default /usr/local).
  --dry-run             Print planned actions without executing.
  --help,    -h         Show this help message.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version|-v)
      VERSION="$2"; shift 2;;
    --prefix|-p)
      PREFIX="$2"; shift 2;;
    --dry-run)
      DRY_RUN=1; shift;;
    --help|-h)
      usage; exit 0;;
    *)
      echo "[install] Unknown option: $1" >&2
      usage; exit 1;;
  esac
done

# Detect OS
OS=$(uname -s)
case "$OS" in
  Darwin) PLATFORM="darwin";;
  Linux)  PLATFORM="linux";;
  *)
    echo "[install] Unsupported OS: $OS" >&2; exit 1;;
esac

# Detect ARCH
UNAME_ARCH=$(uname -m)
case "$UNAME_ARCH" in
  x86_64|amd64) ARCH="amd64";;
  arm64|aarch64) ARCH="arm64";;
  *)
    echo "[install] Unsupported architecture: $UNAME_ARCH" >&2; exit 1;;
esac

# Obtain latest version if none supplied
if [ -z "$VERSION" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    VERSION="latest"
  else
    echo "[install] Determining latest Sprint version…"

    # Try GitHub releases/latest endpoint (may 404 if no release published)
    VERSION="$(eval curl -sSL $CURL_AUTH https://api.github.com/repos/tebriz91/sprint-public/releases/latest 2>/dev/null \
      | grep -oE '"tag_name":\s*"v?[0-9.]+' | head -n1 | grep -oE '[0-9.]+' || true)"

    # Fallback: first tag if no release found
    if [ -z "$VERSION" ]; then
      VERSION="$(eval curl -sSL $CURL_AUTH https://api.github.com/repos/tebriz91/sprint-public/tags 2>/dev/null \
        | grep -oE '"name":\s*"v?[0-9.]+' | head -n1 | grep -oE '[0-9.]+' || true)"
    fi

    # Fallback: git ls-remote (avoids GitHub API rate-limits)
    if [ -z "$VERSION" ]; then
      if command -v git >/dev/null 2>&1; then
        VERSION="$(git ls-remote --tags --quiet --sort='v:refname' https://github.com/tebriz91/sprint-public.git 'v*' \
          | tail -n1 | sed -E 's#.*/v([0-9.]+)$#\1#')"
      fi
    fi

    if [ -z "$VERSION" ]; then
      echo "[install] Could not determine version – pass --version or publish a release." >&2
      exit 1
    fi
  fi
fi

# Normalize leading 'v' if present
VERSION="${VERSION#v}"

echo "[install] Installing Sprint v$VERSION to $PREFIX/bin (platform: $PLATFORM, arch: $ARCH)"

ARCHIVE="sprint_${VERSION}_${PLATFORM}_${ARCH}.tar.gz"
# Download URL
URL="https://github.com/tebriz91/sprint-public/releases/download/v${VERSION}/${ARCHIVE}"
TMP=$(mktemp -t sprint.XXXXXX)

cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "+ $*";
  else
    sh -c "$*";
  fi
}

cmd "curl -fsSL --location-trusted $CURL_AUTH $URL -o $TMP"

cmd "mkdir -p $PREFIX/bin"
cmd "tar -xzf $TMP -C $PREFIX/bin sprint"
cmd "chmod +x $PREFIX/bin/sprint"

if [ "$DRY_RUN" -eq 0 ]; then
  rm -f "$TMP"
  echo "[install] Sprint installed at $PREFIX/bin/sprint. Make sure this directory is in your PATH."
fi 
