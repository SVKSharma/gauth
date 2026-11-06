# shellcheck shell=bash
# Terminal UI layer.
#
# Prompts read keys from stdin and draw on stderr, so callers can capture the
# answer with $(...). A prompt's stdout is therefore never treated as the
# terminal: interactivity is decided by stdin + stderr, not stdout.
#
# Prompt return codes:
#   0  a value was produced
#   1  the UI is unavailable or the answer was empty/EOF
#   2  the user went back (Esc, ctrl-c, or the "‹ Back" item)

UI_BACK_LABEL="‹ Back"
UI_NEW_PROFILE_LABEL="＋ New profile"

# Modern, low-saturation palette (blue/teal/amber), never the default pink.
UI_ACCENT_HEX="#7aa2f7"
UI_SUCCESS_HEX="#9ece6a"
UI_WARN_HEX="#e0af68"
UI_ERROR_HEX="#f7768e"
UI_MUTED_HEX="#565f89"
UI_TEXT_HEX="#c0caf5"
UI_BORDER_HEX="#3b4261"

UI_COLOR_ENABLED=0
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
  UI_COLOR_ENABLED=1
fi

UI_256=0
case "${TERM:-}:${COLORTERM:-}" in
  *256color*|*truecolor*|*24bit*) UI_256=1 ;;
esac

if [ "$UI_COLOR_ENABLED" -eq 1 ]; then
  UI_RESET=$'\033[0m'
  UI_BOLD=$'\033[1m'
  UI_DIM=$'\033[2m'
  if [ "$UI_256" -eq 1 ]; then
    UI_ACCENT=$'\033[38;5;111m'
    UI_GREEN=$'\033[38;5;114m'
    UI_YELLOW=$'\033[38;5;179m'
    UI_RED=$'\033[38;5;203m'
    UI_MUTED=$'\033[38;5;60m'
    UI_TEXT=$'\033[38;5;147m'
  else
    UI_ACCENT=$'\033[36m'
    UI_GREEN=$'\033[32m'
    UI_YELLOW=$'\033[33m'
    UI_RED=$'\033[31m'
    UI_MUTED=$'\033[2m'
    UI_TEXT=""
  fi
  UI_CYAN="$UI_ACCENT"
  UI_BLUE="$UI_ACCENT"
  UI_MAGENTA="$UI_ACCENT"
else
  UI_RESET=""
  UI_BOLD=""
  UI_DIM=""
  UI_ACCENT=""
  UI_GREEN=""
  UI_YELLOW=""
  UI_RED=""
  UI_MUTED=""
  UI_TEXT=""
  UI_CYAN=""
  UI_BLUE=""
  UI_MAGENTA=""
fi

ui_has_gum() {
  gauth_have_gum
}

# gum can only drive a real terminal. stdout may be a pipe; stdin/stderr are
# what matter.
ui_interactive() {
  [ -t 0 ] && [ -t 2 ]
}

ui_plain() {
  printf '%s\n' "$*" >&2
}

ui_dim() {
  printf '%s%s%s\n' "$UI_DIM" "$*" "$UI_RESET" >&2
}

ui_info() {
  printf '%s%s%s\n' "$UI_ACCENT" "$*" "$UI_RESET" >&2
}

ui_success() {
  printf '%s✔%s %s\n' "$UI_GREEN" "$UI_RESET" "$*" >&2
}

ui_warn() {
  printf '%s!%s %s\n' "$UI_YELLOW" "$UI_RESET" "$*" >&2
}

ui_error() {
  printf '%s✖%s %s\n' "$UI_RED" "$UI_RESET" "$*" >&2
}

ui_hint() {
  printf '%s%s%s\n' "$UI_DIM" "$1" "$UI_RESET" >&2
}

# Keybinding legend shown under menus.
ui_nav_hint() {
  printf '%s↑/↓ j/k · ←/→ h/l · Shift+H back · Shift+L forward · enter select · esc back%s\n' \
    "$UI_DIM" "$UI_RESET" >&2
}

# Menu history stack for Shift+H (back) / Shift+L (forward) navigation.
# Each entry is a submenu id (e.g. "add", "settings").
UI_HISTORY=()
UI_HISTORY_POS=-1

