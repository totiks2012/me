Here's the full English translation of the article. I've kept the tone, structure, and all technical details intact.

---

# me: A Terminal That Feels Like Home

For a long time, my terminal felt like a workshop where tools were thrown into one pile — and half of them I couldn't remember why I picked up in the first place. Aliases accumulated in `.bashrc` — I added them, forgot them, added them again. Some conflicted with others, some stopped working after system updates, others simply silently ignored me in scripts. To adjust screen brightness, I googled `busctl` every single time — and every time I was surprised that I couldn't remember that line. I tried different approaches to bring order: wrote separate scripts, organized them in folders, bound them to hotkeys — everything lived its own life, had no documentation, and couldn't be managed.

I didn't need another launcher or command manager. I needed a remote control. Like on an old tape recorder: you see all the buttons, press one — it works. Something I could take with me to another machine, something that wouldn't break from one wrong line, and where every button tells you what it does.

That's how `me` was born.

---

## What Hurts About Aliases in .bashrc

For me, an alias is a hook I hang a command on. Convenient — while there are five hooks. When there are thirty, they start falling off: one was hammered in wrong, another fell off after an update, a third silently conflicts with a fourth. And the main thing — in scripts, these hooks don't exist at all. Here's what I learned from a long life with .bashrc:

| Problem | Why It Hurts |
| --- | --- |
| **Don't work in scripts** | Bash scripts don't see aliases without `shopt -s expand_aliases` (which no one adds). A script with aliases will fail on another machine — you'll be hunting for why. |
| **No documentation** | A month later you don't remember if `alias rd='rm -rf'` or `alias rd='rdesktop'`. You start with `grep alias ~/.bashrc` — every single time. |
| **Arguments only at the end** | `alias backup='tar -czf'` — you can't pass a path into the middle. You need a function, but in .bashrc that's just another pile. |
| **No checks** | An alias doesn't check if the utility is installed. Doesn't handle errors. Doesn't return exit codes. |
| **No isolation** | All aliases in one heap. Variables, exports, custom functions — all mixed together. Version control? Manually cut from .bashrc. |
| **Name conflicts** | Two aliases with the same name — the last one silently wins. No diagnostics. |
| **Only for manual input** | Can't call from a script, can't pass via fifo, can't bind to an i3 hotkey as a reliable command. |

**[SCREENSHOT: bashrc_vs_me.png]**
*Left — .bashrc with aliases mixed with exports, comments, completions, and forgotten functions. Right — me.conf: a clean column of methods with annotations. File sizes are comparable, but readability is different.*

---

## What me Offers

`me` was born as a registry of everything I do in the terminal. It's a bash script (`~/.local/bin/me`) + a config (`~/.config/me/me.conf`). The config describes methods with meta-tags. They're called via `me <verb>`.

**Architecture — three layers:**

```
terminal / script / hotkey
        │
        ▼
  me (bash engine)
        │
        ▼
  me.conf (method registry)
        │
        ├── me_method_play()    — built‑in method
        ├── me_method_upgrade() — built‑in method
        └── me_lib/ff.sh        — external script‑method
```

**[SCREENSHOT: architecture.png]**
*Diagram: input `me <verb>`, the engine searches for the method in me.conf via awk, runs `bash -n`, on error — warning, other methods remain unaffected.*

> *Thought: I specifically designed it so the engine doesn't load everything at once. Because I've been burned when one broken .bashrc crashed the entire shell. Here — if one method fails, the rest keep working. That feels right to me.*

---

### What It Looks Like in Practice

I like to listen to music through mpv in the background. Before, to pause, I'd dive into the terminal and type busctl with a mile‑long path — it was madness. Now I just press `me pause`, or if my hands are busy, toggle via a hotkey that calls `me toggle`. Same with brightness:

Before:
```bash
busctl --user call org.xfce.PowerManager \
  /org/xfce/PowerManager \
  org.xfce.Power.Backlight IncreaseBrightness
```

After:
```bash
me bright up
```

