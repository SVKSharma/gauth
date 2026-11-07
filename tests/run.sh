#!/usr/bin/env bash
# Dependency-free test runner for gauth.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
DIST="$ROOT/dist/gauth"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gauth-tests.XXXXXX")"
FAKE_BIN="$WORK/fakebin"
# Real PATH, so a few tests can deliberately bypass the fake ssh binary.
SAVED_PATH="$PATH"
PASS=0
FAIL=0
CURRENT=""

cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

pass() {
  PASS=$((PASS + 1))
  printf '  ok   %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf '  FAIL %s\n' "$1"
  [ -n "${2:-}" ] && printf '       %s\n' "$2"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$label"
  else
    fail "$label" "expected [$expected], got [$actual]"
  fi
}

assert_ok() {
  local label="$1"
  shift
  if "$@"; then pass "$label"; else fail "$label" "command failed: $*"; fi
}

assert_fail() {
  local label="$1"
  shift
  if "$@"; then fail "$label" "command unexpectedly succeeded: $*"; else pass "$label"; fi
}

assert_file() {
  local label="$1"
  local file="$2"
  if [ -f "$file" ]; then pass "$label"; else fail "$label" "missing file: $file"; fi
}

make_fakes() {
  mkdir -p "$FAKE_BIN"

  cat >"$FAKE_BIN/ssh-keygen" <<'FAKE'
#!/usr/bin/env bash
out=""
last=""
mode=""
for arg in "$@"; do
  [ "$arg" = "-lf" ] && { printf '256 SHA256:testfingerprint test@example.com (ED25519)\n'; exit 0; }
  case "$last" in
    -f) out="$arg" ;;
  esac
  case "$arg" in
    -y) mode="derive" ;;
  esac
  last="$arg"
done
if [ "$mode" = "derive" ]; then
  printf 'ssh-ed25519 AAAATEST derived\n'
  exit 0
fi
if [ -n "$out" ]; then
  printf 'PRIVATE KEY\n' >"$out"
  printf 'ssh-ed25519 AAAATEST test@example.com\n' >"$out.pub"
  chmod 600 "$out"
  chmod 644 "$out.pub"
fi
exit 0
FAKE

  cat >"$FAKE_BIN/ssh-add" <<'FAKE'
#!/usr/bin/env bash
case "${1:-}" in
  -l) printf '256 SHA256:testfingerprint test@example.com (ED25519)\n'; exit 0 ;;
esac
exit 0
FAKE

  cat >"$FAKE_BIN/ssh-agent" <<'FAKE'
#!/usr/bin/env bash
printf 'SSH_AUTH_SOCK=/tmp/fake-agent.sock; export SSH_AUTH_SOCK;\n'
printf 'SSH_AGENT_PID=12345; export SSH_AGENT_PID;\n'
printf 'echo Agent pid 12345;\n'
exit 0
FAKE

  cat >"$FAKE_BIN/ssh" <<'FAKE'
#!/usr/bin/env bash
if [ "${FAKE_SSH_FAIL:-0}" = "1" ]; then
  printf 'git@github.com: Permission denied (publickey).\n' >&2
  exit 255
fi
printf "Hi test! You've successfully authenticated, but GitHub does not provide shell access.\n" >&2
exit 1
FAKE

  cat >"$FAKE_BIN/sudo" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = "-n" ]; then
  [ "${FAKE_SUDO_CACHED:-0}" = "1" ] && exit 0
  exit 1
fi
read -r password || exit 1
[ "$password" = "secret" ] || exit 1
exit 0
FAKE

  cat >"$FAKE_BIN/git" <<'FAKE'
#!/usr/bin/env bash
# Minimal fake used only by tests that exercise local configuration calls.
# Tests opt into a repository with FAKE_GIT_IS_REPO=1 and set
# FAKE_GIT_DIR/FAKE_GIT_REMOTE_URL/FAKE_GIT_PROFILE as needed.
printf '%s\n' "$*" >>"${FAKE_GIT_LOG:-/dev/null}"
is_repo="${FAKE_GIT_IS_REPO:-0}"

fake_config_get() {
  local key="$1" value=""
  case "$key" in
    remote.*.url) value="${FAKE_GIT_REMOTE_URL:-}" ;;
    gauth.profile) value="${FAKE_GIT_PROFILE:-}" ;;
    user.name) value="${FAKE_GIT_NAME:-}" ;;
    user.email) value="${FAKE_GIT_EMAIL:-}" ;;
    *) return 1 ;;
  esac
  [ -n "$value" ] || return 1
  printf '%s\n' "$value"
}

case "${1:-}" in
  config)
    if [ "${2:-}" = "--local" ] && [ "${3:-}" = "--get" ]; then
      fake_config_get "${4:-}"
      exit $?
    fi
    exit 0
    ;;
  clone)
    # Last argument is the destination directory.
    target=""
    for arg in "$@"; do target="$arg"; done
    [ -n "$target" ] || exit 1
    mkdir -p "$target" || exit 1
    exit 0
    ;;
  remote) exit 0 ;;
  rev-parse)
    case "${2:-}" in
      --is-inside-work-tree)
        [ "$is_repo" = 1 ]
        exit $?
        ;;
      --git-path)
        [ "$is_repo" = 1 ] || exit 1
        printf '%s/hooks\n' "${FAKE_GIT_DIR:-.git}"
        exit 0
        ;;
      --git-dir)
        [ "$is_repo" = 1 ] || exit 1
        printf '%s\n' "${FAKE_GIT_DIR:-.git}"
        exit 0
        ;;
      --abbrev-ref)
        [ "$is_repo" = 1 ] || exit 1
        printf 'main\n'
        exit 0
        ;;
      *) exit 1 ;;
    esac
    ;;
  symbolic-ref)
    [ "$is_repo" = 1 ] || exit 1
    printf 'main\n'
    exit 0
    ;;
  init) exit 0 ;;
