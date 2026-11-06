# shellcheck shell=bash
# Git and GitHub repository helpers.

GH_OWNER=""
GH_REPO=""

git_require() {
  if ! gauth_command_exists git; then
    ui_error "git is not installed."
    return 1
  fi
  return 0
}

git_is_repo() {
  git_require >/dev/null 2>&1 || return 1
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

git_current_remote() {
  git config --local --get remote.origin.url 2>/dev/null
}

git_has_origin() {
  git config --local --get remote.origin.url >/dev/null 2>&1
}

git_current_branch() {
  git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null
}

git_has_commits() {
  git rev-parse --verify HEAD >/dev/null 2>&1
}

git_local_config() {
  git config --local --get "$1" 2>/dev/null
}

git_parse_github_url() {
  local url
  url="$(gauth_trim "${1:-}")"
  GH_OWNER=""
  GH_REPO=""

  [ -n "$url" ] || return 1
  case "$url" in
    *' '*) return 1 ;;
  esac

  url="${url%%\?*}"
  url="${url%%#*}"

  local rest=""
  case "$url" in
    https://github.com/*) rest="${url#https://github.com/}" ;;
    http://github.com/*) rest="${url#http://github.com/}" ;;
    git://github.com/*) rest="${url#git://github.com/}" ;;
    ssh://git@github.com/*) rest="${url#ssh://git@github.com/}" ;;
    ssh://github.com/*) rest="${url#ssh://github.com/}" ;;
    git@github.com:*) rest="${url#git@github.com:}" ;;
    www.github.com/*) rest="${url#www.github.com/}" ;;
    github.com/*) rest="${url#github.com/}" ;;
    *)
      # Allow the short "owner/repo" form.
      case "$url" in
        */*/*|*:*) return 1 ;;
        */*) rest="$url" ;;
        *) return 1 ;;
      esac
      ;;
  esac

  while [ "${rest%/}" != "$rest" ]; do
    rest="${rest%/}"
  done
  case "$rest" in
    *.git) rest="${rest%.git}" ;;
  esac
  while [ "${rest%/}" != "$rest" ]; do
    rest="${rest%/}"
  done

  local owner repo extra
  IFS='/' read -r owner repo extra <<<"$rest"
  [ -z "$extra" ] || return 1
  validate_repo_part "$owner" || return 1
  validate_repo_part "$repo" || return 1

  GH_OWNER="$owner"
  GH_REPO="$repo"
  return 0
}

git_remote_url() {
  local alias="$1"
  local owner="$2"
  local repo="$3"
  printf 'git@%s:%s/%s.git\n' "$alias" "$owner" "$repo"
}

git_init_repo() {
  local branch="${1:-$SETTING_DEFAULT_BRANCH}"
  validate_branch_name "$branch" || return 1

  if git_is_repo; then
    return 0
  fi

  if git init -b "$branch" >/dev/null 2>&1; then
    gauth_log "git repository initialized with branch: $branch"
    return 0
  fi

  git init >/dev/null 2>&1 || return 1
  if ! git_has_commits; then
    git symbolic-ref HEAD "refs/heads/$branch" >/dev/null 2>&1 || return 1
  fi
  gauth_log "git repository initialized"
  return 0
}

git_set_local_identity() {
  local name="$1"
  local email="$2"
  validate_email "$email" || return 1
  [ -n "$name" ] || return 1
  git config --local user.name "$name" || return 1
  git config --local user.email "$email" || return 1
  return 0
}

git_set_remote() {
  local url="$1"
  [ -n "$url" ] || return 1
  if git_has_origin; then
    git config --local remote.origin.url "$url" || return 1
  else
    git remote add origin "$url" || return 1
  fi
  return 0
}

git_set_gauth_profile() {
  local name="$1"
  git config --local gauth.profile "$name"
}

git_get_gauth_profile() {
  git config --local --get gauth.profile 2>/dev/null
}

git_repo_summary() {
  if ! git_is_repo; then
    printf 'not a git repository'
    return 0
  fi
  local branch remote profile
  branch="$(git_current_branch)"
  remote="$(git_current_remote)"
  profile="$(git_get_gauth_profile)"
  printf 'branch=%s remote=%s profile=%s' \
    "${branch:-?}" "${remote:-none}" "${profile:-unset}"
}