The difference isn't just that the second version is shorter — it's that it has:
- **Documentation:** `me -m bright` shows description and example.
- **Autocompletion:** Tab completes `bright`, Tab again — `up`/`down`.
- **Notification:** notify-send after brightness change.
- **Fallback:** if XFCE fails, it tries GNOME.
- **Interactive:** `me int` → fzf → selection → command in bash history (press ↑).

**[GIF: me_int_demo.gif]**
*Demo of `me int`: fzf opens with method list. Right — preview with description and example. Selection — command is printed and added to history. Press Up — you see it on the prompt. All done.*

> *Thought: honestly, I stopped remembering method names. When I type `me int`, I see the list and just pick one. Like a quick launcher on a phone — just in the terminal.*

---

## How a Method Is Formally Structured

Each method is a regular bash function with meta-tags before it:

```bash
#@method: pause
#@description: Pause the player
#@example: me pause
me_method_pause() {
    playerctl pause 2>/dev/null || true
}
```

The engine **does not load all methods at once**. When `me` starts, it imports only helpers (generic functions without the `me_method_` prefix). When a specific method is called, the engine:

1. **Finds** the function `me_method_<name>()` in `me.conf` via awk.
2. **Checks** syntax via `bash -n /dev/shm/me_check_XXXXXX.sh`.
3. **eval + cache** in `/dev/shm/me_$USER/me.cache` with automatic invalidation via md5.

If a method has a syntax error — it simply doesn't load, the other methods keep working.

> *Thought: this mechanism is my pride. me will never crash entirely because of one typo. It will say: "there's an error here, go check it." And I go. And fix it. Without fear that everything will collapse.*

```bash
#@method: press
#@description: Send key combination via xdotool
#@example: me press ctrl+shift+t
me_method_press() {
    [ -z "$1" ] && { echo "Specify a combination: me press ctrl+t"; return 1; }
    xdotool key "$1"
}
```

This method can be:
- Called manually: `me press ctrl+shift+t`.
- Used in a script: `if me press ctrl+alt+F2; then echo "terminal opened"; fi`.
- Bound to an i3/sway hotkey: `bindsym $mod+t exec me press ctrl+shift+t`.
- Shared: `me share press` → `tar.gz` in `import/`.

