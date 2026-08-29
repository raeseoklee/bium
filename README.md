# bium

Reclaims disk space on a Mac — counts hard links once, never guesses, and tells you
which directories it was not allowed to read instead of reporting them as empty.

No dependencies. Builds with the Command Line Tools and Swift 6.1; Xcode not required.

```sh
bium scan             # survey only, deletes nothing
bium clean --dry-run  # preview what would be removed
bium clean            # SAFE level only, moved to the Trash
bium empty-trash      # this is where the space actually comes back
```

## The name

**비움 (bium)** is Korean for *emptying* — the act of making something empty, not
the state of being empty.

It was chosen over the obvious options on purpose. "Mac Cleaner", "Mac Optimizer"
and their variants are the naming pattern of macOS scareware: tools that invent
problems to sell a fix. A utility whose entire design is about *not* overstating
what it found should not wear that badge.

Pronounced roughly *bee-oom*.

## Why another one of these

The category is crowded. Three things here are unusual:

**It tells you what it could not see.** macOS gates `~/.Trash`, Safari's cache and
iOS backups behind Full Disk Access, and a denied read is indistinguishable from an
empty directory through the normal APIs. Most tools silently report zero. `bium`
reports the directory as unreadable, with the reason:

```
4 rule(s) not scanned:
  trash          unreadable (needs Full Disk Access): /Users/you/.Trash
  safari-cache   unreadable (needs Full Disk Access): /Users/you/Library/Caches/com.apple.Safari
```

Telling you the space is already gone when it is not is worse than not looking.

**The numbers are real.** Sizes come from allocated blocks, not logical file size,
and hard links are counted once. pnpm stores and Homebrew cellars are mostly hard
links, so a naive walk reports several times the space you would actually get back.

**It uses the editor's own records, not heuristics.** For stale editor extensions it
reads `extensions.json` — the editor's authoritative list of what is installed — and
offers everything else. On the machine it was written for, `~/.vscode/extensions`
held 145 directories and only 45 were installed.

## Safety levels

`clean` only ever touches SAFE by default. Going further requires `--level`.

| Level | Meaning | Examples |
|---|---|---|
| `SAFE` | The machine makes these again. Costs time, never data. | build caches, unregistered editor extensions, browser caches |
| `REVIEW` | Almost certainly disposable, but the contents vary per person. | model weight caches, superseded IDE settings, pnpm store |
| `CAUTION` | Real user data, or expensive to rebuild. Only removed if you name the rule. | iPhone backups, old downloads, the Docker disk image |

Removal goes to the Trash by default, so it stays reversible until you run
`empty-trash`. `--permanent` skips the Trash and cannot be undone. Every real
deletion is recorded as JSON under `~/Library/Application Support/bium/logs/`.

## Guardrails

Paths are re-validated immediately before deletion — not at scan time. A symlink
that changed in between, a hand-written `--only` path, or a bug in a rule is caught
here.

- Nothing outside your home directory. System areas such as `/Library/Caches` need
  root and are deliberately out of scope.
- `~`, `~/Library`, `~/Documents`, `~/.ssh` and friends are never removed themselves.
- Directories named `.git`, `.hg` or `.svn` are never removed, wherever they sit.
- A candidate may not escape the root its rule declared, including via a symlink —
  the parent path is resolved to check.
- Mount points (external drives, network volumes) are skipped.

## Language

English by default. Korean when `LANG`/`LC_ALL` starts with `ko`, or set
`BIUM_LANG=ko` to override just this tool. An unrecognised locale falls back to
English rather than producing a half-translated screen.

## Delegated actions

Some things are safer handed to the tool that owns them than deleted as files.
These appear in the scan marked `▸`.

| Rule | Runs |
|---|---|
| `action-tm-snapshots` | `tmutil thinlocalsnapshots` — APFS local snapshots, the most common reason space does not show up as available |
| `action-simctl-unavailable` | `xcrun simctl delete unavailable` |
| `action-brew-cleanup` | `brew cleanup --prune=all` |
| `action-docker-prune` | `docker system prune -a` |

If the command is not installed, the rule is reported as not scanned rather than
quietly dropped.

## Full Disk Access

Reading `~/.Trash`, Safari caches and iOS backups requires Full Disk Access. Grant it
under **System Settings → Privacy & Security → Full Disk Access**, or just empty the
Trash in Finder. Either way `bium` will say which locations it skipped and why.

## Common questions

**Why does my Mac still say the disk is full after I deleted things?**
Usually APFS local snapshots, which hold space that does not appear as available.
`bium doctor` reports it; `bium clean --only action-tm-snapshots --level review`
hands the thinning to `tmutil`.

**Is it safe to delete `~/Library/Developer/Xcode/DerivedData`?**
Yes — it is intermediate build output and indexes. The next build is slower once.
It is a SAFE rule here.

**Why is `~/.vscode/extensions` so large?**
VS Code does not always remove the previous version when an extension updates, and
interrupted installs leave UUID-named staging folders. `bium` compares the folder
against `extensions.json` and offers only what the editor no longer references.

**Will `brew cleanup` really free what it says?**
Homebrew's own estimate is used, but `bium` measures with hard links counted once,
so the figure it shows is what `df` will actually change by.

## Usage

```sh
bium scan -v                    # show every path
bium scan --deep                # also walk project trees for stale node_modules (slow)
bium doctor                     # disk state + largest directories in $HOME
bium list                       # every rule and its safety level

bium clean --level review       # include REVIEW
bium clean --only npm-cache,gradle-cache
bium clean --exclude trash
bium scan --json                # machine-readable
```

Rule ids are stable and English in every locale, so `--only`/`--exclude` and the
JSON output are safe to script against.

## Building

```sh
swift build -c release
swift run bium-tests            # 384 checks
./Scripts/install.sh            # installs to ~/.local/bin
```

Tests are a plain executable rather than a `.testTarget`: XCTest and swift-testing
both ship inside Xcode, so on a Command Line Tools-only machine that route cannot
run at all.

## What this does not do

- Touch anything outside `$HOME`. `/Library`, `/Applications` and `/opt/homebrew`
  need root; `doctor` reports their size and stops there.
- Find duplicate files, or browse large files.
- Uninstall applications.
- Move anything to iCloud. macOS's own "Optimize Storage" does that; `bium` deletes.

## Korean

[README.ko.md](README.ko.md)
