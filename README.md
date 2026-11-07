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

## 🧭 How gauth works

`gauth` is a helper for the moments where Git and GitHub are connected by SSH keys, aliases, and local identity. It does not rewrite your global Git config blindly; it keeps the work focused on the current repository and the selected profile.

The app has a few clear operating modes:

- **Interactive menu** — run `gauth` and pick the current operation from a guided menu.
- **Profile flow** — add, inspect, and remove saved profiles.
- **Repository flow** — initialize a repo, connect it to GitHub, or attach a selected profile to an existing repo.
- **Clone flow** — clone a repository through the chosen profile's SSH alias and immediately configure the local identity and guard.
- **Guard flow** — install a pre-push hook that blocks wrong-profile pushes and shows the correct next step.

**This is the flow of gauth:**

**You start with a repo situation, and gauth tells you what to do next.**

1. **Start a fresh repo and connect it with GitHub** — if you are not inside a Git repo yet, the first option becomes **Set up this folder (git init + GitHub)**.
2. **Clone an existing GitHub repo with gauth** — if you want to clone a repo and set up the right profile for it, gauth guides you through that flow.
3. **Switch profile anytime** — if you already have a GitHub repo open and want to change the active profile, the first option becomes **Work on this repository (switch profile)**.
4. **You already cloned the repo yourself** — if the repo is already there, open it and run `gauth`; it will let you pick the profile for that repo without changing anything else.

**The menu adapts to your current state:**

- **Outside a Git repo:** the first option becomes **Set up this folder (git init + GitHub)**.
- **Inside a repo without a GitHub origin:** the first option becomes **Connect this repository to GitHub**.
- **Inside a GitHub repo:** the first option becomes **Work on this repository (switch profile)**.
- **No profiles exist yet:** the menu will explain that no profiles are configured and offer to add one.

## 🎯 Interactive mode

Run `gauth` to open the interactive menu. This is the primary way to use the tool. The menu is vim-style: move with **j/k** or **↑/↓**, go back with **h** or **←**, go forward with **l** or **→**, press **Enter** to select, and **q** to quit.

### Root menu

```bash
gauth
```

You will see:

- **Work on this repository (switch profile)** — the folder is already a GitHub repo; select a profile for this work session.
- **Connect this repository to GitHub** — the folder is a repo but has no GitHub origin yet; pick a profile and connect it.
- **Set up this folder (git init + GitHub)** — initialize a repo in the current folder, then connect it to GitHub.
- **Clone a GitHub repository** — clone through a saved profile's SSH alias, then configure the repo automatically.
- **Add profile** — create a new SSH key and Git identity using the wizard.
- **View saved profiles** — show the names of saved profiles and then inspect the details of one saved profile without changing repo state.
- **Remove profile** — authenticate with sudo, then archive or reuse an existing key.
- **Settings** — change defaults such as key type, alias prefix, and branch.
- **Doctor** — check installation health, guard status, and profile readiness.
- **Help** — show usage information.
- **Exit** — quit the app.

The first item is intentionally context-aware. That is the major behavior change in the current flow: it changes from **Set up this folder** to **Connect this repository to GitHub** to **Work on this repository** depending on the repo state.

### Navigation tips

- **j / k** or **↑ / ↓** — move up/down
- **h** or **←** — go back one step/page
- **l** or **→** — go forward (open the highlighted item or advance a wizard step)
- **Esc** — go back, including inside wizard text prompts
- **Ctrl‑C** — cancel and return to the menu
- **Enter** — select / confirm
- **g** / **G** — jump to first / last item
- **q** — quit the whole app

At the root menu, **h**, **Esc**, and the left arrow never close gauth: they walk back through your action history or show a hint. Only **q** or **Exit** quits. When there is nowhere to go back or forward, the menu tells you and stays open.

The profile wizard draws a commit-graph style timeline and records the value selected for each step, for example `01 Profile name [demo]`. Inside a wizard text prompt, press `Esc` to go back or `Ctrl‑C` to cancel without pressing `Enter`. You can also type `:back`, `:forward`, or `:cancel`; menu steps include `‹ Back` and `✕ Cancel` items.

---

## 🚀 Recommended workflow: use the interactive menu first

The best way to use gauth is to start in the directory where you want to work and run:

```bash
gauth
```

From there, the app decides what to do for you based on the current directory and repository state. This is the primary UX of the project, and the command-line helpers are there mostly as convenience shortcuts.

### Typical first-time flow

1. Run `gauth` in the folder you want to work in.
2. If you have no saved profile yet, choose **Add profile**.
3. The wizard asks for:
   - profile name
   - SSH alias
   - Git name
   - email
   - key type
   - key file name
   - optional passphrase flow
4. After the profile exists, the menu continues with the correct repo action for your state.
5. gauth configures the SSH alias, Git identity, remote, and guard for you.

### The interactive flow is context-aware

This is the main thing to understand:

- **Outside a Git repo:** the first option becomes **Set up this folder (git init + GitHub)**.
- **Inside a repo without a GitHub origin:** the first option becomes **Connect this repository to GitHub**.
- **Inside a GitHub repo:** the first option becomes **Work on this repository (switch profile)**.
- **No profiles exist yet:** the menu will explain that no profiles are configured and offer to add one.

