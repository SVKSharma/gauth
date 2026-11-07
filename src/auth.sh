# shellcheck shell=bash
# Administrator authentication for destructive actions.
#
# gauth never runs profile removal as root. The sudo password is only used to
# prove that the person asking for the destructive action controls the account;
# all file changes still happen as the current user. The password is read on the
# TTY and piped to `sudo -S`, so it never appears in argv or the environment.

GAUTH_SUDO_ATTEMPTS="${GAUTH_SUDO_ATTEMPTS:-3}"

# Tests point this at a fake binary. Users should normally leave it unset.
gauth_sudo_bin() {
  printf '%s\n' "${GAUTH_SUDO_BIN:-sudo}"
}

gauth_require_sudo_auth() {
  local purpose="${1:-this action}"

  if [ "$(id -u)" -eq 0 ]; then
    ui_success "Administrator session already active."
    return 0
  fi

  local sudo_bin
  sudo_bin="$(gauth_sudo_bin)"
  if ! gauth_command_exists "$sudo_bin"; then
    ui_error "sudo is required to authenticate before $purpose."
    ui_info "Install sudo, or ask an administrator to complete the action."
    return 1
  fi

  ui_section "Administrator authentication"
  ui_info "Removing a profile is a privileged action."
  ui_dim "sudo verifies your identity; gauth still edits only your own files."
  ui_dim "If sudo already has a valid timestamp, press Enter without typing a password."

  local attempt=1 password=""
  while [ "$attempt" -le "$GAUTH_SUDO_ATTEMPTS" ]; do
    if ! password="$(ui_password "sudo password for $(id -un)")"; then
      ui_info "Authentication cancelled."
      return 1
    fi

    if [ -z "$password" ]; then
      # An empty answer is acceptable only when sudo is cached or passwordless.
      if "$sudo_bin" -n -v >/dev/null 2>&1; then
        ui_success "Administrator authentication confirmed."
        return 0
      fi
      ui_error "The password cannot be empty."
    elif printf '%s\n' "$password" | "$sudo_bin" -S -p '' -v >/dev/null 2>&1; then
      password=""
      ui_success "Administrator authentication confirmed."
      return 0
    else
      password=""
      ui_error "Authentication failed ($attempt/$GAUTH_SUDO_ATTEMPTS)."
    fi
    attempt=$((attempt + 1))
  done

  ui_error "Too many failed authentication attempts; nothing was changed."
  return 1
}
