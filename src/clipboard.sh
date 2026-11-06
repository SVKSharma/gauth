# shellcheck shell=bash
# Clipboard support for the public key only.

clipboard_osc52() {
  local text="$1"
  gauth_command_exists base64 || return 1
  [ -r /dev/tty ] || return 1

  local encoded
  encoded="$(printf '%s' "$text" | base64 | tr -d '\r\n')"
  [ -n "$encoded" ] || return 1

  if [ -n "${TMUX:-}" ]; then
    printf '\033Ptmux;\033\033]52;c;%s\a\033\\' "$encoded" >/dev/tty 2>/dev/null || return 1
  else
    printf '\033]52;c;%s\a' "$encoded" >/dev/tty 2>/dev/null || return 1
  fi
  return 0
}

clipboard_copy() {
  local text="$1"

  case "$(uname -s 2>/dev/null)" in
    Darwin)
      if gauth_command_exists pbcopy; then
        printf '%s' "$text" | pbcopy && return 0
      fi
      ;;
  esac

  # Over SSH the remote clipboard tools usually target the remote machine,
  # so prefer the terminal's OSC 52 support.
  if [ -z "${SSH_CONNECTION:-}" ]; then
    if [ -n "${WAYLAND_DISPLAY:-}" ] && gauth_command_exists wl-copy; then
      printf '%s' "$text" | wl-copy >/dev/null 2>&1 && return 0
    fi
    if [ -n "${DISPLAY:-}" ]; then
      if gauth_command_exists xclip; then
        printf '%s' "$text" | xclip -selection clipboard >/dev/null 2>&1 && return 0
      fi
      if gauth_command_exists xsel; then
        printf '%s' "$text" | xsel --clipboard --input >/dev/null 2>&1 && return 0
      fi
    fi
  fi

  clipboard_osc52 "$text" && return 0
  return 1
}

clipboard_copy_public_key() {
  local key_path="$1"
  local pub="${key_path}.pub"

  if [ ! -f "$pub" ]; then
    ui_error "Public key not found: $pub"
    return 1
  fi

  local public_key
  public_key="$(cat "$pub" 2>/dev/null)"
  if [ -z "$public_key" ]; then
    ui_error "Public key is empty: $pub"
    return 1
  fi

  if clipboard_copy "$public_key"; then
    ui_success "Public key copied to the clipboard."
    return 0
  fi

  ui_warn "Could not reach a clipboard. Copy the key below manually:"
  printf '\n%s%s%s\n\n' "$UI_BOLD" "$public_key" "$UI_RESET" >&2
  return 1
}

# Always-visible public key block, so the key can be copied by hand even when
# the browser opens or the clipboard is unreachable.
clipboard_print_public_key() {
  local pub="$1"
  if [ ! -f "$pub" ]; then
    ui_warn "Public key not found: $pub"
    return 1
  fi
  local key
  key="$(cat "$pub" 2>/dev/null)"
  [ -n "$key" ] || {
    ui_warn "Public key is empty: $pub"
    return 1
  }

  if ui_has_gum && ui_interactive; then
    printf '%s\n' "$key" | "$GAUTH_GUM_BIN" style \
      --border normal \
      --border-foreground "$UI_BORDER_HEX" \
      --foreground "$UI_TEXT_HEX" \
      --padding "0 1" \
      --margin "0 1" >&2
  else
    printf '\n  %s\n\n' "$key" >&2
  fi
  return 0
}

clipboard_name() {
  case "$(uname -s 2>/dev/null)" in
    Darwin)
      gauth_command_exists pbcopy && { printf 'pbcopy\n'; return 0; }
      ;;
  esac
  if [ -n "${WAYLAND_DISPLAY:-}" ] && gauth_command_exists wl-copy; then
    printf 'wl-copy\n'
    return 0
  fi
  if [ -n "${DISPLAY:-}" ] && gauth_command_exists xclip; then
    printf 'xclip\n'
    return 0
  fi
  if [ -n "${DISPLAY:-}" ] && gauth_command_exists xsel; then
    printf 'xsel\n'
    return 0
  fi
  if gauth_command_exists base64 && [ -r /dev/tty ]; then
    printf 'OSC 52\n'
    return 0
  fi
  printf 'unavailable\n'
}
