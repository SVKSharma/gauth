# shellcheck shell=bash
# Entry point and command dispatch.

main() {
  case "${1:-}" in
    help|--help|-h)
      usage
      return 0
      ;;
    version|--version|-V)
      cmd_version
      return 0
      ;;
  esac

  [ -n "${HOME:-}" ] || {
    printf 'gauth: HOME is not set\n' >&2
    return 1
  }

  gauth_init_paths
  config_init || return 1
  settings_init || return 1
  settings_load
  profiles_init || return 1

  local command="${1:-menu}"
  [ "$#" -gt 0 ] && shift

  case "$command" in
    menu) main_menu ;;
    init|connect) cmd_init "$@" ;;
    profile|profiles) cmd_profile "$@" ;;
    account|accounts) cmd_profile "$@" ;;  # v0.1 name
    settings) settings_menu ;;
    doctor) doctor_run "$@" ;;
    *)
      ui_error "Unknown command: $command"
      usage
      return 2
      ;;
  esac
}

if [ "${GAUTH_SOURCE_ONLY:-0}" != "1" ] && [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
