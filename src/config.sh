# shellcheck shell=bash
# Settings and the tab-separated profile registry.

SETTING_DEFAULT_KEY_TYPE="$GAUTH_DEFAULT_KEY_TYPE"
SETTING_DEFAULT_ALIAS_PREFIX="$GAUTH_DEFAULT_ALIAS_PREFIX"
SETTING_DEFAULT_BRANCH="$GAUTH_DEFAULT_BRANCH"
SETTING_COPY_PUBLIC_KEY="$GAUTH_DEFAULT_COPY_KEY"
SETTING_AUTO_START_AGENT="$GAUTH_DEFAULT_AUTO_AGENT"

config_init() {
  gauth_ensure_dir "$GAUTH_CONFIG_HOME" 700 || gauth_die "Cannot create $GAUTH_CONFIG_HOME"
  gauth_ensure_dir "$GAUTH_STATE_HOME" 700 || gauth_die "Cannot create $GAUTH_STATE_HOME"
  gauth_ensure_dir "$GAUTH_BACKUP_DIR" 700 >/dev/null 2>&1 || true
  config_migrate_legacy
}

# v0.1 called these "accounts". Move the registry once, without deleting the
# original file.
config_migrate_legacy() {
  [ -f "$GAUTH_PROFILES_FILE" ] && return 0
  [ -n "${GAUTH_LEGACY_PROFILES_FILE:-}" ] || return 0
  [ -f "$GAUTH_LEGACY_PROFILES_FILE" ] || return 0

  local tmp="${GAUTH_PROFILES_FILE}.migrate.$$"
  {
    printf '# gauth profiles v1\n'
    printf '# name\talias\tgit_name\temail\tkey_path\tkey_type\tcreated\tlast_verified\n'
    local line
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in ''|'#'*) continue ;; esac
      printf '%s\n' "$line"
    done <"$GAUTH_LEGACY_PROFILES_FILE"
  } >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$GAUTH_PROFILES_FILE" || return 1
  ui_dim "Migrated the v0.1 account registry to $GAUTH_PROFILES_FILE"
  return 0
}

settings_init() {
  config_init
  if [ ! -f "$GAUTH_SETTINGS_FILE" ]; then
    settings_save >/dev/null 2>&1 || gauth_die "Cannot write $GAUTH_SETTINGS_FILE"
  fi
}

settings_load() {
  SETTING_DEFAULT_KEY_TYPE="$GAUTH_DEFAULT_KEY_TYPE"
  SETTING_DEFAULT_ALIAS_PREFIX="$GAUTH_DEFAULT_ALIAS_PREFIX"
  SETTING_DEFAULT_BRANCH="$GAUTH_DEFAULT_BRANCH"
  SETTING_COPY_PUBLIC_KEY="$GAUTH_DEFAULT_COPY_KEY"
  SETTING_AUTO_START_AGENT="$GAUTH_DEFAULT_AUTO_AGENT"

  [ -f "$GAUTH_SETTINGS_FILE" ] || return 0

  local key value
  while IFS='=' read -r key value || [ -n "$key" ]; do
    key="$(gauth_trim "$key")"
    case "$key" in
      ''|'#'*) continue ;;
      default_key_type)
        validate_key_type "$value" && SETTING_DEFAULT_KEY_TYPE="$value"
        ;;
      default_alias_prefix)
        validate_alias_prefix "$value" && SETTING_DEFAULT_ALIAS_PREFIX="$value"
        ;;
      default_branch)
        validate_branch_name "$value" && SETTING_DEFAULT_BRANCH="$value"
        ;;
      copy_public_key)
        case "$value" in true|false) SETTING_COPY_PUBLIC_KEY="$value" ;; esac
        ;;
      auto_start_agent)
        case "$value" in true|false) SETTING_AUTO_START_AGENT="$value" ;; esac
        ;;
    esac
  done <"$GAUTH_SETTINGS_FILE"
  return 0
}

validate_alias_prefix() {
  local prefix="$1"
  [ "${#prefix}" -le 96 ] || return 1
  gauth_has_control_chars "$prefix" && return 1
  case "$prefix" in
    *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}

