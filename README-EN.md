```markdown
# me — Terminal Command Center for Linux

**me** is a minimal CLI framework that turns complex terminal commands into simple, memorable methods. One configuration, one command, tab completion, and an interactive TUI selector.

Instead of dozens of messy aliases in `.bashrc`, you get a single declarative file (`~/.config/me/me.conf`) with methods that work everywhere: in your interactive shell, inside scripts, over SSH, and across different machines.

---

## 🚀 Version 2.0 Release Notes

`me` has undergone a fundamental architectural refactoring. The core engine is now fully converted to a declarative **Zero-Eval / Direct Execution** model.

### 🏗️ Key Architectural Changes

- **Complete Elimination of `eval`:** The engine no longer loads BASH function code dynamically into your active session, nor does it generate temporary function cache files. This completely removes syntax crash risks when handling complex quoting, heredocs, or character escaping.
- **Pure Declarative `me.conf`:** The configuration file no longer contains executable code (no more `me_method_*()` functions). It is now a strict metadata manifest that explicitly points to standalone scripts via `#@script: me_lib/<script>.sh`.
- **Direct Dispatcher:** The engine resolves script paths in milliseconds and runs them in clean, isolated subprocesses. Modifying a specific method no longer requires clearing caches and never affects other modules.
- **Automated Idempotent Builder (`me make`):** Automatically scans `me_lib/*.sh` for valid methods, verifies the `#true_method` marker tag on line 2, and idempotently registers new scripts into `me.conf` without touching existing method blocks.
- **Instant Response:** Resolution overhead is virtually non-existent—script path resolution happens in a single `awk` pass over the manifest.
- **Breaking Change:** Old `me.conf` files (from v1.x) are incompatible with version 2.0. Legacy engine files and configs have been archived in `me_old/` for historical reference.

---

## 📋 Declaring Methods in `me.conf` (New Format)

```bash
#@method: mov
#@description: [cat: files] Batch rename files using patterns
#@example: me mov -_ ; me mov "[]photo_1"
#@variants:
#   me mov -_                  # Replace hyphens with underscores
#   me mov "[]photo_1"          # Number files with a custom prefix
#@script: me_lib/mov.sh

```

For project change history, see `CHANGELOG.md`. Archives of legacy code snapshots are preserved for rollback purposes if needed.

---

## 💥 The Problem `me` Solves

Aliases in `.bashrc` work fine when you have 5 to 10 of them. When that number grows to 30+, chaos sets in:

* **No Documentation:** A month later, you can't remember what `alias rd` actually does.
* **Rigid Arguments:** You can't pass arguments into the middle of an alias—only at the end.
* **Script Incompatibility:** Aliases are ignored in non-interactive shell scripts by default.
* **Name Conflicts:** Duplicate alias names silently overwrite previous ones.
* **No Validation:** Aliases cannot check if required utilities are installed or handle errors gracefully.

---

## ⚡ Before vs. After Examples

| Before (Complex Commands) | After (`me` Method) |
| --- | --- |
| `busctl --user call org.mpris.MediaPlayer2.mpv /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Pause` | `me pause` |
| `find ~/.config -type f -name "*.conf" -exec grep --color=always -C2 "server" {} \; | less -R` | `me fi -c "server" ~/.config` |
| `yt-dlp --default-search "ytsearch10:${*:1}" --get-title --get-id --no-warnings 2>/dev/null | paste - - | fzf --reverse | cut -f2 | xargs -I {} mpv --no-video "https://youtube.com/watch?v={}"` | `me smy "led zeppelin kashmir"` |

Instead of long, unreadable commands, you use clean verbs. All execution logic remains safely encapsulated inside method scripts.

---

## 📥 Quick Installation

1. Download `me` and unpack it into `~/.local/bin/me`:

```bash
cd ~/.local/bin/me
bash install_me.sh
source ~/.profile
me

```

**Dependencies:** `fzf`, `playerctl`, `ripgrep`, `ffmpeg` (optional/method-dependent).

---

## 🛠️ Creating Your First Method (30 Seconds)

In Architecture 2.0, a method is **always an isolated executable script**—never an inline shell function inside `me.conf`. All default method scripts live in `~/.local/bin/me/me_lib/` (or any custom path).

### Step 1: Create the Script with `#true_method`

Create `~/.local/bin/me/me_lib/hello.sh`:

```bash
#!/usr/bin/env bash
#true_method
echo "Hello, Terminal!"

```

> **Crucial Rule for `me make`:** Line 2 of your script MUST contain the `#true_method` marker tag. 
This explicitly marks the script as an executable method for `me` and distinguishes it from auxiliary helper libraries or internal tools in `me_lib/