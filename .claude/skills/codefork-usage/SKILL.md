---
name: codefork Usage
description: Drive the codefork CLI to rename a project/module/namespace across a directory tree via diff-first workflow
trigger: when the user asks to fork, rename, or rebrand a codebase (filenames + contents), or mentions codefork / fork.conf
category: tool
---

# codefork — AI usage guide

`codefork` performs systematic text replacements across a directory tree,
in **both filenames and file contents**. Use it when the user wants to
fork/rename a project, module, or namespace.

## Golden rule: diff first, apply second

Never run `codefork apply` without showing the diff first. The tool is
designed around that: bare `codefork` only previews.

## Workflow

1. **Write `fork.conf`** in the target directory (one rule per line).
2. **Preview**: `codefork` (or `codefork other.conf`) → unified diff to STDOUT.
3. **Review with the user**. Save to file if large: `codefork output patch.diff`.
4. **Apply** only after confirmation: `codefork apply`.

## Config rules

Two rule types, one per line:

- `from|to` — regex, applied as `s/from/to/g` to filenames and contents.
  Use for CamelCase, snake_case, and any pattern where you want greedy
  substring replacement.
- `from%to` — **word-boundary** replacement. Only matches when `from` is
  surrounded by non-alphanumeric characters. Use for short tokens that
  would otherwise collide (e.g. `hh` inside `ohhh`).

Empty lines and lines without `|` or `%` are ignored (handy for comments —
but note: there is no real comment syntax, a line like `# foo` is only
ignored because it has no separator).

## Ordering matters

Rules apply top-to-bottom, and each rule sees the output of the previous
one. Put more specific rules first:

```
# good — specific before general
HomeHiveAPI|AqHiveAPI
HomeHive|AqHive
homehive|aqhive
```

If the general rule ran first, `HomeHiveAPI` would already be mangled.

## Case variants

Typical rename needs 2–3 lines covering the case conventions actually used:

```
HomeHive|AqHive       # CamelCase (classes, modules)
homehive|aqhive       # lowercase (filenames, package paths, URLs)
HOME_HIVE|AQ_HIVE     # SCREAMING_SNAKE (env vars, constants)
```

Grep the target tree before writing `fork.conf` to see which variants
actually appear — don't add rules for cases that aren't used.

## Short tokens: prefer `%`

For 2–3 character tokens, `|` almost always over-matches. Use `%`:

```
hh%ah      # matches " hh." but not "ohhh"
```

## What codefork skips

`.git` and `.svn` directories are excluded. Everything else — including
binary files — is processed. If the target tree has build artifacts,
caches, or `node_modules`, clean them before running or the diff will
be huge and slow.

## Debug

`CODEFORK_DEBUG=1 codefork` prints the parsed rules and `modify:` /
`rename:` lines to STDERR. Use when a rule silently doesn't match.

## Common commands

```bash
codefork                         # preview with default fork.conf
codefork other.conf              # preview with alternate config
codefork output patch.diff       # write diff to file (patch -p1 compatible)
codefork output other.conf patch.diff
codefork apply                   # apply fork.conf
codefork apply other.conf        # apply alternate config
```

## Recovery

codefork has no built-in undo. If the target tree is a git repo, commit
before applying — then `git reset --hard` is your undo. If it isn't,
stop and tell the user to back up first.

## When NOT to use codefork

- Semantic refactors (extract method, rename a single variable in one
  file) — use a normal editor or a language-aware tool.
- Renames where context matters (e.g. rename only in one submodule) —
  codefork is whole-tree and context-free.
- Anything requiring AST understanding.

codefork is deliberately dumb. That's the feature.
