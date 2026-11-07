# shellcheck shell=bash
# Repository pre-push guard and hook installation.
#
# The hook is installed in each repository gauth configures. It runs even when
# gauth is not already running, and blocks a push when the remote would use a
# different SSH alias/profile than the one selected for the repository.

GAUTH_HOOK_MARKER_BEGIN="# >>> gauth pre-push hook >>>"
GAUTH_HOOK_MARKER_END="# <<< gauth pre-push hook <<<"

git_hooks_dir() {
  git_is_repo || return 1
  local hooks gitdir
  hooks="$(git rev-parse --git-path hooks 2>/dev/null || true)"
  if [ -z "$hooks" ]; then
    gitdir="$(git rev-parse --git-dir 2>/dev/null || true)"
    [ -n "$gitdir" ] || return 1
    hooks="$gitdir/hooks"
  fi
  case "$hooks" in
    /*) ;;
    *) hooks="$(pwd -P)/$hooks" ;;
  esac
  printf '%s\n' "$hooks"
}

git_pre_push_hook_path() {
  local hooks
  hooks="$(git_hooks_dir)" || return 1
  printf '%s/pre-push\n' "$hooks"
}

git_pre_push_hook_installed() {
  local hooks="${1:-}"
  local hook
  if [ -n "$hooks" ]; then
    hook="$hooks/pre-push"
  else
    hook="$(git_pre_push_hook_path)" || return 1
  fi
  [ -f "$hook" ] || return 1
  grep -Fqx "$GAUTH_HOOK_MARKER_BEGIN" "$hook" 2>/dev/null
}

git_install_pre_push_hook() {
  local hooks="${1:-}"
  if [ -z "$hooks" ]; then
    hooks="$(git_hooks_dir)" || return 3
  fi

  local hook="$hooks/pre-push"
  if [ -e "$hook" ] && ! grep -Fqx "$GAUTH_HOOK_MARKER_BEGIN" "$hook" 2>/dev/null; then
    ui_warn "A pre-push hook already exists and is not managed by gauth: $hook"
    ui_hint "gauth left it untouched; install the guard manually if you want it."
    return 2
  fi

  local self tmp
  self="$(gauth_self_bin)" || return 1
  mkdir -p "$hooks" || return 1
  tmp="$hook.gauth.$$"
  {
    printf '#!/usr/bin/env bash\n'
    printf '%s\n' "$GAUTH_HOOK_MARKER_BEGIN"
    printf '# Managed by gauth. This guard checks the repository profile before push.\n'
    printf 'GAUTH_HOOK_BIN=%s\n' "$(gauth_shell_squote "$self")"
    cat <<'HOOK'
set -u

# Git passes the ref list on stdin. Drain it; prompts use /dev/tty.
cat >/dev/null 2>&1 || true

if [ -n "${GAUTH_BIN:-}" ] && [ -x "$GAUTH_BIN" ]; then
  bin="$GAUTH_BIN"
elif [ -x "${GAUTH_HOOK_BIN:-}" ]; then
  bin="$GAUTH_HOOK_BIN"
elif command -v gauth >/dev/null 2>&1; then
  bin="$(command -v gauth)"
else
  printf 'gauth: pre-push guard cannot find the gauth executable; allowing push.\n' >&2
  printf 'gauth: remove this hook or reinstall gauth.\n' >&2
  exit 0
fi
exec "$bin" hook pre-push "$@"
HOOK
    printf '%s\n' "$GAUTH_HOOK_MARKER_END"
  } >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  chmod 755 "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv "$tmp" "$hook" || {
    rm -f "$tmp"
    return 1
  }
  gauth_log "pre-push hook installed: $hook"
  return 0
}

hook_can_prompt() {
  [ "${GAUTH_HOOK_NO_PROMPT:-0}" != "1" ] || return 1
  [ -t 2 ] || return 1
  [ -r /dev/tty ] || return 1
  return 0
}

hook_pick_profile() {
  local header="$1"
  local preferred="${2:-}"
  local -a names=()
  local name
  while IFS= read -r name; do
    [ -n "$name" ] && names+=("$name")
  done < <(profile_list_names)
  [ "${#names[@]}" -gt 0 ] || return 1

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

  local -a options=()
  for name in "${names[@]}"; do
    options+=("$name")
  done
  options+=("Cancel push")

  local choice pick_rc=0
  choice="$(ui_menu_raw "$header" "${options[@]}")" || pick_rc=$?
  [ "$pick_rc" -eq 0 ] || return 1
  [ "$choice" = "Cancel push" ] && return 1
  printf '%s\n' "$choice"
}

hook_identity_warning() {
  local selected="$1"
  local email
  email="$(git_local_config user.email 2>/dev/null || true)"
  [ -n "$email" ] || return 0
  profile_load "$selected" || return 0
  if [ "$email" != "$PROFILE_EMAIL" ]; then
    ui_warn "Local user.email '$email' differs from profile '$selected' (${PROFILE_EMAIL})."
    ui_info "New commits should use the selected profile's identity."
  fi
}

hook_pre_push() {
  local remote_name="${1:-origin}"
  local remote_url="${2:-}"
  local owner repo remote_alias selected expected selected_alias chosen new_url

  git_require >/dev/null 2>&1 || return 0
  git_is_repo || return 0
  [ -n "$remote_url" ] || remote_url="$(git_remote_get_url "$remote_name" 2>/dev/null || true)"
  [ -n "$remote_url" ] || return 0
  git_parse_github_url "$remote_url" || return 0

  owner="$GH_OWNER"
  repo="$GH_REPO"
  remote_alias="$GH_ALIAS"

  if [ "$(profile_count)" -eq 0 ]; then
    ui_error "Push blocked: no gauth profiles are configured."
    ui_info "Run 'gauth profile add' and then 'gauth profile select'."
    return 1
  fi

  selected="$(git_get_gauth_profile 2>/dev/null || true)"
  expected=""
  if [ -n "$remote_alias" ]; then
    expected="$(profile_name_for_alias "$remote_alias" 2>/dev/null || true)"
  fi

  # A remote that already uses a profile alias identifies the profile even when
  # gauth.profile was never written (for example, a repo cloned by hand).
  if [ -z "$selected" ] && [ -n "$expected" ]; then
    selected="$expected"
  fi

  selected_alias=""
  if [ -n "$selected" ]; then
    if ! profile_load "$selected"; then
      ui_error "Push blocked: repository profile '$selected' no longer exists."
      ui_info "Run 'gauth profile select' in this repository."
      return 1
    fi
    selected_alias="$PROFILE_ALIAS"
    if [ ! -f "$PROFILE_KEY" ]; then
      ui_error "Push blocked: the key for profile '$selected' is missing: $PROFILE_KEY"
      ui_info "Run 'gauth doctor' or add the profile again."
      return 1
    fi
    if ! sshconfig_has_managed "$selected_alias"; then
      ui_error "Push blocked: no gauth SSH config block for '$selected_alias'."
      ui_info "Run 'gauth doctor --fix' or select the profile again."
      return 1
    fi
  fi

  if [ -n "$selected_alias" ] && [ -n "$remote_alias" ] && [ "$selected_alias" = "$remote_alias" ]; then
    git_set_gauth_profile "$selected" >/dev/null 2>&1 || true
    hook_identity_warning "$selected"
    return 0
  fi

  chosen=""
  if hook_can_prompt; then
    ui_section "Push profile check"
    ui_kv "Remote" "$remote_name ($remote_url)"
    ui_kv "Repository" "$owner/$repo"
    ui_kv "Selected profile" "${selected:-unset}"
    [ -n "$expected" ] && ui_kv "Remote alias profile" "$expected"
    ui_warn "This push would not use the selected profile's SSH alias."
    chosen="$(hook_pick_profile "Push with which profile?" "$selected")" || chosen=""
  fi

  if [ -z "$chosen" ]; then
    ui_error "Push blocked: the remote is not using the selected profile's SSH alias."
    ui_info "Run 'gauth profile select' in this repository, then push again."
    ui_dim "Remote: $remote_url"
    return 1
  fi

  profile_load "$chosen" || {
    ui_error "Push blocked: profile '$chosen' could not be loaded."
    return 1
  }

  if [ "$PROFILE_ALIAS" = "$remote_alias" ]; then
    git_set_gauth_profile "$chosen" >/dev/null 2>&1 || true
    git_set_local_identity "$PROFILE_GIT_NAME" "$PROFILE_EMAIL" >/dev/null 2>&1 || true
    hook_identity_warning "$chosen"
    ui_success "Push allowed with profile '$chosen'."
    return 0
  fi

  new_url="$(git_remote_url "$PROFILE_ALIAS" "$owner" "$repo")"
  if git_remote_set_url "$remote_name" "$new_url"; then
    git_set_gauth_profile "$chosen" >/dev/null 2>&1 || true
    git_set_local_identity "$PROFILE_GIT_NAME" "$PROFILE_EMAIL" >/dev/null 2>&1 || true
    ui_success "Remote updated to profile '$chosen'."
    ui_info "Push blocked once so the new SSH alias is used."
    ui_info "Run 'git push' again to push with '$chosen'."
    return 1
  fi

  ui_error "Push blocked: could not update the remote to profile '$chosen'."
  return 1
}

cmd_hook() {
  local sub="${1:-}"
  [ "$#" -gt 0 ] && shift
  case "$sub" in
    pre-push) hook_pre_push "$@" ;;
    *)
      ui_error "Unknown hook: $sub"
      return 2
      ;;
  esac
}