ui_history_record() {
  local action="$1"
  # Drop any forward entries when a new action is chosen.
  if [ "$UI_HISTORY_POS" -ge 0 ] && [ "$UI_HISTORY_POS" -lt "$((${#UI_HISTORY[@]} - 1))" ]; then
    UI_HISTORY=("${UI_HISTORY[@]:0:$((UI_HISTORY_POS + 1))}")
  fi
  UI_HISTORY+=("$action")
  UI_HISTORY_POS=$((${#UI_HISTORY[@]} - 1))
}

ui_history_back() {
  if [ "$UI_HISTORY_POS" -gt 0 ]; then
    UI_HISTORY_POS=$((UI_HISTORY_POS - 1))
    return 0
  fi
  return 1
}

ui_history_forward() {
  if [ "$UI_HISTORY_POS" -ge 0 ] && [ "$UI_HISTORY_POS" -lt "$((${#UI_HISTORY[@]} - 1))" ]; then
    UI_HISTORY_POS=$((UI_HISTORY_POS + 1))
    return 0
  fi
  return 1
}

ui_history_current() {
  [ "$UI_HISTORY_POS" -ge 0 ] && [ "$UI_HISTORY_POS" -lt "${#UI_HISTORY[@]}" ] || return 1
  printf '%s\n' "${UI_HISTORY[$UI_HISTORY_POS]}"
}

# Enhanced header with gum style
ui_header() {
  local text="$1"
  if ui_has_gum && ui_interactive; then
    "$GAUTH_GUM_BIN" style \
      --border rounded \
      --border-foreground "$UI_BORDER_HEX" \
      --foreground "$UI_ACCENT_HEX" \
      --bold \
      --padding "0 2" \
      --margin "1 0 0 0" \
      -- "$text" >&2
    return 0
  fi
  printf '\n%s▌ %s%s\n' "$UI_BOLD$UI_ACCENT" "$text" "$UI_RESET" >&2
}

# Enhanced section with gum style
ui_section() {
  local text="$1"
  if ui_has_gum && ui_interactive; then
    "$GAUTH_GUM_BIN" style \
      --foreground "$UI_ACCENT_HEX" \
      --bold \
      --margin "1 0 0 2" \
      -- "▌ $text" >&2
    return 0
  fi
  printf '\n%s▌ %s%s\n' "$UI_BOLD$UI_ACCENT" "$text" "$UI_RESET" >&2
}

ui_rule() {
  printf '%s%s%s\n' "$UI_MUTED" "──────────────────────────────────────────" "$UI_RESET" >&2
}

ui_prompt_hint() {
  [ -n "${1:-}" ] && ui_hint "$1"
  return 0
}

ui_kv() {
  printf '  %s%-15s%s %s%s%s\n' "$UI_MUTED" "$1" "$UI_RESET" "$UI_TEXT" "$2" "$UI_RESET" >&2
}

ui_badge() {
  printf '%s%s%s %s\n' "$UI_ACCENT" "●" "$UI_RESET" "$*" >&2
}

# ---------------------------------------------------------------------------
# Vertical stepper: one dot per step, joined like a commit graph.
#   ● done   ◉ current   ○ pending
# ---------------------------------------------------------------------------
ui_stepper() {
  local current="$1"
  shift
  local total=$#
  [ "$total" -gt 0 ] || return 0

  local i=0 label marker connector num
  printf '\n' >&2
  for label in "$@"; do
    num=$((i + 1))
    if [ "$i" -lt "$current" ]; then
      marker="${UI_GREEN}●${UI_RESET}"
      connector="${UI_GREEN}│${UI_RESET}"
      printf '  %s  %s%02d%s  %s%s%s\n' \
        "$marker" "$UI_MUTED" "$num" "$UI_RESET" "$UI_DIM" "$label" "$UI_RESET" >&2
    elif [ "$i" -eq "$current" ]; then
      marker="${UI_ACCENT}${UI_BOLD}◉${UI_RESET}"
      connector="${UI_MUTED}│${UI_RESET}"
      printf '  %s  %s%02d%s  %s%s%s\n' \
        "$marker" "$UI_ACCENT" "$num" "$UI_RESET" "$UI_BOLD" "$label" "$UI_RESET" >&2
    else
      marker="${UI_MUTED}○${UI_RESET}"
      connector="${UI_MUTED}│${UI_RESET}"
      printf '  %s  %s%02d%s  %s%s%s\n' \
        "$marker" "$UI_MUTED" "$num" "$UI_RESET" "$UI_DIM" "$label" "$UI_RESET" >&2
    fi
    if [ "$i" -lt "$((total - 1))" ]; then
      printf '  %s\n' "$connector" >&2
    fi
    i=$((i + 1))
  done
  printf '\n' >&2
}

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
ui_input() {
  local header="$1"
  local placeholder="${2:-}"
  local default="${3:-}"
  local answer=""

  if ui_has_gum && ui_interactive; then
    local args=(input --header "$header" --header.foreground "$UI_ACCENT_HEX"
      --prompt "❯ " --prompt.foreground "$UI_ACCENT_HEX"
      --placeholder "$placeholder" --cursor.foreground "$UI_ACCENT_HEX")
    if [ -n "$default" ]; then
      args+=(--value "$default")
    fi
    if answer="$("$GAUTH_GUM_BIN" "${args[@]}")"; then
      printf '%s\n' "$answer"
      return 0
    fi
    return 2
  fi

  if ! [ -t 0 ]; then
    IFS= read -r answer || return 1
    [ -n "$answer" ] || answer="$default"
    printf '%s\n' "$answer"
    return 0
  fi

  printf '%s%s%s ' "$UI_ACCENT" "$header" "$UI_RESET" >&2
  [ -n "$placeholder" ] && printf '%s(%s) %s' "$UI_DIM" "$placeholder" "$UI_RESET" >&2
  [ -n "$default" ] && printf '%s[%s] %s' "$UI_MUTED" "$default" "$UI_RESET" >&2
  printf '❯ ' >&2
  IFS= read -r answer || return 1
  case "$answer" in
    ':b'|'back'|'BACK') return 2 ;;
  esac
  [ -n "$answer" ] || answer="$default"
  printf '%s\n' "$answer"
}

ui_password() {
  local header="$1"
  local answer=""

  if ui_has_gum && ui_interactive; then
    if answer="$("$GAUTH_GUM_BIN" input --password --header "$header" \
      --header.foreground "$UI_ACCENT_HEX" --prompt "❯ " \
      --prompt.foreground "$UI_ACCENT_HEX")"; then
      printf '%s\n' "$answer"
      return 0
    fi
    return 2
  fi

  printf '%s%s%s ❯ ' "$UI_ACCENT" "$header" "$UI_RESET" >&2
  IFS= read -r -s answer || return 1
  printf '\n' >&2
  printf '%s\n' "$answer"
}

# ---------------------------------------------------------------------------
# Confirmation. Returns 0 for yes, 1 for no (abort counts as no).
# ---------------------------------------------------------------------------
ui_confirm() {
  local prompt="$1"
  local default="${2:-no}"
  local answer=""

  if ui_has_gum && ui_interactive; then
    local args=(confirm --prompt.foreground "$UI_ACCENT_HEX"
      --selected.foreground "#1a1b26" --selected.background "$UI_ACCENT_HEX"
      --unselected.foreground "$UI_TEXT_HEX")
    [ "$default" = "yes" ] && args+=(--default)
    "$GAUTH_GUM_BIN" "${args[@]}" -- "$prompt"
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
    '') [ "$default" = "yes" ] && return 0 || return 1 ;;
  esac
  return 1
}

# ---------------------------------------------------------------------------
# Plain-ANSI menu: arrows or j/k, enter to select, esc to go back.
# No numbers, no required gum.
# ---------------------------------------------------------------------------
ui_menu_raw() {
  local header="$1"
  shift
  local -a items=()
  local item
  for item in "$@"; do
    items+=("$item")
  done
  local count=${#items[@]}
  [ "$count" -gt 0 ] || return 1

  local tty=/dev/tty
  [ -r "$tty" ] || return 1
  local saved
  saved="$(stty -g <"$tty" 2>/dev/null)" || return 1
  stty -echo -icanon min 1 time 0 <"$tty" 2>/dev/null || return 1
  printf '\033[?25l' >&2

  local selected=0 drawn=0 key rest first=1
  while :; do
    if [ "$first" -eq 1 ]; then
      first=0
    else
      printf '\033[%dA\r\033[J' "$drawn" >&2
    fi
    drawn=0
    if [ -n "$header" ]; then
      printf '%s❯ %s%s\n' "$UI_BOLD$UI_ACCENT" "$header" "$UI_RESET" >&2
      drawn=$((drawn + 1))
    fi
    local i=0
    for item in "${items[@]}"; do
      if [ "$i" -eq "$selected" ]; then
        printf '  %s❯%s %s%s%s\n' "$UI_ACCENT" "$UI_RESET" "$UI_BOLD" "$item" "$UI_RESET" >&2
      else
        printf '    %s%s%s\n' "$UI_TEXT" "$item" "$UI_RESET" >&2
      fi
      drawn=$((drawn + 1))
      i=$((i + 1))
    done
    printf '%s↑/↓ j/k move · h/l or ←/→ step · Shift+H back · Shift+L forward · esc back%s\n' "$UI_DIM" "$UI_RESET" >&2
    drawn=$((drawn + 1))

    IFS= read -rsn1 key <"$tty" || {
      stty "$saved" <"$tty" 2>/dev/null
      printf '\033[?25h' >&2
      return 1
    }
    case "$key" in
      ''|$'\r'|$'\n') break ;;
      k|K) [ "$selected" -gt 0 ] && selected=$((selected - 1)) ;;
      j|J) [ "$selected" -lt "$((count - 1))" ] && selected=$((selected + 1)) ;;
      h|H)
        stty "$saved" <"$tty" 2>/dev/null
        printf '\033[?25h' >&2
        return 2
        ;;
      g) selected=0 ;;
      G) selected=$((count - 1)) ;;
      l|L)
        stty "$saved" <"$tty" 2>/dev/null
        printf '\033[?25h' >&2
        return 3
        ;;
      q) stty "$saved" <"$tty" 2>/dev/null
        printf '\033[?25h' >&2
        return 2 ;;
      $'\033')
        # Distinguish a bare Esc (back) from a CSI/SS3 arrow sequence. A plain
        # read with VMIN=0/VTIME=1 returns empty after ~0.1s for a bare Esc,
        # and returns the buffered bytes ("[A", "OD", ...) for arrows. This
        # works on Bash 3.2 without fractional `read -t`.
        stty min 0 time 1 <"$tty" 2>/dev/null
        rest=""
        # A plain read returns nonzero when there is no trailing newline, but
        # it still fills `rest` with the buffered arrow bytes, so don't reset.
        IFS= read -r rest <"$tty" || true
        if [ -z "$rest" ]; then
          stty "$saved" <"$tty" 2>/dev/null
          printf '\033[?25h' >&2
          return 2
        fi
        case "$rest" in
          '['*|'O'*)
            key="${rest#?}"
            if [ -z "$key" ]; then
              IFS= read -rsn1 key <"$tty" || key=""
            fi
            case "$key" in
              A) [ "$selected" -gt 0 ] && selected=$((selected - 1)) ;;
              B) [ "$selected" -lt "$((count - 1))" ] && selected=$((selected + 1)) ;;
              H) selected=0 ;;
              F) selected=$((count - 1)) ;;
              D)
                stty "$saved" <"$tty" 2>/dev/null
                printf '\033[?25h' >&2
                return 2
                ;;
              C)
                stty "$saved" <"$tty" 2>/dev/null
                printf '\033[?25h' >&2
                return 3
                ;;
            esac
            ;;
        esac
        stty min 1 time 0 <"$tty" 2>/dev/null
        ;;
    esac
  done

  stty "$saved" <"$tty" 2>/dev/null
  printf '\033[?25h' >&2
  printf '\n' >&2
  printf '%s\n' "${items[$selected]}"
}

