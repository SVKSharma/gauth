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

  cat >"$FAKE_BIN/git" <<'FAKE'
#!/usr/bin/env bash
# Minimal fake used only by tests that exercise local configuration calls.
printf '%s\n' "$*" >>"${FAKE_GIT_LOG:-/dev/null}"
case "${1:-}" in
  config)
    if [ "${2:-}" = "--local" ] && [ "${3:-}" = "--get" ]; then
      exit 1
    fi
    exit 0
    ;;
  remote) exit 0 ;;
  rev-parse) exit 1 ;;
  symbolic-ref) exit 0 ;;
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
  assert_eq "gauth 0.2.0" "$("$DIST" version)" "version command"
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
run_test "settings" test_settings
run_test "profiles" test_profiles
run_test "repository setup" test_repo_setup
run_test "SSH config" test_ssh_config
run_test "SSH keys" test_ssh_key
run_test "SSH connection" test_ssh_connection

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
