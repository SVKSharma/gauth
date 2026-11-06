# shellcheck shell=bash
# Command implementations and the interactive menu.

usage() {
  cat <<EOF
gauth $GAUTH_VERSION - guided Git and GitHub profile setup

Usage:
  gauth                         Interactive menu
  gauth init [options]          Connect the current directory to GitHub
  gauth profile <command>       list | add | remove | show | select
  gauth settings                Change defaults
  gauth doctor [--test] [--fix] Check the installation
  gauth version                 Print the version
  gauth help                    Show this help

init options:
  --profile NAME   Use an existing gauth profile
  --repo URL       GitHub repository URL (HTTPS or SSH)
  --yes            Apply without confirmation prompts
  --no-test        Skip the ssh -T connection test

Examples:
  gauth
  gauth init --repo https://github.com/owner/repo.git
  gauth init --profile work --repo git@github.com:owner/repo.git
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
    if repo_url="$(ui_input "GitHub repository URL" "https://github.com/owner/repo.git" "")"; then
      :
    else
      [ "$?" -eq 2 ] && continue
      return 1
    fi
    if git_parse_github_url "$repo_url"; then
      printf '%s\n' "$repo_url"
      return 0
    fi
    ui_error "Use a GitHub URL like https://github.com/owner/repo.git"
  done
}

repo_apply() {
  local profile_name="$1"
  local repo_url="$2"
  local assume_yes="${3:-0}"
  local do_test="${4:-1}"

  git_require || return 1
  profile_require "$profile_name"

  if [ ! -f "$PROFILE_KEY" ]; then
    ui_error "The private key for '$profile_name' is missing: $PROFILE_KEY"
    ui_info "Run 'gauth doctor' or add the profile again."
    return 1
  fi

  if ! sshconfig_has_managed "$PROFILE_ALIAS"; then
    if sshconfig_alias_exists "$PROFILE_ALIAS"; then
      ui_error "Alias '$PROFILE_ALIAS' exists outside gauth; cannot add a managed block."
      return 1
    fi
    ui_warn "SSH config block is missing; adding it for '$profile_name'."
    sshconfig_upsert "$PROFILE_ALIAS" "$PROFILE_KEY" || return 1
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
  remote_url="$(git_remote_url "$PROFILE_ALIAS" "$owner" "$repo")"
  local needs_init=0
  local target_branch="$SETTING_DEFAULT_BRANCH"
  if ! git_is_repo; then
    needs_init=1
  else
    target_branch="$(git_current_branch)"
    [ -n "$target_branch" ] || target_branch="$SETTING_DEFAULT_BRANCH"
  fi

  ui_section "Repository plan"
  ui_kv "Profile" "$profile_name"
  ui_kv "Git name" "$PROFILE_GIT_NAME"
  ui_kv "Email" "$PROFILE_EMAIL"
  ui_kv "Remote" "$remote_url"
  if [ "$needs_init" -eq 1 ]; then
    ui_kv "Repository" "will be initialized on '$target_branch'"
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

  if ! git_set_local_identity "$PROFILE_GIT_NAME" "$PROFILE_EMAIL"; then
    ui_error "Could not set the local git identity."
    return 1
  fi
  if ! git_set_remote "$remote_url"; then
    ui_error "Could not set remote.origin.url."
    return 1
  fi
  git_set_gauth_profile "$profile_name" || true

  ui_success "Local repository configured."
  ui_kv "user.name" "$(git_local_config user.name)"
  ui_kv "user.email" "$(git_local_config user.email)"
  ui_kv "remote.origin.url" "$(git_current_remote)"

  if [ "$do_test" -eq 1 ]; then
    if ui_task "Testing git@$PROFILE_ALIAS" ssh_test_connection "$PROFILE_ALIAS"; then
      ui_success "GitHub SSH authentication works."
      profile_update_verified "$profile_name" "$(gauth_now)" || true
    else
      ui_warn "SSH test did not succeed; the repository was still configured."
      printf '%s\n' "$SSH_TEST_OUTPUT" >&2
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
  local profile_name="${1:-}"
  if [ -z "$profile_name" ]; then
    # Item 5: offer to create a profile from inside the repo flow.
    profile_name="$(profile_pick "Profile for this repository" 1)" || return 1
  fi
  repo_apply "$profile_name" "" 0 1
}