# ---------------------------------------------------------------------------
# Choice. Vim keys and arrows in both backends; Esc returns 2.
# ---------------------------------------------------------------------------
ui_choose() {
  local header="$1"
  shift
  [ "$#" -gt 0 ] || return 1

  # The custom menu is the default because it provides the vim-style
  # navigation (j/k, h/l, Shift+H/Shift+L, g/G, Esc) the project documents.
  # Set GAUTH_GUM_CHOOSE=1 to use gum's own chooser instead.
  if ui_interactive && [ "${GAUTH_GUM_CHOOSE:-0}" != "1" ]; then
    if ui_has_gum; then
      "$GAUTH_GUM_BIN" style \
        --border rounded \
        --border-foreground "$UI_BORDER_HEX" \
        --foreground "$UI_ACCENT_HEX" \
        --bold \
        --padding "0 1" \
        --margin "1 0 0 0" \
        -- "$header" >&2
      ui_menu_raw "" "$@"
    else
      ui_menu_raw "$header" "$@"
    fi
    return $?
  fi

  if ui_has_gum && ui_interactive; then
    local height=$#
    [ "$height" -gt 14 ] && height=14
    local choice
    if choice="$("$GAUTH_GUM_BIN" choose \
      --header "$header" \
      --header.foreground "$UI_ACCENT_HEX" \
      --cursor "❯ " \
      --cursor.foreground "$UI_ACCENT_HEX" \
      --selected.foreground "$UI_ACCENT_HEX" \
      --item.foreground "$UI_TEXT_HEX" \
      --height "$height" \
      -- "$@")"; then
      printf '%s\n' "$choice"
      return 0
    fi
    return 2
  fi

  if ui_interactive; then
    ui_menu_raw "$header" "$@"
    return $?
  fi

  # Non-interactive: read one line from stdin. An exact option wins; a 1-based
  # number is accepted so scripts and tests can drive the same helpers.
  local line option candidate
  if ! IFS= read -r line; then
    return 1
  fi
  for option in "$@"; do
    if [ "$option" = "$line" ]; then
      printf '%s\n' "$option"
      return 0
    fi
  done
  case "$line" in
    ''|*[!0-9]*) return 1 ;;
  esac
  if [ "$line" -lt 1 ] || [ "$line" -gt "$#" ]; then
    return 1
  fi
  shift $((line - 1))
  candidate="$1"
  printf '%s\n' "$candidate"
  return 0
}

