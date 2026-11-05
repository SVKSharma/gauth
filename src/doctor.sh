# shellcheck shell=bash
# Diagnostics and permission repair.

DOCTOR_FAILURES=0

doctor_ok() {
  printf '%s✔%s %s\n' "$UI_GREEN" "$UI_RESET" "$*"
}

doctor_warn() {
  printf '%s!%s %s\n' "$UI_YELLOW" "$UI_RESET" "$*"
}

doctor_bad() {
  printf '%s✖%s %s\n' "$UI_RED" "$UI_RESET" "$*"
  DOCTOR_FAILURES=$((DOCTOR_FAILURES + 1))
}

doctor_check_mode() {
  local path="$1"
  local label="$2"
  local expected="$3"
  if [ ! -e "$path" ]; then
    doctor_warn "$label does not exist: $path"
    return 0
  fi
  local mode
  mode="$(gauth_file_mode "$path")"
  if [ -z "$mode" ]; then
    doctor_warn "$label permission could not be read: $path"
    return 0
  fi
  if [ "$mode" = "$expected" ]; then
    doctor_ok "$label permissions: $mode"
  else
    doctor_warn "$label permissions are $mode (expected $expected): $path"
  fi
}

doctor_fix_permissions() {
  ui_header "Repair permissions"
  ui_info "This only changes file modes; it does not rewrite config contents."
  ui_confirm "Repair gauth/SSH permissions now?" no || return 0

  [ -d "$GAUTH_SSH_DIR" ] && chmod 700 "$GAUTH_SSH_DIR"
  [ -f "$GAUTH_SSH_CONFIG" ] && chmod 600 "$GAUTH_SSH_CONFIG"
  [ -f "$GAUTH_ACCOUNTS_FILE" ] && chmod 600 "$GAUTH_ACCOUNTS_FILE"
  [ -f "$GAUTH_SETTINGS_FILE" ] && chmod 600 "$GAUTH_SETTINGS_FILE"

  local name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    account_load "$name" || continue
    [ -f "$ACC_KEY" ] && chmod 600 "$ACC_KEY"
    [ -f "${ACC_KEY}.pub" ] && chmod 644 "${ACC_KEY}.pub"
  done < <(account_list_names)

  ui_success "Permissions repaired where possible."
}

doctor_check_account() {
  local name="$1"
  local test_connection="${2:-0}"
  account_load "$name" || {
    doctor_bad "Account record cannot be read: $name"
    return 1
  }

  ui_section "Account: $name"

  if [ -f "$ACC_KEY" ]; then
    doctor_ok "Private key exists: $ACC_KEY"
    local mode
    mode="$(gauth_file_mode "$ACC_KEY")"
    case "$mode" in
      600|400) doctor_ok "Private key permissions: $mode" ;;
      *) doctor_warn "Private key permissions are ${mode:-unknown}; run 'gauth doctor --fix'" ;;
    esac
  else
    doctor_bad "Private key is missing: $ACC_KEY"
  fi

  if [ -f "${ACC_KEY}.pub" ]; then
    doctor_ok "Public key exists: ${ACC_KEY}.pub"
  else
    doctor_warn "Public key is missing: ${ACC_KEY}.pub"
  fi

  if sshconfig_has_managed "$ACC_ALIAS"; then
    doctor_ok "gauth SSH config block exists: $ACC_ALIAS"
  elif sshconfig_alias_exists "$ACC_ALIAS"; then
    doctor_bad "Alias '$ACC_ALIAS' exists but is not managed by gauth"
  else
    doctor_bad "SSH config block is missing for alias: $ACC_ALIAS"
  fi

  local hostname
  hostname="$(ssh_config_hostname "$ACC_ALIAS" 2>/dev/null || true)"
  if [ "$hostname" = "$GAUTH_DEFAULT_HOST" ]; then
    doctor_ok "ssh resolves $ACC_ALIAS to $hostname"
  else
    doctor_bad "ssh -G $ACC_ALIAS did not resolve HostName=$GAUTH_DEFAULT_HOST"
  fi

  local identity
  identity="$(ssh_config_identity "$ACC_ALIAS" 2>/dev/null || true)"
  if [ "$identity" = "$ACC_KEY" ]; then
    doctor_ok "ssh resolves the expected IdentityFile"
  elif [ -n "$identity" ]; then
    doctor_warn "ssh resolves IdentityFile=$identity (expected $ACC_KEY)"
  else
    doctor_warn "ssh did not report an IdentityFile"
  fi

  if ssh_agent_running; then
    if ssh_agent_has_key "$ACC_KEY"; then
      doctor_ok "Key is loaded in ssh-agent"
    else
      doctor_warn "Key is not loaded in ssh-agent"
    fi
  else
    doctor_warn "No running ssh-agent (many setups still work without one)"
  fi

  if [ "$test_connection" = "1" ]; then
    ui_info "Testing git@${ACC_ALIAS} ..."
    if ssh_test_connection "$ACC_ALIAS"; then
      doctor_ok "GitHub SSH authentication works"
      account_update_verified "$name" "$(gauth_now)" || true
    else
      doctor_bad "GitHub SSH authentication failed"
      ssh_friendly_failure
    fi
  fi
  return 0
}

