# shellcheck shell=bash
# Command implementations and the interactive menu.

usage() {
  cat <<EOF
gauth $GAUTH_VERSION - guided Git and GitHub account setup

Usage:
  gauth                         Interactive menu
  gauth init [options]          Connect the current directory to GitHub
  gauth account <command>       list | add | remove | show | select
  gauth settings                Change defaults
  gauth doctor [--test] [--fix] Check the installation
  gauth version                 Print the version
  gauth help                    Show this help

init options:
  --account NAME   Use an existing gauth account
  --repo URL       GitHub repository URL (HTTPS or SSH)
  --yes            Apply without confirmation prompts
  --no-test        Skip the ssh -T connection test

Examples:
  gauth
  gauth init --repo https://github.com/owner/repo.git
  gauth init --account work --repo git@github.com:owner/repo.git
  gauth doctor --test

gauth never commits, pushes, or changes your global git identity.
EOF
}

cmd_version() {
  printf 'gauth %s\n' "$GAUTH_VERSION"
}

repo_prompt_url() {
  local repo_url=""
  while :; do
    repo_url="$(ui_input "GitHub repository URL" "https://github.com/owner/repo.git" "")" || return 1
    if git_parse_github_url "$repo_url"; then
      printf '%s\n' "$repo_url"
      return 0
    fi
    ui_error "Use a GitHub URL like https://github.com/owner/repo.git"
  done
}

repo_apply() {
  local account_name="$1"
  local repo_url="$2"
  local assume_yes="${3:-0}"
  local do_test="${4:-1}"

  git_require || return 1
  account_require "$account_name"

  if [ ! -f "$ACC_KEY" ]; then
    ui_error "The private key for '$account_name' is missing: $ACC_KEY"
    ui_info "Run 'gauth doctor' or add the account again."
    return 1
  fi

  if ! sshconfig_has_managed "$ACC_ALIAS"; then
    if sshconfig_alias_exists "$ACC_ALIAS"; then
      ui_error "Alias '$ACC_ALIAS' exists outside gauth; cannot add a managed block."
      return 1
    fi
    ui_warn "SSH config block is missing; adding it for '$account_name'."
    sshconfig_upsert "$ACC_ALIAS" "$ACC_KEY" || return 1
  fi

  if [ -z "$repo_url" ]; then
    repo_url="$(git_current_remote 2>/dev/null || true)"
    if [ -n "$repo_url" ]; then
      if git_parse_github_url "$repo_url"; then
        if [ "$assume_yes" -eq 0 ]; then
          if ! ui_confirm "Use the current origin '$repo_url'?" yes; then
            repo_url=""
          fi
        fi
      else
        ui_warn "Current origin is not a GitHub URL: $repo_url"
        repo_url=""
      fi
    fi
  fi

  if [ -z "$repo_url" ]; then
    if [ "$assume_yes" -eq 1 ] || ! gauth_is_tty; then
      ui_error "A GitHub repository URL is required."
      return 1
    fi
    repo_url="$(repo_prompt_url)" || return 1
  fi

  if ! git_parse_github_url "$repo_url"; then
    ui_error "Not a supported GitHub URL: $repo_url"
    return 1
  fi

  local owner="$GH_OWNER"
  local repo="$GH_REPO"
  local remote_url
  remote_url="$(git_remote_url "$ACC_ALIAS" "$owner" "$repo")"
  local needs_init=0
  local target_branch="$SETTING_DEFAULT_BRANCH"
  if ! git_is_repo; then
    needs_init=1
  else
    target_branch="$(git_current_branch)"
    [ -n "$target_branch" ] || target_branch="$SETTING_DEFAULT_BRANCH"
  fi

  ui_section "Repository plan"
  ui_kv "Account" "$account_name"
  ui_kv "Git name" "$ACC_GIT_NAME"
  ui_kv "Email" "$ACC_EMAIL"
  ui_kv "Remote" "$remote_url"
  if [ "$needs_init" -eq 1 ]; then
    ui_kv "Repository" "will be initialized with branch '$SETTING_DEFAULT_BRANCH'"
  else
    ui_kv "Repository" "existing git repository"
    ui_kv "Current origin" "$(git_current_remote 2>/dev/null || printf 'none')"
  fi

  if [ "$assume_yes" -eq 0 ]; then
    ui_confirm "Apply these repository settings?" yes || {
      ui_info "Cancelled."
      return 1
    }
  fi

  if [ "$needs_init" -eq 1 ]; then
    if ! git_init_repo "$SETTING_DEFAULT_BRANCH"; then
      ui_error "Could not initialize the git repository."
      return 1
    fi
    ui_success "Git repository initialized (branch: $SETTING_DEFAULT_BRANCH)."
  fi

  if ! git_set_local_identity "$ACC_GIT_NAME" "$ACC_EMAIL"; then
    ui_error "Could not set the local git identity."
    return 1
  fi
  if ! git_set_remote "$remote_url"; then
    ui_error "Could not set remote.origin.url."
    return 1
  fi
  git_set_gauth_account "$account_name" || true

  ui_success "Local repository configured."
  ui_kv "user.name" "$(git_local_config user.name)"
  ui_kv "user.email" "$(git_local_config user.email)"
  ui_kv "remote.origin.url" "$(git_current_remote)"

  if [ "$do_test" -eq 1 ]; then
    ui_info "Testing git@${ACC_ALIAS} ..."
    if ssh_test_connection "$ACC_ALIAS"; then
      ui_success "GitHub SSH authentication works."
      account_update_verified "$account_name" "$(gauth_now)" || true
    else
      ui_warn "SSH test did not succeed; the repository was still configured."
      ssh_friendly_failure
    fi
  fi

  ui_section "Next steps"
  ui_info "gauth does not commit or push. When you are ready:"
  printf '  git add .\n' >&2
  printf '  git commit -m "Initial commit"\n' >&2
  printf '  git push -u origin %s\n' "$target_branch" >&2
  return 0
}

