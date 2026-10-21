# App-codefork

Rewrites a directory tree for forking a codebase: it renames files and rewrites their
content, driven by a `fork.conf` with one rule per line — `from|to` (regex, names and
content), `from%to` (whole word, content only). Diff-first: bare `codefork` only
prints a unified diff, `codefork apply` writes, `codefork output file` saves the diff.

Released to CPAN as `App-codefork` (last release `1.000`, the diff-first rewrite),
built with `Dist::Zilla` via `[@Author::GETTY]`; the release also pushes the
`raudssus/codefork` Docker image. One Moo class (`App::codefork`) plus the thin
`codefork` script. Development happens on `main`; `master` is the 2014 history.

The architecture, the config format, the rule order and the traps live in skill
`app-codefork-core`; how an agent *uses* the CLI on another tree lives in skill
`codefork-usage` — neither is repeated here.

## Delegation

Delegate behavior-relevant code to the right agent instead of touching it yourself —
the principle and the lane boundaries are in `.claude/rules/app-codefork-rules.md`.

| Task | Agent |
|---|---|
| Implement / refactor / debug behavior-relevant code | `app-codefork-worker` (default) |
| Commits, `Changes`, card → done, pre-release audit | `app-codefork-release-manager` |

The agents carry their skills via `briefing.skills` (see `.claude/agents/`); the main
agent delegates rather than loading them. Skill sources live under `.claude/skills/` —
the `getty-*`, `perl-release-dist-ini` and karr skills are installed by skilletor
(`.claude/skilletor.json`); `app-codefork-core` and `codefork-usage` are owned by this
repo.

Work is coordinated on the repo's `karr` board (`karr board`).

## Build & test

```bash
prove -lr t/
dzil test
dzil build
```
