#!/usr/bin/env bash
# Complete gauth uninstaller.
#
# Removes the installed binary, the private gum copy, gauth's config/state/data,
# the keys gauth created under ~/.ssh/gauth, and only gauth-managed blocks in
# ~/.ssh/config. Your repositories, global git config, and non-gauth SSH keys
# are left alone.
set -u

ROOT="$(cd "$(dirname "$0")" && pwd -P)"
PREFIX="${PREFIX:-/usr/local}"
BINDIR="${BINDIR:-}"
LIBEXECDIR="${LIBEXECDIR:-}"
ASSUME_YES=0
PURGE_KEYS=0
KEYS_FILE=""
SUDO_BIN="${GAUTH_SUDO_BIN:-sudo}"
SUDO_ATTEMPTS="${GAUTH_SUDO_ATTEMPTS:-3}"

usage() {
  cat <<EOF
gauth uninstaller

Usage:
  ./uninstall.sh [options]

Options:
  --prefix DIR       Installation prefix to remove (default: /usr/local)
  --bindir DIR       Override the binary directory (default: PREFIX/bin)
  --libexecdir DIR   Override the gum directory (default: PREFIX/libexec/gauth)
  --purge-keys       Also delete legacy profile keys stored outside ~/.ssh/gauth
  --yes, -y          Do not ask for confirmation
  --help             Show this help

Removes:
  - the gauth binary and gauth's private gum copy
  - ~/.config/gauth, ~/.local/state/gauth, ~/.local/share/gauth
  - ~/.ssh/gauth (keys created by gauth)
  - gauth-managed blocks in ~/.ssh/config (other entries are preserved)

The script asks for sudo authentication before removing anything, even with
--yes. sudo is also used to remove files in a system directory. Run it as your
normal user, not as root.
EOF
}

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
  C_SUCCESS=$'\033[1;32m'
  C_ACCENT=$'\033[1;36m'
  C_WARN=$'\033[1;33m'
  C_ERROR=$'\033[1;31m'
  C_RESET=$'\033[0m'
else
  C_SUCCESS=""
  C_ACCENT=""
  C_WARN=""
  C_ERROR=""
  C_RESET=""
fi

log() { printf '%s\n' "$*"; }
warn() { printf '%s! %s%s\n' "$C_WARN" "$*" "$C_RESET" >&2; }
note() { printf '%s%s%s\n' "$C_ACCENT" "$*" "$C_RESET"; }
die() { printf '%s✖ %s%s\n' "$C_ERROR" "$*" "$C_RESET" >&2; exit 1; }
success() { printf '%s✔ %s%s\n' "$C_SUCCESS" "$*" "$C_RESET"; }

run_priv() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    command -v "$SUDO_BIN" >/dev/null 2>&1 || die "sudo is required to remove $*"
    "$SUDO_BIN" "$@"
  fi
}

# Removing gauth is destructive, so require a real sudo identity check even
# when --yes is used. A cached/passwordless sudo timestamp satisfies the check
# without a prompt. The password is read on stdin and piped to sudo -S; it is
# never placed in argv or the environment.
require_admin_auth() {
  local user
  user="$(id -un 2>/dev/null || printf '%s' "${USER:-user}")"

  if ! command -v "$SUDO_BIN" >/dev/null 2>&1; then
    die "sudo is required to authenticate before removing gauth."
  fi

  if "$SUDO_BIN" -n -v >/dev/null 2>&1; then
    success "Administrator authentication confirmed."
    return 0
  fi

  note "Administrator authentication"
  log "Removing gauth is a privileged action."
  log "sudo verifies your identity and authorizes system-path removal."
  log "Your personal files are still removed as $user."
  log "If sudo is already cached or passwordless, no password is needed."

  local attempt=1 password=""
  while [ "$attempt" -le "$SUDO_ATTEMPTS" ]; do
    printf '%s[sudo] password for %s:%s ' "$C_ACCENT" "$user" "$C_RESET" >&2
    if ! IFS= read -r -s password; then
      printf '\n' >&2
      die "Authentication cancelled; nothing was removed."
    fi
    printf '\n' >&2

    if [ -z "$password" ]; then
      if "$SUDO_BIN" -n -v >/dev/null 2>&1; then
        success "Administrator authentication confirmed."
        return 0
      fi
      warn "The password cannot be empty."
    elif printf '%s\n' "$password" | "$SUDO_BIN" -S -p '' -v >/dev/null 2>&1; then
      password=""
      success "Administrator authentication confirmed."
      return 0
    else
      password=""
      warn "Authentication failed ($attempt/$SUDO_ATTEMPTS)."
    fi
    attempt=$((attempt + 1))
  done

  die "Too many failed authentication attempts; nothing was removed."
}