settings_save() {
  config_init
  local tmp="${GAUTH_SETTINGS_FILE}.tmp.$$"
  umask 077
  {
    printf '# gauth settings v1\n'
    printf 'default_key_type=%s\n' "$SETTING_DEFAULT_KEY_TYPE"
    printf 'default_alias_prefix=%s\n' "$SETTING_DEFAULT_ALIAS_PREFIX"
    printf 'default_branch=%s\n' "$SETTING_DEFAULT_BRANCH"
    printf 'copy_public_key=%s\n' "$SETTING_COPY_PUBLIC_KEY"
    printf 'auto_start_agent=%s\n' "$SETTING_AUTO_START_AGENT"
  } >"$tmp" || return 1
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$GAUTH_SETTINGS_FILE" || return 1
  return 0
}

settings_set() {
  local key="$1"
  local value="$2"

  case "$key" in
    default_key_type)
      validate_key_type "$value" || return 1
      SETTING_DEFAULT_KEY_TYPE="$value"
      ;;
    default_alias_prefix)
      validate_alias_prefix "$value" || return 1
      SETTING_DEFAULT_ALIAS_PREFIX="$value"
      ;;
    default_branch)
      validate_branch_name "$value" || return 1
      SETTING_DEFAULT_BRANCH="$value"
      ;;
    copy_public_key)
      case "$value" in true|false) SETTING_COPY_PUBLIC_KEY="$value" ;; *) return 1 ;; esac
      ;;
    auto_start_agent)
      case "$value" in true|false) SETTING_AUTO_START_AGENT="$value" ;; *) return 1 ;; esac
      ;;
    *) return 1 ;;
  esac
  settings_save
}

settings_show() {
  ui_kv "Key type" "$SETTING_DEFAULT_KEY_TYPE"
  ui_kv "Alias prefix" "$SETTING_DEFAULT_ALIAS_PREFIX"
  ui_kv "Default branch" "$SETTING_DEFAULT_BRANCH"
  ui_kv "Copy public key" "$SETTING_COPY_PUBLIC_KEY"
  ui_kv "Auto-start agent" "$SETTING_AUTO_START_AGENT"
}

profiles_init() {
  config_init
  [ -f "$GAUTH_PROFILES_FILE" ] && return 0
  umask 077
  {
    printf '# gauth profiles v1\n'
    printf '# name\talias\tgit_name\temail\tkey_path\tkey_type\tcreated\tlast_verified\n'
  } >"$GAUTH_PROFILES_FILE" || return 1
  chmod 600 "$GAUTH_PROFILES_FILE" 2>/dev/null || true
  return 0
}

profile_count() {
  [ -f "$GAUTH_PROFILES_FILE" ] || {
    printf '0\n'
    return 0
  }
  local count=0
  local n a g e k kt c v
  while IFS=$'\t' read -r n a g e k kt c v || [ -n "$n" ]; do
    case "$n" in ''|'#'*) continue ;; esac
    count=$((count + 1))
  done <"$GAUTH_PROFILES_FILE"
  printf '%s\n' "$count"
}

profile_list_names() {
  [ -f "$GAUTH_PROFILES_FILE" ] || return 0
  local n a g e k kt c v
  while IFS=$'\t' read -r n a g e k kt c v || [ -n "$n" ]; do
    case "$n" in ''|'#'*) continue ;; esac
    printf '%s\n' "$n"
  done <"$GAUTH_PROFILES_FILE"
}

profile_exists() {
  local wanted="$1"
  local n a g e k kt c v
  [ -f "$GAUTH_PROFILES_FILE" ] || return 1
  while IFS=$'\t' read -r n a g e k kt c v || [ -n "$n" ]; do
    [ "$n" = "$wanted" ] && return 0
  done <"$GAUTH_PROFILES_FILE"
  return 1
}

profile_load() {
  local wanted="$1"
  PROFILE_NAME=""
  PROFILE_ALIAS=""
  PROFILE_GIT_NAME=""
  PROFILE_EMAIL=""
  PROFILE_KEY=""
  PROFILE_KEY_TYPE=""
  PROFILE_CREATED=""
  PROFILE_VERIFIED=""

  [ -f "$GAUTH_PROFILES_FILE" ] || return 1
  local n a g e k kt c v
  while IFS=$'\t' read -r n a g e k kt c v || [ -n "$n" ]; do
    if [ "$n" = "$wanted" ]; then
      PROFILE_NAME="$n"
      PROFILE_ALIAS="$a"
      PROFILE_GIT_NAME="$g"
      PROFILE_EMAIL="$e"
      PROFILE_KEY="$k"
      PROFILE_KEY_TYPE="$kt"
      PROFILE_CREATED="$c"
      PROFILE_VERIFIED="$v"
      return 0
    fi
  done <"$GAUTH_PROFILES_FILE"
  return 1
}

