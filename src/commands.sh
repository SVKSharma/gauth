# shellcheck shell=bash
# Command implementations and the interactive menu.

usage() {
  cat <<EOF
gauth $GAUTH_VERSION - guided Git and GitHub profile setup

Usage:
  gauth                         Interactive menu
  gauth init [options]          Connect the current directory to GitHub
  gauth clone <url> [dir]       Clone a GitHub repository and select a profile
  gauth profile <command>       list | add | remove | show | select
  gauth profile select [NAME]   Use a profile in the current repository
  gauth profile show [NAME]     Show one profile (or pick one)
  gauth settings                Change defaults
  gauth doctor [--test] [--fix] Check the installation
  gauth version                 Print the version
  gauth help                    Show this help

init options:
  --profile NAME   Use an existing gauth profile
  --repo URL       GitHub repository URL (HTTPS or SSH)
  --yes            Apply without confirmation prompts
  --no-test        Skip the ssh -T connection test

clone options:
  --profile NAME   Clone with an existing gauth profile
  --yes            Clone without confirmation prompts
  --no-test        Skip the ssh -T connection test

Examples:
  gauth
  gauth init --repo https://github.com/owner/repo.git
  gauth init --profile work --repo git@github.com:owner/repo.git
  gauth clone https://github.com/owner/repo.git --profile work
  gauth doctor --test

Quick start:
  New project:    mkdir my-app && cd my-app && gauth
                  (choose "Set up this folder"; gauth runs git init for you)
  Existing repo:  cd repo && gauth
                  (choose "Work on this repository", then pick a profile)
  Cloned repo:    gauth clone https://github.com/owner/repo.git
                  (clones with the chosen profile and installs the guard)
  Already cloned: cd repo && gauth profile select
                  (uses the existing GitHub origin; no URL prompt)
  First profile:  gauth profile add
                  (creates the SSH key and the Git identity)

Push guard:
  gauth installs a pre-push hook in configured repositories. If the remote
  would use a different profile's SSH alias, it blocks the push and lets you
  choose the right profile.

Navigation, when prompted:
  up/down or j/k move · left/h back · right/l forward
  enter selects · esc goes back · q quits the app

gauth never commits, pushes, or changes your global git identity.
EOF
}

cmd_version() {
  printf 'gauth %s\n' "$GAUTH_VERSION"
}

repo_prompt_url() {
  local repo_url="" read_rc=0
  while :; do
    # Esc and Ctrl-C both leave this prompt (they must not re-prompt forever).
    ui_hint "Esc: cancel · Ctrl-C: cancel · :cancel"
    read_rc=0
    repo_url="$(ui_input "GitHub repository URL" "https://github.com/owner/repo.git" "")" || read_rc=$?
    case "$read_rc" in
      0) : ;;
      2|4) ui_info "Clone cancelled."; return 1 ;;
      *) return 1 ;;
    esac
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
  profile_require "$profile_name" || return 1

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
  ui_kv "GitHub repository" "$owner/$repo"
  ui_kv "Git name" "$PROFILE_GIT_NAME"
  ui_kv "Email" "$PROFILE_EMAIL"
  ui_kv "Remote" "$remote_url"
  if [ "$needs_init" -eq 1 ]; then
    ui_kv "Repository" "will be initialized on '$target_branch'"
    ui_hint "This folder is not a git repository yet; gauth will run git init."
  else
    ui_kv "Repository" "existing git repository"
    local current_origin
    current_origin="$(git_current_remote 2>/dev/null || printf 'none')"
    ui_kv "Current origin" "$current_origin"
    if [ "$current_origin" != "$remote_url" ] && [ "$current_origin" != "none" ]; then
      ui_info "Origin will be updated to use the '$profile_name' alias."
    fi
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

  local hook_rc=0
  git_install_pre_push_hook || hook_rc=$?
  case "$hook_rc" in
    0) ui_dim "Pre-push guard installed: pushes verify the selected profile." ;;
    2|3) : ;;
    *) ui_warn "Could not install the pre-push guard." ;;
  esac

  ui_success "Local repository configured."
  ui_kv "user.name" "$(git_local_config user.name)"
  ui_kv "user.email" "$(git_local_config user.email)"
  ui_kv "remote.origin.url" "$(git_current_remote)"

  if [ "$do_test" -eq 1 ]; then
    # A passphrase-protected key must be unlocked before a BatchMode test.
    if ! ssh_ensure_key_loaded "$PROFILE_KEY" "$profile_name"; then
      ui_dim "Key is not loaded in ssh-agent; the connection test may fail if it has a passphrase."
    fi
    if ui_task "Testing git@$PROFILE_ALIAS" ssh_test_connection "$PROFILE_ALIAS"; then
      ui_success "GitHub SSH authentication works."
      profile_update_verified "$profile_name" "$(gauth_now)" || true
    else
      ui_warn "SSH test did not succeed; the repository was still configured."
      printf '%s\n' "$SSH_TEST_OUTPUT" >&2
      ssh_friendly_failure
    fi
  fi

  ui_section "All set"
  ui_success "This folder is connected to GitHub through profile '$profile_name'."
  ui_kv "Branch" "$target_branch"
  ui_kv "Remote" "$remote_url"
  if [ "$needs_init" -eq 1 ] || ! git_has_commits; then
    ui_info "gauth does not commit or push. When you are ready:"
    printf '  git add .\n' >&2
    printf '  git commit -m "Initial commit"\n' >&2
    printf '  git push -u origin %s\n' "$target_branch" >&2
  else
    ui_info "This repository already has history. Next:"
    printf '  git pull\n' >&2
    printf '  git push\n' >&2
  fi
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

