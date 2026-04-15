# CLAUDE.md

Guidance for Claude Code when working on **App::codefork** (`codefork` CLI).

## What the app does

Systematic text replacements across a directory tree — both filenames and
file contents. Intended for forking a codebase by renaming a project,
module, or namespace.

**Safe by default**: without arguments it only prints a diff preview, no writes.

## Architecture (short)

- `lib/App/codefork.pm` — Moo class, all the logic
  - `collect_changes` → plans changes (pure computation)
  - `generate_diff` → unified diff from the collected changes
  - `apply_changes` → writes to disk
  - `run(@ARGV)` → CLI entry, dispatches `diff` / `apply` / `output`
- `bin/codefork` — thin wrapper calling `App::codefork->run(@ARGV)`
- `eg/conf` — example config

## Config format (`fork.conf`)

- `from|to` — regex replacement (`s/from/to/g`) in filenames and contents
- `from%to` — word-boundary replacement (only between non-alphanumeric chars)
- Empty lines and lines without `|`/`%` are ignored

## Rules when changing code

- **Do not break the diff-based workflow**: `collect_changes` must return
  changes as data structures before anything touches disk.
- **`.git` / `.svn` stay excluded** (see `_collect_dir`).
- **Debug** goes through `CODEFORK_DEBUG=1`, not flags.
- **No new CLI flags**: the interface is positional
  (`codefork [apply|output] [conf] [file]`). Pre-1.000 `--config`/`--dir`/`--debug`
  were removed on purpose.

## Build & test

```bash
prove -lv t/             # tests (load.t, basic.t)
dzil test                # full Dist::Zilla test run
dzil build               # build distribution
```

Releases use `[@Author::GETTY]` — see that bundle for version/Changes conventions.

## POD convention

Inline `=attr` / `=method` right next to the attribute/method definition
(as already done in `codefork.pm`). Don't collect them at the end of the file.
