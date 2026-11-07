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
#   2  the user went back (Esc, left arrow, h, or "‹ Back")
#   3  the user went forward (right arrow or l)
#   4  the user cancelled/quit (q or "✕ Cancel")

UI_BACK_LABEL="‹ Back"
UI_CANCEL_LABEL="✕ Cancel"
UI_NEW_PROFILE_LABEL="Add new profile"

# Menu items that match this label are drawn in green so the "create" action
# stands out from the saved profiles above it. Comparison and return values
# still use the plain label text.
UI_MENU_HIGHLIGHT="$UI_NEW_PROFILE_LABEL"

# Semantic palette: blue means information/navigation, green means success,
# amber means warning, and red means error. Each level also has its own glyph
# (✔ / ! / ✖), so meaning never depends on color alone.
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
    UI_SUCCESS=$'\033[1;38;5;114m'
    UI_GREEN=$'\033[38;5;114m'
    UI_YELLOW=$'\033[38;5;179m'
    UI_RED=$'\033[38;5;203m'
    UI_MUTED=$'\033[38;5;60m'
    UI_TEXT=$'\033[38;5;147m'
  else
    UI_ACCENT=$'\033[36m'
    UI_SUCCESS=$'\033[1;32m'
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
  UI_SUCCESS=""
  UI_GREEN=""
  UI_YELLOW=""
  UI_RED=""
  UI_MUTED=""
  UI_TEXT=""
  UI_CYAN=""
  UI_BLUE=""
  UI_MAGENTA=""
fi

# ---------------------------------------------------------------------------
# Pixel-block banner. The cat head with the terminal prompt mirrors the app
# icon in assets/, and the gradient changes each row so it reads as full color.
# ---------------------------------------------------------------------------
UI_BANNER_LOGO_ART=(
  "  ▄█▄    ▄█▄  "
  " ████████████ "
  " ██  ▀  ▀  ██ "
  " ██   >_   ██ "
  "  ▀████████▀  "
  "   ▀▀▀▀▀▀▀▀   "
)

UI_BANNER_WORD_ART=(
  " ██████╗  █████╗ ██╗   ██╗ ████████╗ ██╗  ██╗"
  "██╔════╝ ██╔══██╗██║   ██║ ╚══██╔══╝ ██║  ██║"
  "██║  ███╗███████║██║   ██║    ██║    ███████║"
  "██║   ██║██╔══██║██║   ██║    ██║    ██╔══██║"
  "╚██████╔╝██║  ██║╚██████╔╝    ██║    ██║  ██║"
  " ╚═════╝ ╚═╝  ╚═╝ ╚═════╝     ╚═╝    ╚═╝  ╚═╝"
)

if [ "$UI_COLOR_ENABLED" -eq 1 ]; then
  if [ "$UI_256" -eq 1 ]; then
    UI_BANNER_LOGO_COLORS=(
      $'\033[38;5;51m' $'\033[38;5;45m' $'\033[38;5;39m'
      $'\033[38;5;33m' $'\033[38;5;27m' $'\033[38;5;21m'
    )
    UI_BANNER_WORD_COLORS=(
      $'\033[38;5;45m' $'\033[38;5;51m' $'\033[38;5;63m'
      $'\033[38;5;69m' $'\033[38;5;105m' $'\033[38;5;141m'
    )
  else
    UI_BANNER_LOGO_COLORS=(
      $'\033[36m' $'\033[36m' $'\033[34m'
      $'\033[34m' $'\033[35m' $'\033[35m'
    )
    UI_BANNER_WORD_COLORS=(
      $'\033[36m' $'\033[34m' $'\033[35m'
      $'\033[36m' $'\033[34m' $'\033[35m'
    )
  fi
else
  UI_BANNER_LOGO_COLORS=("" "" "" "" "" "")
  UI_BANNER_WORD_COLORS=("" "" "" "" "" "")
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
  printf '%s✔ %s%s\n' "$UI_SUCCESS" "$*" "$UI_RESET" >&2
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

# A four-stop gradient rule, used above and below the banner.
ui_banner_rule() {
  printf '%s━━━━━━━━━━%s━━━━━━━━━━%s━━━━━━━━━━%s━━━━━━━━━━%s\n' \
    "${UI_BANNER_WORD_COLORS[0]}" \
    "${UI_BANNER_WORD_COLORS[1]}" \
    "${UI_BANNER_WORD_COLORS[2]}" \
    "${UI_BANNER_WORD_COLORS[3]}" \
    "$UI_RESET" >&2
}

