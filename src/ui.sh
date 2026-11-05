# shellcheck shell=bash
# Gum-backed UI with a dependency-free ANSI fallback.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
  UI_RESET=$'\033[0m'
  UI_BOLD=$'\033[1m'
  UI_DIM=$'\033[2m'
  UI_RED=$'\033[31m'
  UI_GREEN=$'\033[32m'
  UI_YELLOW=$'\033[33m'
  UI_BLUE=$'\033[34m'
  UI_MAGENTA=$'\033[35m'
  UI_CYAN=$'\033[36m'
else
  UI_RESET=""
  UI_BOLD=""
  UI_DIM=""
  UI_RED=""
  UI_GREEN=""
  UI_YELLOW=""
  UI_BLUE=""
  UI_MAGENTA=""
  UI_CYAN=""
fi

ui_has_gum() {
  gauth_have_gum
}

ui_plain() {
  printf '%s\n' "$*" >&2
}

ui_dim() {
  printf '%s%s%s\n' "$UI_DIM" "$*" "$UI_RESET" >&2
}

ui_info() {
  printf '%s%s%s\n' "$UI_CYAN" "$*" "$UI_RESET" >&2
}

ui_success() {
  printf '%s✔ %s%s\n' "$UI_GREEN" "$*" "$UI_RESET" >&2
}

ui_warn() {
  printf '%s! %s%s\n' "$UI_YELLOW" "$*" "$UI_RESET" >&2
}

ui_error() {
  printf '%s✖ %s%s\n' "$UI_RED" "$*" "$UI_RESET" >&2
}

ui_header() {
  local text="$1"
  if ui_has_gum && gauth_is_tty; then
    "$GAUTH_GUM_BIN" style \
      --border rounded \
      --border-foreground 212 \
      --foreground 212 \
      --padding "0 2" \
      --margin "1 0" \
      "$text"
  else
    printf '%s%s%s\n' "$UI_BOLD$UI_MAGENTA" "$text" "$UI_RESET"
    printf '%s\n' "----------------------------------------"
  fi
}

ui_section() {
  printf '\n%s%s%s\n' "$UI_BOLD$UI_BLUE" "$1" "$UI_RESET" >&2
}

ui_prompt_hint() {
  [ -n "${1:-}" ] && printf '%s%s%s\n' "$UI_DIM" "$1" "$UI_RESET" >&2
  return 0
}

ui_input() {
  local header="$1"
  local placeholder="${2:-}"
  local default="${3:-}"
  local answer=""

  if ui_has_gum && gauth_is_tty; then
    if [ -n "$default" ]; then
      answer="$("$GAUTH_GUM_BIN" input --header "$header" --placeholder "$placeholder" --value "$default")" || return 1
    else
      answer="$("$GAUTH_GUM_BIN" input --header "$header" --placeholder "$placeholder")" || return 1
    fi
    printf '%s\n' "$answer"
    return 0
  fi

  printf '%s' "$header" >&2
  [ -n "$placeholder" ] && printf ' %s(%s)%s' "$UI_DIM" "$placeholder" "$UI_RESET" >&2
  printf ': ' >&2
  IFS= read -r answer || return 1
  [ -n "$answer" ] || answer="$default"
  printf '%s\n' "$answer"
}

ui_password() {
  local header="$1"
  local answer=""

  if ui_has_gum && gauth_is_tty; then
    answer="$("$GAUTH_GUM_BIN" input --password --header "$header")" || return 1
    printf '%s\n' "$answer"
    return 0
  fi

  printf '%s: ' "$header" >&2
  IFS= read -r -s answer || return 1
  printf '\n' >&2
  printf '%s\n' "$answer"
}

ui_confirm() {
  local prompt="$1"
  local default="${2:-no}"
  local answer=""

  if ui_has_gum && gauth_is_tty; then
    if [ "$default" = "yes" ]; then
      "$GAUTH_GUM_BIN" confirm --default "$prompt"
    else
      "$GAUTH_GUM_BIN" confirm "$prompt"
    fi
    return $?
  fi

  if [ "$default" = "yes" ]; then
    printf '%s [Y/n]: ' "$prompt" >&2
  else
    printf '%s [y/N]: ' "$prompt" >&2
  fi
  IFS= read -r answer || return 1
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    n|N|no|NO) return 1 ;;
    "") [ "$default" = "yes" ] && return 0 || return 1 ;;
  esac
  return 1
}

ui_choose() {
  local header="$1"
  shift
  local choice=""

  if [ "$#" -eq 0 ]; then
    return 1
  fi

  if ui_has_gum && gauth_is_tty; then
    choice="$("$GAUTH_GUM_BIN" choose --header "$header" "$@")" || return 1
    printf '%s\n' "$choice"
    return 0
  fi

  printf '%s\n' "$header" >&2
  local i=1
  local option
  for option in "$@"; do
    printf '  %s) %s\n' "$i" "$option" >&2
    i=$((i + 1))
  done
  printf 'Select: ' >&2
  IFS= read -r choice || return 1
  case "$choice" in
    ''|*[!0-9]*) return 1 ;;
  esac
  if [ "$choice" -lt 1 ] || [ "$choice" -gt "$#" ]; then
    return 1
  fi
  i=1
  for option in "$@"; do
    if [ "$i" -eq "$choice" ]; then
      printf '%s\n' "$option"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

ui_confirm_or_die() {
  local prompt="$1"
  ui_confirm "$prompt" "${2:-no}" || gauth_die "Cancelled."
}

ui_spin() {
  local title="$1"
  shift
  if [ "$#" -eq 0 ]; then
    return 1
  fi
  if ui_has_gum && gauth_is_tty; then
    "$GAUTH_GUM_BIN" spin --spinner dot --title "$title" -- "$@"
  else
    ui_info "$title"
    "$@"
  fi
}

ui_pause() {
  gauth_pause "${1:-Press Enter to continue...}"
}

ui_kv() {
  local key="$1"
  local value="$2"
  printf '%s%-16s%s %s\n' "$UI_DIM" "$key" "$UI_RESET" "$value"
}

ui_rule() {
  printf '%s\n' "────────────────────────────────────────" >&2
}

ui_github_key_url() {
  printf 'https://github.com/settings/ssh/new\n'
}