profile_require() {
  profile_load "$1" && return 0
  ui_error "Unknown profile: $1"
  ui_info "Run 'gauth profile list' to see the saved profiles."
  return 1
}

profile_save() {
  local name="$1"
  local alias="$2"
  local git_name="$3"
  local email="$4"
  local key_path="$5"
  local key_type="$6"

  validate_profile_name "$name" || return 1
  validate_alias "$alias" || return 1
  validate_email "$email" || return 1
  validate_key_type "$key_type" || return 1
  [ -n "$git_name" ] || return 1
  gauth_has_control_chars "$git_name" && return 1
  [ -n "$key_path" ] || return 1
  gauth_has_control_chars "$key_path" && return 1
  case "$key_path" in
    *[[:space:]]*|*'#'*) return 1 ;;
  esac

  profiles_init || return 1
  profile_exists "$name" && return 1

  umask 077
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$alias" "$git_name" "$email" "$key_path" "$key_type" "$(gauth_now)" "-" \
    >>"$GAUTH_PROFILES_FILE" || return 1
  gauth_log "profile saved: $name"
  return 0
}

profile_delete() {
  local wanted="$1"
  [ -f "$GAUTH_PROFILES_FILE" ] || return 1
  local tmp="${GAUTH_PROFILES_FILE}.tmp.$$"
  local found=1
  local n a g e k kt c v
  : >"$tmp" || return 1
  while IFS=$'\t' read -r n a g e k kt c v || [ -n "$n" ]; do
    case "$n" in
      ''|'#'*)
        printf '%s\n' "$n" >>"$tmp"
        continue
        ;;
    esac
    if [ "$n" = "$wanted" ]; then
      found=0
      continue
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$a" "$g" "$e" "$k" "$kt" "$c" "$v" >>"$tmp"
  done <"$GAUTH_PROFILES_FILE"

  if [ "$found" -ne 0 ]; then
    rm -f "$tmp"
    return 1
  fi
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$GAUTH_PROFILES_FILE" || return 1
  gauth_log "profile deleted: $wanted"
  return 0
}

profile_update_verified() {
  local wanted="$1"
  local stamp="${2:-$(gauth_now)}"
  [ -f "$GAUTH_PROFILES_FILE" ] || return 1
  local tmp="${GAUTH_PROFILES_FILE}.tmp.$$"
  local found=1
  local n a g e k kt c v
  : >"$tmp" || return 1
  while IFS=$'\t' read -r n a g e k kt c v || [ -n "$n" ]; do
    case "$n" in
      ''|'#'*)
        printf '%s\n' "$n" >>"$tmp"
        continue
        ;;
    esac
    if [ "$n" = "$wanted" ]; then
      found=0
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$a" "$g" "$e" "$k" "$kt" "$c" "$stamp" >>"$tmp"
    else
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$a" "$g" "$e" "$k" "$kt" "$c" "$v" >>"$tmp"
    fi
  done <"$GAUTH_PROFILES_FILE"

  if [ "$found" -ne 0 ]; then
    rm -f "$tmp"
    return 1
  fi
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$GAUTH_PROFILES_FILE" || return 1
  return 0
}

profile_key_in_use() {
  local key_path="$1"
  local exclude="${2:-}"
  local n a g e k kt c v
  [ -f "$GAUTH_PROFILES_FILE" ] || return 1
  while IFS=$'\t' read -r n a g e k kt c v || [ -n "$n" ]; do
    [ "$n" = "$exclude" ] && continue
    [ "$k" = "$key_path" ] && return 0
  done <"$GAUTH_PROFILES_FILE"
  return 1
}

profile_alias_in_use() {
  local alias="$1"
  local exclude="${2:-}"
  local n a g e k kt c v
  [ -f "$GAUTH_PROFILES_FILE" ] || return 1
  while IFS=$'\t' read -r n a g e k kt c v || [ -n "$n" ]; do
    [ "$n" = "$exclude" ] && continue
    [ "$a" = "$alias" ] && return 0
  done <"$GAUTH_PROFILES_FILE"
  return 1
}

