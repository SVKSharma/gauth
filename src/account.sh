# shellcheck shell=bash
# Interactive account lifecycle.

account_add() {
  gauth_require_tty || return 1
  ssh_require_tools || return 1

  ui_header "Add a GitHub account"

  local name="" alias="" git_name="" email="" key_type="" key_path=""
  local key_choice="" generate=1 passphrase_mode="none"
  local default_alias default_git_name default_email default_key_path

  while :; do
    name="$(ui_input "Account name" "personal, work, client-a" "")" || return 1
    if ! validate_account_name "$name"; then
      ui_error "Use 1-64 chars: letters, numbers, dot, underscore, or hyphen."
      continue
    fi
    if account_exists "$name"; then
      ui_error "Account '$name' already exists."
      continue
    fi
    break
  done

  default_alias="${SETTING_DEFAULT_ALIAS_PREFIX}${name}"
  while :; do
    alias="$(ui_input "SSH alias" "Host name used in git@ALIAS:owner/repo.git" "$default_alias")" || return 1
    if ! validate_alias "$alias"; then
      ui_error "Use 1-128 chars: letters, numbers, dot, underscore, or hyphen."
      continue
    fi
    if account_alias_in_use "$alias" ""; then
      ui_error "Alias '$alias' is already used by another gauth account."
      continue
    fi
    if sshconfig_alias_exists "$alias" && ! sshconfig_has_managed "$alias"; then
      ui_error "Alias '$alias' already exists outside gauth. Choose another."
      continue
    fi
    break
  done

  default_git_name="$(git config --global user.name 2>/dev/null || true)"
  while :; do
    git_name="$(ui_input "Git user.name" "Name shown in commits" "$default_git_name")" || return 1
    if [ -z "$git_name" ] || gauth_has_control_chars "$git_name"; then
      ui_error "Git user.name cannot be empty."
      continue
    fi
    break
  done

  default_email="$(git config --global user.email 2>/dev/null || true)"
  while :; do
    email="$(ui_input "Git email" "you@example.com" "$default_email")" || return 1
    if ! validate_email "$email"; then
      ui_error "That does not look like a valid email address."
      continue
    fi
    break
  done

  key_choice="$(ui_choose "SSH key type" \
    "ed25519 (recommended)" \
    "rsa (4096-bit)" \
    "ecdsa (384-bit)")" || return 1
  case "$key_choice" in
    ed25519*) key_type="ed25519" ;;
    rsa*) key_type="rsa" ;;
    ecdsa*) key_type="ecdsa" ;;
    *) key_type="$SETTING_DEFAULT_KEY_TYPE" ;;
  esac

  default_key_path="$(ssh_default_key_path "$name" "$key_type")"
  key_path="$(ui_input "Private key path" "$default_key_path" "$default_key_path")" || return 1
  key_path="$(gauth_abs_path "$key_path")"
  [ -n "$key_path" ] || {
    ui_error "Key path cannot be empty."
    return 1
  }
  case "$key_path" in
    *[[:space:]]*|*'#'*)
      ui_error "Key path cannot contain whitespace or '#'."
      return 1
      ;;
  esac

  if [ -e "$key_path" ] || [ -e "${key_path}.pub" ]; then
    key_choice="$(ui_choose "Key file already exists" \
      "Use the existing key" \
      "Archive it and generate a new key" \
      "Cancel")" || return 1
    case "$key_choice" in
      "Use the existing key")
        generate=0
        if ! ssh_ensure_public_key "$key_path"; then
          ui_error "Could not read the existing key: $key_path"
          return 1
        fi
        chmod 600 "$key_path" 2>/dev/null || true
        chmod 644 "${key_path}.pub" 2>/dev/null || true
        ;;
      "Archive it and generate a new key")
        local archive_dest
        archive_dest="$(ssh_archive_key "$key_path")" || {
          ui_error "Could not archive the existing key."
          return 1
        }
        ui_info "Existing key archived at: $archive_dest"
        generate=1
        ;;
      *)
        ui_info "Cancelled."
        return 1
        ;;
    esac
  fi

  if [ "$generate" -eq 1 ]; then
    if ui_confirm "Protect the private key with a passphrase?" no; then
      passphrase_mode="prompt"
    else
      passphrase_mode="none"
    fi
    local key_dir
    key_dir="$(dirname "$key_path")"
    if [ ! -d "$key_dir" ]; then
      mkdir -p "$key_dir" 2>/dev/null || {
        ui_error "Cannot create key directory: $key_dir"
        return 1
      }
      chmod 700 "$key_dir" 2>/dev/null || true
    fi
    if ! ssh_generate_key "$key_path" "$email" "$key_type" "$passphrase_mode"; then
      return 1
    fi
  fi

  if ! sshconfig_upsert "$alias" "$key_path"; then
    ui_error "Could not update the SSH config for alias '$alias'."
    return 1
  fi

  if ! account_save "$name" "$alias" "$git_name" "$email" "$key_path" "$key_type"; then
    ui_error "Could not save the account record."
    return 1
  fi

  ui_success "Account '$name' saved."
  ui_kv "SSH alias" "$alias"
  ui_kv "Key" "$key_path"
  ui_kv "Fingerprint" "$(ssh_key_fingerprint "$key_path" 2>/dev/null || printf 'unknown')"

  if is_true "$SETTING_COPY_PUBLIC_KEY"; then
    clipboard_copy_public_key "$key_path" || true
  else
    printf '\n%s%s%s\n\n' "$UI_BOLD" "$(cat "${key_path}.pub")" "$UI_RESET"
  fi

  ui_section "Add this key to GitHub"
  ui_info "Open: https://github.com/settings/ssh/new"
  if ui_confirm "Open the GitHub SSH key page in your browser?" yes; then
    ssh_open_github_keys || ui_warn "Could not open a browser; use the URL above."
  fi
  ui_info "Paste the public key into GitHub, then return here."
  ui_pause

  if is_true "$SETTING_AUTO_START_AGENT"; then
    if ! ssh_agent_running; then
      if ssh_agent_start; then
        ui_success "ssh-agent started."
      else
        ui_warn "Could not start ssh-agent."
      fi
    fi
    if ssh_agent_running; then
      ssh_agent_add "$key_path" || true
    fi
    if [ -f "$GAUTH_AGENT_ENV" ]; then
      ssh_agent_instructions
    fi
  elif ui_confirm "Add the key to ssh-agent for this session?" yes; then
    if ! ssh_agent_running && ssh_agent_start; then
      :
    fi
    ssh_agent_add "$key_path" || true
  fi

  if ui_confirm "Test the GitHub SSH connection now?" yes; then
    ui_info "Testing git@${alias} ..."
    if ssh_test_connection "$alias"; then
      ui_success "GitHub authentication works."
      account_update_verified "$name" "$(gauth_now)" || true
    else
      ui_warn "SSH test did not succeed."
      ssh_friendly_failure
      ui_info "The account is saved. Run 'gauth doctor' after fixing the key on GitHub."
    fi
  fi

  if ui_confirm "Set up the current directory with this account now?" no; then
    repo_connect_flow "$name"
  fi
  return 0
}

