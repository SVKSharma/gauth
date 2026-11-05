# shellcheck shell=bash
# SSH key generation, agent handling, and GitHub connection checks.

SSH_TEST_OUTPUT=""
SSH_TEST_RC=0

ssh_require_tools() {
  local missing=""
  local tool
  for tool in ssh ssh-keygen ssh-add ssh-agent; do
    gauth_command_exists "$tool" || missing="$missing $tool"
  done
  if [ -n "$missing" ]; then
    ui_error "Missing OpenSSH tools:$missing"
    ui_info "Install openssh-client (Debian/Ubuntu) or openssh (Arch/Fedora)."
    return 1
  fi
  return 0
}

ssh_ensure_dir() {
  gauth_ensure_dir "$GAUTH_SSH_DIR" 700 || return 1
}

ssh_default_key_path() {
  local name="$1"
  local key_type="$2"
  printf '%s/id_%s_%s\n' "$GAUTH_SSH_DIR" "$key_type" "$name"
}

ssh_key_fingerprint() {
  local key_path="$1"
  [ -f "${key_path}.pub" ] || return 1
  ssh-keygen -lf "${key_path}.pub" 2>/dev/null | awk '{print $2; exit}'
}

ssh_key_comment() {
  local key_path="$1"
  [ -f "${key_path}.pub" ] || return 1
  ssh-keygen -lf "${key_path}.pub" 2>/dev/null | sed 's/^.*(\(.*\))$/\1/'
}

ssh_ensure_public_key() {
  local key_path="$1"
  local pub="${key_path}.pub"
  [ -f "$pub" ] && {
    chmod 644 "$pub" 2>/dev/null || true
    return 0
  }
  [ -f "$key_path" ] || return 1
  ssh-keygen -y -f "$key_path" >"$pub" 2>/dev/null || return 1
  chmod 644 "$pub" 2>/dev/null || true
  return 0
}

ssh_generate_key() {
  local key_path="$1"
  local email="$2"
  local key_type="$3"
  local passphrase_mode="${4:-none}"

  validate_key_type "$key_type" || {
    ui_error "Unsupported key type: $key_type"
    return 1
  }
  ssh_ensure_dir || return 1

  if [ -e "$key_path" ] || [ -e "${key_path}.pub" ]; then
    ui_error "Key already exists: $key_path"
    return 1
  fi

  local args=()
  case "$key_type" in
    ed25519) args=(-t ed25519) ;;
    rsa) args=(-t rsa -b 4096) ;;
    ecdsa) args=(-t ecdsa -b 384) ;;
  esac
  args+=(-C "$email" -f "$key_path")

  if [ "$passphrase_mode" = "none" ]; then
    args+=(-N "")
  else
    if ! gauth_is_tty; then
      ui_error "A passphrase-protected key needs an interactive terminal."
      return 1
    fi
    ui_info "ssh-keygen will now ask for your passphrase."
  fi

  if ! ssh-keygen "${args[@]}"; then
    ui_error "ssh-keygen failed."
    return 1
  fi

  chmod 700 "$GAUTH_SSH_DIR" 2>/dev/null || true
  chmod 600 "$key_path" 2>/dev/null || true
  ssh_ensure_public_key "$key_path" || return 1
  chmod 644 "${key_path}.pub" 2>/dev/null || true
  gauth_log "ssh key generated: $key_path"
  return 0
}

ssh_archive_key() {
  local key_path="$1"
  [ -e "$key_path" ] || [ -e "${key_path}.pub" ] || return 1
  gauth_ensure_dir "$GAUTH_ARCHIVE_DIR" 700 >/dev/null 2>&1 || return 1
  local dest="$GAUTH_ARCHIVE_DIR/$(gauth_timestamp)-$$"
  mkdir -p "$dest" || return 1
  chmod 700 "$dest" 2>/dev/null || true
  if [ -e "$key_path" ]; then
    mv "$key_path" "$dest/" || return 1
  fi
  if [ -e "${key_path}.pub" ]; then
    mv "${key_path}.pub" "$dest/" || return 1
  fi
  gauth_log "ssh key archived: $key_path -> $dest"
  printf '%s\n' "$dest"
}

ssh_agent_running() {
  [ -n "${SSH_AUTH_SOCK:-}" ] || return 1
  [ -S "$SSH_AUTH_SOCK" ] || return 1
  ssh-add -l >/dev/null 2>&1
  case "$?" in
    0|1) return 0 ;;
    *) return 1 ;;
  esac
}