REPO_ORIGIN_URL=""
REPO_ORIGIN_ALIAS=""
REPO_OWNER=""
REPO_REPO=""

repo_detect_github_origin() {
  REPO_ORIGIN_URL=""
  REPO_ORIGIN_ALIAS=""
  REPO_OWNER=""
  REPO_REPO=""

  local url
  url="$(git_current_remote 2>/dev/null || true)"
  [ -n "$url" ] || return 1
  git_parse_github_url "$url" || return 1

  REPO_ORIGIN_URL="$url"
  REPO_ORIGIN_ALIAS="$GH_ALIAS"
  REPO_OWNER="$GH_OWNER"
  REPO_REPO="$GH_REPO"
  return 0
}

# Existing/cloned repository: the GitHub origin is already present, so the user
# only needs to choose the profile for this work session. No URL prompt.
repo_existing_flow() {
  local profile_name current
  current="$(git_get_gauth_profile 2>/dev/null || true)"

  ui_section "Existing GitHub repository"
  ui_kv "Origin" "$REPO_ORIGIN_URL"
  ui_kv "Repository" "$REPO_OWNER/$REPO_REPO"
  ui_kv "Current profile" "${current:-unset}"
  ui_info "Choose the profile to use for this work session."

  profile_name="$(profile_pick "Profile for this repository" 1 "$current")" || return 1
  repo_apply "$profile_name" "$REPO_ORIGIN_URL" 0 1
}

repo_flow() {
  if git_is_repo && repo_detect_github_origin; then
    repo_existing_flow
  else
    repo_connect_flow
  fi
}

# Arm the pre-push guard as soon as gauth sees a GitHub checkout without a
# selected profile. The guard blocks a push until a profile is chosen, so a
# forgotten hand-clone cannot silently push with another account. A foreign
# pre-push hook is never touched.
repo_arm_push_guard() {
  git_is_repo || return 1
  git_pre_push_hook_installed && return 0
  local rc=0
  git_install_pre_push_hook >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) ui_success "Push guard armed: pushes are blocked until a profile is selected." ;;
    2) ui_warn "A custom pre-push hook exists; gauth left it untouched." ;;
  esac
  return "$rc"
}

