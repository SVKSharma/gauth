# shellcheck shell=bash
# Safe editing of ~/.ssh/config.
#
# gauth blocks are inserted at the TOP of the file on purpose: OpenSSH uses the
# first value it obtains for each option, so a later "Host *" block cannot
# override an earlier IdentityFile. Removing gauth only removes its own block.

sshconfig_ensure_file() {
  ssh_ensure_dir || return 1
  if [ ! -e "$GAUTH_SSH_CONFIG" ]; then
    umask 077
    : >"$GAUTH_SSH_CONFIG" || return 1
    chmod 600 "$GAUTH_SSH_CONFIG" 2>/dev/null || true
  fi
  return 0
}

sshconfig_has_managed() {
  local alias="$1"
  [ -f "$GAUTH_SSH_CONFIG" ] || return 1
  grep -Fqx "# >>> gauth:${alias} >>>" "$GAUTH_SSH_CONFIG" 2>/dev/null
}

sshconfig_alias_exists() {
  local alias="$1"
  [ -f "$GAUTH_SSH_CONFIG" ] || return 1

  local line trimmed rest token
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in
      [Hh][Oo][Ss][Tt]|[Hh][Oo][Ss][Tt][[:space:]]*)
        rest="${trimmed#[Hh][Oo][Ss][Tt]}"
        ;;
      *)
        continue
        ;;
    esac
    for token in $rest; do
      [ "$token" = "$alias" ] && return 0
    done
  done <"$GAUTH_SSH_CONFIG"
  return 1
}

sshconfig_backup() {
  [ -s "$GAUTH_SSH_CONFIG" ] || return 0
  local backup
  backup="$(gauth_backup_file "$GAUTH_SSH_CONFIG" "ssh_config")" || return 1
  ui_dim "SSH config backup: $backup"
  return 0
}

sshconfig_upsert() {
  local alias="$1"
  local key_path="$2"

  validate_alias "$alias" || {
    ui_error "Invalid SSH alias: $alias"
    return 1
  }
  case "$key_path" in
    ''|*[[:space:]]*|*'#'*)
      ui_error "Invalid SSH key path: $key_path"
      return 1
      ;;
  esac
  sshconfig_ensure_file || return 1

  if sshconfig_alias_exists "$alias" && ! sshconfig_has_managed "$alias"; then
    ui_error "SSH alias '$alias' already exists outside gauth; refusing to modify it."
    return 2
  fi

  sshconfig_backup || {
    ui_error "Could not back up the SSH config; aborting."
    return 1
  }

  local workdir block kept output
  workdir="$(mktemp -d "${TMPDIR:-/tmp}/gauth-sshconfig.XXXXXX")" || return 1
  block="$workdir/block"
  kept="$workdir/kept"
  output="$workdir/output"

  {
    printf '# >>> gauth:%s >>>\n' "$alias"
    printf 'Host %s\n' "$alias"
    printf '  HostName %s\n' "$GAUTH_DEFAULT_HOST"
    printf '  User git\n'
    printf '  IdentityFile %s\n' "$key_path"
    printf '  IdentitiesOnly yes\n'
    printf '# <<< gauth:%s <<<\n' "$alias"
  } >"$block" || {
    rm -rf "$workdir"
    return 1
  }

  local skip=0 line
  : >"$kept" || {
    rm -rf "$workdir"
    return 1
  }
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "# >>> gauth:${alias} >>>")
        skip=1
        continue
        ;;
      "# <<< gauth:${alias} <<<")
        skip=0
        continue
        ;;
    esac
    [ "$skip" -eq 1 ] && continue
    printf '%s\n' "$line" >>"$kept"
  done <"$GAUTH_SSH_CONFIG"

  {
    cat "$block"
    printf '\n'
    cat "$kept"
  } >"$output" || {
    rm -rf "$workdir"
    return 1
  }

  chmod 600 "$output" 2>/dev/null || true
  mv "$output" "$GAUTH_SSH_CONFIG" || {
    rm -rf "$workdir"
    return 1
  }
  rm -rf "$workdir"
  gauth_log "ssh config upsert: $alias"
  return 0
}

sshconfig_remove() {
  local alias="$1"
  [ -f "$GAUTH_SSH_CONFIG" ] || return 1
  sshconfig_has_managed "$alias" || return 1

  sshconfig_backup || return 1

  local workdir kept output
  workdir="$(mktemp -d "${TMPDIR:-/tmp}/gauth-sshconfig.XXXXXX")" || return 1
  kept="$workdir/kept"
  output="$workdir/output"
  : >"$kept" || {
    rm -rf "$workdir"
    return 1
  }

  local skip=0 line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "# >>> gauth:${alias} >>>")
        skip=1
        continue
        ;;
      "# <<< gauth:${alias} <<<")
        skip=0
        continue
        ;;
    esac
    [ "$skip" -eq 1 ] && continue
    printf '%s\n' "$line" >>"$kept"
  done <"$GAUTH_SSH_CONFIG"

  cp "$kept" "$output" || {
    rm -rf "$workdir"
    return 1
  }
  chmod 600 "$output" 2>/dev/null || true
  mv "$output" "$GAUTH_SSH_CONFIG" || {
    rm -rf "$workdir"
    return 1
  }
  rm -rf "$workdir"
  gauth_log "ssh config removed: $alias"
  return 0
}

sshconfig_list_managed() {
  [ -f "$GAUTH_SSH_CONFIG" ] || return 0
  sed -n 's/^# >>> gauth:\(.*\) >>>$/\1/p' "$GAUTH_SSH_CONFIG"
}
