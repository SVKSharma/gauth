# shellcheck shell=bash
# Profile lifecycle: add (step wizard), view, remove.

PROFILE_STEPS=(
  "Profile name"
  "SSH alias"
  "Git name"
  "Email"
  "Key type"
  "Key file"
  "Passphrase"
)

PROFILE_LAST_ADDED=""
PROFILE_KEY_ACTION="generate"

is_true() {
  gauth_is_true "$1"
}

# Item 4: a missing choice must never end the wizard. Anything unexpected
# falls back to the recommended algorithm.
profile_key_type_from_choice() {
  case "${1:-}" in
    ed25519*) printf 'ed25519\n' ;;
    rsa*) printf 'rsa\n' ;;
    ecdsa*) printf 'ecdsa\n' ;;
    *) printf '%s\n' "$GAUTH_DEFAULT_KEY_TYPE" ;;
  esac
}

# ---------------------------------------------------------------------------
# Add
# ---------------------------------------------------------------------------
profile_add() {
  local context="${1:-menu}"
  gauth_require_tty || return 1
  ssh_require_tools || return 1

  local name="" alias="" git_name="" email="" key_type="" key_path=""
  local key_action="generate" passphrase="no"
  local step=0 rc=0 total=${#PROFILE_STEPS[@]} max_step=0
  local candidate="" choice="" key_rc=0 decision="" dec_rc=0 fwd_ok=0
  local key_dir
  key_dir="$(ssh_key_dir)"

  # Modern welcome animation with gum
  if ui_has_gum && ui_interactive; then
    "$GAUTH_GUM_BIN" style \
      --border rounded \
      --border-foreground "$UI_ACCENT_HEX" \
      --foreground "$UI_ACCENT_HEX" \
      --bold \
      --padding "1 2" \
      --margin "1 0" \
      -- "Creating a new profile" >&2
    "$GAUTH_GUM_BIN" style \
      --foreground "$UI_MUTED_HEX" \
      --italic \
      --margin "0 0 1 2" \
      -- "Each step builds your GitHub identity: SSH key, git config, and aliases" >&2
    "$GAUTH_GUM_BIN" style \
      --foreground "$UI_MUTED_HEX" \
      --margin "0 0 1 2" \
      -- "Esc or h/←: back · l/→: forward · :cancel exits · enter: confirm" >&2
  else
    ui_header "Add new profile"
    ui_hint "h/← or Esc: back · l/→: forward · :cancel exits · the timeline records each choice."
  fi

  while [ "$step" -lt "$total" ]; do
    fwd_ok=0
    [ "$step" -lt "$max_step" ] && fwd_ok=1
    # Show the value chosen at each completed step, not just the step name.
    ui_stepper "$step" \
      "Profile name${name:+ [$name]}" \
      "SSH alias${alias:+ [$alias]}" \
      "Git name${git_name:+ [$git_name]}" \
      "Email${email:+ [$email]}" \
      "Key type${key_type:+ [$key_type]}" \
      "Key file${key_path:+ [${key_path##*/}]}" \
      "Passphrase${passphrase:+ [$passphrase]}"
    rc=0

    case "$step" in
      0)
        while :; do
          if candidate="$(ui_input "Profile name" "personal, work, client-a" "$name" 1)"; then
            :
          else
            rc=$?
            break
          fi
          candidate="$(gauth_trim "$candidate")"
          if ! validate_profile_name "$candidate"; then
            ui_error "Use 1-64 chars: letters, numbers, dot, underscore or hyphen."
            continue
          fi
          if profile_exists "$candidate"; then
            ui_warn "Profile '$candidate' already exists with this configuration:"
            if profile_load "$candidate"; then
              ui_kv "SSH alias" "$PROFILE_ALIAS"
              ui_kv "Git name" "$PROFILE_GIT_NAME"
              ui_kv "Email" "$PROFILE_EMAIL"
              ui_kv "Key" "$PROFILE_KEY"
            fi
            ui_hint "Choose a different name, or use 'View / select profile' to reuse it."
            continue
          fi
          name="$candidate"
          rc=0
          break
        done
        ;;

      1)
        local default_alias
        if [ -n "$alias" ]; then
          default_alias="$alias"
        else
          default_alias="${SETTING_DEFAULT_ALIAS_PREFIX}${name}"
        fi
        while :; do
          if candidate="$(ui_input "SSH alias" "host in git@ALIAS:owner/repo.git" "$default_alias" 1)"; then
            :
          else
            rc=$?
            break
          fi
          candidate="$(gauth_trim "$candidate")"
          if ! validate_alias "$candidate"; then
            ui_error "Use 1-128 chars: letters, numbers, dot, underscore or hyphen."
            continue
          fi
          if profile_alias_in_use "$candidate" ""; then
            ui_warn "Alias '$candidate' is already used by another profile."
            ui_hint "Choose a different alias, :back, or :cancel."
            continue
          fi
          if sshconfig_alias_exists "$candidate" && ! sshconfig_has_managed "$candidate"; then
            ui_error "Alias '$candidate' already exists outside gauth. Pick another."
            continue
          fi
          alias="$candidate"
          rc=0
          break
        done
        ;;

      2)
        local default_name="$git_name"
        if [ -z "$default_name" ]; then
          default_name="$(git config --global user.name 2>/dev/null || true)"
        fi
        while :; do
          if candidate="$(ui_input "Git user.name" "name shown in commits" "$default_name" 1)"; then
            :
          else
            rc=$?
            break
          fi
          candidate="$(gauth_trim "$candidate")"
          if [ -z "$candidate" ] || gauth_has_control_chars "$candidate"; then
            ui_error "Git user.name cannot be empty."
            continue
          fi
          git_name="$candidate"
          rc=0
          break
        done
        ;;

      3)
        local default_email="$email"
        if [ -z "$default_email" ]; then
          default_email="$(git config --global user.email 2>/dev/null || true)"
        fi
        while :; do
          if candidate="$(ui_input "Git email" "you@example.com" "$default_email" 1)"; then
            :
          else
            rc=$?
            break
          fi
          candidate="$(gauth_trim "$candidate")"
          if ! validate_email "$candidate"; then
            ui_error "That does not look like a valid email address."
            continue
          fi
          email="$candidate"
          rc=0
          break
        done
        ;;

      4)
        local -a key_options=("ed25519 (recommended)" "rsa (4096-bit)" "ecdsa (384-bit)")
        key_options+=("Skip — use the recommended type")
        key_options+=("$UI_BACK_LABEL")
        key_options+=("$UI_CANCEL_LABEL")
        key_rc=0
        choice="$(ui_choose_nav 1 "$fwd_ok" "Key type" "${key_options[@]}")" || key_rc=$?
        case "$key_rc" in
          0)
            case "$choice" in
              "$UI_BACK_LABEL") rc=2 ;;
              "$UI_CANCEL_LABEL") rc=4 ;;
              "Skip — use the recommended type")
                key_type="$GAUTH_DEFAULT_KEY_TYPE"
                ui_info "Using the recommended key type: $key_type."
                rc=0
                ;;
              *)
                key_type="$(profile_key_type_from_choice "$choice")"
                ui_info "Using key type: $key_type."
                rc=0
                ;;
            esac
            ;;
          4) rc=4 ;;
          2) rc=2 ;;
          *)
            # No selection (EOF/ctrl-c): never abort; use the recommended type.
            key_type="$GAUTH_DEFAULT_KEY_TYPE"
            ui_info "No selection made; using the recommended key type: $key_type."
            rc=0
            ;;
        esac
        ;;

      5)
        local default_file=""
        if [ -n "$key_path" ]; then
          default_file="${key_path##*/}"
        else
          default_file="$(ssh_default_key_path "$name" "${key_type:-$GAUTH_DEFAULT_KEY_TYPE}")"
          default_file="${default_file##*/}"
        fi
        while :; do
          if candidate="$(ui_input "SSH key file name" "stored in $key_dir" "$default_file" 1)"; then
            :
          else
            rc=$?
            break
          fi
          candidate="$(gauth_trim "$candidate")"
          candidate="${candidate%.pub}"
          case "$candidate" in
            ''|.|..|-*)
              ui_error "Enter a file name (not a path)."
              continue
              ;;
            */*|*\\*|*[[:space:]]*|*'#'*)
              ui_error "Enter only a file name; gauth stores keys in $key_dir."
              continue
              ;;
          esac
          candidate="$key_dir/$candidate"
          if [ -e "$candidate" ] || [ -e "${candidate}.pub" ]; then
            if profile_key_in_use "$candidate"; then
              ui_warn "This key is already used by another profile."
            fi
            dec_rc=0
            decision="$(ui_choose "Key file already exists" \
              "Use the existing key" \
              "Archive it and create a new key" \
              "$UI_BACK_LABEL" \
              "$UI_CANCEL_LABEL")" || dec_rc=$?
            if [ "$dec_rc" -ne 0 ]; then
              [ "$dec_rc" -eq 4 ] && rc=4 || rc=2
              break
            fi
            case "$decision" in
              "Use the existing key") key_action="use" ;;
              "Archive it and create a new key") key_action="archive" ;;
              "$UI_BACK_LABEL") rc=2; break ;;
              "$UI_CANCEL_LABEL") rc=4; break ;;
            esac
          else
            key_action="generate"
          fi
          key_path="$candidate"
          rc=0
          break
        done
        ;;

      6)
        if [ "$key_action" = "use" ]; then
          ui_hint "Reusing the existing key — nothing to generate."
          rc=0
        else
          local -a pp_options=("No passphrase (recommended)" "Yes — protect with a passphrase")
          pp_options+=("$UI_BACK_LABEL")
          pp_options+=("$UI_CANCEL_LABEL")
          key_rc=0
          choice="$(ui_choose "Protect the private key?" "${pp_options[@]}")" || key_rc=$?
          case "$key_rc" in
            0)
              case "$choice" in
                "$UI_BACK_LABEL") rc=2 ;;
                "$UI_CANCEL_LABEL") rc=4 ;;
                "Yes — protect with a passphrase") passphrase="yes"; rc=0 ;;
                *) passphrase="no"; rc=0 ;;
              esac
              ;;
            4) rc=4 ;;
            2) rc=2 ;;
            *) passphrase="no"; rc=0 ;;
          esac
        fi
        ;;
    esac

    case "$rc" in
      0)
        step=$((step + 1))
        [ "$step" -gt "$max_step" ] && max_step=$step
        ;;
      2)
        if [ "$step" -gt 0 ]; then
          step=$((step - 1))
          ui_hint "← back to ${PROFILE_STEPS[$step]}  (Shift+L to go forward)"
        else
          ui_info "Cancelled."
          return 1
        fi
        ;;
      3)
        if [ "$step" -lt "$max_step" ]; then
          step=$((step + 1))
          ui_hint "→ forward to ${PROFILE_STEPS[$step]}"
        else
          ui_hint "Already at the furthest step reached."
        fi
        ;;
      4)
        ui_info "Cancelled; no profile was created."
        return 1
        ;;
      *)
        ui_error "No answer; cancelling."
        return 1
        ;;
    esac
  done

  ui_stepper "$total" \
    "Profile name [$name]" \
    "SSH alias [$alias]" \
    "Git name [$git_name]" \
    "Email [$email]" \
    "Key type [$key_type]" \
    "Key file [${key_path##*/}]" \
    "Passphrase [$passphrase]"

  # Pre-flight: re-check everything after the wizard, before creating any files.
  if profile_exists "$name"; then
    ui_error "Profile '$name' already exists; nothing was changed."
    ui_info "Use 'View / select profile' to reuse it, or choose another name."
    return 1
  fi
  if profile_alias_in_use "$alias" ""; then
    ui_error "Alias '$alias' is already used by another profile; nothing was changed."
    return 1
  fi
  if [ "$key_action" = "generate" ] &&
     { [ -e "$key_path" ] || [ -e "${key_path}.pub" ]; }; then
    ui_error "Key file appeared while creating the profile: $key_path"
    ui_info "Nothing was changed. Re-run and choose 'Use the existing key'."
    return 1
  fi

  # -------------------------------------------------------------------------
  # Side effects
  # -------------------------------------------------------------------------
  if [ "$key_action" = "archive" ]; then
    local archived=""
    if ui_task "Archiving the existing key" ssh_archive_key "$key_path"; then
      archived="$UI_TASK_OUTPUT"
      ui_info "Existing key archived at: $archived"
    else
      ui_error "Could not archive the existing key: $key_path"
      return 1
    fi
  fi

  if [ "$key_action" != "use" ]; then
    if ! ssh_ensure_key_dir; then
      ui_error "Cannot create the key directory: $key_dir"
      return 1
    fi
    local pp_mode="none"
    [ "$passphrase" = "yes" ] && pp_mode="prompt"
    if ! ssh_generate_key "$key_path" "$email" "$key_type" "$pp_mode"; then
      return 1
    fi
    ui_success "Key created: $key_path"
  else
    if ! ssh_ensure_public_key "$key_path"; then
      ui_error "Could not read the existing key: $key_path"
      return 1
    fi
    chmod 600 "$key_path" 2>/dev/null || true
    chmod 644 "${key_path}.pub" 2>/dev/null || true
    ui_success "Reusing key: $key_path"
  fi

  if ! sshconfig_upsert "$alias" "$key_path"; then
    ui_error "Could not update the SSH config for alias '$alias'."
    ui_info "The key exists, but the profile was not saved."
    return 1
  fi

  if ! profile_save "$name" "$alias" "$git_name" "$email" "$key_path" "$key_type"; then
    ui_error "Could not save the profile record."
    return 1
  fi
  PROFILE_LAST_ADDED="$name"

  # Modern success display with gum
  if ui_has_gum && ui_interactive; then
    "$GAUTH_GUM_BIN" style \
      --border rounded \
      --border-foreground "$UI_SUCCESS_HEX" \
      --foreground "$UI_SUCCESS_HEX" \
      --bold \
      --padding "1 2" \
      --margin "1 0" \
      -- "Profile created successfully!" >&2
    "$GAUTH_GUM_BIN" style \
      --foreground "$UI_TEXT_HEX" \
      --margin "0 0 1 2" \
      -- "$(printf 'Profile: %s\nSSH alias: %s\nKey: %s\nFingerprint: %s' \
        "$name" "$alias" "$key_path" "$(ssh_key_fingerprint "$key_path" 2>/dev/null || printf 'unknown')")" >&2
  else
    ui_header "Profile ready"
    ui_kv "Profile" "$name"
    ui_kv "SSH alias" "$alias"
    ui_kv "Key" "$key_path"
    ui_kv "Fingerprint" "$(ssh_key_fingerprint "$key_path" 2>/dev/null || printf 'unknown')"
  fi

  if is_true "$SETTING_COPY_PUBLIC_KEY"; then
    clipboard_copy_public_key "$key_path" || true
  else
    ui_dim "Automatic clipboard copy is off."
  fi

  # Always show the key, even when the browser opens, so it can be copied by hand.
  ui_section "Add this key to GitHub"
  ui_hint "Copy the public key below (or from your clipboard) and paste it into GitHub."
  clipboard_print_public_key "${key_path}.pub"
  ui_info "Open: https://github.com/settings/ssh/new"
  if ui_confirm "Open the GitHub SSH key page in your browser?" yes; then
    ssh_open_github_keys || ui_warn "Could not open a browser; use the URL above."
  fi

  if is_true "$SETTING_AUTO_START_AGENT"; then
    if ! ssh_agent_running; then
      if ui_task "Starting ssh-agent" ssh_agent_start; then
        ui_success "ssh-agent started."
      else
        ui_warn "Could not start ssh-agent."
      fi
    fi
    if ssh_agent_running; then
      ssh_agent_add "$key_path" "$name" || true
    fi
    if [ -f "$GAUTH_AGENT_ENV" ]; then
      ssh_agent_instructions
    fi
  elif ui_confirm "Add the key to ssh-agent for this session?" yes; then
    ssh_agent_running || ui_task "Starting ssh-agent" ssh_agent_start || true
    ssh_agent_add "$key_path" "$name" || true
  fi

  if ui_confirm "Test the GitHub SSH connection now?" yes; then
    if ui_task "Testing git@$alias" ssh_test_connection "$alias"; then
      ui_success "GitHub authentication works."
      profile_update_verified "$name" "$(gauth_now)" || true
    else
      ui_warn "SSH test did not succeed."
      printf '%s\n' "$SSH_TEST_OUTPUT" >&2
      ssh_friendly_failure
      ui_info "The profile is saved. Fix the key on GitHub, then run 'gauth doctor'."
    fi
  fi

  if [ "$context" != "repo" ]; then
    if ui_confirm "Set up the current directory with this profile now?" no; then
      repo_connect_flow "$name"
      return $?
    fi
  fi

  # Finish with a clear "everything is fine, here is what to do next" summary.
  # (The repo flow prints its own next steps.)
  if [ "$context" != "repo" ]; then
    ui_section "All set"
    ui_success "Profile '$name' is ready to use."
    ui_info "In an existing project: cd <project> && gauth → 'Set up this repository'"
    ui_info "For a brand-new project: mkdir <project> && cd <project> && gauth"
    ui_dim "Run 'gauth doctor --test' any time to re-check the connection."
  fi
  return 0
}