**[SCREENSHOT: method_block.png]**
*Syntax highlighting of me.conf in micro/Neovim. Three tags visible (#@method, #@description, #@example), followed by the function body. Visually: the block takes about a screen and a half.*

---

## What Aliases Can't Do

Without me you write:

```bash
yt-dlp --default-search "ytsearch10:${*:1}" --get-title --get-id --no-warnings 2>/dev/null | \
  paste - - | fzf --reverse | cut -f2 | \
  xargs -I {} mpv --no-video "https://youtube.com/watch?v={}"
```

With me it's:

```bash
me smy "led zeppelin kashmir"
```

Not because me is smart. But because `smy` is a method in the me library `me_lib/smy.sh`, where all the logic is extracted into a separate script with checks:

- checks yt-dlp and mpv before running
- searches 20 results → fzf → selection
- plays via mpv

**Aliases can't:**
- Check if ffmpeg/yt-dlp/mpv is installed before calling
- Return an exit code and handle errors
- Be called from a script (sh/ash/dash — no aliases)
- Have internal variables and arguments in the middle of a line
- Have autocompletion with descriptions

**me can — and this isn't magic, it's bash.** When I wrote me, I deliberately didn't add any languages, frameworks, or dependency managers. A method is a bash function — that's it. I wanted anyone who knows bash to be able to open me.conf, immediately understand what's written there, and fix it if needed.

---

## What Switching from Aliases to me Gives You

### 1. Centralized Management

Instead of 50 lines in `.bashrc` — one file `~/.config/me/me.conf`. You can put it in git, diff it, roll it back. Sounds basic, but when I first ran `git diff me.conf` and saw what I'd changed in methods over a month — I knew I was never going back to .bashrc.

### 2. Documentation by Default

Meta-tags `#@description:` and `#@example:` are written once — when you create the method. A month later `me` shows help, a year later — too.

### 3. Script Compatibility

`me pause` works inside bash scripts, in `cron`, in `systemd --user`, in window manager keybindings. You're not tied to interactive mode.

### 4. Works in Any Context — Without Losing Environment

One common problem when moving scripts to `/usr/local/bin` is losing environment variables. A script run as a separate process does not inherit `DISPLAY`, `DBUS_SESSION_BUS_ADDRESS`, `PULSE_SERVER`, and other variables set in the interactive session. This breaks notifications, brightness control, or volume commands.

The usual fix — manually exporting needed variables at the start of the script or using aliases — but aliases don't work in non‑interactive shells.

`me` solves this differently. A `me` method runs in the context of the current shell — it's loaded via `source` (or eval) and inherits all environment variables from the parent process. So calling `me bright up` or `me say` always works, regardless of where it's called from: terminal, script, hotkey, or even `cron` (if the full path to `me` is given and the environment is passed correctly).

In practice, this means a method written once doesn't need adjustments when moved to another machine or environment. It eliminates "magical" environment‑related errors and makes `me` a reliable automation tool.

And here's another strong argument in favor of me:

### Portability Without .bashrc Dependency

On different Linux machines, `.bashrc` files often differ significantly: one distro loads `bash_completion`, another loads `profile.d`, a third has custom GUI variables. Extracting aliases from this zoo and moving them to a new system is tedious and can cause conflicts.

`me` solves this radically: all methods live in a separate file `~/.config/me/me.conf` that does not depend on shell settings. To move to another machine, just copy this file and install `me` (or copy the entire `~/.local/bin/me/` directory). No changes to `.bashrc` required — `me` works as a separate executable in `PATH`.

This makes `me` ideal for working across different systems: from minimalistic live images to full desktop environments. The same set of methods works identically everywhere.

### 5. Error Isolation

A method with a syntax error doesn't break the remote. The error goes to stderr. The engine keeps running.

### 6. Extensibility Without Collisions

A new method = 5 lines in `me.conf`. Names are unique within the config. No conflicts with exports and sources.

### 7. Interactive Selection

`me int` → fzf with method list, preview, and example. Select → command goes to history. I've stopped remembering names. When you want to pause and the method is called `pause`, it's easy. But when there are thirty — it's easier to pick with your eyes than recall.

### 8. Social — share/import

When I moved me to a new machine, I realized: copying me.conf is half the job — what about dependencies? Scripts from me_lib? So I built share/import.

```
me share gifx   # → ~/.local/bin/me/import/gifx.tar.gz
me import gifx  # → extracts, adds method to me.conf, copies libraries
```

Inside the archive — the method, dependencies (scripts from `me_lib/`, configs) and `install.sh` which does everything automatically. You can load from pastebin — `me import https://...` — and the method appears on a clean system. I don't call it "a social network for geeks" — it's just a way not to write the same thing twice.

### 9. RAM Caching

The method cache lives in `/dev/shm/me_$USER/` — a RAM disk. The hash of `me.conf` is compared on every call. If the config hasn't changed — loaded from RAM. If it has — rebuilt.

---

## Full List of Methods

### System
| Command | What It Does | Example |
| --- | --- | --- |
| `me vol up/down/mute` | Volume (pulseaudio → alsa fallback) | `me vol up` |
| `me bright up/down` | Brightness (XFCE → GNOME fallback via D-Bus) | `me bright down` |
| `me upgrade` | System update (pacman/apt/apk) | `me upgrade` |
| `me restart` | Reboot via systemctl | `me restart` |
| `me offnow` | Power off via systemctl | `me offnow` |
| `me logout` | Log out via loginctl | `me logout` |
| `me stat` | System snapshot: CPU, battery, volume | `me stat` |
| `me status [service]` | List running services or status | `me status dbus_tamer` |
| `me on <service>` | Start a systemd service | `me on dbus_tamer` |
| `me off <service>` | Stop a systemd service | `me off dbus_tamer` |

### Media
| Command | What It Does | Example |
| --- | --- | --- |
| `me play/pause/stop` | MPRIS player control | `me pause` |
| `me next/prev/toggle` | Track navigation | `me toggle` |
| `me smy <query>` | Search music on YouTube → mpv | `me smy "kashmir"` |
| `me svy <query>` | Search video on YouTube → mpv 720p | `me svy "linux review"` |
| `me say <text>` | Desktop notification | `me say "Done" "Backup complete"` |

### Utilities
| Command | What It Does | Example |
| --- | --- | --- |
| `me fi -c <text>` | Search file contents (ripgrep + fzf + micro) | `me fi -c "TODO"` |
| `me fi -s <name>` | Search by filename (find + fzf) | `me fi -s "config"` |
| `me ff` | Interactive ffmpeg builder (cut/glue) | `me ff` |
| `me calc <formula>` | Calculator (bc with trigonometry) | `me calc "sqrt(2^10)"` |
| `me id -s <text>` | Save a note/idea | `me id -s "Buy transistors"` |
| `me id -r` | Show notes via fzf | `me id -r` |
| `me run <name>` | Run a script by name from ~/.local/bin/ | `me run pam4.sh` |
| `me color <color> <text>` | Color terminal text | `me color red "Error"` |
| `me uni_tables <columns>` | Format tables with auto‑width | `me uni_tables "A" "B"` |
| `me itag` | ID3 tag editor for MP3/FLAC (fzf + micro + mutagen) | `me itag` |
| `me crossfade [path]` | Merge MP3 with crossfade (ffmpeg) | `me crossfade` |
| `me gifx` | Record GIF/MP4 screen area (F5 start/stop) | `me gifx` |
| `me wfb` | Open a book from clipboard in browser | `me wfb` |
| `me cy` | Launch Cyan player | `me cy` |

### Communication
| Command | What It Does | Example |
| --- | --- | --- |
| `me share <method>` | Package method with dependencies into tar.gz | `me share gifx` |
| `me import <method>` | Import method from archive/URL | `me import gifx` |

### Navigation
| Command | What It Does | Example |
| --- | --- | --- |
| `me` | Show help with all methods | `me` |
| `me -m <method>` | Help for a specific method | `me -m ff` |
| `me int` | Interactive selection via fzf | `me int` |

**[GIF: me_library_animation.gif]**
*Sequence: `me` (list all methods) → `me -m smy` (describe smy) → `me smy "query"` (search and play). Demonstration of three modes in one screencast.*

---

## File Versioning with cit

Beyond ready‑to‑use methods, `me` provides a lightweight versioning tool — `cit`. It's not a Git replacement, but a way to save file states during work, without initializing a repo or writing commits.

`cit` stores snapshots of files in a hidden `.cit/` folder next to your project. Each snapshot includes a copy of the file and a comment — a changelog. The filename format is: `filename__dd-mm-yyyy_hh-mm-ss.cit`.

Core operations:

- **Create snapshot (Push)** — select files or folders via `fzf`, enter a comment. The snapshot is saved with a timestamp. If the file has a shebang (`#!`), the comment is automatically inserted into its header.
- **Revert to previous version** — the current file is replaced with the latest snapshot from `.cit/`. The previous state isn't saved — to preserve it, make a snapshot manually in advance.
- **Choose version to restore** — `fzf` shows all snapshots with their changelogs. Selecting one overwrites the current file.
- **Delete to trash** — the snapshot is moved to `.cit/tr_cit/` preserving the path structure. This prevents irreversible deletion.
- **Restore from trash** — list of deleted snapshots with the ability to move them back to the main storage.
- **Empty trash** — permanently removes all snapshots from `.cit/tr_cit/`.

**Flag `-f` (finalize)** — builds a full changelog from all snapshots. All comments are collected into one block and inserted into the main file (after the shebang). A copy with the suffix `-F` and a separate log file with the full history are also created. This is useful for locking down a release version of a script.

All operations are available via the interactive `cit` menu or through `me cit` (if the method is registered).

---

## me create — Method Generator (Coming Soon)

People often ask: "how do I quickly add a new method?". Writing a block manually in `me.conf` takes 30 seconds, but it can be faster.

**`me create <name>`** will:

1. Ask for: description, example, internal or external script
2. Generate a block with meta-tags and a function stub
3. Insert it into `me.conf` (alphabetically or at a specified position)
4. If the method uses an external script — create a stub in `me_lib/`
5. Check the resulting config syntax

```
$ me create docker-ps
  Name: docker-ps
  Description: List running Docker containers
  Example: me docker-ps
  Type: [internal] external

  #@method: docker-ps
  #@description: List running Docker containers
  #@example: me docker-ps
  me_method_docker-ps() {
      docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  }

  Add to me.conf? [Y/n]
```

Not yet released — still polishing the question flow and positioning in the config. Will arrive in one of the upcoming commits.

---

## Scaling to a Fleet of Machines

`me` was initially designed for a single machine, but its architecture allows scaling to a fleet without rewriting code.

**Export and import of methods** is the key mechanism for this.

- `me share <method_name>` — packages the method, its meta‑tags, and all dependencies (scripts from `me_lib/`, configs) into a single `tar.gz` archive in `~/.local/bin/me/import/`. Inside is an `install.sh` that automatically registers the method in `me.conf` and copies files to the right places.
- `me import <method_name>` or `me import ./pkg.tar.gz` or `me import https://...` — installs the method on the current machine. If the method already exists, you're asked for confirmation to replace it.

**Scenario for a fleet:**

1. Create a set of methods on the master machine.
2. Run `me share` for each method — get an archive.
3. Distribute archives over the network (via shared folder, `scp`, `rsync`, or HTTP).
4. On each target machine, run `me import` with the path or URL.

This way, an administrator can roll out a unified set of commands to dozens of servers in minutes. Each admin can also extend `me.conf` locally — personal methods don't conflict with shared ones, because `me` loads methods from one config, and names are unique.

---

## Numbers

- **me (engine):** 244 lines of bash
- **me.conf (registry):** 416 lines, ~30 methods
- **Dependencies:** bash 4.0+, fzf, playerctl, ripgrep, ffmpeg (optional)
- **Installation:** `bash install_me.sh` → PATH, completion, me.conf
- **Empty me load time:** ~0.02 sec (cache in /dev/shm)
- **First method call time:** ~0.05 sec (bash -n + eval)
- **Disk usage:** < 150 KB for the entire project with libraries

---

## Why It's Just a Tool

me doesn't have:
- Dependency managers
- Languages other than bash
- Configuration formalisms (yaml/toml/json)
- Plugins (method == bash‑function)
- ORM, DI, middleware, etc.

me has:
- awk that extracts blocks from the config
- `bash -n` that checks syntax
- `/dev/shm` for cache
- md5sum for automatic invalidation

That's it. That's why it works — there's no layer between you and the terminal.

---

## When You Don't Need It

me does not:
- Replace man/info — complex tools have their own docs
- Automate things you do once a year
- Turn the terminal into a GUI

If you have 3 aliases and they work — me isn't needed. If you spend time recalling/googling/typing a command you use daily — me can remove that step.

**[SCREENSHOT: terminal_comparison.png]**
*Terminal window: left — a session without me (history search, grep .bashrc), right — me int (list of commands in a second).*

---

## Try It

Today, I can't imagine my work without me. It's become my second language for the terminal. If you feel the same pain — give it a try.

Installation takes 5 minutes:

```bash
bash ~/.local/bin/me/install_me.sh
source ~/.profile
me
```

Create one method — for playerctl, for brightness, for anything. Open `~/.config/me/me.conf`, add five lines:

```bash
#@method: hello
#@description: My first command
#@example: me hello
me_method_hello() {
    echo "Hello, terminal!"
}
```

Call it: `me hello`. If something goes wrong — the engine will tell you where and won't break anything else.

The terminal becomes comfortable. Not magically — just because the commands you use every day are right in front of you and they tell you what they do. Like the remote on an old tape recorder.

---

*me v3.5. License: GNU GPLv3. Dependencies: bash 4.0+, fzf, playerctl, ripgrep (optional), ffmpeg (optional).*