account_remove() {
  gauth_require_tty || return 1
  local name
  name="$(account_pick "Remove which account?")" || return 1
  account_require "$name"

  ui_header "Remove account '$name'"
  account_print "$name"

  ui_confirm "Remove this account from gauth?" no || {
    ui_info "Cancelled."
    return 1
  }

  if account_alias_in_use "$ACC_ALIAS" "$name"; then
    ui_warn "Another account uses alias '$ACC_ALIAS'; leaving the SSH config block."
  elif sshconfig_has_managed "$ACC_ALIAS"; then
    if ui_confirm "Remove the gauth SSH config block for '$ACC_ALIAS'?" yes; then
      if sshconfig_remove "$ACC_ALIAS"; then
        ui_success "SSH config block removed."
      else
        ui_warn "Could not remove the SSH config block."
      fi
    fi
  else
    ui_warn "No gauth-managed SSH config block was found for '$ACC_ALIAS'."
  fi

  if [ -f "$ACC_KEY" ] || [ -f "${ACC_KEY}.pub" ]; then
    if account_key_in_use "$ACC_KEY" "$name"; then
      ui_warn "The key is shared with another account; leaving it in place."
    elif ui_confirm "Archive the key files instead of deleting them?" yes; then
      local archive_dest
      if archive_dest="$(ssh_archive_key "$ACC_KEY")"; then
        ui_info "Key archived at: $archive_dest"
      else
        ui_warn "Could not archive the key files."
      fi
    fi
  fi

  if account_delete "$name"; then
    ui_success "Account '$name' removed."
    ui_dim "Existing repositories still reference this account's remote URL."
  else
    ui_error "Could not remove the account record."
    return 1
  fi
  return 0
}

account_select_view() {
  local name
  name="$(account_pick "Select an account")" || return 1
  ui_header "Account details"
  account_print "$name"
  if git_is_repo; then
    ui_section "Current repository"
    ui_kv "Status" "$(git_repo_summary)"
  fi
  return 0
}

is_true() {
  gauth_is_true "$1"
}
