#!/usr/bin/env bash
# gauth installer.
#
# Installs the built executable to PREFIX/bin/gauth and, when needed, a private
# copy of gum to PREFIX/libexec/gauth/gum. sudo is used only for the individual
# commands that write into a system directory.
set -u

ROOT="$(cd "$(dirname "$0")" && pwd -P)"
PREFIX="${PREFIX:-/usr/local}"
BINDIR=""
LIBEXECDIR=""
GUM_VERSION="${GAUTH_GUM_VERSION:-2.0.2}"
INSTALL_GUM="ask"
DO_UNINSTALL=0
TMPDIR_INSTALL=""

usage() {
  cat <<EOF
gauth installer

Usage:
  ./install.sh [options]

Options:
  --prefix DIR       Install under DIR (default: /usr/local)
  --bindir DIR       Override the binary directory (default: PREFIX/bin)
  --libexecdir DIR   Override the gum directory (default: PREFIX/libexec/gauth)
  --no-gum           Do not install or check for gum
  --gum-version VER  Pin the gum release (default: $GUM_VERSION)
  --uninstall        Remove the gauth binary and private gum copy
  --help             Show this help

A user-local install needs no sudo:
  ./install.sh --prefix "\$HOME/.local"

gauth never deletes SSH keys, SSH config, or ~/.config/gauth on uninstall.
EOF
}

log() { printf '%s\n' "$*"; }
warn() { printf '! %s\n' "$*" >&2; }
die() { printf 'x %s\n' "$*" >&2; exit 1; }

trim_newline() {
  local value="$1"
  value="${value%$'\n'}"
  printf '%s' "$value"
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file" | awk '{print $NF}'
  else
    return 1
  fi
}

download() {
  local url="$1"
  local dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url"
  else
    return 1
  fi
}

run_priv() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    command -v sudo >/dev/null 2>&1 || die "sudo is required to write to a system directory"
    sudo "$@"
  fi
}

ensure_dir() {
  local dir="$1"
  if mkdir -p "$dir" 2>/dev/null; then
    chmod 0755 "$dir" 2>/dev/null || true
    return 0
  fi
  run_priv install -d -m 0755 "$dir"
}

install_file() {
  local source="$1"
  local dest="$2"
  local mode="$3"
  local parent
  parent="$(dirname "$dest")"
  ensure_dir "$parent" || return 1
  if [ -w "$parent" ]; then
    install -m "$mode" "$source" "$dest"
  else
    run_priv install -m "$mode" "$source" "$dest"
  fi
}

cleanup() {
  [ -n "${TMPDIR_INSTALL:-}" ] && rm -rf "$TMPDIR_INSTALL"
}

detect_gum_asset() {
  local os arch
  case "$(uname -s 2>/dev/null)" in
    Linux) os="Linux" ;;
    Darwin) os="Darwin" ;;
    *) return 1 ;;
  esac
  case "$(uname -m 2>/dev/null)" in
    x86_64|amd64) arch="x86_64" ;;
    arm64|aarch64) arch="arm64" ;;
    armv7l|armv6l) arch="armv6" ;;
    i386|i686) arch="i386" ;;
    *) return 1 ;;
  esac
  printf 'gum_%s_%s_%s.tar.gz\n' "$GUM_VERSION" "$os" "$arch"
}

install_gum() {
  local existing
  if [ "$INSTALL_GUM" = "no" ]; then
    return 0
  fi
  existing="$(command -v gum 2>/dev/null || true)"
  if [ -n "$existing" ]; then
    log "gum found: $existing"
    return 0
  fi

  if [ "$INSTALL_GUM" = "ask" ] && [ -t 0 ]; then
    printf 'gum was not found. Install a private copy automatically? [Y/n]: '
    local answer
    IFS= read -r answer || answer=""
    case "$answer" in
      n|N|no|NO) warn "Skipping gum; gauth will use its plain ANSI fallback UI."; return 0 ;;
    esac
  fi

  local asset
  asset="$(detect_gum_asset)" || {
    warn "No gum binary is available for this OS/CPU; skipping gum."
    return 0
  }

  TMPDIR_INSTALL="$(mktemp -d "${TMPDIR:-/tmp}/gauth-install.XXXXXX")" || {
    warn "Could not create a temporary directory; skipping gum."
    return 0
  }

  local base url archive checksums expected actual
  base="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}"
  url="${base}/${asset}"
  archive="$TMPDIR_INSTALL/$asset"
  checksums="$TMPDIR_INSTALL/checksums.txt"

  log "Downloading $asset ..."
  if ! download "$url" "$archive"; then
    warn "Could not download gum; gauth will use its plain ANSI fallback UI."
    return 0
  fi
  if ! download "${base}/checksums.txt" "$checksums"; then
    warn "Could not download gum checksums; refusing to install it."
    return 0
  fi

  expected="$(awk -v asset="$asset" '$2 == asset {print $1; exit}' "$checksums" 2>/dev/null)"
  if [ -z "$expected" ]; then
    warn "No checksum found for $asset; refusing to install it."
    return 0
  fi
  actual="$(sha256_file "$archive")" || {
    warn "No SHA-256 tool available; refusing to install gum."
    return 0
  }
  if [ "$expected" != "$actual" ]; then
    warn "gum checksum mismatch; refusing to install it."
    return 0
  fi

  if ! tar -xzf "$archive" -C "$TMPDIR_INSTALL" 2>/dev/null; then
    warn "Could not extract gum; skipping."
    return 0
  fi
  local gum_binary
  gum_binary="$(find "$TMPDIR_INSTALL" -type f -name gum 2>/dev/null | head -1)"
  if [ -z "$gum_binary" ] || [ ! -f "$gum_binary" ]; then
    warn "The gum archive did not contain a gum binary; skipping."
    return 0
  fi

  if install_file "$gum_binary" "$LIBEXECDIR/gum" 0755; then
    log "Installed private gum: $LIBEXECDIR/gum"
  else
    warn "Could not install gum; gauth will use its plain ANSI fallback UI."
  fi
  return 0
}

