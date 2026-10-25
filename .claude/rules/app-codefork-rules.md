# App-codefork House Rules

The shared house rules come from skilletor — bundle `getty-cpan-dist@getty`: engineering
discipline, the delegation lock, the publish gate, karr coordination, CPAN release. They load
as `.claude/rules/.local.*.md`; if they are missing, run `skilletor sync` and publish nothing
until they load. This file adds what is true only here, and wins where it differs.

## What this repo is

Worlds dumbest code forker — one class (`App::codefork`) and one script (`bin/codefork`).
Contract: skill `app-codefork-core`.

## Agent team

| Task | Agent |
|---|---|
| Implement / refactor / debug behavior-relevant code | `app-codefork-worker` (default) |
| Commits, `Changes`, card → done, pre-release audit | `app-codefork-release-manager` |
| Read-only research, audit, gap analysis | `app-codefork-worker` ("read-only, change nothing") |

Behavior-relevant = anything in `lib/`, in `bin/`, the tests, the config format, the rule order
and the CLI. `README.md` and `Changes` wording are not.

## Release

The release also pushes the `raudssus/codefork` Docker image (`[Run::AfterRelease]`) — one
more reason it waits for the maintainer's go-ahead.

## Deviations from the house rules

- A topic raised on the public GitHub tracker becomes an internal karr card; the issue itself
  stays untouched.

## Hazards

- **Config format, rule order and diff-first are the product — don't regress them.** One rule
  per line: `from|to` (regex) in names and content, `from%to` (whole word) in content only;
  every rule applies, top to bottom. Nothing touches disk before the plan is complete, and the
  CLI is positional. A change to any of that is user-visible: it needs a `Changes` entry and a
  test.
- **A test needs its own temp tree** and must never point the tool at the repository.
- **One class and one script.** A second dependency, a second entry point or a plugin system
  needs a card that asks for it.

## Perl specifics — reference, don't restate

Object-system rules live in skill `getty-perl-moo` — this distribution is Moo, not Moose.
Module loading, cpanfile pinning, per-file version declarations, POD conventions and house
style live in `getty-perl-core`, `getty-perl-pod` and `getty-perl-release-author-getty`. The
config format, the rule order and the traps live in skill `app-codefork-core`.
