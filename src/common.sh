# shellcheck shell=bash
# Shared constants and small, dependency-free helpers.

GAUTH_VERSION="0.2.0"
GAUTH_PROGRAM="gauth"
GAUTH_DEFAULT_HOST="github.com"
GAUTH_DEFAULT_KEY_TYPE="ed25519"
GAUTH_DEFAULT_ALIAS_PREFIX="github.com-"
GAUTH_DEFAULT_BRANCH="main"
GAUTH_DEFAULT_COPY_KEY="true"
GAUTH_DEFAULT_AUTO_AGENT="true"

# The path globals are populated by gauth_init_paths. Environment overrides
# (GAUTH_CONFIG_HOME, GAUTH_STATE_HOME, GAUTH_SSH_DIR, GAUTH_SSH_CONFIG) are
# intentionally honored for tests and custom installations.

gauth_now() {
  date +%s 2>/dev/null || printf '0\n'
}

gauth_timestamp() {
  date +%Y%m%d-%H%M%S 2>/dev/null || printf 'unknown\n'
}

gauth_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Prompts read keys from stdin and draw on stderr. Callers capture a prompt's
# stdout, so stdout being a pipe does not make the session non-interactive.
gauth_is_tty() {
  [ -t 0 ] && [ -t 2 ]
}

gauth_require_tty() {
  if ! gauth_is_tty; then
    ui_error "This command needs an interactive terminal (stdin and stderr)."
    return 1
  fi
  return 0
}

gauth_is_writable() {
  local path="$1"
  [ -w "$path" ] && return 0
  [ -w "$(dirname "$path")" ] && return 0
  return 1
}

gauth_file_uid() {
  local path="$1"
  case "$(uname -s 2>/dev/null)" in
    Darwin|FreeBSD|OpenBSD|NetBSD) stat -f '%u' "$path" 2>/dev/null ;;
    *) stat -c '%u' "$path" 2>/dev/null ;;
  esac
}

# gauth never escalates privileges. When a file was created by another user
# (usually an earlier sudo run), say exactly what to run instead of failing
# with a bare permission error.
gauth_permission_hint() {
  local path="$1"
  local owner
  owner="$(gauth_file_uid "$path" 2>/dev/null || printf '?')"
  ui_error "Cannot modify $path (owner uid $owner, you are uid $(id -u))."
  ui_info "gauth never runs sudo. Fix ownership yourself with:"
  printf '  sudo chown %s:%s %s\n' "$(id -u)" "$(id -g)" "$path" >&2
}

gauth_log() {
  [ -n "${GAUTH_LOG_FILE:-}" ] || return 0
  gauth_ensure_dir "$(dirname "$GAUTH_LOG_FILE")" 700 >/dev/null 2>&1 || true
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '?')" "$*" \
    >>"$GAUTH_LOG_FILE" 2>/dev/null || true
}

gauth_die() {
  ui_error "$1"
  exit "${2:-1}"
}

gauth_ensure_dir() {
  local dir="$1"
  local mode="${2:-700}"
  if [ -d "$dir" ]; then
    chmod "$mode" "$dir" 2>/dev/null || true
    return 0
  fi
  mkdir -p "$dir" 2>/dev/null || return 1
  chmod "$mode" "$dir" 2>/dev/null || true
  return 0
}

gauth_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

gauth_has_control_chars() {
  case "$1" in
    *$'\n'*|*$'\r'*|*$'\t'*) return 0 ;;
  esac
  return 1
}

gauth_is_true() {
  case "${1:-}" in
    true|TRUE|yes|YES|1|on|ON) return 0 ;;
  esac
  return 1
}

validate_profile_name() {
  local name="$1"
  [ -n "$name" ] || return 1
  [ "${#name}" -le 64 ] || return 1
  gauth_has_control_chars "$name" && return 1
  case "$name" in
    -*) return 1 ;;
  esac
  case "$name" in
    *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}

validate_alias() {
  local alias="$1"
  [ -n "$alias" ] || return 1
  [ "${#alias}" -le 128 ] || return 1
  gauth_has_control_chars "$alias" && return 1
  case "$alias" in
    -*) return 1 ;;
  esac
  case "$alias" in
    *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}

validate_email() {
  local email="$1"
  [ -n "$email" ] || return 1
  gauth_has_control_chars "$email" && return 1
  case "$email" in
    *' '*|*@*@*|@*|*@) return 1 ;;
    *@*.*) return 0 ;;
  esac
  return 1
}

validate_key_type() {
  case "${1:-}" in
    ed25519|rsa|ecdsa) return 0 ;;
  esac
  return 1
}

validate_branch_name() {
  local branch="$1"
  [ -n "$branch" ] || return 1
  gauth_has_control_chars "$branch" && return 1
  case "$branch" in
    -*) return 1 ;;
    *..*|*' '*|*'~'*|*'^'*|*':'*|*'?'*|*'*'*|*'['*|*'\'*) return 1 ;;
  esac
  return 0
}

validate_repo_part() {
  local part="$1"
  [ -n "$part" ] || return 1
  [ "${#part}" -le 100 ] || return 1
  gauth_has_control_chars "$part" && return 1
  case "$part" in
    .|..|-*) return 1 ;;
  esac
  case "$part" in
    *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}