esac
exit 0
FAKE

  chmod 755 "$FAKE_BIN"/*
  export PATH="$FAKE_BIN:$PATH"
}

setup_env() {
  rm -rf "$WORK/home" "$WORK/config" "$WORK/state" "$WORK/data" "$WORK/ssh"
  export HOME="$WORK/home"
  mkdir -p "$HOME"
  export GAUTH_CONFIG_HOME="$WORK/config/gauth"
  export GAUTH_STATE_HOME="$WORK/state/gauth"
  export GAUTH_DATA_HOME="$WORK/data/gauth"
  export GAUTH_SSH_DIR="$WORK/ssh"
  export GAUTH_SSH_CONFIG="$GAUTH_SSH_DIR/config"
  export GAUTH_GUM="$WORK/no-such-gum"
  export NO_COLOR=1
  gauth_init_paths
  config_init
  settings_init
  profiles_init
}

run_test() {
  local name="$1"
  shift
  CURRENT="$name"
  setup_env
  "$@"
}

# ---------------------------------------------------------------------------
# Build and CLI
# ---------------------------------------------------------------------------

test_build_and_cli() {
  pass "build"
  assert_ok "generated script parses" bash -n "$DIST"
  assert_eq "gauth 0.1.1" "$("$DIST" version)" "version command"
  local help
  help="$("$DIST" help 2>&1)"
  case "$help" in
    *"guided Git and GitHub profile setup"*) pass "help command" ;;
    *) fail "help command" "$help" ;;
  esac
}

# ---------------------------------------------------------------------------
# Validation and URL parsing
# ---------------------------------------------------------------------------

test_validation() {
  assert_ok "valid profile name" validate_profile_name "work-1"
  assert_fail "reject leading dash" validate_profile_name "-work"
  assert_fail "reject spaces" validate_profile_name "my work"
  assert_ok "valid email" validate_email "a@example.com"
  assert_ok "valid dotted email" validate_email "first.last+tag@example.co.uk"
  assert_fail "reject malformed email" validate_email "a@example"
  assert_fail "reject double @" validate_email "a@b@example.com"
  assert_ok "valid branch" validate_branch_name "main"
  assert_fail "reject branch with space" validate_branch_name "my branch"
  assert_ok "valid repo part" validate_repo_part "repo.name"
  assert_fail "reject traversal" validate_repo_part ".."
}

test_github_urls() {
  local url
  for url in \
    "https://github.com/owner/repo.git" \
    "https://github.com/owner/repo" \
    "http://github.com/owner/repo.git" \
    "git@github.com:owner/repo.git" \
    "ssh://git@github.com/owner/repo.git" \
    "git://github.com/owner/repo.git" \
    "github.com/owner/repo" \
    "owner/repo"
  do
    if git_parse_github_url "$url"; then
      assert_eq "owner/repo" "$GH_OWNER/$GH_REPO" "parse $url"
    else
      fail "parse $url" "rejected"
    fi
  done

  assert_fail "reject non-github URL" git_parse_github_url "https://gitlab.com/owner/repo.git"
  assert_fail "reject extra path" git_parse_github_url "https://github.com/owner/repo/tree/main"
  assert_fail "reject missing repo" git_parse_github_url "https://github.com/owner"

  if git_parse_github_url "https://github.com/owner/repo.git"; then
    assert_eq "git@github.com-work:owner/repo.git" \
      "$(git_remote_url "github.com-work" "$GH_OWNER" "$GH_REPO")" \
      "remote URL composition"
  fi
}

# ---------------------------------------------------------------------------
# UI fallback
# ---------------------------------------------------------------------------

test_ui_fallback() {
  local answer
  answer="$(printf '2\n' | ui_choose "Pick" one two 2>/dev/null)"
  assert_eq "two" "$answer" "numbered choose fallback"
  answer="$(printf 'hello\n' | ui_input "Name" "" "" 2>/dev/null)"
  assert_eq "hello" "$answer" "input fallback"

  local rc=0
  printf ':back\n' | ui_input "Name" "" "" 1 >/dev/null 2>&1 || rc=$?
  assert_eq "2" "$rc" "input :back returns 2"
  rc=0
  printf ':cancel\n' | ui_input "Name" "" "" 1 >/dev/null 2>&1 || rc=$?
  assert_eq "4" "$rc" "input :cancel returns 4"
  rc=0
  printf ':q\n' | ui_input "Name" "" "" 1 >/dev/null 2>&1 || rc=$?
  assert_eq "4" "$rc" "input :q returns 4"
  if printf 'y\n' | ui_confirm "Proceed?" no 2>/dev/null; then
    pass "confirm fallback"
  else
    fail "confirm fallback"
  fi
  if printf '2\n' | ui_choose "Pick" one two >/dev/null 2>&1; then
    pass "choose accepts numeric input"
  else
    fail "choose accepts numeric input"
  fi
}

test_repo_prompt_url_cancel() {
  local rc=0
  printf ':cancel\n' | repo_prompt_url >/dev/null 2>&1 || rc=$?
  assert_eq "1" "$rc" "clone URL prompt cancels on :cancel"
  rc=0
  printf ':back\n' | repo_prompt_url >/dev/null 2>&1 || rc=$?
  assert_eq "1" "$rc" "clone URL prompt cancels on :back"
}

test_banner_and_success() {
  assert_eq "#9ece6a" "$UI_SUCCESS_HEX" "success uses the green palette"
  if [ "$UI_SUCCESS_HEX" != "$UI_ACCENT_HEX" ] && [ "$UI_SUCCESS_HEX" != "$UI_ERROR_HEX" ]; then
    pass "success, information, and error colors are distinct"
  else
    fail "success, information, and error colors are distinct"
  fi
  assert_eq "6" "${#UI_BANNER_LOGO_ART[@]}" "banner logo has six rows"
  assert_eq "6" "${#UI_BANNER_WORD_ART[@]}" "banner wordmark has six rows"
  local i expected ok=1
  expected="${#UI_BANNER_LOGO_ART[0]}"
  for i in 1 2 3 4 5; do
    [ "${#UI_BANNER_LOGO_ART[$i]}" -eq "$expected" ] || ok=0
  done
  if [ "$ok" -eq 1 ]; then pass "banner logo rows align"; else fail "banner logo rows align"; fi
  expected="${#UI_BANNER_WORD_ART[0]}"
  ok=1
  for i in 1 2 3 4 5; do
    [ "${#UI_BANNER_WORD_ART[$i]}" -eq "$expected" ] || ok=0
  done
  if [ "$ok" -eq 1 ]; then pass "banner wordmark rows align"; else fail "banner wordmark rows align"; fi
  local out
  out="$(ui_banner 2>&1)"
  assert_eq "" "$out" "banner stays quiet when non-interactive"
  out="$(ui_success "attention" 2>&1)"
  case "$out" in
    *"attention"*) pass "success message is still readable" ;;
    *) fail "success message is still readable" "$out" ;;
  esac
}

test_sudo_auth() {
  export GAUTH_SUDO_BIN="$FAKE_BIN/sudo"
  export GAUTH_SUDO_ATTEMPTS=1
  unset FAKE_SUDO_CACHED

  if printf 'secret\n' | gauth_require_sudo_auth "test removal" >/dev/null 2>&1; then
    pass "sudo auth accepts the correct password"
  else
    fail "sudo auth accepts the correct password"
  fi
  if printf 'wrong\n' | gauth_require_sudo_auth "test removal" >/dev/null 2>&1; then
    fail "sudo auth rejects a wrong password"
  else
    pass "sudo auth rejects a wrong password"
  fi

  export FAKE_SUDO_CACHED=1
  if printf '\n' | gauth_require_sudo_auth "test removal" >/dev/null 2>&1; then
    pass "sudo auth accepts a cached credential"
  else
    fail "sudo auth accepts a cached credential"
  fi

  unset FAKE_SUDO_CACHED GAUTH_SUDO_BIN GAUTH_SUDO_ATTEMPTS
}

# ---------------------------------------------------------------------------
# Settings and profiles
# ---------------------------------------------------------------------------

test_settings() {
  assert_eq "ed25519" "$SETTING_DEFAULT_KEY_TYPE" "default key type"
  settings_set default_key_type rsa || fail "set key type"
  settings_set copy_public_key false || fail "set clipboard"
  settings_set auto_start_agent false || fail "set agent"
  settings_load
  assert_eq "rsa" "$SETTING_DEFAULT_KEY_TYPE" "persisted key type"
  assert_eq "false" "$SETTING_COPY_PUBLIC_KEY" "persisted clipboard"
  assert_eq "false" "$SETTING_AUTO_START_AGENT" "persisted agent"
  assert_fail "reject bad key type" settings_set default_key_type dsa
  assert_fail "reject bad branch" settings_set default_branch "bad branch"
}

test_profiles() {
  assert_eq "0" "$(profile_count)" "empty profile count"
  profile_save work "github.com-work" "Work User" "work@example.com" "/tmp/id_ed25519_work" ed25519 || fail "save profile"
  assert_eq "1" "$(profile_count)" "profile count"
  assert_ok "profile exists" profile_exists work
  assert_ok "load profile" profile_load work
  assert_eq "github.com-work" "$PROFILE_ALIAS" "profile alias"
  assert_eq "Work User" "$PROFILE_GIT_NAME" "profile git name"
  assert_eq "work@example.com" "$PROFILE_EMAIL" "profile email"
  assert_fail "reject duplicate" profile_save work "github.com-work2" "Work" "work@example.com" "/tmp/k" ed25519
  assert_ok "alias in use" profile_alias_in_use "github.com-work"
  assert_fail "alias excluded for same profile" profile_alias_in_use "github.com-work" work
  profile_update_verified work 12345 || fail "update verified"
  profile_load work
  assert_eq "12345" "$PROFILE_VERIFIED" "verified timestamp"
  profile_delete work || fail "delete profile"
  assert_fail "profile gone" profile_exists work
  assert_eq "0" "$(profile_count)" "count after delete"
  assert_ok "header survives" grep -q '^# gauth profiles v1' "$GAUTH_PROFILES_FILE"
}

# ---------------------------------------------------------------------------
# SSH config editing
# ---------------------------------------------------------------------------

write_ssh_config() {
  mkdir -p "$GAUTH_SSH_DIR"
  cat >"$GAUTH_SSH_CONFIG" <<'EOF'
# user comment
Host *
  ServerAliveInterval 60

Host existing
  HostName example.com
EOF
}

test_ssh_config() {
  write_ssh_config
  assert_ok "upsert managed block" sshconfig_upsert "github.com-work" "/tmp/id_ed25519_work"
  assert_ok "managed marker exists" sshconfig_has_managed "github.com-work"
  assert_eq "1" "$(grep -c '^Host github.com-work$' "$GAUTH_SSH_CONFIG")" "one host block"
  assert_eq "1" "$(grep -c '^# user comment$' "$GAUTH_SSH_CONFIG")" "user comment preserved"
  assert_ok "wildcard preserved" grep -q '^Host \*$' "$GAUTH_SSH_CONFIG"
  assert_eq "1" "$(head -1 "$GAUTH_SSH_CONFIG" | grep -c '^# >>> gauth:github.com-work >>>$')" "managed block is first"

  sshconfig_upsert "github.com-work" "/tmp/id_ed25519_work" >/dev/null 2>&1
  assert_eq "1" "$(grep -c '^Host github.com-work$' "$GAUTH_SSH_CONFIG")" "upsert is idempotent"

  if [ -n "${SAVED_PATH:-}" ]; then
    assert_eq "$GAUTH_DEFAULT_HOST" "$(PATH="$SAVED_PATH" ssh_config_hostname "github.com-work")" "ssh resolves alias hostname"
    assert_eq "/tmp/id_ed25519_work" "$(PATH="$SAVED_PATH" ssh_config_identity "github.com-work")" "ssh resolves identity file"
  fi

  assert_ok "remove managed block" sshconfig_remove "github.com-work"
  assert_fail "managed marker gone" sshconfig_has_managed "github.com-work"
  assert_ok "user block survives removal" grep -q '^Host existing$' "$GAUTH_SSH_CONFIG"
  assert_ok "wildcard survives removal" grep -q '^Host \*$' "$GAUTH_SSH_CONFIG"

  printf '\nHost github.com-foreign\n  HostName example.com\n' >>"$GAUTH_SSH_CONFIG"
  assert_fail "foreign alias refused" sshconfig_upsert "github.com-foreign" "/tmp/key" >/dev/null 2>&1
  assert_ok "foreign block untouched" grep -q '^Host github.com-foreign$' "$GAUTH_SSH_CONFIG"
}

# ---------------------------------------------------------------------------
# Alias-aware URLs and key layout
# ---------------------------------------------------------------------------

test_alias_urls_and_key_layout() {
  assert_eq "$GAUTH_SSH_DIR/gauth/id_ed25519_demo" \
    "$(ssh_default_key_path demo ed25519)" \
    "new keys live under ~/.ssh/gauth"

  write_ssh_config
  sshconfig_upsert "github.com-work" "/tmp/id_ed25519_work" >/dev/null 2>&1
  if git_parse_github_url "git@github.com-work:owner/repo.git"; then
    assert_eq "owner/repo" "$GH_OWNER/$GH_REPO" "parse managed alias SSH URL"
  else
    fail "parse managed alias SSH URL" "rejected"
  fi
  if git_parse_github_url "ssh://git@github.com-work/owner/repo.git"; then
    assert_eq "owner/repo" "$GH_OWNER/$GH_REPO" "parse managed alias ssh:// URL"
  else
    fail "parse managed alias ssh:// URL" "rejected"
  fi
  assert_fail "reject foreign SSH host" git_parse_github_url "git@example.com:owner/repo.git"

  if profile_require "__definitely_missing__" >/dev/null 2>&1; then
    fail "unknown profile is non-fatal"
  else
    pass "unknown profile is non-fatal"
  fi
}

# ---------------------------------------------------------------------------
# Repository setup (fake git)
# ---------------------------------------------------------------------------

test_repo_setup() {
  mkdir -p "$GAUTH_SSH_DIR"
  : >"$GAUTH_SSH_DIR/id_ed25519_work"
  profile_save work "github.com-work" "Work User" "work@example.com" "$GAUTH_SSH_DIR/id_ed25519_work" ed25519 || fail "save repo profile"
  export FAKE_GIT_LOG="$WORK/git.log"
  : >"$FAKE_GIT_LOG"

  repo_apply work "https://github.com/owner/repo.git" 1 0 >/dev/null 2>&1 || {
    fail "repo apply"
    return
  }
  pass "repo apply"
  assert_ok "init uses default branch" grep -q '^init -b main$' "$FAKE_GIT_LOG"
  assert_ok "local identity set" grep -q '^config --local user.name Work User$' "$FAKE_GIT_LOG"
  assert_ok "remote added" grep -q '^remote add origin git@github.com-work:owner/repo.git$' "$FAKE_GIT_LOG"
  assert_ok "profile recorded in git config" grep -q '^config --local gauth.profile work$' "$FAKE_GIT_LOG"
}

# ---------------------------------------------------------------------------
# Profile selection, existing repositories, and the pre-push guard
# ---------------------------------------------------------------------------

save_repo_profile() {
  local name="$1" alias="$2" email="$3"
  mkdir -p "$GAUTH_SSH_DIR"
  : >"$GAUTH_SSH_DIR/id_ed25519_$name"
  profile_save "$name" "$alias" "${name} User" "$email" \
    "$GAUTH_SSH_DIR/id_ed25519_$name" ed25519
}

test_no_profile_message() {
  local out rc=0
  out="$(profile_list_cmd 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "profile list fails when there are no profiles"
  else
    fail "profile list fails when there are no profiles"
  fi
  case "$out" in
    *"No accounts/profiles"*) pass "profile list explains that no profile exists" ;;
    *) fail "profile list explains that no profile exists" "$out" ;;
  esac

  rc=0
  out="$(profile_select_view 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "view/select fails when there are no profiles"
  else
    fail "view/select fails when there are no profiles"
  fi
  case "$out" in
    *"No accounts/profiles"*) pass "view/select explains that no profile exists" ;;
    *) fail "view/select explains that no profile exists" "$out" ;;
  esac
}

test_profile_alias_lookup() {
  save_repo_profile work "github.com-work" "work@example.com" || fail "save alias profile"
  assert_eq "work" "$(profile_name_for_alias "github.com-work")" "profile name from alias"
  assert_fail "unknown alias has no profile" profile_name_for_alias "github.com-other"
}

test_github_origin_detection() {
  save_repo_profile work "github.com-work" "work@example.com" || fail "save origin profile"
  export FAKE_GIT_IS_REPO=1
  export FAKE_GIT_DIR="$WORK/origin-repo/.git"
  mkdir -p "$FAKE_GIT_DIR"

  export FAKE_GIT_REMOTE_URL="git@github.com-work:owner/repo.git"
  assert_ok "detect alias GitHub origin" repo_detect_github_origin
  assert_eq "owner/repo" "$REPO_OWNER/$REPO_REPO" "detected repository"
  assert_eq "github.com-work" "$REPO_ORIGIN_ALIAS" "detected origin alias"
  assert_eq "$FAKE_GIT_REMOTE_URL" "$REPO_ORIGIN_URL" "detected origin URL"
  assert_eq "work" "$(profile_name_for_alias "$REPO_ORIGIN_ALIAS")" "origin alias maps to profile"

  export FAKE_GIT_REMOTE_URL="https://github.com/owner/repo.git"
  assert_ok "detect HTTPS GitHub origin" repo_detect_github_origin
  assert_eq "" "$REPO_ORIGIN_ALIAS" "HTTPS origin has no alias"

  export FAKE_GIT_REMOTE_URL="https://gitlab.com/owner/repo.git"
  assert_fail "ignore non-GitHub origin" repo_detect_github_origin

  unset FAKE_GIT_IS_REPO FAKE_GIT_DIR FAKE_GIT_REMOTE_URL
}

test_existing_origin_reused() {
  save_repo_profile work "github.com-work" "work@example.com" || fail "save existing profile"
  write_ssh_config
  sshconfig_upsert "github.com-work" "$GAUTH_SSH_DIR/id_ed25519_work" >/dev/null 2>&1

  export FAKE_GIT_IS_REPO=1
  export FAKE_GIT_DIR="$WORK/existing-repo/.git"
  export FAKE_GIT_REMOTE_URL="https://github.com/owner/repo.git"
  mkdir -p "$FAKE_GIT_DIR"
  export FAKE_GIT_LOG="$WORK/existing-git.log"
  : >"$FAKE_GIT_LOG"

  # No URL argument: repo_apply must reuse the existing GitHub origin.
  repo_apply work "" 1 0 >/dev/null 2>&1 || {
    fail "existing origin reused"
    return
  }
  pass "existing origin reused"
  assert_ok "existing origin rewritten to profile alias" \
    grep -q '^config --local remote.origin.url git@github.com-work:owner/repo.git$' "$FAKE_GIT_LOG"
  if grep -q '^remote add origin' "$FAKE_GIT_LOG"; then
    fail "existing origin is not re-added"
  else
    pass "existing origin is not re-added"
  fi
  assert_ok "selected profile recorded" \
    grep -q '^config --local gauth.profile work$' "$FAKE_GIT_LOG"
  assert_ok "pre-push guard installed" git_pre_push_hook_installed "$FAKE_GIT_DIR/hooks"
  assert_file "guard file exists" "$FAKE_GIT_DIR/hooks/pre-push"
  assert_ok "guard calls gauth hook" \
    grep -q 'hook pre-push' "$FAKE_GIT_DIR/hooks/pre-push"

  unset FAKE_GIT_IS_REPO FAKE_GIT_DIR FAKE_GIT_REMOTE_URL FAKE_GIT_LOG
}

test_pre_push_hook_install() {
  local hooks="$WORK/hook-install"
  assert_ok "install guard in a hooks directory" git_install_pre_push_hook "$hooks"
  assert_file "guard installed" "$hooks/pre-push"
  assert_ok "guard is executable" test -x "$hooks/pre-push"
  assert_ok "guard has gauth marker" grep -qFqx "$GAUTH_HOOK_MARKER_BEGIN" "$hooks/pre-push"
  assert_ok "guard invokes gauth hook pre-push" grep -q 'hook pre-push' "$hooks/pre-push"
  assert_ok "guard installation is idempotent" git_install_pre_push_hook "$hooks"

  local foreign="$WORK/hook-foreign"
  mkdir -p "$foreign"
  printf '#!/bin/sh\nexit 0\n' >"$foreign/pre-push"
  local rc=0
  git_install_pre_push_hook "$foreign" >/dev/null 2>&1 || rc=$?
  assert_eq "2" "$rc" "foreign pre-push hook is refused"
  assert_eq "#!/bin/sh" "$(head -1 "$foreign/pre-push")" "foreign hook is untouched"

  export FAKE_GIT_IS_REPO=0
  rc=0
  git_install_pre_push_hook >/dev/null 2>&1 || rc=$?
  assert_eq "3" "$rc" "guard reports a non-repository"
  unset FAKE_GIT_IS_REPO
}

test_pre_push_guard() {
  save_repo_profile work "github.com-work" "work@example.com" || fail "save guard profile"
  save_repo_profile personal "github.com-personal" "me@example.com" || fail "save second profile"
  write_ssh_config
  sshconfig_upsert "github.com-work" "$GAUTH_SSH_DIR/id_ed25519_work" >/dev/null 2>&1
  sshconfig_upsert "github.com-personal" "$GAUTH_SSH_DIR/id_ed25519_personal" >/dev/null 2>&1

  export FAKE_GIT_IS_REPO=1
  export FAKE_GIT_DIR="$WORK/guard-repo/.git"
  mkdir -p "$FAKE_GIT_DIR"
  export GAUTH_HOOK_NO_PROMPT=1

  export FAKE_GIT_PROFILE=work
  export FAKE_GIT_REMOTE_URL="git@github.com-work:owner/repo.git"
  assert_ok "matching profile allows the push" \
    hook_pre_push origin "$FAKE_GIT_REMOTE_URL"

  unset FAKE_GIT_PROFILE
  export FAKE_GIT_LOG="$WORK/guard-git.log"
  : >"$FAKE_GIT_LOG"
  assert_ok "remote alias identifies a cloned repository" \
    hook_pre_push origin "$FAKE_GIT_REMOTE_URL"
  assert_ok "detected profile is recorded" \
    grep -q '^config --local gauth.profile work$' "$FAKE_GIT_LOG"

  export FAKE_GIT_PROFILE=work
  export FAKE_GIT_REMOTE_URL="https://github.com/owner/repo.git"
  local rc=0 out=""
  out="$(hook_pre_push origin "$FAKE_GIT_REMOTE_URL" 2>&1)" || rc=$?
  assert_eq "1" "$rc" "mismatched profile blocks the push"
  case "$out" in
    *"Push blocked"*) pass "mismatch explains the block" ;;
    *) fail "mismatch explains the block" "$out" ;;
  esac

  assert_ok "non-GitHub remote passes through" \
    hook_pre_push origin "https://gitlab.com/owner/repo.git"

  # With a prompt, choosing a profile rewrites the remote and blocks once so
  # the next push actually uses the new SSH alias.
  export FAKE_GIT_REMOTE_URL="https://github.com/owner/repo.git"
  : >"$FAKE_GIT_LOG"
  rc=0
  out="$(
    hook_can_prompt() { return 0; }
    hook_pick_profile() { printf 'personal\n'; }
    hook_pre_push origin "$FAKE_GIT_REMOTE_URL" 2>&1
  )" || rc=$?
  assert_eq "1" "$rc" "chosen profile blocks once after updating the remote"
  case "$out" in
    *"Remote updated to profile 'personal'"*) pass "guard reports the remote update" ;;
    *) fail "guard reports the remote update" "$out" ;;
  esac
  assert_ok "remote rewritten to the chosen profile" \
    grep -q '^config --local remote.origin.url git@github.com-personal:owner/repo.git$' "$FAKE_GIT_LOG"
  assert_ok "chosen profile recorded" \
    grep -q '^config --local gauth.profile personal$' "$FAKE_GIT_LOG"

  profile_delete work
  profile_delete personal
  rc=0
  out="$(hook_pre_push origin "https://github.com/owner/repo.git" 2>&1)" || rc=$?
  assert_eq "1" "$rc" "guard blocks when no profiles exist"
  case "$out" in
    *"no gauth profiles"*) pass "guard explains the missing profiles" ;;
    *) fail "guard explains the missing profiles" "$out" ;;
  esac

  unset FAKE_GIT_IS_REPO FAKE_GIT_DIR FAKE_GIT_PROFILE FAKE_GIT_REMOTE_URL
  unset FAKE_GIT_LOG GAUTH_HOOK_NO_PROMPT
}

test_profile_select_view_is_read_only() {
  save_repo_profile work "github.com-work" "work@example.com" || fail "save view profile"
  write_ssh_config
  sshconfig_upsert "github.com-work" "$GAUTH_SSH_DIR/id_ed25519_work" >/dev/null 2>&1

  export FAKE_GIT_IS_REPO=1
  export FAKE_GIT_DIR="$WORK/view-repo/.git"
  export FAKE_GIT_REMOTE_URL="https://github.com/owner/repo.git"
  mkdir -p "$FAKE_GIT_DIR"
  export FAKE_GIT_LOG="$WORK/view-git.log"
  : >"$FAKE_GIT_LOG"

  out="$(printf 'work\n' | profile_select_view 2>&1)" || {
    fail "view/select should display a saved profile"
    return
  }
  pass "view/select displays a saved profile"
  case "$out" in
    *"Profile: work"*) pass "view/select shows the selected profile by name" ;;
    *) fail "view/select shows the selected profile by name" "$out" ;;
  esac
  assert_fail "view/select does not rewrite the remote" \
    grep -q '^config --local remote.origin.url git@github.com-work:owner/repo.git$' "$FAKE_GIT_LOG"
  assert_fail "view/select does not record the profile" \
    grep -q '^config --local gauth.profile work$' "$FAKE_GIT_LOG"
  assert_fail "view/select does not install the guard" git_pre_push_hook_installed "$FAKE_GIT_DIR/hooks"

  unset FAKE_GIT_IS_REPO FAKE_GIT_DIR FAKE_GIT_REMOTE_URL FAKE_GIT_LOG
}

# ---------------------------------------------------------------------------
# Clone flow and duplicate-clone safeguards
# ---------------------------------------------------------------------------

test_clone_repository() {
  save_repo_profile work "github.com-work" "work@example.com" || fail "save clone profile"
  write_ssh_config
  sshconfig_upsert "github.com-work" "$GAUTH_SSH_DIR/id_ed25519_work" >/dev/null 2>&1

  export FAKE_GIT_IS_REPO=0
  export FAKE_GIT_LOG="$WORK/clone-git.log"
  : >"$FAKE_GIT_LOG"
  unset FAKE_GIT_REMOTE_URL FAKE_GIT_PROFILE

  local dir="$WORK/cloned-repo"
  cmd_clone "https://github.com/owner/repo.git" "$dir" \
    --profile work --yes --no-test >/dev/null 2>&1 || {
    fail "clone command"
    return
  }
  pass "clone command"

  assert_ok "clone uses the profile's SSH alias" \
    grep -q "^clone -- git@github.com-work:owner/repo.git $dir$" "$FAKE_GIT_LOG"
  assert_ok "clone creates the destination" test -d "$dir"
  assert_ok "clone configures local identity" \
    grep -q '^config --local user.name work User$' "$FAKE_GIT_LOG"
  assert_ok "clone records the selected profile" \
    grep -q '^config --local gauth.profile work$' "$FAKE_GIT_LOG"

  unset FAKE_GIT_IS_REPO FAKE_GIT_LOG
}

test_clone_duplicate_safeguard() {
  save_repo_profile work "github.com-work" "work@example.com" || fail "save duplicate profile"

  export FAKE_GIT_IS_REPO=1
  export FAKE_GIT_REMOTE_URL="git@github.com-work:owner/repo.git"
  export FAKE_GIT_PROFILE=work
  export FAKE_GIT_LOG="$WORK/duplicate-git.log"
  : >"$FAKE_GIT_LOG"

  local out rc=0
  out="$(printf 'n\n' | cmd_clone "https://github.com/owner/repo.git" 2>&1)" || rc=$?
  assert_eq "1" "$rc" "cloning from inside the repository is refused"
  case "$out" in
    *"Repository detected"*) pass "duplicate clone reports the detected repository" ;;
    *) fail "duplicate clone reports the detected repository" "$out" ;;
  esac
  if grep -q '^clone ' "$FAKE_GIT_LOG"; then
    fail "duplicate clone does not run git clone"
  else
    pass "duplicate clone does not run git clone"
  fi

  unset FAKE_GIT_IS_REPO FAKE_GIT_REMOTE_URL FAKE_GIT_PROFILE FAKE_GIT_LOG
}

test_clone_existing_directory_safeguard() {
  save_repo_profile work "github.com-work" "work@example.com" || fail "save existing-dir profile"

  local dir="$WORK/already-cloned"
  mkdir -p "$dir/.git"
  export FAKE_GIT_IS_REPO=0
  export FAKE_GIT_REMOTE_URL="https://github.com/owner/repo.git"
  export FAKE_GIT_LOG="$WORK/existing-dir-git.log"
  : >"$FAKE_GIT_LOG"

  local out rc=0
  out="$(printf 'n\n' | cmd_clone "https://github.com/owner/repo.git" "$dir" \
    --profile work --yes --no-test 2>&1)" || rc=$?
  assert_eq "1" "$rc" "existing checkout is not cloned over"
  case "$out" in
    *"Repository already cloned at"*) pass "existing checkout is reported" ;;
    *) fail "existing checkout is reported" "$out" ;;
  esac
  if grep -q '^clone ' "$FAKE_GIT_LOG"; then
    fail "existing checkout does not run git clone"
  else
    pass "existing checkout does not run git clone"
  fi

  unset FAKE_GIT_IS_REPO FAKE_GIT_REMOTE_URL FAKE_GIT_LOG
}

test_profile_select_for_repo() {
  save_repo_profile work "github.com-work" "work@example.com" || fail "save switch profile"
  write_ssh_config
  sshconfig_upsert "github.com-work" "$GAUTH_SSH_DIR/id_ed25519_work" >/dev/null 2>&1

  export FAKE_GIT_IS_REPO=1
  export FAKE_GIT_DIR="$WORK/select-repo/.git"
  export FAKE_GIT_REMOTE_URL="https://github.com/owner/repo.git"
  mkdir -p "$FAKE_GIT_DIR"
  export FAKE_GIT_LOG="$WORK/select-git.log"
  : >"$FAKE_GIT_LOG"

  printf 'y\n' | profile_select_for_repo work >/dev/null 2>&1 || {
    fail "switch profile for the repository"
    return
  }
  pass "switch profile for the repository"
  assert_ok "switch rewrites the remote to the profile alias" \
    grep -q '^config --local remote.origin.url git@github.com-work:owner/repo.git$' "$FAKE_GIT_LOG"
  assert_ok "switch records the profile" \
    grep -q '^config --local gauth.profile work$' "$FAKE_GIT_LOG"
  assert_ok "switch installs the guard" git_pre_push_hook_installed "$FAKE_GIT_DIR/hooks"

  unset FAKE_GIT_IS_REPO FAKE_GIT_DIR FAKE_GIT_REMOTE_URL FAKE_GIT_LOG
}

# ---------------------------------------------------------------------------
# SSH key and connection helpers
# ---------------------------------------------------------------------------

test_ssh_key() {
  local key="$GAUTH_SSH_DIR/id_ed25519_test"
  assert_ok "generate key" ssh_generate_key "$key" "test@example.com" ed25519 none
  assert_file "private key written" "$key"
  assert_file "public key written" "${key}.pub"
  assert_eq "600" "$(gauth_file_mode "$key")" "private key mode"
  assert_eq "644" "$(gauth_file_mode "${key}.pub")" "public key mode"
  assert_eq "700" "$(gauth_file_mode "$GAUTH_SSH_DIR")" "ssh directory mode"
  assert_eq "SHA256:testfingerprint" "$(ssh_key_fingerprint "$key")" "fingerprint"
  assert_fail "refuse overwrite" ssh_generate_key "$key" "test@example.com" ed25519 none >/dev/null 2>&1
}

test_ssh_connection() {
  unset FAKE_SSH_FAIL
  assert_ok "ssh -T exit 1 success handling" ssh_test_connection "github.com-work"
  assert_eq "1" "$SSH_TEST_RC" "captured ssh exit code"
  export FAKE_SSH_FAIL=1
  assert_fail "ssh permission denied" ssh_test_connection "github.com-work"
  unset FAKE_SSH_FAIL
}

# ---------------------------------------------------------------------------
# Complete uninstaller
# ---------------------------------------------------------------------------

test_uninstall_script() {
  local home="$WORK/uninstall-home"
  local prefix="$WORK/uninstall-prefix"
  local cfg="$home/.ssh/config"
  local key="$home/.ssh/gauth/id_ed25519_work"
  local rc=0

  rm -rf "$home" "$prefix"
  mkdir -p "$home/.config/gauth" "$home/.local/state/gauth" \
    "$home/.local/share/gauth" "$home/.ssh/gauth" \
    "$prefix/bin" "$prefix/libexec/gauth"

  printf 'binary\n' >"$prefix/bin/gauth"
  printf 'gum\n' >"$prefix/libexec/gauth/gum"
  printf 'private\n' >"$key"
  printf 'ssh-ed25519 AAAA test@example.com\n' >"$key.pub"
  printf 'key_type=ed25519\n' >"$home/.config/gauth/settings.conf"
  {
    printf '# gauth profiles v1\n'
    printf '# name\talias\tgit_name\temail\tkey_path\tkey_type\tcreated\tlast_verified\n'
    printf 'work\tgithub.com-work\tWork User\twork@example.com\t%s\ted25519\t0\t-\n' "$key"
  } >"$home/.config/gauth/profiles.tsv"
  {
    printf '# >>> gauth:github.com-work >>>\n'
    printf 'Host github.com-work\n'
    printf '  HostName github.com\n'
    printf '  User git\n'
    printf '  IdentityFile %s\n' "$key"
    printf '  IdentitiesOnly yes\n'
    printf '# <<< gauth:github.com-work <<<\n'
    printf '\n'
    printf 'Host existing\n'
    printf '  HostName example.com\n'
  } >"$cfg"

  run_uninstall() {
    HOME="$home" \
      GAUTH_CONFIG_HOME="$home/.config/gauth" \
      GAUTH_STATE_HOME="$home/.local/state/gauth" \
      GAUTH_DATA_HOME="$home/.local/share/gauth" \
      GAUTH_SSH_DIR="$home/.ssh" \
      GAUTH_SSH_CONFIG="$cfg" \
      GAUTH_SUDO_BIN="$FAKE_BIN/sudo" \
      GAUTH_SUDO_ATTEMPTS=1 \
      bash "$ROOT/uninstall.sh" --yes --prefix "$prefix" \
        --bindir "$prefix/bin" --libexecdir "$prefix/libexec/gauth"
  }

  local deny_rc=0
  run_uninstall </dev/null >/dev/null 2>&1 || deny_rc=$?
  if [ "$deny_rc" -ne 0 ]; then
    pass "uninstaller refuses without sudo authentication"
  else
    fail "uninstaller refuses without sudo authentication"
  fi
  if [ -e "$prefix/bin/gauth" ] && [ -e "$key" ]; then
    pass "failed authentication leaves gauth installed"
  else
    fail "failed authentication leaves gauth installed"
  fi

  local wrong_rc=0
  printf 'wrong\n' | run_uninstall >/dev/null 2>&1 || wrong_rc=$?
  if [ "$wrong_rc" -ne 0 ]; then
    pass "uninstaller rejects a wrong sudo password"
  else
    fail "uninstaller rejects a wrong sudo password"
  fi
  if [ -e "$prefix/bin/gauth" ]; then
    pass "wrong password leaves gauth installed"
  else
    fail "wrong password leaves gauth installed"
  fi

  local out=""
  out="$(printf 'secret\n\n' | run_uninstall 2>&1)" || rc=$?
  case "$out" in
    *"THIS WILL REMOVE EVERYTHING"*|*"WARNING"*) pass "uninstaller warns before permanent removal" ;;
    *) fail "uninstaller warns before permanent removal" "$out" ;;
  esac
  assert_eq "0" "$rc" "uninstaller exits successfully"

  local cancel_rc=0
  out="$(printf '\033\n' | run_uninstall 2>&1)" || cancel_rc=$?
  if [ "$cancel_rc" -ne 0 ]; then pass "uninstaller cancels on Esc"; else fail "uninstaller cancels on Esc" "$out"; fi

  if [ ! -e "$prefix/bin/gauth" ]; then pass "uninstaller removes the binary"; else fail "uninstaller removes the binary"; fi
  if [ ! -e "$prefix/libexec/gauth/gum" ]; then pass "uninstaller removes private gum"; else fail "uninstaller removes private gum"; fi
  if [ ! -e "$home/.config/gauth" ]; then pass "uninstaller removes config"; else fail "uninstaller removes config"; fi
  if [ ! -e "$home/.local/state/gauth" ]; then pass "uninstaller removes state"; else fail "uninstaller removes state"; fi
  if [ ! -e "$home/.local/share/gauth" ]; then pass "uninstaller removes data"; else fail "uninstaller removes data"; fi
  if [ ! -e "$home/.ssh/gauth" ]; then pass "uninstaller removes gauth keys"; else fail "uninstaller removes gauth keys"; fi
  if grep -q '^Host existing$' "$cfg"; then pass "uninstaller preserves user SSH entries"; else fail "uninstaller preserves user SSH entries"; fi
  if grep -q 'gauth:' "$cfg"; then fail "uninstaller removes managed SSH blocks"; else pass "uninstaller removes managed SSH blocks"; fi
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

make_fakes
( cd "$ROOT" && ./build.sh >/dev/null ) || {
  printf 'build failed\n' >&2
  exit 1
}
GAUTH_SOURCE_ONLY=1
. "$DIST"

printf 'gauth tests\n'
run_test "build and CLI" test_build_and_cli
run_test "validation" test_validation
run_test "GitHub URLs" test_github_urls
run_test "UI fallback" test_ui_fallback
run_test "Clone URL prompt cancel" test_repo_prompt_url_cancel
run_test "banner and success" test_banner_and_success
run_test "sudo authentication" test_sudo_auth
run_test "settings" test_settings
run_test "profiles" test_profiles
run_test "alias URLs and key layout" test_alias_urls_and_key_layout
run_test "repository setup" test_repo_setup
run_test "no profile message" test_no_profile_message
run_test "profile alias lookup" test_profile_alias_lookup
run_test "GitHub origin detection" test_github_origin_detection
run_test "existing origin reused" test_existing_origin_reused
run_test "pre-push hook installation" test_pre_push_hook_install
run_test "pre-push guard" test_pre_push_guard
run_test "profile select for repository" test_profile_select_for_repo
run_test "profile view/select is read-only" test_profile_select_view_is_read_only
run_test "clone repository" test_clone_repository
run_test "duplicate clone safeguard" test_clone_duplicate_safeguard
run_test "existing directory clone safeguard" test_clone_existing_directory_safeguard
run_test "SSH config" test_ssh_config
run_test "SSH keys" test_ssh_key
run_test "SSH connection" test_ssh_connection
run_test "uninstaller" test_uninstall_script

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