doctor_run() {
  local test_connection=0
  local fix=0
  local arg
  for arg in "$@"; do
    case "$arg" in
      --test) test_connection=1 ;;
      --fix) fix=1 ;;
      --help|-h)
        printf 'Usage: gauth doctor [--test] [--fix]\n'
        return 0
        ;;
    esac
  done

  gauth_init_paths
  config_init
  settings_load
  accounts_init
  DOCTOR_FAILURES=0

  ui_header "gauth doctor $GAUTH_VERSION"
  ui_section "Environment"
  printf '  %-18s %s\n' "OS" "$(uname -s 2>/dev/null) $(uname -m 2>/dev/null)"
  printf '  %-18s %s\n' "Bash" "$BASH_VERSION"
  printf '  %-18s %s\n' "Config" "$GAUTH_CONFIG_HOME"
  printf '  %-18s %s\n' "SSH dir" "$GAUTH_SSH_DIR"

  if [ "${BASH_VERSINFO[0]}" -gt 3 ] || { [ "${BASH_VERSINFO[0]}" -eq 3 ] && [ "${BASH_VERSINFO[1]}" -ge 2 ]; }; then
    doctor_ok "Bash 3.2+ compatibility check passed"
  else
    doctor_bad "Bash 3.2+ is required"
  fi

  local tool
  for tool in git ssh ssh-keygen ssh-add ssh-agent; do
    if gauth_command_exists "$tool"; then
      doctor_ok "$tool found"
    else
      doctor_bad "$tool is missing"
    fi
  done

  if gauth_have_gum; then
    doctor_ok "gum found: $GAUTH_GUM_BIN ($("$GAUTH_GUM_BIN" --version 2>/dev/null | head -1))"
  else
    doctor_warn "gum not found; gauth will use its plain ANSI fallback UI"
  fi

  doctor_ok "Clipboard backend: $(clipboard_name)"

  ui_section "Files and permissions"
  doctor_check_mode "$GAUTH_SSH_DIR" "SSH directory" 700
  doctor_check_mode "$GAUTH_SSH_CONFIG" "SSH config" 600
  doctor_check_mode "$GAUTH_ACCOUNTS_FILE" "Accounts registry" 600
  doctor_check_mode "$GAUTH_SETTINGS_FILE" "Settings" 600

  ui_section "Accounts"
  local count
  count="$(account_count)"
  if [ "$count" -eq 0 ]; then
    doctor_warn "No accounts configured yet"
  else
    local name
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      doctor_check_account "$name" "$test_connection"
    done < <(account_list_names)
  fi

  ui_section "Repository"
  if git_is_repo; then
    doctor_ok "Current directory is a git repository ($(git_repo_summary))"
  else
    doctor_warn "Current directory is not a git repository"
  fi

  if [ "$fix" -eq 1 ]; then
    doctor_fix_permissions
  fi

  printf '\n'
  if [ "$DOCTOR_FAILURES" -eq 0 ]; then
    ui_success "Doctor finished with no blocking problems."
    return 0
  fi
  ui_error "Doctor found $DOCTOR_FAILURES blocking problem(s)."
  return 1
}
