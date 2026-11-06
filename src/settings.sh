# shellcheck shell=bash
# Settings menu.

settings_menu() {
  gauth_require_tty || return 1
  settings_load

  if ui_has_gum && ui_interactive; then
    "$GAUTH_GUM_BIN" style \
      --border rounded \
      --border-foreground "$UI_BORDER_HEX" \
      --foreground "$UI_ACCENT_HEX" \
      --bold \
      --padding "1 2" \
      --margin "1 0" \
      -- "Settings" >&2
  else
    ui_header "Settings"
  fi

  local choice value
  while :; do
    settings_show
    choice="$(ui_choose_nav 1 1 "Change a setting" \
      "Default key type: $SETTING_DEFAULT_KEY_TYPE" \
      "Default alias prefix: $SETTING_DEFAULT_ALIAS_PREFIX" \
      "Default branch: $SETTING_DEFAULT_BRANCH" \
      "Copy public key to clipboard: $SETTING_COPY_PUBLIC_KEY" \
      "Automatically start ssh-agent: $SETTING_AUTO_START_AGENT" \
      "$UI_BACK_LABEL")" || return 0

    case "$choice" in
      "Default key type:"*)
        if value="$(ui_choose "Default key type" \
          "ed25519 (recommended)" "rsa (4096-bit)" "ecdsa (384-bit)" \
          "$UI_BACK_LABEL")"; then
          if [ "$value" = "$UI_BACK_LABEL" ]; then
            continue
          fi
          if settings_set default_key_type "$(profile_key_type_from_choice "$value")"; then
            ui_success "Default key type updated."
          else
            ui_error "Could not update the setting."
          fi
        fi
        ;;
      "Default alias prefix:"*)
        if value="$(ui_input "Default alias prefix" "github.com-" "$SETTING_DEFAULT_ALIAS_PREFIX")"; then
          if settings_set default_alias_prefix "$value"; then
            ui_success "Alias prefix updated."
          else
            ui_error "Use only letters, numbers, dot, underscore, or hyphen."
          fi
        fi
        ;;
      "Default branch:"*)
        if value="$(ui_input "Default branch" "main" "$SETTING_DEFAULT_BRANCH")"; then
          if settings_set default_branch "$value"; then
            ui_success "Default branch updated."
          else
            ui_error "Invalid branch name."
          fi
        fi
        ;;
      "Copy public key to clipboard:"*)
        if is_true "$SETTING_COPY_PUBLIC_KEY"; then
          settings_set copy_public_key false && ui_success "Automatic clipboard copy disabled."
        else
          settings_set copy_public_key true && ui_success "Automatic clipboard copy enabled."
        fi
        ;;
      "Automatically start ssh-agent:"*)
        if is_true "$SETTING_AUTO_START_AGENT"; then
          settings_set auto_start_agent false && ui_success "Automatic ssh-agent start disabled."
        else
          settings_set auto_start_agent true && ui_success "Automatic ssh-agent start enabled."
        fi
        ;;
      "$UI_BACK_LABEL"|"") return 0 ;;
    esac
  done
}