profile_name_for_alias() {
  local wanted="$1"
  local n a g e k kt c v
  [ -n "$wanted" ] || return 1
  [ -f "$GAUTH_PROFILES_FILE" ] || return 1
  while IFS=$'\t' read -r n a g e k kt c v || [ -n "$n" ]; do
    case "$n" in ''|'#'*) continue ;; esac
    if [ "$a" = "$wanted" ]; then
      printf '%s\n' "$n"
      return 0
    fi
  done <"$GAUTH_PROFILES_FILE"
  return 1
}

profile_pick() {
  local header="${1:-Select a profile}"
  local allow_new="${2:-0}"
  local preferred="${3:-}"
  local -a names=()
  local name
  while IFS= read -r name; do
    [ -n "$name" ] && names+=("$name")
  done < <(profile_list_names)

  # Put the currently selected profile first so switching is quick.
  if [ -n "$preferred" ] && [ "${#names[@]}" -gt 1 ]; then
    local -a ordered=()
    for name in "${names[@]}"; do
      [ "$name" = "$preferred" ] && ordered+=("$name")
    done
    for name in "${names[@]}"; do
      [ "$name" = "$preferred" ] && continue
      ordered+=("$name")
    done
    names=("${ordered[@]}")
  fi

  if [ "${#names[@]}" -eq 0 ] && [ "$allow_new" -eq 0 ]; then
    profile_none_message
    return 1
  fi
  if [ "${#names[@]}" -eq 1 ] && [ "$allow_new" -eq 0 ]; then
    printf '%s\n' "${names[0]}"
    return 0
  fi

  local -a options=()
  for name in "${names[@]}"; do
    options+=("$name")
  done
  [ "$allow_new" -eq 1 ] && options+=("$UI_NEW_PROFILE_LABEL")
  [ "${#options[@]}" -gt 0 ] || return 1

  local choice pick_rc=0
  choice="$(ui_choose "$header" "${options[@]}")" || pick_rc=$?
  [ "$pick_rc" -eq 0 ] || return 1

  # Item 5: create a profile inline and return it as the selection. Keep the
  # wizard's stdout off this function's stdout: callers capture the selected
  # name with $(...), so any stray output would corrupt it.
  if [ "$choice" = "$UI_NEW_PROFILE_LABEL" ]; then
    profile_add repo >&2 || return 1
    [ -n "${PROFILE_LAST_ADDED:-}" ] || return 1
    printf '%s\n' "$PROFILE_LAST_ADDED"
    return 0
  fi

  [ -n "$choice" ] || return 1
  printf '%s\n' "$choice"
}

profile_print() {
  local name="$1"
  profile_require "$name" || return 1
  ui_kv "Profile" "$PROFILE_NAME"
  ui_kv "SSH alias" "$PROFILE_ALIAS"
  ui_kv "Git name" "$PROFILE_GIT_NAME"
  ui_kv "Email" "$PROFILE_EMAIL"
  ui_kv "Key path" "$PROFILE_KEY"
  ui_kv "Key type" "$PROFILE_KEY_TYPE"
  if [ -f "$PROFILE_KEY" ]; then
    ui_kv "Key file" "present"
  else
    ui_kv "Key file" "MISSING"
  fi
  if [ "$PROFILE_VERIFIED" = "-" ] || [ -z "$PROFILE_VERIFIED" ]; then
    ui_kv "Last verified" "never"
  else
    ui_kv "Last verified" "$(gauth_format_epoch "$PROFILE_VERIFIED" || printf '%s' "$PROFILE_VERIFIED")"
  fi
}

profile_list_cmd() {
  local count
  count="$(profile_count)"
  if [ "$count" -eq 0 ]; then
    profile_none_message
    return 1
  fi

  ui_section "Configured profiles"
  printf '%-16s %-26s %-22s %s\n' "NAME" "SSH ALIAS" "EMAIL" "KEY"
  local n a g e k kt c v
  while IFS=$'\t' read -r n a g e k kt c v || [ -n "$n" ]; do
    case "$n" in ''|'#'*) continue ;; esac
    printf '%-16s %-26s %-22s %s\n' "$n" "$a" "$e" "$k"
  done <"$GAUTH_PROFILES_FILE"
  return 0
}
