# gauth

**gauth** is a guided command-line tool that connects a Git repository to a
GitHub account. It handles the parts that are easy to forget: SSH keys, SSH
aliases, permissions, `ssh-agent`, connection tests, local Git identity, and
the remote URL.

It is built for Linux and macOS, works with multiple GitHub accounts, and is
written in Bash with a modern [`gum`](https://github.com/charmbracelet/gum) UI.

```
gauth
```

## Why

Connecting Git to GitHub once is tedious. Doing it for a second account means
remembering aliases, key names, `~/.ssh/config` rules, and remote URL formats.
gauth walks through the setup once, records the account, and lets you reuse it
for every repository.

## Features

- Interactive menu for adding, viewing, selecting, and removing accounts
- Guided repository setup from an HTTPS or SSH GitHub URL
- ed25519 (default), RSA 4096, or ECDSA 384 keys
- Optional passphrase, handled by `ssh-keygen` directly
- Safe `~/.ssh/config` editing with backups and managed blocks
- Public key copied to the clipboard, with OSC 52 and manual fallbacks
- `ssh-agent` reuse, startup, and environment files for bash/zsh/fish
- Correct `ssh -T` test (GitHub exits `1` even on success)
- Local `user.name`, `user.email`, and `remote.origin.url` setup
- Doctor command for permissions, keys, aliases, agent state, and connectivity
- Plain ANSI fallback when `gum` is unavailable

## Requirements

- Linux or macOS
- Bash 3.2 or newer (macOS's built-in Bash works)
- Git
- OpenSSH: `ssh`, `ssh-keygen`, `ssh-add`, `ssh-agent`
- `gum` for the rich UI. The installer can install a private copy automatically.

## Install

Recommended system install:

```bash
./install.sh
```

This installs `gauth` to `/usr/local/bin/gauth` and uses `sudo` only for the
individual write operations that need it. If `gum` is missing, the installer
offers to download a pinned release, verifies its SHA-256 checksum, and places
it in `/usr/local/libexec/gauth/gum`.

User-local install, no sudo:

```bash
./install.sh --prefix "$HOME/.local"
```

Make sure `$HOME/.local/bin` is on `PATH`.

Other options:

```bash
./install.sh --bindir /custom/bin --libexecdir /custom/libexec/gauth
./install.sh --no-gum
./install.sh --gum-version 2.0.2
./install.sh --uninstall
```

If you use a non-standard `--libexecdir`, set `GAUTH_LIBEXEC` to that
directory so `gauth` can find the private `gum` binary.

Uninstalling removes the executable and the private `gum` copy. It does **not**
delete `~/.config/gauth`, SSH keys, SSH config entries, or repositories.

## Quick start

```bash
# Add your first account
gauth account add

# In a project, connect the current directory
gauth init

# Or open the interactive menu
gauth
```

`gauth init` accepts an existing account and an optional URL:

```bash
gauth init --account work --repo https://github.com/owner/repo.git
gauth init --account personal --repo git@github.com:owner/repo.git
```

The resulting remote is based on the account's alias:

```
git@github.com-work:owner/repo.git
```

## Commands

| Command | Purpose |
| --- | --- |
| `gauth` | Interactive menu |
| `gauth init [--account NAME] [--repo URL] [--yes] [--no-test]` | Configure the current repository |
| `gauth account list` | List configured accounts |
| `gauth account add` | Add an account |
| `gauth account show` | View an account |
| `gauth account remove` | Remove an account |
| `gauth settings` | Change defaults |
| `gauth doctor [--test] [--fix]` | Diagnose the installation and optionally test accounts |
| `gauth version` | Print the version |

## What gauth changes

- Creates `~/.ssh/id_<type>_<account>` and its `.pub` file if needed
- Ensures `~/.ssh` is `700`, private keys are `600`, public keys are `644`
- Adds a managed block to `~/.ssh/config`:

```sshconfig
# >>> gauth:github.com-work >>>
Host github.com-work
  HostName github.com
  User git
  IdentityFile /home/you/.ssh/id_ed25519_work
  IdentitiesOnly yes
# <<< gauth:github.com-work <<<
```

- Stores account metadata in `~/.config/gauth/accounts.tsv`
- Stores defaults in `~/.config/gauth/settings.conf`
- Writes backups under `~/.local/state/gauth/backups/`
- Writes ssh-agent environment files under `~/.local/state/gauth/`
- Sets **local** Git config only: `user.name`, `user.email`,
  `remote.origin.url`, and `gauth.account`

gauth never commits, pushes, changes your global Git identity, or rewrites
existing SSH keys without confirmation.

## The SSH config block is inserted at the top

OpenSSH uses the first value it obtains for each option. If your config has a
later `Host *` block with `IdentityFile`, a gauth block appended at the bottom
would be ignored. gauth therefore prepends its managed block.

Existing aliases that were not created by gauth are never modified. gauth will
ask you to choose another alias instead.

## ssh-agent behavior

If an agent is already running (`SSH_AUTH_SOCK` is valid), gauth reuses it. If
not, it can start one and add the key.

A started agent keeps running, but new shells do not automatically know its
socket. gauth writes:

```bash
~/.local/state/gauth/agent.env
~/.local/state/gauth/agent.fish
```

Source the right one when you need it:

```bash
# bash / zsh
source ~/.local/state/gauth/agent.env

# fish
source ~/.local/state/gauth/agent.fish
```

gauth does not edit your shell startup files.

## Clipboard

The public key is copied with:

- macOS: `pbcopy`
- Wayland: `wl-copy`
- X11: `xclip` or `xsel`
- SSH/headless: terminal OSC 52, then manual display as a fallback

The private key is never copied.

## Development

```bash
./build.sh          # concatenate src/ into dist/gauth
./tests/run.sh      # dependency-free test suite
bash -n dist/gauth  # syntax check

# optional, if installed
shellcheck src/*.sh install.sh build.sh tests/run.sh
shfmt -d -i 2 -ci src install.sh build.sh tests/run.sh
```

The project deliberately targets Bash 3.2 so the built-in `/bin/bash` on macOS
works. Avoid associative arrays, `mapfile`, `${var,,}`, `declare -n`, and
`&>>`.

Layout:

```
src/common.sh      constants, validation, paths, atomic helpers
src/ui.sh          gum wrappers and ANSI fallback
src/config.sh      settings and account registry
src/clipboard.sh   cross-platform clipboard + OSC 52
src/ssh.sh         key generation, agent, ssh -T
src/sshconfig.sh   managed SSH config blocks
src/git.sh         URL parsing and local git config
src/account.sh     account wizard and removal
src/settings.sh    settings menu
src/doctor.sh      diagnostics
src/commands.sh    init/menu commands
src/main.sh        entry point
```

## Limitations in v1

- GitHub.com only (not GitHub Enterprise)
- One SSH key per account
- No automatic GitHub API key upload; you paste the key in the browser
- No commit/push automation
- No shell completion yet
- `gum` is the only optional runtime dependency

## License

MIT. See [LICENSE](LICENSE).