cmd_clone() {
  local profile_name="" dir="" url="" assume_yes=0 do_test=1

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
      --yes|-y) assume_yes=1; shift ;;
      --no-test) do_test=0; shift ;;
      --help|-h) usage; return 0 ;;
      -*)
        ui_error "Unknown clone option: $1"
        return 2
        ;;
      *)
        if [ -z "$url" ]; then
          url="$1"
        elif [ -z "$dir" ]; then
          dir="$1"
        else
          ui_error "Unexpected argument: $1"
          return 2
        fi
        shift
        ;;
    esac
  done

  git_require || return 1

  if [ -z "$url" ]; then
    if ! gauth_is_tty; then
      ui_error "Usage: gauth clone <github-url> [directory] [--profile NAME]"
      return 1
    fi
    url="$(repo_prompt_url)" || return 1
  fi
  if ! git_parse_github_url "$url"; then
    ui_error "Not a supported GitHub URL: $url"
    return 1
  fi

  local owner="$GH_OWNER" repo="$GH_REPO"
  [ -n "$dir" ] || dir="$repo"

  # Safeguard: never silently nest a clone inside an existing checkout. Show
  # the repository that was detected and offer to switch its profile instead.
  if git_is_repo; then
    if repo_detect_github_origin; then
      ui_warn "Repository detected: $REPO_OWNER/$REPO_REPO ($(pwd -P))"
      if [ "$REPO_OWNER/$REPO_REPO" = "$owner/$repo" ]; then
        ui_info "This repository is already cloned here; cloning it again is unnecessary."
      fi
      if ui_confirm "Switch the profile for this repository instead?" yes; then
        repo_existing_flow
        return $?
      fi
      ui_info "No clone was made."
      return 1
    fi
    ui_warn "You are inside a git repository that is not connected to GitHub."
    ui_info "Cloning here would create a nested repository."
    if ! ui_confirm "Clone '$owner/$repo' into ./$dir anyway?" no; then
      return 1
    fi
  fi

  # Safeguard: an existing checkout is a profile-switch case, not a re-clone.
  if [ -e "$dir" ]; then
    local existing_repo=""
    if [ -d "$dir" ]; then
      existing_repo="$( cd "$dir" 2>/dev/null && repo_detect_github_origin && \
        printf '%s/%s' "$REPO_OWNER" "$REPO_REPO" )" || existing_repo=""
    fi
    if [ -n "$existing_repo" ]; then
      ui_warn "Repository already cloned at $dir: $existing_repo"
      if ui_confirm "Switch the profile for that checkout instead?" yes; then
        ( cd "$dir" && repo_existing_flow )
        return $?
      fi
      return 1
    fi
    ui_error "Target directory already exists: $dir"
    ui_info "Choose another directory: gauth clone <url> <directory>"
    return 1
  fi

  if [ -z "$profile_name" ]; then
    if [ "$(profile_count)" -eq 0 ]; then
      profile_none_message
      ui_confirm "Add a profile now?" yes || return 1
      profile_add repo || return 1
      profile_name="$PROFILE_LAST_ADDED"
    else
      profile_name="$(profile_pick "Profile for cloning" 0)" || return 1
    fi
  fi
  profile_require "$profile_name" || return 1

  # The clone itself authenticates over SSH, so the key and alias must exist
  # before git runs.
  if [ ! -f "$PROFILE_KEY" ]; then
    ui_error "The private key for '$profile_name' is missing: $PROFILE_KEY"
    ui_info "Run 'gauth doctor' or add the profile again."
    return 1
  fi
  if ! sshconfig_has_managed "$PROFILE_ALIAS"; then
    if sshconfig_alias_exists "$PROFILE_ALIAS"; then
      ui_error "Alias '$PROFILE_ALIAS' exists outside gauth; cannot use it to clone."
      return 1
    fi
    ui_warn "SSH config block is missing; adding it for '$profile_name'."
    sshconfig_upsert "$PROFILE_ALIAS" "$PROFILE_KEY" || return 1
  fi

  local clone_url
  clone_url="$(git_remote_url "$PROFILE_ALIAS" "$owner" "$repo")"
  ui_section "Clone plan"
  ui_kv "Repository" "$owner/$repo"
  ui_kv "Profile" "$profile_name"
  ui_kv "SSH alias" "$PROFILE_ALIAS"
  ui_kv "Clone URL" "$clone_url"
  ui_kv "Destination" "$dir"
  if [ "$assume_yes" -eq 0 ]; then
    ui_confirm "Clone this repository now?" yes || {
      ui_info "Cancelled."
      return 1
    }
  fi

  if ! ssh_ensure_key_loaded "$PROFILE_KEY" "$profile_name"; then
    ui_dim "Key is not loaded in ssh-agent; the clone may prompt if it has a passphrase."
  fi

  if ! ui_task "Cloning $owner/$repo" git_clone "$clone_url" "$dir"; then
    ui_error "git clone failed."
    printf '%s\n' "$UI_TASK_OUTPUT" >&2
    ui_info "Check that the key for '$profile_name' is added to GitHub, then retry."
    return 1
  fi
  ui_success "Cloned $owner/$repo into $dir"

  local rc=0
  ( cd "$dir" && repo_apply "$profile_name" "$clone_url" 1 "$do_test" ) || rc=$?
  if [ "$rc" -ne 0 ]; then
    ui_warn "The repository was cloned, but gauth could not finish configuring it."
    ui_info "Run 'gauth profile select' inside $dir to retry."
    return "$rc"
  fi

  ui_section "Cloned and ready"
  ui_success "$owner/$repo is ready with profile '$profile_name'."
  ui_info "Next: cd $dir"
  return 0
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
    show|view)
      if [ "$#" -gt 0 ]; then
        profile_show_cmd "$1"
      else
        profile_select_view
      fi
      ;;
    select|use)
      if [ "$#" -gt 0 ]; then
        profile_select_for_repo "$1"
      else
        profile_select_for_repo
      fi
      ;;
    help|--help|-h) usage ;;
    *)
      ui_error "Unknown profile command: $sub"
      usage
      return 2
      ;;
  esac
}