cleanup() {
  [ -n "${KEYS_FILE:-}" ] && rm -f "$KEYS_FILE" "$KEYS_FILE.dedup" "$KEYS_FILE.external"
}
trap cleanup EXIT INT TERM

safe_remove_path() {
  local path="$1"
  case "$path" in
    ''|/|"$HOME"|"$HOME/"| \
    "$HOME/.ssh"|"$HOME/.ssh/"| \
    "$HOME/.config"|"$HOME/.config/"| \
    "$HOME/.local"|"$HOME/.local/"| \
    "$HOME/.local/state"|"$HOME/.local/state/"| \
    "$HOME/.local/share"|"$HOME/.local/share/")
      warn "Refusing to remove protected path: $path"
      return 1
      ;;
  esac
  if [ -e "$path" ] || [ -L "$path" ]; then
    rm -rf -- "$path" || {
      warn "Could not remove $path"
      return 1
    }
    log "Removed $path"
  fi
  return 0
}

safe_remove_file() {
  local path="$1"
  case "$path" in
    ''|/|"$HOME"|"$HOME/")
      warn "Refusing to remove protected path: $path"
      return 1
      ;;
  esac
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    return 0
  fi
  rm -f -- "$path" || {
    warn "Could not remove $path"
    return 1
  }
  log "Removed $path"
  return 0
}

remove_installed_file() {
  local path="$1"
  [ -e "$path" ] || [ -L "$path" ] || return 0
  if [ -w "$(dirname "$path")" ]; then
    rm -f -- "$path" || {
      warn "Could not remove $path"
      return 1
    }
  else
    run_priv rm -f -- "$path" || {
      warn "Could not remove $path"
      return 1
    }
  fi
  log "Removed $path"
  return 0
}

# A block is safe to remove only when its open/close pair is present exactly
# once and no gauth block is nested inside another one.
ssh_config_block_well_formed() {
  local cfg="$1"
  local alias="$2"
  awk -v start="# >>> gauth:$alias >>>" -v end="# <<< gauth:$alias <<<" '
    /^# >>> gauth:/ {
      if (inblock) bad = 1
      inblock = 1
      if ($0 == start) opens++
      next
    }
    /^# <<< gauth:/ {
      if (!inblock) bad = 1
      inblock = 0
      if ($0 == end) closes++
      next
    }
    END {
      if (bad || inblock || opens != 1 || closes != 1) exit 1
      exit 0
    }
  ' "$cfg"
}

# Remove only well-formed gauth blocks. If any marker is malformed, leave the
# whole SSH config untouched so a user entry can never be deleted by accident.
remove_managed_ssh_config() {
  local cfg="$GAUTH_SSH_CONFIG"
  [ -f "$cfg" ] || return 0

  local aliases
  aliases="$(sed -n 's/^# >>> gauth:\(.*\) >>>$/\1/p' "$cfg" 2>/dev/null | awk '!seen[$0]++')"
  [ -n "$aliases" ] || return 0

  local tmp="$cfg.gauth-uninstall.$$"
  local next="$cfg.gauth-uninstall-next.$$"
  local alias_file="$cfg.gauth-uninstall-aliases.$$"
  cp -p "$cfg" "$tmp" || {
    warn "Could not prepare $cfg for editing."
    return 1
  }
  printf '%s\n' "$aliases" >"$alias_file" || {
    rm -f "$tmp"
    warn "Could not prepare $cfg for editing."
    return 1
  }

  local alias rc=0
  while IFS= read -r alias; do
    [ -n "$alias" ] || continue
    if ! ssh_config_block_well_formed "$tmp" "$alias"; then
      warn "Skipping malformed gauth block for '$alias' in $cfg."
      rc=1
      continue
    fi
    if ! awk -v start="# >>> gauth:$alias >>>" \
             -v end="# <<< gauth:$alias <<<" '
      $0 == start { skip = 1; next }
      $0 == end   { skip = 0; next }
      skip != 1   { print }
    ' "$tmp" >"$next"; then
      warn "Could not rewrite $cfg while removing '$alias'."
      rc=1
      break
    fi
    mv "$next" "$tmp" || {
      rc=1
      break
    }
  done <"$alias_file"

  if [ "$rc" -eq 0 ]; then
    chmod 600 "$tmp" 2>/dev/null || true
    if mv "$tmp" "$cfg"; then
      log "Removed gauth-managed SSH config blocks from $cfg"
    else
      warn "Could not replace $cfg"
      rc=1
    fi
  else
    warn "Left $cfg unchanged because some gauth blocks were malformed."
  fi

  rm -f "$tmp" "$next" "$alias_file"
  return "$rc"
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
    --purge-keys) PURGE_KEYS=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