This is the real flow of gauth:

1. **You start a fresh repo and want to connect it with GitHub** — run `gauth` in the new folder and choose **Set up this folder (git init + GitHub)**.
2. **You want to clone an existing GitHub repo** — use gauth to clone it and set up the profile for that repo.
3. **You already cloned a repo and now want to switch profiles anytime** — open the repo, run `gauth`, and choose **Work on this repository (switch profile)**.
4. **You already have the repo locally and just want to select a profile** — the menu will let you pick the correct profile for that repo without changing the repository itself.

That makes the app feel like a guided setup assistant instead of a collection of raw shell commands.

### The main interactive entry paths

#### 1) Fresh start: create a new repo and connect it to GitHub

```bash
mkdir my-app && cd my-app
gauth
```

Choose **Set up this folder (git init + GitHub)**. gauth runs `git init`, asks for the GitHub repo URL, and configures the repository in one flow.

#### 2) Clone an existing GitHub repo with gauth

```bash
gauth clone https://github.com/owner/repo.git
```

This is the easiest path when you want gauth to clone the repository through your profile's SSH alias. It configures the repo, identity, and pre-push guard automatically.

#### 3) You already cloned the repo and want to switch profiles

```bash
cd existing-repo
gauth
```

Choose **Work on this repository (switch profile)** if the repo already has a GitHub origin and you want to change which profile is active for the working session.

#### 4) You already have the repo locally and just want to pick a profile

```bash
cd existing-repo
gauth
```

If the repo is already there, gauth will recognize the current state and let you select the profile for that repo. This is the same idea as “switch profile anytime,” but without creating or re-cloning anything.

#### 4) Browse saved profiles without changing repo state

```bash
gauth
```

Choose **View saved profiles** and pick a saved profile to inspect the details. This is read-only and does not modify your repo or Git identity.

#### 5) Add or remove a profile

```bash
gauth
```

Use **Add profile** to create a new SSH key + Git identity, or **Remove profile** to delete a profile after confirmation.

The interactive menu is the recommended path for all of these actions. The direct commands are available as shortcuts, but they are not the primary experience.

### The direct commands still exist

These are still useful as shortcuts, but they are not the primary experience:

```bash
gauth profile add
gauth profile select
gauth profile remove
gauth clone https://github.com/owner/repo.git
gauth init --profile work --repo https://github.com/owner/repo.git
```

The direct commands mirror the same actions that the interactive menu performs, but the interactive mode is the recommended and most natural way to use gauth.

### What gauth does under the hood

In every interactive flow, gauth will:

1. Run `git init` if needed
2. Set local Git config (`user.name`, `user.email`, `remote.origin.url`)
3. Configure the SSH remote using your profile alias (for example `git@github.com-work:owner/repo.git`)
4. Install the repository's pre-push profile guard
5. Start or reuse `ssh-agent` and unlock the key
6. Test the connection with `ssh -T git@alias`
7. Show an **All set** summary with next steps

The SSH key is saved under `~/.ssh/gauth/id_<type>_<profile>`.

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

This keeps the binary in `$HOME/.local/bin` and avoids the system install path. Make sure `$HOME/.local/bin` is on `PATH`.

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

`gauth` can be uninstalled in two stages:

1. the script asks for your sudo password to verify identity
2. it shows a red, bold warning telling you that this will remove the gauth-managed SSH config, keys, installed files, and local data
3. it waits for you to press **Enter** to confirm the permanent removal

This final confirmation is intentionally explicit because the uninstall is destructive. It removes:

- the installed `gauth` binary and gauth's private `gum` copy
- `~/.config/gauth`, `~/.local/state/gauth`, and `~/.local/share/gauth`
- keys created by gauth under `~/.ssh/gauth`
- only the `# >>> gauth:... >>>` blocks in `~/.ssh/config`; all other SSH entries are preserved

The sudo check is an identity gate. It is required even with `--yes`; if sudo already has a valid timestamp or is passwordless, the check succeeds without prompting. Your personal files are still removed as your normal user, and sudo is used only for files in a system directory. If authentication is cancelled or fails, nothing is removed.

It does **not** delete your repositories, global Git config, SSH keys that gauth did not create, or the source checkout you ran the script from.

Options:

```bash
./uninstall.sh --prefix "$HOME/.local"   # user-local install
./uninstall.sh --yes                     # skip the initial yes/no prompt; sudo auth and final Enter confirmation still apply
./uninstall.sh --purge-keys              # also remove legacy profile keys outside ~/.ssh/gauth
```

`./install.sh --uninstall` is kept as a shortcut and delegates to `./uninstall.sh`.

---

## ⚡ quick start (interactive-first)

```bash
# Start here in the folder you want to set up
gauth

# If you need a profile first, use the menu:
# Add profile -> then return to the main menu
```

The interactive menu is the recommended path. It adapts to your current repo state and guides you through the correct setup flow without having to memorize command syntax. The direct commands remain available as shortcuts, but they are secondary.

`gauth init` still accepts an existing profile and an optional URL:

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