ssh_agent_start() {
  ssh_require_tools || return 1
  local output
  output="$(ssh-agent -s 2>/dev/null)" || return 1
  eval "$output" >/dev/null 2>&1 || return 1
  [ -n "${SSH_AUTH_SOCK:-}" ] || return 1
  [ -S "$SSH_AUTH_SOCK" ] || return 1

  gauth_ensure_dir "$GAUTH_STATE_HOME" 700 >/dev/null 2>&1 || true
  umask 077
  {
    printf '# Source this from bash or zsh: . %s\n' "$GAUTH_AGENT_ENV"
    printf 'export SSH_AUTH_SOCK=%s\n' "$(printf '%q' "$SSH_AUTH_SOCK")"
    printf 'export SSH_AGENT_PID=%s\n' "$(printf '%q' "${SSH_AGENT_PID:-}")"
  } >"$GAUTH_AGENT_ENV" 2>/dev/null || true
  chmod 600 "$GAUTH_AGENT_ENV" 2>/dev/null || true

  {
    printf '# Source this from fish: source %s\n' "$GAUTH_AGENT_FISH"
    printf "set -gx SSH_AUTH_SOCK '%s'\n" "$(printf '%s' "$SSH_AUTH_SOCK" | sed "s/'/'\\\\''/g")"
    printf "set -gx SSH_AGENT_PID '%s'\n" "$(printf '%s' "${SSH_AGENT_PID:-}" | sed "s/'/'\\\\''/g")"
  } >"$GAUTH_AGENT_FISH" 2>/dev/null || true
  chmod 600 "$GAUTH_AGENT_FISH" 2>/dev/null || true

  gauth_log "ssh-agent started"
  return 0
}

ssh_agent_add() {
  local key_path="$1"
  ssh_require_tools || return 1
  if ! ssh_agent_running; then
    ui_warn "No running ssh-agent found."
    return 1
  fi
  if ! ssh-add "$key_path"; then
    ui_error "Could not add the key to ssh-agent."
    return 1
  fi
  gauth_log "ssh key added to agent: $key_path"
  return 0
}

ssh_agent_has_key() {
  local key_path="$1"
  local fingerprint
  fingerprint="$(ssh_key_fingerprint "$key_path")" || return 1
  [ -n "$fingerprint" ] || return 1
  ssh-add -l 2>/dev/null | grep -F "$fingerprint" >/dev/null 2>&1
}

ssh_agent_instructions() {
  ui_section "ssh-agent environment"
  ui_info "The agent keeps running, but new shells must learn its socket."
  printf '  bash/zsh: source %s\n' "$GAUTH_AGENT_ENV" >&2
  printf '  fish:     source %s\n' "$GAUTH_AGENT_FISH" >&2
  ui_dim "gauth reuses SSH_AUTH_SOCK when it is already set."
}

ssh_test_connection() {
  local alias="$1"
  SSH_TEST_OUTPUT=""
  SSH_TEST_RC=0

  if ! gauth_command_exists ssh; then
    SSH_TEST_OUTPUT="ssh is not installed"
    SSH_TEST_RC=127
    return 1
  fi

  SSH_TEST_OUTPUT="$(ssh \
    -T \
    -o BatchMode=yes \
    -o ConnectTimeout=15 \
    -o StrictHostKeyChecking=accept-new \
    "git@${alias}" 2>&1 </dev/null)" || SSH_TEST_RC=$?

  case "$SSH_TEST_OUTPUT" in
    *"successfully authenticated"*|*"You've successfully authenticated"*|*"Hi "*)
      return 0
      ;;
  esac
  return 1
}

# OpenSSH expands "~" using the passwd home directory, not $HOME, so a
# diagnostic run under a different HOME would silently read the wrong file.
# Probe the exact file gauth manages whenever it exists.
ssh_config_custom() {
  [ -n "${GAUTH_SSH_CONFIG:-}" ] && [ -f "$GAUTH_SSH_CONFIG" ]
}

ssh_config_probe() {
  gauth_command_exists ssh || return 1
  if ssh_config_custom; then
    ssh -F "$GAUTH_SSH_CONFIG" -G "$1" 2>/dev/null
  else
    ssh -G "$1" 2>/dev/null
  fi
}

ssh_config_hostname() {
  local alias="$1"
  ssh_config_probe "$alias" | awk 'tolower($1) == "hostname" {print $2; exit}'
}

ssh_config_identity() {
  local alias="$1"
  ssh_config_probe "$alias" | awk 'tolower($1) == "identityfile" {print $2; exit}'
}

ssh_open_github_keys() {
  gauth_open_url "$(ui_github_key_url)"
}

ssh_friendly_failure() {
  case "${SSH_TEST_OUTPUT:-}" in
    *"Host key verification failed"*|*"REMOTE HOST IDENTIFICATION HAS CHANGED"*)
      ui_error "GitHub host key verification failed. Check ~/.ssh/known_hosts."
      ;;
    *"Permission denied"*)
      ui_error "GitHub rejected the key. Make sure the public key was added to this GitHub account."
      ;;
    *"Could not resolve hostname"*|*"Connection timed out"*)
      ui_error "Could not reach GitHub. Check your network or SSH config."
      ;;
    *"no such identity"*|*"Identity file"*)
      ui_error "SSH could not find the configured private key."
      ;;
    *)
      [ -n "${SSH_TEST_OUTPUT:-}" ] && printf '%s\n' "$SSH_TEST_OUTPUT" >&2
      ;;
  esac
}
