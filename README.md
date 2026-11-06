<div align="center">

<img src="assets/gauth banner.png" alt="gauth banner" style="width:100%; max-width:900px; margin-bottom:1rem; border-radius: 8px;">

<h1 style="font-size: 3rem; font-weight: 800; display: inline-flex; align-items: center; gap: 0.5rem;">
  <img src="assets/gauth logo.png" width="48" height="48" alt="gauth logo" style="vertical-align: middle; border-radius: 6px;" /> gauth
</h1>

<h3 style="font-size: 1.2rem; font-weight: 700; color: #7aa2f7;">Your guided Git + GitHub connection</h3>

<h2 style="font-size: 1.8rem; font-weight: 800;">Don't use git init, use gauth instead, your go to git init to initialize connect with git Host( github, gitlab etc. ) specially github.</h2>

<p style="font-size: 1.1rem; color: #c0caf5;">
  gauth is a Bash CLI that connects Git repositories to GitHub accounts. It handles SSH keys, <code>~/.ssh/config</code> aliases, permissions, <code>ssh-agent</code>, <code>ssh -T</code>, local Git identity, and <code>remote.origin.url</code>. Linux + macOS. User-facing docs: <code>README.md</code>.
</p>

[![GitHub](https://img.shields.io/badge/GitHub-View%20on%20GitHub-181717?style=for-the-badge&logo=github)](https://github.com/SVKSharma/gauth)
[![Version](https://img.shields.io/badge/Version-0.2.0-7aa2f7?style=for-the-badge)](https://github.com/SVKSharmi)
[![Bash](https://img.shields.io/badge/Bash-3.2%2B-4e73df?style=for-the-badge)](https://www.gnu.org/software/bash/)

</div>

---

## 🔗 Project Links

| Resource | Link |
| --- | --- |
| 📦 **Source code** | [github.com/SVKSharma/gauth](https://github.com/SVKSharma/gauth) |
| 🛠️ **Build & test** | `./build.sh && bash -n dist/gauth && ./tests/run.sh` |
| 📄 **License** | MIT. See [LICENSE](LICENSE). |

---

## 🎯 Interactive mode

Run `gauth` to open the interactive menu. This is the primary way to use the tool — you'll be presented with a vim‑style menu where you can navigate with **j/k** or **↑/↓**, move back with **h** or **←**, go forward with **l** or **→**, press **Enter** to select, and **q** to quit.

### Root menu

```bash
gauth
```

You'll see:

- **Set up this repository** — connect the current git repo to GitHub (runs `git init` if needed)
- **Set up this folder (git init + GitHub)** — initialize a new repo and connect to GitHub
- **Add profile** — create a new SSH key + Git identity (wizard‑driven)
- **View / select profile** — list and reuse saved profiles
- **Remove profile** — archive or reuse an existing key
- **Settings** — change defaults (key type, alias prefix, branch)
- **Doctor** — check the installation and optionally test profiles
- **Help** — show this help
- **Exit** — quit the app

### Navigation tips

- **j / k** or **↑ / ↓** — move up/down
- **h** or **←** — go back one step/page
- **l** or **→** — go forward (opens the highlighted item on menu pages, or moves to the next wizard step)
- **Esc** — go back (for non‑vim users)
- **Enter** — select / confirm
- **g** / **G** — jump to first / last item
- **q** — quit the whole app

At the root menu, **h**, **Esc**, and the left arrow never close gauth: they walk back through your action history or show a hint. Only **q** (or the **Exit** item) quits. When there is nowhere to go back or forward, the menu says so and stays open; a repeated **l**/→ reminds you that **Enter** selects an item.

The profile wizard draws a commit‑graph timeline and records the value chosen at each completed step, for example `01 Profile name [demo]`. Inside a wizard text prompt, type `:back`, `:forward`, or `:cancel`; menu steps also include `‹ Back` and `✕ Cancel` items.

---

## 🚀 Quick start

### Adding your first profile

```bash
gauth profile add
```

Follow the wizard: profile name, SSH alias, git name, email, key type, key file name, passphrase. The SSH key is saved under `~/.ssh/gauth/id_<type>_<profile>`.

### In a project, connect to GitHub

```bash
gauth init
```

Or from the interactive menu:

```bash
gauth
```

Choose **Set up this repository** (or **Set up this folder** if the folder has no git repo yet). gauth will:

1. Run `git init` if needed
2. Set local Git config (`user.name`, `user.email`, `remote.origin.url`)
3. Configure the SSH remote using your profile's alias (e.g. `git@github.com-work:owner/repo.git`)
4. Start or reuse `ssh-agent` and unlock the key
5. Test the connection with `ssh -T git@alias`
6. Show an **All set** summary with next steps

### From the root menu

```bash
gauth
```

Select from the interactive menu (see above).

---

## 📥 Install

### Recommended system install (uses `sudo` only for individual write operations)

```bash
./install.sh
```

This installs `gauth` to `/usr/local/bin/gauth` and uses `sudo` only for the individual write operations that need it. If `gum` is missing, the installer offers to download a pinned release, verifies its SHA-256 checksum, and places it in `/usr/local/libexec/gauth/gum`.

### User-local install, no sudo

```bash
./install.sh --prefix "$HOME/.local"
```

Make sure `$HOME/.local/bin` is on `PATH`.

### Other options

```bash
./install.sh --bindir /custom/bin --libexecdir /custom/libexec/gauth
./install.sh --no-gum
./install.sh --gum-version 2.0.2
./install.sh --uninstall
```

If you use a non-standard `--libexecdir`, set `GAUTH_LIBEXEC` to that directory so `gauth` can find the private `gum` binary.

Uninstalling removes the executable and the private `gum` copy. It does **not** delete `~/.config/gauth`, SSH keys, SSH config entries, or repositories.

---

## � quick start (condensed)

```bash
# 1. Add your first profile
gauth profile add

# 2. In a project, connect the current directory
gauth init

# 3. Or open the interactive menu
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

---

## ⚙️ Navigation (vim‑style)

The interactive menu and the profile wizard use vim‑style keys:

| Keys | Action |
| --- | --- |
| `j` / `k`, ↓ / ↑ | Move down / up |
| `h` / ← | Back (previous step or menu) |
| `l` / → | Forward (wizard step or menu history) |
| `Esc` | Back, for non‑vim users |
| `g` / `G` | Jump to the first / last item |
| `Enter` | Select / confirm |
| `q` | Quit the whole app |

At the root menu, `h`, `Esc`, and the left arrow never close gauth: they either walk back through your action history or show a hint. Only `q` (or the `Exit` item) quits. When there is nowhere to go back or forward, the menu says so and stays open; a repeated `l`/→ reminds you that `Enter` selects an item.

The wizard draws a commit‑graph timeline and records the value chosen at each completed step, for example `01 Profile name [work]`. Inside a wizard text prompt, type `:back`, `:forward`, or `:cancel`; menu steps also include `‹ Back` and `✕ Cancel` items.

---

## 📜 Commands

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

---

## 🔐 What gauth changes

- Creates `~/.ssh/gauth/id_<type>_<profile>` and its `.pub` file if needed (the wizard only lets you choose the file name, never an arbitrary path)
- Ensures `~/.ssh` and `~/.ssh/gauth` are `700`, private keys are `600`, public keys are `644`
- Asks `ssh-add` for the passphrase with the profile name and key path shown, and never passes the passphrase through argv or the environment
- Adds a managed block to `~/.ssh/config`:

```ssh
# >>> gauth:github.com-work >>>
Host github.com-work
  HostName github.com
  User git
  IdentityFile /home/you/.ssh/gauth/id_ed25519_work
  IdentitiesOnly yes
# <<< gauth:github.com-work <<<
```

- Stores profile metadata in `~/.config/gauth/profiles.tsv` (8 tab-separated fields: name, alias, git_name, email, key_path, key_type, created, last_verified)
- Stores defaults in `~/.config/gauth/settings.conf`
- Writes backups under `~/.local/state/gauth/backups/`
- Writes ssh-agent environment files under `~/.local/state/gauth/` (`agent.env`, `agent.fish`)
- Sets **local** Git config only: `user.name`, `user.email`, `remote.origin.url`, and `gauth.profile`

> gauth never commits, pushes, changes your global Git identity, or rewrites existing SSH keys without confirmation.

The SSH config block is inserted at the top. OpenSSH uses the first value it obtains for each option. If your config has a later `Host *` block with `IdentityFile`, a gauth block appended at the bottom would be ignored. gauth therefore prepends its managed block.

Existing aliases that were not created by gauth are never modified. gauth will ask you to choose another alias instead.

---

## 🤖 ssh-agent behavior

If an agent is already running (`SSH_AUTH_SOCK` is valid), gauth reuses it. If not, it can start one and add the key.

A started agent keeps running, but new shells do not automatically know its socket. gauth writes:

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

---

## 📋 Clipboard

The public key is copied with:

- macOS: `pbcopy`
- Wayland: `wl-copy`
- X11: `xclip` or `xsel`
- SSH/headless: terminal OSC 52, then manual display as a fallback

The private key is never copied.

---

## 🛠️ Development

```bash
./build.sh          # concatenate src/ into dist/gauth
./tests/run.sh      # dependency-free test suite
bash -n dist/gauth  # syntax check

# optional, if installed
shellcheck src/*.sh install.sh build.sh tests/run.sh
shfmt -d -i 2 -ci src install.sh build.sh tests/run.sh
```

The project deliberately targets Bash 3.2 so the built‑in `/bin/bash` on macOS works. Avoid associative arrays, `mapfile`, `${var,,}`, `declare -n`, and `&>>`.

### Layout

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

---

## ⚠️ Limitations in v1

- GitHub.com only (not GitHub Enterprise)
- One SSH key per profile
- No automatic GitHub API key upload; you paste the key in the browser
- No commit/push automation
- No shell completion yet
- `gum` is the only optional runtime dependency (ANSI fallback works without it)

---

## 📄 License

MIT. See [LICENSE](LICENSE).

---

<div align="center">

Built with ❤️ by [the Bash CLI community](https://github.com/SVKSharma)

</div>