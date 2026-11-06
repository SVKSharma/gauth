# gauth

**gauth** is a guided command-line tool that connects a Git repository to a
GitHub account. It handles the parts that are easy to forget: SSH keys, SSH
aliases, permissions, `ssh-agent`, connection tests, local Git identity, and
the remote URL.

It is built for Linux and macOS, works with multiple GitHub profiles, and is
written in Bash with a modern [`gum`](https://github.com/charmbracelet/gum) UI.

```
gauth
```

## Why

Connecting Git to GitHub once is tedious. Doing it for a second profile means
remembering aliases, key names, `~/.ssh/config` rules, and remote URL formats.
gauth walks through the setup once, records the profile, and lets you reuse it
for every repository.

## Features

- Interactive menu for adding, viewing, selecting, and removing profiles
- Guided repository setup from an HTTPS or SSH GitHub URL, including URLs that
  already use a gauth alias such as `git@github.com-work:owner/repo.git`
- Works in an empty folder too: setup runs `git init` and connects the remote
- ed25519 (default), RSA 4096, or ECDSA 384 keys
- Optional passphrase, handled by `ssh-keygen` directly, with a profile-aware
  prompt when the key is unlocked later
- Duplicate-profile and existing-key safeguards with an explicit archive/use choice
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
# Add your first profile
gauth profile add

# In a project, connect the current directory
gauth init

# Or open the interactive menu
gauth
```

`gauth init` accepts an existing profile and an optional URL:

```bash
gauth init --profile work --repo https://github.com/owner/repo.git
gauth init --profile personal --repo git@github.com:owner/repo.git
```

The resulting remote is based on the profile's alias:

```
git@github.com-work:owner/repo.git
```

### Navigation

The interactive menu and the profile wizard use vim-style keys:

| Keys | Action |
| --- | --- |
| `j` / `k`, ↓ / ↑ | Move down / up |
| `h` / ← | Back (previous step or menu) |
| `l` / → | Forward (wizard step or menu history) |
| `Esc` | Back, for non-vim users |
| `g` / `G` | Jump to the first / last item |
| `Enter` | Select / confirm |
| `q` | Quit the whole app |

At the root menu, `h`, `Esc`, and the left arrow never close gauth: they either
walk back through your action history or show a hint. Only `q` (or the `Exit`
item) quits. When there is nowhere to go back or forward, the menu says so and
stays open; a repeated `l`/→ reminds you that `Enter` selects an item.

The wizard draws a commit-graph timeline and records the value chosen at each
completed step, for example `01 Profile name [work]`. Inside a wizard text
prompt, type `:back`, `:forward`, or `:cancel`; menu steps also expose
`‹ Back` and `✕ Cancel` items.

## Commands

| Command | Purpose |
| --- | --- |
| `gauth` | Interactive menu |
| `gauth init [--profile NAME] [--repo URL] [--yes] [--no-test]` | Configure the current repository |
| `gauth profile list` | List configured profiles |
| `gauth profile add` | Add a profile |
| `gauth profile show` | View a profile |
| `gauth profile remove` | Remove a profile |
| `gauth settings` | Change defaults |
| `gauth doctor [--test] [--fix]` | Diagnose the installation and optionally test profiles |
| `gauth version` | Print the version |

## What gauth changes

- Creates `~/.ssh/gauth/id_<type>_<profile>` and its `.pub` file if needed
  (the wizard only lets you choose the file name, never an arbitrary path)
- Ensures `~/.ssh` and `~/.ssh/gauth` are `700`, private keys are `600`,
  public keys are `644`
- Asks `ssh-add` for the passphrase with the profile name and key path shown,
  and never passes the passphrase through argv or the environment
- Adds a managed block to `~/.ssh/config`:

```sshconfig
# >>> gauth:github.com-work >>>
Host github.com-work
  HostName github.com
  User git
  IdentityFile /home/you/.ssh/gauth/id_ed25519_work
  IdentitiesOnly yes
# <<< gauth:github.com-work <<<
```

- Stores profile metadata in `~/.config/gauth/profiles.tsv`
- Stores defaults in `~/.config/gauth/settings.conf`
- Writes backups under `~/.local/state/gauth/backups/`
- Writes ssh-agent environment files under `~/.local/state/gauth/`
- Sets **local** Git config only: `user.name`, `user.email`,
  `remote.origin.url`, and `gauth.profile`

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
src/config.sh      settings and profile registry
src/clipboard.sh   cross-platform clipboard + OSC 52
src/ssh.sh         key generation, agent, ssh -T
src/sshconfig.sh   managed SSH config blocks
src/git.sh         URL parsing and local git config
src/profile.sh     profile wizard and removal
src/settings.sh    settings menu
src/doctor.sh      diagnostics
src/commands.sh    init/menu commands
src/main.sh        entry point
```

## Limitations in v1

- GitHub.com only (not GitHub Enterprise)
- One SSH key per profile
- No automatic GitHub API key upload; you paste the key in the browser
- No commit/push automation
- No shell completion yet
- `gum` is the only optional runtime dependency

## License

MIT. See [LICENSE](LICENSE).
