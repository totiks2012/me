# me — CLI command hub

**me** is a minimalist CLI framework that turns complex commands into simple methods. One config, one command, autocompletion, interactive selection.

Instead of dozens of aliases in `.bashrc` — a single file `~/.config/me/me.conf` with methods that work everywhere: in terminal, scripts, over SSH, across different machines.

---

## The Problem me Solves

Aliases in `.bashrc` work fine when you have 5–10. When you hit 30+, chaos begins:

- **No documentation** — a month later you forget what `alias rd` does.
- **Arguments only at the end** — you can't pass a path into the middle.
- **Don't work in scripts** — aliases are invisible in non‑interactive bash.
- **Name conflicts** — the last alias silently overwrites previous ones.
- **No checks** — an alias doesn't verify if a utility is installed or handle errors.

**me fixes this:** methods are bash functions with meta‑tags, self‑documented, validated, and work from anywhere.

---

## Before / After Examples

| Before (monster) | After (me) |
|------------------|------------|
| `busctl --user call org.mpris.MediaPlayer2.mpv /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Pause` | `me pause` |
| `find ~/.config -type f -name "*.conf" -exec grep --color=always -C2 "server" {} \; \| less -R` | `me fi -c "server" ~/.config` |
| `yt-dlp --default-search "ytsearch10:${*:1}" --get-title --get-id --no-warnings 2>/dev/null \| paste - - \| fzf --reverse \| cut -f2 \| xargs -I {} mpv --no-video "https://youtube.com/watch?v={}"` | `me smy "led zeppelin kashmir"` |
| `aria2c --seed-time=0 --max-connection-per-server=16 --split=16 --continue=true --file-allocation=none --allow-overwrite=true --dir=/mnt/downloads "magnet:?xt=urn:btih:..."` | `me tor add "magnet:..."` |

Instead of mile‑long lines — simple verbs. Everything else lives inside methods.

---

## Quick Install

```bash
git clone https://codeberg.org/totiks2026/Me ~/.local/bin/me
cd ~/.local/bin/me
bash install_me.sh
source ~/.profile
me
```

Optional dependencies: `fzf`, `playerctl`, `ripgrep`, `ffmpeg`.

---

## Your First Method in 30 Seconds

Open `~/.config/me/me.conf` and add:

```bash
#@method: hello
#@description: My first command
#@example: me hello
me_method_hello() {
    echo "Hello, terminal!"
}
```

Save and run:

```bash
me hello
```

Done. The method works like a native command.

---

## Interactive Method Creation — `me create`

Don't want to manually open an editor? Use the built‑in generator:

```bash
me create
```

It will ask:

- **Method name** — lowercase letters, digits, underscores.
- **Description** — what it does.
- **Example** — how to call it (defaults to `me <name>`).
- **Command body** — the bash code to execute.

After you enter everything, `me create`:
- generates a block with meta‑tags and function;
- checks syntax with `bash -n`;
- appends it to `me.conf`;
- reports success.

Example session:

```
$ me create
Method name: backup
Description: Backup home directory
Example: me backup
Command body: tar -czf /backup/home.tar.gz ~/ && notify-send "Backup" "Done"
Method 'backup' created in /home/user/.config/me/me.conf.
Run: me backup
```

The method is ready to use.

### Working with External Scripts

As a command body, you can specify a path to an existing script:

- `$HOME/.local/bin/my_script.sh` — any script in `PATH`.
- `$HOME/.local/bin/me/me_lib/my_method.sh` — a library script from `me` itself.

If you give a script path, `me create` generates a method that calls that script with the passed arguments. For example:

```
Command body: $HOME/.local/bin/me/me_lib/backup.sh "$@"
```

This lets you instantly wrap any existing script as a `me` method, without rewriting it — with documentation, autocompletion, and exportability.

---

## Key Features

### Interactive Mode — `me int`

Don't remember the exact method name? Type `me int` — you'll get a list of all methods with descriptions and examples. Pick one — the command goes into history, press `↑` and run.

### Built‑in Documentation

- `me` — list all methods with descriptions.
- `me -m <method>` — detailed help for a specific method.

### File Versioning — `cit`

Store snapshots of files in `.cit/` next to your project, revert, view diffs, delete to trash, restore. No Git required.

- `cit` (or `me cit`) — interactive menu.
- `cit -f` — finalize with full changelog, creates a `-F` copy.

### Export and Import — `share/import`

- `me share <method>` — packages the method with dependencies into `tar.gz`.
- `me import <method>` — installs the method on another machine (from file, folder, or URL).

This lets you roll out a set of methods across a fleet in minutes.

### Portability

Everything `me` lives in two directories: `~/.local/bin/me/` and `~/.config/me/`. To move to another Linux machine, just copy them and add `me` to `PATH`. No changes to `.bashrc` needed.

---

## Why me Over Aliases or Bash Functions

| Feature | Alias | Bash Function | me Method |
|---------|-------|---------------|-----------|
| Documentation | No | Comments | Meta‑tags + autoprompt |
| Arguments | Tail only | Full `$@` | Full `$@` |
| Conditionals | No | Yes | Yes |
| Help | `grep` | `declare -f` | `me -m` |
| Command search | Manual | Manual | `me` — ready list |
| Centralization | `.bashrc` | Any file | One `me.conf` |
| Works in scripts | No | Yes | Yes |
| Portability | Only with `.bashrc` | Manual | Copy two folders |

---

## When to Use me

- You have more than 5–10 aliases.
- You administer multiple machines (or live systems).
- You bind scripts to hotkeys (i3/sway/bspwm).
- You want a clean `.bashrc` without clutter.
- You need interactive command selection via `fzf`.

## When Not to Use me

- You have 3–5 aliases and they work fine.
- You don't use the terminal for routine tasks.
- You don't want to centralise command management.

---

## Full Method List (30+)

| Category | Examples |
|----------|----------|
| **System** | `vol up/down`, `bright up/down`, `upgrade`, `restart`, `offnow`, `stat` |
| **Media** | `play/pause/next/prev/toggle`, `smy`, `svy`, `say` |
| **Utilities** | `fi`, `ff`, `calc`, `id`, `run`, `color`, `uni_tables`, `itag`, `crossfade`, `gifx`, `wfb` |
| **Communication** | `share`, `import`, `create` |
| **Navigation** | `me`, `me -m`, `me int` |

For details on each method, see the full article or run `me -m <method>`.

---

## Links


- **Full article (English):** [link to your English article] — philosophy, architecture, all methods, real‑world use cases, scaling, and `cit`.
- **License:** GNU GPLv3

---

*me v3.5. Compatibility: Bash 4.0+, POSIX sh for internal methods.*