# ---------------------------------------------------------------------------
# View / select
# ---------------------------------------------------------------------------
profile_select_view() {
  local name
  name="$(profile_pick "Select a profile")" || return 1

  if ui_has_gum && ui_interactive; then
    "$GAUTH_GUM_BIN" style \
      --border rounded \
      --border-foreground "$UI_ACCENT_HEX" \
      --foreground "$UI_ACCENT_HEX" \
      --bold \
      --padding "1 2" \
      --margin "1 0" \
      -- "Profile: $name" >&2
  else
    ui_header "Profile: $name"
  fi
  profile_print "$name"
  if git_is_repo; then
    ui_section "Current repository"
    ui_kv "Status" "$(git_repo_summary)"
  else
    ui_hint "Not inside a git repository."
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Remove
# ---------------------------------------------------------------------------
profile_remove() {
  gauth_require_tty || return 1
  local name
  name="$(profile_pick "Remove which profile?")" || return 1
  profile_require "$name" || return 1

  # Pre-flight: the registry must be rewritable. gauth never escalates
  # privileges, so explain exactly how to fix a root-owned file up front.
  if ! gauth_is_writable "$GAUTH_PROFILES_FILE"; then
    gauth_permission_hint "$GAUTH_PROFILES_FILE"
    ui_info "gauth never runs sudo; fix the ownership above and retry."
    return 1
  fi

  if ui_has_gum && ui_interactive; then
    "$GAUTH_GUM_BIN" style \
      --border rounded \
      --border-foreground "$UI_ERROR_HEX" \
      --foreground "$UI_ERROR_HEX" \
      --bold \
      --padding "1 2" \
      --margin "1 0" \
      -- "Remove profile: $name" >&2
  else
    ui_header "Remove profile '$name'"
  fi
  profile_print "$name"

  ui_confirm "Remove this profile from gauth?" no || {
    ui_info "Cancelled."
    return 1
  }

  if profile_alias_in_use "$PROFILE_ALIAS" "$name"; then
    ui_warn "Another profile uses alias '$PROFILE_ALIAS'; leaving the SSH block."
  elif sshconfig_has_managed "$PROFILE_ALIAS"; then
    if ui_confirm "Remove the gauth SSH config block for '$PROFILE_ALIAS'?" yes; then
      if ! gauth_is_writable "$GAUTH_SSH_CONFIG"; then
        gauth_permission_hint "$GAUTH_SSH_CONFIG"
      elif sshconfig_remove "$PROFILE_ALIAS"; then
        ui_success "SSH config block removed."
      else
        ui_warn "Could not remove the SSH config block."
      fi
    fi
  else
    ui_warn "No gauth-managed SSH config block found for '$PROFILE_ALIAS'."
  fi

  if [ -f "$PROFILE_KEY" ] || [ -f "${PROFILE_KEY}.pub" ]; then
    if profile_key_in_use "$PROFILE_KEY" "$name"; then
      ui_warn "The key is shared with another profile; leaving it in place."
    elif ui_confirm "Archive the key files instead of deleting them?" yes; then
      if ! gauth_is_writable "$PROFILE_KEY"; then
        gauth_permission_hint "$PROFILE_KEY"
      elif ui_task "Archiving the key" ssh_archive_key "$PROFILE_KEY"; then
        ui_info "Key archived at: $UI_TASK_OUTPUT"
      else
        ui_warn "Could not archive the key files."
      fi
    fi
  fi

  if profile_delete "$name"; then
    if ui_has_gum && ui_interactive; then
      "$GAUTH_GUM_BIN" style \
        --border rounded \
        --border-foreground "$UI_SUCCESS_HEX" \
        --foreground "$UI_SUCCESS_HEX" \
        --bold \
        --padding "1 2" \
        --margin "1 0" \
        -- "Profile '$name' removed." >&2
    else
      ui_success "Profile '$name' removed."
    fi
    ui_dim "Repositories that used this alias keep their current remote URL."
    return 0
  fi
  ui_error "Could not remove the profile record."
  if ! gauth_is_writable "$GAUTH_PROFILES_FILE"; then
    gauth_permission_hint "$GAUTH_PROFILES_FILE"
  fi
  return 1
}
