# shellcheck shell=bash
# Settings menu.

settings_menu() {
  gauth_require_tty || return 1
  settings_load
  local choice value
  while :; do
    ui_header "Settings"
    settings_show
    choice="$(ui_choose "Change a setting" \
      "Default key type: $SETTING_DEFAULT_KEY_TYPE" \
      "Default alias prefix: $SETTING_DEFAULT_ALIAS_PREFIX" \
      "Default branch: $SETTING_DEFAULT_BRANCH" \
      "Copy public key to clipboard: $SETTING_COPY_PUBLIC_KEY" \
      "Automatically start ssh-agent: $SETTING_AUTO_START_AGENT" \
      "Back")" || return 0

    case "$choice" in
      "Default key type:"*)
        value="$(ui_choose "Default key type" ed25519 rsa ecdsa)" || continue
        if settings_set default_key_type "$value"; then
          ui_success "Default key type updated."
        else
          ui_error "Could not update the setting."
        fi
        ;;
      "Default alias prefix:"*)
        value="$(ui_input "Default alias prefix" "github.com-" "$SETTING_DEFAULT_ALIAS_PREFIX")" || continue
        if settings_set default_alias_prefix "$value"; then
          ui_success "Alias prefix updated."
        else
          ui_error "Use only letters, numbers, dot, underscore, or hyphen."
        fi
        ;;
      "Default branch:"*)
        value="$(ui_input "Default branch" "main" "$SETTING_DEFAULT_BRANCH")" || continue
        if settings_set default_branch "$value"; then
          ui_success "Default branch updated."
        else
          ui_error "Invalid branch name."
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
      "Back"|"") return 0 ;;
    esac
  done
}
