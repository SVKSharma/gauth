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
[![Version](https://img.shields.io/badge/Version-0.1.1-7aa2f7?style=for-the-badge)](https://github.com/SVKSharma/gauth)
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

## ✨ What's new in 0.1.1

- **Color banner** — the interactive menu opens with a pixel-block cat/terminal mark and a multi-color **GAUTH** wordmark.
- **Protected profile removal** — `gauth profile remove` and the **Remove profile** menu item now ask for your sudo password before changing anything. sudo is used only to verify your identity; gauth still edits files as you.
- **Protected complete uninstall** — the new [`uninstall.sh`](uninstall.sh) authenticates with sudo before removing anything, then removes the binary, private `gum`, gauth config/state/data, gauth-created keys, and only gauth-managed SSH config blocks.
- **Semantic color messages** — success is bold green, information and navigation are blue, warnings are amber, and errors are red. Each level also has its own glyph, so the meaning is clear even without color.
- **Repo-aware profile selection** — existing and cloned GitHub repositories reuse their current origin; you only pick the profile for the work session. No URL re-entry.
- **Clone with a profile** — `gauth clone <url>` clones through the chosen profile's SSH alias, then sets the local identity, remote, and guard in one step.
- **Unconfigured-repo safeguard** — opening gauth in a hand-cloned GitHub repository warns that no profile is selected and arms the pre-push guard. Cloning from inside a checkout, or into an existing one, offers a profile switch instead.
- **Pre-push profile guard** — gauth installs a `pre-push` hook in configured repositories. If a push would use a different profile's SSH alias, it blocks the push and offers the right profile, even when gauth is not already running.

---

## 🎯 Interactive mode

Run `gauth` to open the interactive menu. This is the primary way to use the tool — you'll be presented with a vim‑style menu where you can navigate with **j/k** or **↑/↓**, move back with **h** or **←**, go forward with **l** or **→**, press **Enter** to select, and **q** to quit.

### Root menu

```bash
gauth
```

You'll see:

- **Work on this repository (switch profile)** — an existing GitHub repo: choose the profile for this work session, reusing the current origin
- **Connect this repository to GitHub** — a git repo without a GitHub origin: choose a profile and provide the GitHub URL
- **Set up this folder (git init + GitHub)** — initialize a new repo and connect to GitHub
- **Clone a GitHub repository** — clone with a profile, then configure the checkout automatically
- **Add profile** — create a new SSH key + Git identity (wizard‑driven)
- **View / switch profile** — view a profile and make it the current profile for the repository you are in
- **Remove profile** — authenticate with sudo, then archive or reuse an existing key
- **Settings** — change defaults (key type, alias prefix, branch)
- **Doctor** — check the installation, the pre-push guard, and optionally test profiles
- **Help** — show this help
- **Exit** — quit the app

The first item changes with the current directory: it says **Set up this folder** outside a repository, **Work on this repository** when a GitHub origin exists, and **Connect this repository to GitHub** when a repository has no GitHub origin yet. If no profiles exist, **View / switch profile** explains that no accounts are configured and offers to add one.

### Navigation tips

- **j / k** or **↑ / ↓** — move up/down
- **h** or **←** — go back one step/page
- **l** or **→** — go forward (opens the highlighted item on menu pages, or moves to the next wizard step)
- **Esc** — go back (for non‑vim users), including inside wizard text prompts
- **Ctrl‑C** — cancel and return to the menu
- **Enter** — select / confirm
- **g** / **G** — jump to first / last item
- **q** — quit the whole app

At the root menu, **h**, **Esc**, and the left arrow never close gauth: they walk back through your action history or show a hint. Only **q** (or the **Exit** item) quits. When there is nowhere to go back or forward, the menu says so and stays open; a repeated **l**/→ reminds you that **Enter** selects an item.

The profile wizard draws a commit‑graph timeline and records the value chosen at each completed step, for example `01 Profile name [demo]`. Inside a wizard text prompt, press `Esc` to go back or `Ctrl‑C` to cancel without pressing `Enter`. You can also type `:back`, `:forward`, or `:cancel`; menu steps include `‹ Back` and `✕ Cancel` items.

---

## 🚀 Quick start

### Adding your first profile

```bash
gauth profile add
```

Follow the wizard: profile name, SSH alias, git name, email, key type, key file name, passphrase. The SSH key is saved under `~/.ssh/gauth/id_<type>_<profile>`.

### In a project, connect to GitHub

There are three common situations:

**New local folder** — no git repository yet:

```bash
mkdir my-app && cd my-app
gauth
```

Choose **Set up this folder (git init + GitHub)**. gauth runs `git init`, asks for the new GitHub repository URL, and connects it.

**Active GitHub repository** — the directory is already a repository with a GitHub origin:

```bash
cd existing-repo
gauth
```

Choose **Work on this repository (switch profile)**. The existing origin is detected and reused; you only choose which profile to use for this work session, then `git pull` and `git push` as usual.

**Cloned repository** — let gauth clone it with the right profile from the start:

```bash
gauth clone https://github.com/owner/repo.git
```

gauth picks (or asks for) a profile, clones through that profile's SSH alias, sets the local identity, and installs the pre-push guard. Pass `--profile work` to choose directly.

If you already cloned by hand, `cd` into the repository and run:

```bash
gauth profile select
```

gauth reads the GitHub origin, lets you pick a profile, rewrites the remote to that profile's SSH alias, and installs the pre-push guard. No URL prompt. Simply opening `gauth` in that repository warns when no profile is selected and arms the guard.

`gauth init` also works for the first two flows. It accepts an existing profile and an optional URL:

```bash
gauth init --profile work --repo https://github.com/owner/repo.git
gauth init --profile personal --repo git@github.com:owner/repo.git
```

In every flow, gauth will:

1. Run `git init` if needed
2. Set local Git config (`user.name`, `user.email`, `remote.origin.url`)
3. Configure the SSH remote using your profile's alias (e.g. `git@github.com-work:owner/repo.git`)
4. Install the repository's pre-push profile guard
5. Start or reuse `ssh-agent` and unlock the key
6. Test the connection with `ssh -T git@alias`
7. Show an **All set** summary with next steps

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
./install.sh --uninstall   # delegates to ./uninstall.sh
```

If you use a non-standard `--libexecdir`, set `GAUTH_LIBEXEC` to that directory so `gauth` can find the private `gum` binary.

A successful install ends with a green ✔ message showing the installed path.

---

## 🗑️ Uninstall completely

```bash
./uninstall.sh
```

The uninstaller asks for confirmation, then authenticates with sudo before removing anything:

- the installed `gauth` binary and gauth's private `gum` copy
- `~/.config/gauth`, `~/.local/state/gauth`, and `~/.local/share/gauth`
- keys created by gauth under `~/.ssh/gauth`
- only the `# >>> gauth:... >>>` blocks in `~/.ssh/config`; all other SSH entries are preserved

The sudo check is an identity gate. It is required even with `--yes`; if sudo already has a valid timestamp or is passwordless, the check succeeds without prompting. Your personal files are still removed as your normal user, and sudo is used only for files in a system directory. If authentication is cancelled or fails, nothing is removed.

It does **not** delete your repositories, global Git config, SSH keys that gauth did not create, or the source checkout you ran the script from.

Options:

```bash
./uninstall.sh --prefix "$HOME/.local"   # user-local install
./uninstall.sh --yes                     # skip confirmation; sudo auth still required
./uninstall.sh --purge-keys              # also remove legacy profile keys outside ~/.ssh/gauth
```

`./install.sh --uninstall` is kept as a shortcut and delegates to `./uninstall.sh`.

---

## ⚡ quick start (condensed)

```bash
# 1. Add your first profile
gauth profile add

# 2. New folder, or an existing/cloned repository
gauth                      # menu adapts to the current directory
gauth profile select       # clone: reuse the origin and pick a profile

# 3. Or open the interactive menu
gauth
```

`gauth init` accepts an existing profile and an optional URL:

```bash
gauth init --profile work --repo https://github.com/owner/repo.git
gauth init --profile personal --repo git@github.com:owner/repo.git
```

When the repository already has a GitHub origin, omit `--repo`; gauth reuses it:

```bash
gauth init --profile work
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
| `Esc` | Back, for non‑vim users (also inside wizard text prompts) |
| `Ctrl‑C` | Cancel and return to the menu (works in the wizard and the menus) |
| `g` / `G` | Jump to the first / last item |
| `Enter` | Select / confirm |
| `q` | Quit the whole app |

At the root menu, `h`, `Esc`, and the left arrow never close gauth: they either walk back through your action history or show a hint. Only `q` (or the `Exit` item) quits. When there is nowhere to go back or forward, the menu says so and stays open; a repeated `l`/→ reminds you that `Enter` selects an item.

The wizard draws a commit‑graph timeline and records the value chosen at each completed step, for example `01 Profile name [work]`. Inside a wizard text prompt, press `Esc` to go back or `Ctrl‑C` to cancel immediately — no `Enter` needed. You can also type `:back`, `:forward`, or `:cancel`; menu steps include `‹ Back` and `✕ Cancel` items. The terminal is restored on every exit path.

---

## 📜 Commands

| Command | Purpose |
| --- | --- |
| `gauth` | Interactive menu |
| `gauth init [--profile NAME] [--repo URL] [--yes] [--no-test]` | Configure the current repository; reuses an existing GitHub origin |
| `gauth clone <url> [dir] [--profile NAME] [--yes] [--no-test]` | Clone a GitHub repository with a profile and install the guard |
| `gauth profile list` | List configured profiles |
| `gauth profile add` | Add a profile |
| `gauth profile show [NAME]` | View a profile, or pick one to view |
| `gauth profile select [NAME]` | Make a profile current for the repository you are in |
| `gauth profile remove` | Remove a profile (asks for sudo authentication) |
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
- Installs a managed `.git/hooks/pre-push` guard that calls `gauth hook pre-push`

> gauth never commits, pushes, changes your global Git identity, or rewrites existing SSH keys without confirmation.

The SSH config block is inserted at the top. OpenSSH uses the first value it obtains for each option. If your config has a later `Host *` block with `IdentityFile`, a gauth block appended at the bottom would be ignored. gauth therefore prepends its managed block.

Existing aliases that were not created by gauth are never modified. gauth will ask you to choose another alias instead.

---

## 🛡️ Pre-push profile guard

Every repository configured by gauth gets a managed `.git/hooks/pre-push` hook. The hook runs on `git push` whether or not gauth is currently running, and invokes the installed `gauth` binary.

Before a push is allowed, the guard checks:

- the repository's selected profile (`gauth.profile`)
- the profile's SSH alias and key
- the alias used by the push remote

If the remote would use the selected profile's alias, the push continues. If it would use a different alias — or an HTTPS remote — the guard blocks the push, shows the mismatch, and offers the configured profiles. Choosing a profile updates `remote.origin.url` to that profile's alias and asks you to run `git push` again, so the next push actually uses the new SSH alias.

The guard also identifies a profile from a cloned repository's alias URL (for example `git@github.com-work:owner/repo.git`) and records it in `gauth.profile`.

A repository cloned by hand has no guard yet. When you open gauth in such a repository, it warns that no profile is selected and installs the guard immediately, so a forgotten profile blocks the next push instead of using another account. `gauth clone` installs it from the start. Pushes made without ever running gauth in that repository cannot be intercepted; run gauth (or `gauth profile select`) once in each checkout you intend to push from.

Safety behavior:

- A foreign `pre-push` hook is never overwritten. gauth leaves it in place and reports that the guard was not installed.
- Non-GitHub remotes are allowed through unchanged.
- If no profiles exist, the guard blocks the push and explains how to add one.
- If the gauth executable is no longer installed, the hook allows the push rather than trapping you. Uninstall leaves hooks in your repositories; remove `.git/hooks/pre-push` manually if you want them gone.
- `git push --no-verify` bypasses any hook, as with all Git hooks.

Run `gauth doctor` in a repository to see whether the guard is installed, or `gauth doctor --fix` to install or refresh it. The test suite uses `GAUTH_HOOK_NO_PROMPT=1` to exercise the guard without an interactive terminal.

---

## 🔒 Profile removal authentication

Removing a profile is destructive, so gauth asks for your **sudo password** immediately after you pick the profile and before it shows or changes anything. The password is read on the terminal and piped to `sudo -S`; it is never placed in argv or the environment. sudo is used only to verify your identity — the profile registry, SSH config, and keys are still edited as your normal user, so file ownership stays correct.

If `sudo` is unavailable, or authentication is cancelled or fails, gauth stops and leaves the profile untouched. The prompt always appears; if sudo already has a valid timestamp (or is passwordless), press Enter instead of typing a password.

---

## 🎨 Theme and messages

- The interactive menu opens with a pixel-block cat/terminal mark and a multi-color **GAUTH** wordmark drawn from the logo in `assets/`.
- The palette follows meaning: **green ✔** for success, **blue** for information and navigation, **amber !** for warnings, and **red ✖** for errors. The glyphs keep the levels distinguishable even when color is unavailable.
- Set `GAUTH_NO_BANNER=1` for a compact session without the banner.

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
shellcheck src/*.sh install.sh uninstall.sh build.sh tests/run.sh
shfmt -d -i 2 -ci src install.sh uninstall.sh build.sh tests/run.sh
```

The project deliberately targets Bash 3.2 so the built‑in `/bin/bash` on macOS works. Avoid associative arrays, `mapfile`, `${var,,}`, `declare -n`, and `&>>`.

### Layout

```
src/common.sh      constants, validation, paths, atomic helpers
src/ui.sh          gum wrappers, ANSI fallback, banner, themes
src/auth.sh        sudo authentication gate for profile removal
src/config.sh      settings and profile registry
src/clipboard.sh   cross-platform clipboard + OSC 52
src/ssh.sh         key generation, agent, ssh -T
src/sshconfig.sh   managed SSH config blocks
src/git.sh         URL parsing and local git config
src/hooks.sh       pre-push profile guard and hook installation
src/profile.sh     profile wizard, view/select, and removal
src/settings.sh    settings menu
src/doctor.sh      diagnostics
src/commands.sh    init/menu commands
src/main.sh        entry point
install.sh         installer (delegates --uninstall to uninstall.sh)
uninstall.sh       sudo-gated complete removal of gauth data, keys, and SSH blocks
```

---

## ⚠️ Limitations

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

Built with 💚 by Showvik

</div>