# Run a main-menu action by id.
main_run_action() {
  local action="$1"
  local count
  count="$(profile_count)"
  case "$action" in
    repo)
      # With no profiles yet, the picker offers "Add new profile" inline.
      repo_flow || true
      ;;
    clone)
      cmd_clone || true
      ;;
    add)
      profile_add || true
      ;;
    view)
      if [ "$count" -eq 0 ]; then
        profile_none_message
        if ui_confirm "Add a profile now?" yes; then
          profile_add || true
        fi
      else
        profile_select_view || true
      fi
      ;;
    remove)
      if [ "$count" -eq 0 ]; then
        profile_none_message
      else
        profile_remove || true
      fi
      ;;
    settings)
      settings_menu || true
      ;;
    doctor)
      doctor_run || true
      ;;
    help)
      usage
      ;;
  esac
}

main_menu() {
  if ! gauth_is_tty; then
    usage
    return 1
  fi

  local choice count action choose_rc repo_label current
  local first_screen=1
  ui_banner
  while :; do
    count="$(profile_count)"
    if [ "$first_screen" -eq 1 ]; then
      first_screen=0
    else
      ui_header "gauth $GAUTH_VERSION"
    fi
    if [ "$count" -eq 0 ]; then
      ui_section "Welcome"
      ui_info "1. Add a profile — creates the SSH key and Git identity"
      ui_info "2. In a project, choose 'Set up this repository'"
      ui_info "3. New project? Run gauth inside the empty folder; git init is automatic"
    else
      ui_dim "  $count profile(s) configured"
    fi
    if git_is_repo; then
      ui_dim "  repository: $(git_repo_summary)"
      if repo_detect_github_origin; then
        current="$(git_get_gauth_profile 2>/dev/null || true)"
        ui_dim "  GitHub: $REPO_OWNER/$REPO_REPO"
        if [ -z "$current" ]; then
          ui_warn "  No profile selected for this repository yet."
          ui_hint "  Select one before pushing to avoid using the wrong account."
          repo_arm_push_guard || true
          repo_label="Select a profile for this repository"
        else
          ui_dim "  profile: $current"
          repo_label="Work on this repository (switch profile)"
        fi
      else
        repo_label="Connect this repository to GitHub"
      fi
    else
      ui_dim "  not a git repository — setup will run git init for you"
      repo_label="Set up this folder (git init + GitHub)"
    fi

    # Root page: there is no parent, so h/Esc show a notice instead of exiting,
    # and l/→ opens the highlighted action just like Enter.
    choice="$(ui_choose_nav 0 1 "What do you want to do?" \
      "$repo_label" \
      "Clone a GitHub repository" \
      "Add profile" \
      "View / switch profile" \
      "Remove profile" \
      "Settings" \
      "Doctor" \
      "Help" \
      "Exit")"
    choose_rc=$?
    case "$choose_rc" in
      0)
        case "$choice" in
          "$repo_label"|"Set up this repository"|"Connect this repository to GitHub"|"Work on this repository (switch profile)"|"Select a profile for this repository") action="repo" ;;
          "Clone a GitHub repository") action="clone" ;;
          "Add profile") action="add" ;;
          "View / switch profile") action="view" ;;
          "Remove profile") action="remove" ;;
          "Settings") action="settings" ;;
          "Doctor") action="doctor" ;;
          "Help") action="help" ;;
          "Exit"|"") break ;;
          *) continue ;;
        esac
        main_run_action "$action"
        ;;
      2)
        # Defensive: back at the root never quits.
        ui_hint "You are at the top level. Press Enter to select, or q to quit."
        ;;
      4)
        # q only: leave the application.
        break
        ;;
      *)
        break
        ;;
    esac
  done
  printf '\n'
  return 0
}