gauth_expand_path() {
  local path="$1"
  case "$path" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${path#\~/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

gauth_abs_path() {
  local path
  path="$(gauth_expand_path "$1")"
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s/%s\n' "$(pwd -P)" "$path" ;;
  esac
}

gauth_backup_file() {
  local source="$1"
  local label="${2:-file}"
  [ -e "$source" ] || return 1
  gauth_ensure_dir "$GAUTH_BACKUP_DIR" 700 >/dev/null 2>&1 || return 1
  local safe_label
  safe_label="$(printf '%s' "$label" | tr -c 'A-Za-z0-9._-' '_')"
  local target="$GAUTH_BACKUP_DIR/${safe_label}.$(gauth_timestamp).$$.bak"
  cp -p "$source" "$target" 2>/dev/null || return 1
  printf '%s\n' "$target"
}

gauth_file_mode() {
  local path="$1"
  case "$(uname -s 2>/dev/null)" in
    Darwin|FreeBSD|OpenBSD|NetBSD) stat -f '%Lp' "$path" 2>/dev/null ;;
    *) stat -c '%a' "$path" 2>/dev/null ;;
  esac
}

gauth_format_epoch() {
  local epoch="$1"
  case "$epoch" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$(uname -s 2>/dev/null)" in
    Darwin|FreeBSD|OpenBSD|NetBSD) date -r "$epoch" '+%Y-%m-%d %H:%M' 2>/dev/null ;;
    *) date -d "@$epoch" '+%Y-%m-%d %H:%M' 2>/dev/null ;;
  esac
}

gauth_sha256() {
  local file="$1"
  if gauth_command_exists sha256sum; then
    sha256sum "$file" | awk '{print $1}'
  elif gauth_command_exists shasum; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif gauth_command_exists openssl; then
    openssl dgst -sha256 "$file" | awk '{print $NF}'
  else
    return 1
  fi
}

gauth_open_url() {
  local url="$1"
  [ -z "${GAUTH_NO_BROWSER:-}" ] || return 1
  case "$(uname -s 2>/dev/null)" in
    Darwin)
      gauth_command_exists open || return 1
      open "$url" >/dev/null 2>&1
      ;;
    *)
      if gauth_command_exists xdg-open; then
        xdg-open "$url" >/dev/null 2>&1
      else
        return 1
      fi
      ;;
  esac
}

gauth_pause() {
  local message="${1:-Press Enter to continue...}"
  if [ -t 0 ]; then
    printf '%s' "$message" >&2
    IFS= read -r _ || true
  fi
}

gauth_init_paths() {
  [ -n "${HOME:-}" ] || gauth_die "HOME is not set."

  GAUTH_CONFIG_HOME="${GAUTH_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/gauth}"
  GAUTH_STATE_HOME="${GAUTH_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/gauth}"
  GAUTH_DATA_HOME="${GAUTH_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/gauth}"
  GAUTH_SSH_DIR="${GAUTH_SSH_DIR:-$HOME/.ssh}"
  GAUTH_SSH_CONFIG="${GAUTH_SSH_CONFIG:-$GAUTH_SSH_DIR/config}"

  GAUTH_PROFILES_FILE="$GAUTH_CONFIG_HOME/profiles.tsv"
  GAUTH_LEGACY_PROFILES_FILE="$GAUTH_CONFIG_HOME/accounts.tsv"
  GAUTH_SETTINGS_FILE="$GAUTH_CONFIG_HOME/settings.conf"
  GAUTH_BACKUP_DIR="$GAUTH_STATE_HOME/backups"
  GAUTH_LOG_FILE="$GAUTH_STATE_HOME/gauth.log"
  GAUTH_AGENT_ENV="$GAUTH_STATE_HOME/agent.env"
  GAUTH_AGENT_FISH="$GAUTH_STATE_HOME/agent.fish"
  GAUTH_ARCHIVE_DIR="$GAUTH_STATE_HOME/archive"

  GAUTH_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
  gauth_find_gum
}

gauth_find_gum() {
  # Explicit opt-out, handy for tests and for users who prefer the ANSI UI.
  if [ "${GAUTH_NO_GUM:-0}" = "1" ]; then
    GAUTH_GUM_BIN=""
    return 1
  fi
  if [ -n "${GAUTH_GUM:-}" ] && [ -x "$GAUTH_GUM" ]; then
    GAUTH_GUM_BIN="$GAUTH_GUM"
    return 0
  fi
  if gauth_command_exists gum; then
    GAUTH_GUM_BIN="$(command -v gum)"
    return 0
  fi
  if [ -n "${GAUTH_LIBEXEC:-}" ] && [ -x "$GAUTH_LIBEXEC/gum" ]; then
    GAUTH_GUM_BIN="$GAUTH_LIBEXEC/gum"
    return 0
  fi
  local candidate
  for candidate in \
    "$GAUTH_SELF_DIR/../libexec/gauth/gum" \
    "$HOME/.local/libexec/gauth/gum" \
    "/usr/local/libexec/gauth/gum"
  do
    if [ -x "$candidate" ]; then
      GAUTH_GUM_BIN="$candidate"
      return 0
    fi
  done
  GAUTH_GUM_BIN=""
  return 1
}

gauth_have_gum() {
  [ -n "${GAUTH_GUM_BIN:-}" ] && [ -x "$GAUTH_GUM_BIN" ]
}