# The cat-with-terminal pixel mark plus the wordmark. Interactive screens only;
# set GAUTH_NO_BANNER=1 for a compact, text-only session.
ui_banner() {
  [ "${GAUTH_NO_BANNER:-0}" = "1" ] && return 0
  ui_interactive || return 0
  [ "${#UI_BANNER_LOGO_ART[@]}" -eq 6 ] || return 0
  [ "${#UI_BANNER_WORD_ART[@]}" -eq 6 ] || return 0

  local i logo word
  printf '\n' >&2
  ui_banner_rule
  for i in 0 1 2 3 4 5; do
    logo="${UI_BANNER_LOGO_ART[$i]}"
    word="${UI_BANNER_WORD_ART[$i]}"
    printf '  %s%s%s  %s%s%s\n' \
      "${UI_BANNER_LOGO_COLORS[$i]}" "$logo" "$UI_RESET" \
      "${UI_BANNER_WORD_COLORS[$i]}" "$word" "$UI_RESET" >&2
  done
  printf '                  %sYour guided Git + GitHub connection%s  %sv%s%s\n' \
    "$UI_MUTED" "$UI_RESET" "$UI_SUCCESS" "$GAUTH_VERSION" "$UI_RESET" >&2
  ui_banner_rule
  printf '\n' >&2
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
# One key/byte from the terminal, without waiting for Enter. bash's
# `read -n 1` routes through readline on a terminal, which re-enables ISIG, so
# Ctrl-C would kill gauth instead of reaching our handler. dd/od reads the byte
# directly, keeping Esc and Ctrl-C usable. Result is in UI_KEY_CHAR.
UI_KEY_CHAR=""
ui_read_key() {
  local tty="$1"
  local code=""
  [ -r "$tty" ] || return 1

  if command -v dd >/dev/null 2>&1 && command -v od >/dev/null 2>&1; then
    code="$(dd bs=1 count=1 <"$tty" 2>/dev/null | od -An -tu1 2>/dev/null | tr -d ' \n')"
    [ -n "$code" ] || return 1
    printf -v UI_KEY_CHAR "\\$(printf '%03o' "$code")"
    return 0
  fi

  # Minimal system fallback; Ctrl-C may not be recoverable here.
  IFS= read -rsn1 UI_KEY_CHAR || return 1
  return 0
}

# Editable line for wizard prompts, read from the terminal without waiting for
# Enter for the navigation keys:
#   Esc               -> 2 (back)
#   Ctrl-C / Ctrl-D   -> 4 (cancel)
#   Enter             -> 0 and prints the line
# Only called once the prompt has been printed. Terminal settings are restored
# before returning, so an interrupted wizard never leaves the shell raw.
ui_read_editable_line() {
  local tty=/dev/tty
  [ -r "$tty" ] || return 1
  local saved
  saved="$(stty -g <"$tty" 2>/dev/null)" || return 1
  # -isig makes Ctrl-C arrive as a byte instead of killing the whole process,
  # so it can cancel the wizard and return to the menu.
  stty -echo -icanon min 1 time 0 -isig <"$tty" 2>/dev/null || return 1

  local line="" ch rc=0 n=0
  while :; do
    ui_read_key "$tty" || { rc=4; break; }
    ch="$UI_KEY_CHAR"
    case "$ch" in
      $'\r'|$'\n') break ;;
      $'\033')
        # A bare Esc goes back; a buffered arrow/CSI key (Esc [ A, ...) is
        # swallowed so its trailing bytes do not land in the next prompt.
        stty min 0 time 0 <"$tty" 2>/dev/null
        n=0
        while [ "$n" -lt 4 ] && ui_read_key "$tty"; do
          n=$((n + 1))
          case "$UI_KEY_CHAR" in
            '['|'O'|';'|'~'|[0-9]|[A-H]) ;;
            *) break ;;
          esac
        done
        stty min 1 time 0 <"$tty" 2>/dev/null
        rc=2
        break
        ;;
      $'\003'|$'\004') rc=4; break ;;
      $'\177'|$'\b')
        if [ -n "$line" ]; then
          line="${line%?}"
          printf '\b \b' >&2
        fi
        ;;
      $'\025')
        while [ -n "$line" ]; do
          line="${line%?}"
          printf '\b \b' >&2
        done
        ;;
      [[:cntrl:]]*) ;;
      *)
        line="$line$ch"
        printf '%s' "$ch" >&2
        ;;
    esac
  done

  stty "$saved" <"$tty" 2>/dev/null || true
  printf '\n' >&2
  [ "$rc" -eq 0 ] && printf '%s\n' "$line"
  return "$rc"
}