build_gauth() {
  local artifact="$ROOT/dist/gauth"
  if [ "${GAUTH_SKIP_BUILD:-0}" != "1" ]; then
    log "Building gauth ..." >&2
    bash "$ROOT/build.sh" >&2 || die "Build failed."
  fi
  [ -f "$artifact" ] || die "Missing $artifact"
  printf '%s\n' "$artifact"
}

uninstall_gauth() {
  local binary="$BINDIR/gauth"
  if [ -e "$binary" ]; then
    if [ -w "$(dirname "$binary")" ]; then
      rm -f "$binary"
    else
      run_priv rm -f "$binary"
    fi
    log "Removed $binary"
  else
    warn "Not installed at $binary"
  fi
  if [ -e "$LIBEXECDIR/gum" ]; then
    if [ -w "$(dirname "$LIBEXECDIR/gum")" ]; then
      rm -f "$LIBEXECDIR/gum"
    else
      run_priv rm -f "$LIBEXECDIR/gum"
    fi
    log "Removed $LIBEXECDIR/gum"
  fi
  log "Kept ~/.config/gauth, ~/.ssh keys, and SSH config entries."
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix)
      [ "$#" -ge 2 ] || die "--prefix needs a value"
      PREFIX="$2"
      shift 2
      ;;
    --bindir)
      [ "$#" -ge 2 ] || die "--bindir needs a value"
      BINDIR="$2"
      shift 2
      ;;
    --libexecdir)
      [ "$#" -ge 2 ] || die "--libexecdir needs a value"
      LIBEXECDIR="$2"
      shift 2
      ;;
    --no-gum) INSTALL_GUM="no"; shift ;;
    --gum-version)
      [ "$#" -ge 2 ] || die "--gum-version needs a value"
      GUM_VERSION="$2"
      shift 2
      ;;
    --uninstall) DO_UNINSTALL=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

case "$PREFIX" in
  "~") PREFIX="$HOME" ;;
  "~/"*) PREFIX="$HOME/${PREFIX#\~/}" ;;
  /*) ;;
  *) PREFIX="$(pwd -P)/$PREFIX" ;;
esac
BINDIR="${BINDIR:-$PREFIX/bin}"
LIBEXECDIR="${LIBEXECDIR:-$PREFIX/libexec/gauth}"

trap cleanup EXIT INT TERM

if [ "$DO_UNINSTALL" -eq 1 ]; then
  uninstall_gauth
  exit 0
fi

if [ "${BASH_VERSINFO[0]}" -lt 3 ] || { [ "${BASH_VERSINFO[0]}" -eq 3 ] && [ "${BASH_VERSINFO[1]}" -lt 2 ]; }; then
  die "gauth requires Bash 3.2 or newer"
fi

ARTIFACT="$(build_gauth)" || exit 1
install_file "$ARTIFACT" "$BINDIR/gauth" 0755 || die "Could not install gauth."
log "Installed gauth: $BINDIR/gauth"

install_gum

case ":${PATH:-}:" in
  *":$BINDIR:"*) ;;
  *)
    warn "$BINDIR is not in PATH."
    printf '  bash/zsh: export PATH="%s:$PATH"\n' "$BINDIR" >&2
    printf '  fish:     fish_add_path %s\n' "$BINDIR" >&2
    ;;
esac

log "Run: gauth"