cmd_init() {
  local profile_name=""
  local repo_url=""
  local assume_yes=0
  local do_test=1

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --profile|--account)
        [ "$#" -ge 2 ] || {
          ui_error "$1 needs a value."
          return 2
        }
        profile_name="$2"
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

  if [ -z "$profile_name" ]; then
    if ! gauth_is_tty; then
      ui_error "Use --profile NAME in a non-interactive session."
      return 1
    fi
    profile_name="$(profile_pick "Profile for this repository" 1)" || return 1
  fi

  repo_apply "$profile_name" "$repo_url" "$assume_yes" "$do_test"
}

cmd_profile() {
  local sub="${1:-list}"
  [ "$#" -gt 0 ] && shift
  case "$sub" in
    list|ls) profile_list_cmd ;;
    add) profile_add ;;
    remove|rm|delete) profile_remove ;;
    show|view|select|use) profile_select_view ;;
    help|--help|-h) usage ;;
    *)
      ui_error "Unknown profile command: $sub"
      usage
      return 2
      ;;
  esac
}

# Run a main-menu action by id. Shared by direct selection and history navigation.
main_run_action() {
  local action="$1"
  local count
  count="$(profile_count)"
  case "$action" in
    repo)
      if [ "$count" -eq 0 ]; then
        ui_warn "Add a profile first."
      else
        repo_connect_flow || true
      fi
      ui_pause
      ;;
    add)
      profile_add || true
      ui_pause
      ;;
    view)
      if [ "$count" -eq 0 ]; then
        ui_warn "No profiles configured yet."
      else
        profile_select_view || true
      fi
      ui_pause
      ;;
    remove)
      if [ "$count" -eq 0 ]; then
        ui_warn "No profiles configured yet."
      else
        profile_remove || true
      fi
      ui_pause
      ;;
    settings)
      settings_menu || true
      ;;
    doctor)
      doctor_run || true
      ui_pause
      ;;
    help)
      usage
      ui_pause
      ;;
  esac
}

main_menu() {
  if ! gauth_is_tty; then
    usage
    return 1
  fi

  UI_HISTORY=()
  UI_HISTORY_POS=-1

  local choice count action
  while :; do
    count="$(profile_count)"
    ui_header "gauth $GAUTH_VERSION"
    if [ "$count" -eq 0 ]; then
      ui_dim "  no profiles yet — start with 'Add profile'"
    else
      ui_dim "  $count profile(s) configured"
    fi
    if git_is_repo; then
      ui_dim "  repository: $(git_repo_summary)"
    fi

    choice="$(ui_choose "What do you want to do?" \
      "Set up this repository" \
      "Add profile" \
      "View / select profile" \
      "Remove profile" \
      "Settings" \
      "Doctor" \
      "Help" \
      "Exit")"
    local choose_rc=$?
    case "$choose_rc" in
      0)
        case "$choice" in
          "Set up this repository") action="repo" ;;
          "Add profile") action="add" ;;
          "View / select profile") action="view" ;;
          "Remove profile") action="remove" ;;
          "Settings") action="settings" ;;
          "Doctor") action="doctor" ;;
          "Help") action="help" ;;
          "Exit"|"") break ;;
          *) continue ;;
        esac
        ui_history_record "$action"
        main_run_action "$action"
        ;;
      2)
        # Back at the root menu means leave the app.
        break
        ;;
      3)
        # Forward through the history stack.
        if ui_history_forward; then
          action="$(ui_history_current)"
          main_run_action "$action"
        else
          ui_warn "Nothing further to go forward to."
          ui_pause
        fi
        ;;
      *)
        break
        ;;
    esac
  done
  printf '\n'
  return 0
}