# The optional 4th argument adds wizard-style navigation: Enter keeps the
# value, ":back" returns 2, and ":cancel"/":q" returns 4. On a terminal, Esc
# and Ctrl-C do the same immediately, without needing Enter.
ui_input() {
  local header="$1"
  local placeholder="${2:-}"
  local default="${3:-}"
  local show_nav="${4:-0}"
  local answer=""

  if ui_has_gum && ui_interactive; then
    local args=(input --header "$header" --header.foreground "$UI_ACCENT_HEX"
      --prompt "❯ " --prompt.foreground "$UI_ACCENT_HEX"
      --placeholder "$placeholder" --cursor.foreground "$UI_ACCENT_HEX")
    if [ -n "$default" ]; then
      args+=(--value "$default")
    fi
    if answer="$("$GAUTH_GUM_BIN" "${args[@]}")"; then
      case "$answer" in
        ':b'|':back') return 2 ;;
        ':f'|':forward') return 3 ;;
        ':cancel'|':c'|':q') return 4 ;;
      esac
      printf '%s\n' "$answer"
      return 0
    fi
    return 2
  fi

  if ! [ -t 0 ]; then
    IFS= read -r answer || return 1
    case "$answer" in
      ':b'|':back') return 2 ;;
      ':f'|':forward') return 3 ;;
      ':cancel'|':c'|':q') return 4 ;;
    esac
    [ -n "$answer" ] || answer="$default"
    printf '%s\n' "$answer"
    return 0
  fi

  [ "$show_nav" -eq 1 ] && ui_hint "  Esc: back · Ctrl-C: cancel · :back · :forward"
  printf '%s%s%s ' "$UI_ACCENT" "$header" "$UI_RESET" >&2
  [ -n "$placeholder" ] && printf '%s(%s) %s' "$UI_DIM" "$placeholder" "$UI_RESET" >&2
  [ -n "$default" ] && printf '%s[%s] %s' "$UI_MUTED" "$default" "$UI_RESET" >&2
  printf '❯ ' >&2
  local read_rc=0
  answer="$(ui_read_editable_line)" || read_rc=$?
  [ "$read_rc" -eq 0 ] || return "$read_rc"
  case "$answer" in
    $'\033'*) return 2 ;;
    ':b'|':back'|'back'|'BACK') return 2 ;;
    ':f'|':forward') return 3 ;;
    ':c'|':cancel'|':q'|'cancel'|'CANCEL') return 4 ;;
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
# Plain-ANSI menu: arrows or j/k to move, h/left to go back one page, l/right
# to open the highlighted item, enter to select, q to quit.
#
# UI_MENU_CAN_BACK says whether a parent page exists (0 shows an inline notice
# instead of returning 2). UI_MENU_L_OPENS=1 means the menu is a navigation page
# (main menu, settings list), so l/right acts like Enter and opens the item.
# For value menus (key type, profiles, ...) l only reminds you to press Enter.
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

  local can_back="${UI_MENU_CAN_BACK:-1}"
  local l_opens="${UI_MENU_L_OPENS:-0}"

  local tty=/dev/tty
  [ -r "$tty" ] || return 1
  local saved
  saved="$(stty -g <"$tty" 2>/dev/null)" || return 1
  # -isig lets Ctrl-C cancel the menu instead of killing the process and
  # leaving the terminal in raw mode.
  stty -echo -icanon min 1 time 0 -isig <"$tty" 2>/dev/null || return 1
  printf '\033[?25l' >&2

  local selected=0 drawn=0 key rest first=1 notice=""
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
    local i=0 item_color
    for item in "${items[@]}"; do
      item_color="$UI_TEXT"
      if [ -n "${UI_MENU_HIGHLIGHT:-}" ] && [ "$item" = "$UI_MENU_HIGHLIGHT" ]; then
        item_color="$UI_GREEN"
      fi
      if [ "$i" -eq "$selected" ]; then
        printf '  %s❯%s %s%s%s\n' "$UI_ACCENT" "$UI_RESET" "$UI_BOLD$item_color" "$item" "$UI_RESET" >&2
      else
        printf '    %s%s%s\n' "$item_color" "$item" "$UI_RESET" >&2
      fi
      drawn=$((drawn + 1))
      i=$((i + 1))
    done
    printf '%s↑/↓ j/k move · h/← back · l/→ open · enter select · q/ctrl-c quit%s\n' "$UI_DIM" "$UI_RESET" >&2
    drawn=$((drawn + 1))
    if [ -n "$notice" ]; then
      printf '%s! %s%s\n' "$UI_YELLOW" "$notice" "$UI_RESET" >&2
      drawn=$((drawn + 1))
    fi

    ui_read_key "$tty" || {
      stty "$saved" <"$tty" 2>/dev/null
      printf '\033[?25h' >&2
      return 1
    }
    key="$UI_KEY_CHAR"
    case "$key" in
      ''|$'\r'|$'\n') break ;;
      k|K) [ "$selected" -gt 0 ] && selected=$((selected - 1)); notice="" ;;
      j|J) [ "$selected" -lt "$((count - 1))" ] && selected=$((selected + 1)); notice="" ;;
      g) selected=0; notice="" ;;
      G) selected=$((count - 1)); notice="" ;;
      h)
        if [ "$can_back" -eq 1 ]; then
          stty "$saved" <"$tty" 2>/dev/null
          printf '\033[?25h' >&2
          return 2
        fi
        notice="No previous screen. Press Enter to select an item, or q to quit."
        ;;
      l)
        # On navigation pages l/→ opens the highlighted item, exactly like Enter.
        if [ "$l_opens" -eq 1 ]; then
          break
        fi
        notice="Use Enter to select an item; l/→ does not choose."
        ;;
      q|Q|$'\003')
        # Distinct from "back": only q/Ctrl-C leaves the application at the
        # root menu.
        stty "$saved" <"$tty" 2>/dev/null
        printf '\033[?25h' >&2
        printf '\n' >&2
        return 4
        ;;
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
          if [ "$can_back" -eq 1 ]; then
            stty "$saved" <"$tty" 2>/dev/null
            printf '\033[?25h' >&2
            return 2
          fi
          notice="No previous screen. Press Enter to select an item, or q to quit."
        else
          case "$rest" in
            '['*|'O'*)
              key="${rest#?}"
              if [ -z "$key" ]; then
                IFS= read -rsn1 key <"$tty" || key=""
              fi
              case "$key" in
                A) [ "$selected" -gt 0 ] && selected=$((selected - 1)); notice="" ;;
                B) [ "$selected" -lt "$((count - 1))" ] && selected=$((selected + 1)); notice="" ;;
                H) selected=0; notice="" ;;
                F) selected=$((count - 1)); notice="" ;;
                D)
                  if [ "$can_back" -eq 1 ]; then
                    stty "$saved" <"$tty" 2>/dev/null
                    printf '\033[?25h' >&2
                    return 2
                  fi
                  notice="No previous screen. Press Enter to select an item, or q to quit."
                  ;;
                C)
                  if [ "$l_opens" -eq 1 ]; then
                    break
                  fi
                  notice="Use Enter to select an item; l/→ does not choose."
                  ;;
              esac
              ;;
          esac
        fi
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

# ui_choose with explicit page behaviour:
#   BACK_OK  1 when a parent page exists (h/Esc go back); 0 keeps the menu open
#            and shows "No previous screen..." instead.
#   L_OPENS  1 for navigation pages (main menu, settings list) where l/→ opens
#            the highlighted item; 0 for value menus, where only Enter selects.
ui_choose_nav() {
  local back_ok="$1"
  local l_opens="$2"
  shift 2
  local header="$1"
  shift
  [ "$#" -gt 0 ] || return 1

  local saved_back="${UI_MENU_CAN_BACK-}"
  local saved_opens="${UI_MENU_L_OPENS-}"
  UI_MENU_CAN_BACK="$back_ok"
  UI_MENU_L_OPENS="$l_opens"
  ui_choose "$header" "$@"
  local rc=$?
  UI_MENU_CAN_BACK="$saved_back"
  UI_MENU_L_OPENS="$saved_opens"
  return "$rc"
}

ui_choose() {
  local header="$1"
  shift
  [ "$#" -gt 0 ] || return 1

  # The custom menu is the default because it provides the vim-style
  # navigation (j/k, h/l, g/G, Esc) the project documents.
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

ui_github_key_url() {
  printf 'https://github.com/settings/ssh/new\n'
}
