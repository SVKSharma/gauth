# shellcheck shell=bash
# Settings and the tab-separated account registry.

SETTING_DEFAULT_KEY_TYPE="$GAUTH_DEFAULT_KEY_TYPE"
SETTING_DEFAULT_ALIAS_PREFIX="$GAUTH_DEFAULT_ALIAS_PREFIX"
SETTING_DEFAULT_BRANCH="$GAUTH_DEFAULT_BRANCH"
SETTING_COPY_PUBLIC_KEY="$GAUTH_DEFAULT_COPY_KEY"
SETTING_AUTO_START_AGENT="$GAUTH_DEFAULT_AUTO_AGENT"

config_init() {
  gauth_ensure_dir "$GAUTH_CONFIG_HOME" 700 || gauth_die "Cannot create $GAUTH_CONFIG_HOME"
  gauth_ensure_dir "$GAUTH_STATE_HOME" 700 || gauth_die "Cannot create $GAUTH_STATE_HOME"
  gauth_ensure_dir "$GAUTH_BACKUP_DIR" 700 >/dev/null 2>&1 || true
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

accounts_init() {
  config_init
  [ -f "$GAUTH_ACCOUNTS_FILE" ] && return 0
  umask 077
  {
    printf '# gauth accounts v1\n'
    printf '# name\talias\tgit_name\temail\tkey_path\tkey_type\tcreated\tlast_verified\n'
  } >"$GAUTH_ACCOUNTS_FILE" || return 1
  chmod 600 "$GAUTH_ACCOUNTS_FILE" 2>/dev/null || true
  return 0
}

account_count() {
  [ -f "$GAUTH_ACCOUNTS_FILE" ] || {
    printf '0\n'
    return 0
  }
  local count=0
  local n a g e k kt c v
  while IFS=$'\t' read -r n a g e k kt c v || [ -n "$n" ]; do
    case "$n" in ''|'#'*) continue ;; esac
    count=$((count + 1))
  done <"$GAUTH_ACCOUNTS_FILE"
  printf '%s\n' "$count"
}

account_list_names() {
  [ -f "$GAUTH_ACCOUNTS_FILE" ] || return 0
  local n a g e k kt c v
  while IFS=$'\t' read -r n a g e k kt c v || [ -n "$n" ]; do
    case "$n" in ''|'#'*) continue ;; esac
    printf '%s\n' "$n"
  done <"$GAUTH_ACCOUNTS_FILE"
}

account_exists() {
  local wanted="$1"
  local n a g e k kt c v
  [ -f "$GAUTH_ACCOUNTS_FILE" ] || return 1
  while IFS=$'\t' read -r n a g e k kt c v || [ -n "$n" ]; do
    [ "$n" = "$wanted" ] && return 0
  done <"$GAUTH_ACCOUNTS_FILE"
  return 1
}

account_load() {
  local wanted="$1"
  ACC_NAME=""
  ACC_ALIAS=""
  ACC_GIT_NAME=""
  ACC_EMAIL=""
  ACC_KEY=""
  ACC_KEY_TYPE=""
  ACC_CREATED=""
  ACC_VERIFIED=""

  [ -f "$GAUTH_ACCOUNTS_FILE" ] || return 1
  local n a g e k kt c v
  while IFS=$'\t' read -r n a g e k kt c v || [ -n "$n" ]; do
    if [ "$n" = "$wanted" ]; then
      ACC_NAME="$n"
      ACC_ALIAS="$a"
      ACC_GIT_NAME="$g"
      ACC_EMAIL="$e"
      ACC_KEY="$k"
      ACC_KEY_TYPE="$kt"
      ACC_CREATED="$c"
      ACC_VERIFIED="$v"
      return 0
    fi
  done <"$GAUTH_ACCOUNTS_FILE"
  return 1
}

account_require() {
  account_load "$1" || gauth_die "Unknown account: $1"
}

account_save() {
  local name="$1"
  local alias="$2"
  local git_name="$3"
  local email="$4"
  local key_path="$5"
  local key_type="$6"

  validate_account_name "$name" || return 1
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

  accounts_init || return 1
  account_exists "$name" && return 1

  umask 077
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$alias" "$git_name" "$email" "$key_path" "$key_type" "$(gauth_now)" "-" \
    >>"$GAUTH_ACCOUNTS_FILE" || return 1
  gauth_log "account saved: $name"
  return 0
}

