---
name: app-codefork-core
description: "Load before editing App-codefork — the Moo CLI that rewrites file names and file contents in a directory tree with a diff-first workflow: the config format with the pipe and percent rules, the plan/diff/apply split, the positional CLI, the rule order, and the byte-level traps."
---

# App::codefork — core

A command line tool that rewrites a directory tree: it renames files and directories
and rewrites their content, driven by a config file that lists the rewrites. Since
1.000 (2026-03-06) it is **diff-first**: by default it only prints what it would
change.

| File | Role |
|---|---|
| `lib/App/codefork.pm` | the whole implementation — one Moo class: config parsing, planning, diff, apply, the CLI dispatch `run` |
| `bin/codefork` | thin wrapper: `App::codefork->run(@ARGV)`, plus the user POD |
| `t/*.t` | load test; plan/diff/apply (`basic`), collisions, directories, the word rule, the output file, the config parsing, the CLI `run` — each on its own temp tree |
| `eg/conf` | the sample config |
| `Dockerfile`, `docker-release.sh`, `.dockerignore` | the `raudssus/codefork` image, pushed by `[Run::AfterRelease]` after a CPAN release — pruned from the tarball |
| `.claude/skills/codefork-usage` | how an agent *uses* the CLI on another tree — not about this code |

## The config format

One rule per line, split at the first separator (`split …, 2`, so `a|b|c` is
`a` → `b|c`). A line with `|` is a replace rule even if it also holds `%`. Empty lines
and lines with neither separator are ignored — there is no comment syntax, `# x` is
only skipped because it has no separator.

| Rule | Kind | Applies to | Match |
|---|---|---|---|
| `from\|to` | `replace` | names and content | `from` is **regex source** (`s/$from/$to/g`), documented as such since 1.000 — a contract, not a bug. `to` is a plain string, no `$1` |
| `from%to` | `word` | content only | `from` only between non-alphanumeric characters (`hh` never inside `ohhh`) |

## The contract

1. **Plan** — `collect_changes` walks `dir` (absolute, `.` by default) sorted, skips
   `.git` and `.svn`, and returns change hashrefs (`old_path`, `new_path`,
   `old_content`, `new_content`; paths relative to `dir`). Nothing touches disk.
   The plan is checked before it is returned: a new path that already exists and is
   not renamed away, a new path two changes share, a new path below an existing file
   that is not renamed away or below another change's new path, or a cycle of renames
   is refused with a croak — the run writes nothing. The walk skips the config file
   itself (same real path as `config`), so it is never part of a change.
2. **Names**: every replace rule, top to bottom, each on the output of the previous
   one; a directory's new name becomes the prefix of every path below it.
3. **Content**: every rule, top to bottom, on the raw bytes. A file is a change when
   its path or its content differs; an empty directory whose path changes is a change
   with empty content on both sides.
4. **Diff** — `generate_diff` renders a unified diff (Text::Diff), with
   `rename from/to` headers for renamed files.
5. **Apply** — `apply_changes` checks the plan again and writes it in an order that
   moves the file or directory in a new path's way, or in its parent chain, first.
   New content goes into the existing inode (open read-write, truncate, write) after
   the old content is copied to a 0600 `.codefork-*` backup next to the file; the
   backup is removed on success, on failure the content is restored from it and apply
   croaks naming it. A rename is always a move, so owner, group, mode, hard links,
   ACLs and xattrs stay. A directory created for a rename takes the mode, and as far
   as permitted the owner and group, of the directory it replaces. Directories the
   renames left empty are removed afterwards, deepest first. Returns the number of
   changes. The plan refuses a file whose content changes but which is not writable.
6. **CLI** — `run(@ARGV)`, positional: `codefork [conf]` (diff, default `fork.conf`),
   `codefork apply [conf]`, `codefork output [conf] file`. It works on the cwd. Debug
   is `CODEFORK_DEBUG=1` to STDERR. `run` prints a refused plan without the croak's file and
   line and dies non-zero; the library methods keep croaking with the location. The pre-1.000 `--config`/`--dir`/`--debug`
   flags were removed on purpose — no new flags.

The plan/apply split is the product: every check that can refuse a run belongs in the
plan, before a single byte is written.

## Traps

- **Bytes, not characters.** Content is read with `slurp_raw` and written with
  `spew_raw`; the diff is therefore a byte string. Any `_utf8` read or write in this
  path double-encodes non-ASCII content.
- **Files are the unit.** A non-empty directory is renamed only implicitly, through
  the paths of the files below it; an emptied old directory is cleaned up after the
  apply, one that still holds something (e.g. a skipped `.git`) stays.
- **`run` works on the cwd.** A test of `run` must chdir into its own temp tree and
  back — never run it, or point `dir`, at the repository.

Open defects are cards on the karr board, not paragraphs here.

## Tests

Test files are numbered `NN-name.t`, as in the sibling distributions.
`t/01-basic.t` builds a temp tree with `Path::Tiny->tempdir`, keeps the config in a
second temp dir, and asserts plan, diff and apply. Every new test does the same —
the tool rewrites files in place.

## Distribution conventions

- `[@Author::GETTY]`; POD uses the inline `=attr` / `=method` commands next to the
  definition, not collected at the end. The bundle generates `SUPPORT`, `AUTHOR` and
  `COPYRIGHT`.
- Moo only; requirements `Moo`, `Path::Tiny`, `Text::Diff`.
- Every file under `lib/` and `bin/` carries `our $VERSION`, the next unreleased
  version — `1.001` after the `1.000` release.
- `bin/codefork` is a plain wrapper with no `FindBin`/`use lib`; from a checkout it
  runs as `perl -Ilib bin/codefork`, and the Docker image passes `-I/app/lib`.