repo_connect_flow() {
  local account_name="${1:-}"
  if [ -z "$account_name" ]; then
    account_name="$(account_pick "Account for this repository")" || return 1
  fi
  repo_apply "$account_name" "" 0 1
}

cmd_init() {
  local account_name=""
  local repo_url=""
  local assume_yes=0
  local do_test=1

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --account)
        [ "$#" -ge 2 ] || {
          ui_error "--account needs a value."
          return 2
        }
        account_name="$2"
        shift 2
        ;;
      --repo)
        [ "$#" -ge 2 ] || {
          ui_error "--repo needs a value."
          return 2
        }
        repo_url="$2"
        shift 2
        ;;
      --yes|-y) assume_yes=1; shift ;;
      --no-test) do_test=0; shift ;;
      --help|-h) usage; return 0 ;;
      *)
        ui_error "Unknown init option: $1"
        return 2
        ;;
    esac
  done

  if [ -z "$account_name" ]; then
    if ! gauth_is_tty; then
      ui_error "Use --account NAME in a non-interactive session."
      return 1
    fi
    account_name="$(account_pick "Account for this repository")" || return 1
  fi

  repo_apply "$account_name" "$repo_url" "$assume_yes" "$do_test"
}

cmd_account() {
  local sub="${1:-list}"
  [ "$#" -gt 0 ] && shift
  case "$sub" in
    list|ls) account_list_cmd ;;
    add) account_add ;;
    remove|rm|delete) account_remove ;;
    show|view|select|use) account_select_view ;;
    help|--help|-h) usage ;;
    *)
      ui_error "Unknown account command: $sub"
      usage
      return 2
      ;;
  esac
}

main_menu() {
  if ! gauth_is_tty; then
    usage
    return 1
  fi

  local choice count account
  while :; do
    count="$(account_count)"
    ui_header "gauth $GAUTH_VERSION"
    if [ "$count" -eq 0 ]; then
      ui_dim "No accounts configured yet. Start with 'Add account'."
    else
      ui_dim "$count account(s) configured"
    fi
    if git_is_repo; then
      ui_dim "Repository: $(git_repo_summary)"
    fi

    choice="$(ui_choose "What do you want to do?" \
      "Set up this repository" \
      "Add account" \
      "View / select account" \
      "Remove account" \
      "Settings" \
      "Doctor" \
      "Help" \
      "Exit")" || break

    case "$choice" in
      "Set up this repository")
        if [ "$count" -eq 0 ]; then
          ui_warn "Add an account first."
        else
          repo_connect_flow || true
        fi
        ui_pause
        ;;
      "Add account")
        account_add || true
        ui_pause
        ;;
      "View / select account")
        if [ "$count" -eq 0 ]; then
          ui_warn "No accounts configured yet."
        else
          account_select_view || true
        fi
        ui_pause
        ;;
      "Remove account")
        if [ "$count" -eq 0 ]; then
          ui_warn "No accounts configured yet."
        else
          account_remove || true
        fi
        ui_pause
        ;;
      "Settings")
        settings_menu || true
        ;;
      "Doctor")
        doctor_run || true
        ui_pause
        ;;
      "Help")
        usage
        ui_pause
        ;;
      "Exit"|"") break ;;
    esac
  done
  printf '\n'
  return 0
}