account_delete() {
  local wanted="$1"
  [ -f "$GAUTH_ACCOUNTS_FILE" ] || return 1
  local tmp="${GAUTH_ACCOUNTS_FILE}.tmp.$$"
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
  done <"$GAUTH_ACCOUNTS_FILE"

  if [ "$found" -ne 0 ]; then
    rm -f "$tmp"
    return 1
  fi
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$GAUTH_ACCOUNTS_FILE" || return 1
  gauth_log "account deleted: $wanted"
  return 0
}

account_update_verified() {
  local wanted="$1"
  local stamp="${2:-$(gauth_now)}"
  [ -f "$GAUTH_ACCOUNTS_FILE" ] || return 1
  local tmp="${GAUTH_ACCOUNTS_FILE}.tmp.$$"
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
  done <"$GAUTH_ACCOUNTS_FILE"

  if [ "$found" -ne 0 ]; then
    rm -f "$tmp"
    return 1
  fi
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$GAUTH_ACCOUNTS_FILE" || return 1
  return 0
}

account_key_in_use() {
  local key_path="$1"
  local exclude="${2:-}"
  local n a g e k kt c v
  [ -f "$GAUTH_ACCOUNTS_FILE" ] || return 1
  while IFS=$'\t' read -r n a g e k kt c v || [ -n "$n" ]; do
    [ "$n" = "$exclude" ] && continue
    [ "$k" = "$key_path" ] && return 0
  done <"$GAUTH_ACCOUNTS_FILE"
  return 1
}

account_alias_in_use() {
  local alias="$1"
  local exclude="${2:-}"
  local n a g e k kt c v
  [ -f "$GAUTH_ACCOUNTS_FILE" ] || return 1
  while IFS=$'\t' read -r n a g e k kt c v || [ -n "$n" ]; do
    [ "$n" = "$exclude" ] && continue
    [ "$a" = "$alias" ] && return 0
  done <"$GAUTH_ACCOUNTS_FILE"
  return 1
}

account_pick() {
  local header="${1:-Select an account}"
  local names=()
  local name
  while IFS= read -r name; do
    [ -n "$name" ] && names+=("$name")
  done < <(account_list_names)

  if [ "${#names[@]}" -eq 0 ]; then
    ui_warn "No accounts configured yet."
    return 1
  fi
  if [ "${#names[@]}" -eq 1 ]; then
    printf '%s\n' "${names[0]}"
    return 0
  fi
  ui_choose "$header" "${names[@]}"
}

account_print() {
  local name="$1"
  account_require "$name"
  ui_kv "Account" "$ACC_NAME"
  ui_kv "SSH alias" "$ACC_ALIAS"
  ui_kv "Git name" "$ACC_GIT_NAME"
  ui_kv "Email" "$ACC_EMAIL"
  ui_kv "Key path" "$ACC_KEY"
  ui_kv "Key type" "$ACC_KEY_TYPE"
  if [ -f "$ACC_KEY" ]; then
    ui_kv "Key file" "present"
  else
    ui_kv "Key file" "MISSING"
  fi
  if [ "$ACC_VERIFIED" = "-" ] || [ -z "$ACC_VERIFIED" ]; then
    ui_kv "Last verified" "never"
  else
    ui_kv "Last verified" "$(gauth_format_epoch "$ACC_VERIFIED" || printf '%s' "$ACC_VERIFIED")"
  fi
}

account_list_cmd() {
  local count
  count="$(account_count)"
  if [ "$count" -eq 0 ]; then
    ui_warn "No accounts configured yet."
    return 1
  fi

  ui_section "Configured accounts"
  printf '%-16s %-26s %-22s %s\n' "NAME" "SSH ALIAS" "EMAIL" "KEY"
  local n a g e k kt c v
  while IFS=$'\t' read -r n a g e k kt c v || [ -n "$n" ]; do
    case "$n" in ''|'#'*) continue ;; esac
    printf '%-16s %-26s %-22s %s\n' "$n" "$a" "$e" "$k"
  done <"$GAUTH_ACCOUNTS_FILE"
  return 0
}