if [ "$(id -u)" -eq 0 ]; then
  die "Run uninstall.sh as your normal user. It asks for sudo only for system files."
fi

[ -n "${HOME:-}" ] || die "HOME is not set."

case "$PREFIX" in
  "~") PREFIX="$HOME" ;;
  "~/"*) PREFIX="$HOME/${PREFIX#\~/}" ;;
  /*) ;;
  *) PREFIX="$(pwd -P)/$PREFIX" ;;
esac
BINDIR="${BINDIR:-$PREFIX/bin}"
LIBEXECDIR="${LIBEXECDIR:-$PREFIX/libexec/gauth}"

GAUTH_CONFIG_HOME="${GAUTH_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/gauth}"
GAUTH_STATE_HOME="${GAUTH_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/gauth}"
GAUTH_DATA_HOME="${GAUTH_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/gauth}"
GAUTH_SSH_DIR="${GAUTH_SSH_DIR:-$HOME/.ssh}"
GAUTH_SSH_CONFIG="${GAUTH_SSH_CONFIG:-$GAUTH_SSH_DIR/config}"
GAUTH_KEY_DIR="$GAUTH_SSH_DIR/gauth"

# Collect profile keys before the config directory is removed. Keys inside
# ~/.ssh/gauth go away with the directory; legacy keys outside it are reported
# and only removed with --purge-keys.
KEYS_FILE="$(mktemp "${TMPDIR:-/tmp}/gauth-uninstall-keys.XXXXXX")" || die "Could not create a temporary file."
: >"$KEYS_FILE"
if [ -f "$GAUTH_CONFIG_HOME/profiles.tsv" ]; then
  awk -F '\t' '!/^#/ && NF >= 5 && $5 != "" { print $5 }' \
    "$GAUTH_CONFIG_HOME/profiles.tsv" >>"$KEYS_FILE" 2>/dev/null || true
fi
if [ -s "$KEYS_FILE" ]; then
  awk '!seen[$0]++' "$KEYS_FILE" >"$KEYS_FILE.dedup" || die "Could not prepare the key list."
  mv "$KEYS_FILE.dedup" "$KEYS_FILE" || die "Could not prepare the key list."
fi

EXTERNAL_KEYS="$KEYS_FILE.external"
: >"$EXTERNAL_KEYS" || die "Could not prepare the key list."
while IFS= read -r key; do
  [ -n "$key" ] || continue
  case "$key" in
    "$GAUTH_KEY_DIR/"*) continue ;;
  esac
  printf '%s\n' "$key" >>"$EXTERNAL_KEYS"
done <"$KEYS_FILE"

if [ "$ASSUME_YES" -eq 0 ]; then
  [ -t 0 ] || die "Confirmation needs a terminal. Re-run with --yes."
  printf '\nThe uninstaller will remove gauth from this system:\n'
  [ -e "$BINDIR/gauth" ] && printf '  - %s\n' "$BINDIR/gauth"
  [ -e "$LIBEXECDIR/gum" ] && printf '  - %s\n' "$LIBEXECDIR/gum"
  [ -e "$GAUTH_CONFIG_HOME" ] && printf '  - %s\n' "$GAUTH_CONFIG_HOME"
  [ -e "$GAUTH_STATE_HOME" ] && printf '  - %s\n' "$GAUTH_STATE_HOME"
  [ -e "$GAUTH_DATA_HOME" ] && printf '  - %s\n' "$GAUTH_DATA_HOME"
  [ -e "$GAUTH_KEY_DIR" ] && printf '  - %s\n' "$GAUTH_KEY_DIR"
  if [ -f "$GAUTH_SSH_CONFIG" ] && grep -q '^# >>> gauth:.* >>>$' "$GAUTH_SSH_CONFIG" 2>/dev/null; then
    printf '  - gauth-managed blocks in %s\n' "$GAUTH_SSH_CONFIG"
  fi
  if [ -s "$EXTERNAL_KEYS" ]; then
    if [ "$PURGE_KEYS" -eq 1 ]; then
      printf '  - legacy profile keys listed in %s (--purge-keys)\n' "$GAUTH_CONFIG_HOME/profiles.tsv"
    else
      printf '\nThese legacy profile keys are outside %s and will be kept:\n' "$GAUTH_KEY_DIR"
      sed 's/^/  - /' "$EXTERNAL_KEYS"
      printf 'Use --purge-keys to remove them too.\n'
    fi
  fi
  printf '\nRemove gauth completely? [y/N]: '
  IFS= read -r answer || answer=""
  case "$answer" in
    y|Y|yes|YES) ;;
    *)
      log "Cancelled; nothing was removed."
      exit 1
      ;;
  esac
fi

# Authentication comes after confirmation but before the first deletion, so a
# cancelled prompt leaves everything untouched.
require_admin_auth

FAILED=0
LEGACY_KEPT=0
if [ -s "$EXTERNAL_KEYS" ] && [ "$PURGE_KEYS" -eq 0 ]; then
  LEGACY_KEPT=1
fi

# 1. SSH config blocks and keys. If the config cannot be cleaned safely, keep
# the keys so the existing SSH config does not point at missing files.
if remove_managed_ssh_config; then
  if [ -d "$GAUTH_KEY_DIR" ]; then
    safe_remove_path "$GAUTH_KEY_DIR" || FAILED=1
  fi

  if [ -s "$EXTERNAL_KEYS" ]; then
    if [ "$PURGE_KEYS" -eq 1 ]; then
      while IFS= read -r key; do
        [ -n "$key" ] || continue
        case "$key" in
          "$HOME"/*) safe_remove_file "$key" || FAILED=1 ;;
          *) warn "Refusing to delete a key outside HOME: $key" ;;
        esac
        safe_remove_file "$key.pub" >/dev/null 2>&1 || FAILED=1
      done <"$EXTERNAL_KEYS"
    else
      while IFS= read -r key; do
        [ -n "$key" ] && warn "Kept legacy key outside ${GAUTH_KEY_DIR}: $key"
      done <"$EXTERNAL_KEYS"
    fi
  fi
else
  FAILED=1
  warn "Kept ${GAUTH_KEY_DIR} because the SSH config could not be cleaned safely."
fi

# 2. gauth-owned user data.
safe_remove_path "$GAUTH_CONFIG_HOME" || FAILED=1
safe_remove_path "$GAUTH_STATE_HOME" || FAILED=1
safe_remove_path "$GAUTH_DATA_HOME" || FAILED=1

# 3. Installed binary and private gum. Also catch common user-local installs
# even when --prefix was omitted.
remove_installed_file "$BINDIR/gauth" || FAILED=1
remove_installed_file "$LIBEXECDIR/gum" || FAILED=1
rmdir "$LIBEXECDIR" 2>/dev/null || true

if [ "$BINDIR/gauth" != "$HOME/.local/bin/gauth" ]; then
  remove_installed_file "$HOME/.local/bin/gauth" || FAILED=1
fi
if [ "$LIBEXECDIR/gum" != "$HOME/.local/libexec/gauth/gum" ]; then
  remove_installed_file "$HOME/.local/libexec/gauth/gum" || FAILED=1
fi
rmdir "$HOME/.local/libexec/gauth" 2>/dev/null || true

printf '\n'
if [ "$FAILED" -eq 0 ]; then
  if [ "$LEGACY_KEPT" -eq 1 ]; then
    success "gauth has been removed from this system."
    warn "Legacy profile keys outside ${GAUTH_KEY_DIR} were kept; re-run with --purge-keys to remove them."
  else
    success "gauth has been completely removed from this system."
  fi
  log "Kept: your repositories, global git config, and non-gauth SSH keys."
  exit 0
fi
warn "gauth was not completely removed. Review the messages above and retry."
exit 1