ui_confirm_or_die() {
  local prompt="$1"
  ui_confirm "$prompt" "${2:-no}" || gauth_die "Cancelled."
}

# ---------------------------------------------------------------------------
# Spinner around a command that produces output. The animated frames are plain
# ANSI, so this also works without gum.
# ---------------------------------------------------------------------------
UI_TASK_OUTPUT=""
UI_SPIN_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

# Runs in the foreground so shell functions can set globals (SSH_TEST_OUTPUT,
# SSH_AUTH_SOCK, ...) while a spinner animates on stderr. stdout and stderr of
# the command are captured into UI_TASK_OUTPUT.
ui_task() {
  local title="$1"
  shift
  [ "$#" -gt 0 ] || return 1

  local out rc
  out="$(mktemp "${TMPDIR:-/tmp}/gauth-task.XXXXXX")" || return 1
  UI_TASK_OUTPUT=""

  if ! ui_interactive; then
    "$@" >"$out" 2>&1
    rc=$?
    UI_TASK_OUTPUT="$(cat "$out" 2>/dev/null)"
    rm -f "$out"
    return "$rc"
  fi

  # Modern braille spinner, drawn in the accent color. The task itself must run
  # in this shell (not a child) so functions can export globals to the caller.
  local pid i=0
  (
    while :; do
      printf '\r%s%s %s%s' "$UI_ACCENT" "${UI_SPIN_FRAMES[$((i % 10))]}" "$title" "$UI_RESET" >&2
      i=$((i + 1))
      sleep 0.08
    done
  ) &
  pid=$!

  "$@" >"$out" 2>&1
  rc=$?

  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  printf '\r\033[2K' >&2

  UI_TASK_OUTPUT="$(cat "$out" 2>/dev/null)"
  rm -f "$out"
  return "$rc"
}

ui_spin() {
  local title="$1"
  shift
  [ "$#" -gt 0 ] || return 1
  ui_task "$title" "$@"
}

ui_pause() {
  gauth_pause "${1:-Press enter to continue…}"
}

ui_github_key_url() {
  printf 'https://github.com/settings/ssh/new\n'
}
