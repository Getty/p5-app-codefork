# codefork

[![CPAN](https://img.shields.io/cpan/v/App-codefork)](https://metacpan.org/dist/App-codefork)
[![CI](https://github.com/Getty/p5-app-codefork/actions/workflows/ci.yml/badge.svg)](https://github.com/Getty/p5-app-codefork/actions/workflows/ci.yml)
[![Docker](https://img.shields.io/docker/v/raudssus/codefork?label=docker&sort=semver)](https://hub.docker.com/r/raudssus/codefork)

**The world's dumbest code forker.** Rename a project, a module or a namespace
across a whole directory tree, in the file names *and* in the file contents,
with a three-line config file. You see the full diff first. Nothing is
written until you say `apply`.

```
HomeHive|AqHive
homehive|aqhive
hh%ah
```

That is the whole config. It knows nothing about syntax or ASTs. It does
search and replace over a tree, and it does that carefully.

## See it

Here is a small Perl project called `HomeHive`, with the `fork.conf` above
next to it:

```
lib/HomeHive.pm
lib/HomeHive/Config.pm
bin/homehive
fork.conf
```

Running bare `codefork` shows what would happen and touches nothing:

```diff
$ codefork
rename from lib/HomeHive.pm
rename to lib/AqHive.pm
--- a/lib/HomeHive.pm
+++ b/lib/AqHive.pm
@@ -1,4 +1,4 @@
-package HomeHive;
-# The homehive core
-my $hh = HomeHive::Config->new;
+package AqHive;
+# The aqhive core
+my $ah = AqHive::Config->new;
 1;
rename from lib/HomeHive/Config.pm
rename to lib/AqHive/Config.pm
...
```

`apply` writes it:

```
$ codefork apply
Applied 3 change(s).
```

```
lib/AqHive.pm
lib/AqHive/Config.pm
bin/aqhive            # still executable
fork.conf             # untouched: the config never rewrites itself
```

## Install

```bash
cpanm App::codefork
```

You can also skip installing and run the Docker image. It mounts the current
directory as the tree to fork:

```bash
docker run --rm -v "$PWD:/work" raudssus/codefork          # diff
docker run --rm -v "$PWD:/work" raudssus/codefork apply    # write
```

## Usage

```bash
codefork                              # show the diff, using ./fork.conf
codefork other.conf                   # show the diff, using another config
codefork apply [other.conf]           # write the changes
codefork output [other.conf] my.diff  # save the diff, for review or patch -p1
CODEFORK_DEBUG=1 codefork             # parsed rules and every step on STDERR
```

codefork works on the current directory and everything below it, except
`.git` and `.svn`.

## The config

One rule per line, and there are two kinds:

| Rule | What it does | Where |
|---|---|---|
| `from\|to` | replaces every match of `from` with `to`. `from` is a Perl regex | file names **and** contents |
| `from%to` | replaces `from` only as a whole word: no letter or digit may directly precede or follow it | contents only |

- **Rules run top to bottom.** Each rule sees the output of the one before
  it, so put the specific rules first (`HomeHiveAPI|AqHiveAPI` before
  `HomeHive|AqHive`).
- **Cover each spelling** your code actually uses: `HomeHive` for packages,
  `homehive` for files and URLs, `HOME_HIVE` for constants. Grep first, then
  write only the rules you need.
- **Use `%` for short tokens.** With `hh%ah`, `my $hh` becomes `my $ah`, and
  `ohhh` stays as it is. The start and the end of a file count as word
  boundaries.
- **`from` is a regex.** A `.` matches any character, so write `\.` when you
  mean a literal dot. `to` is plain text.
- Empty lines and lines without `|` or `%` are ignored.

## Safe by design

codefork plans every change before it writes the first byte. If the plan
would lose something, it refuses and writes nothing:

```
$ codefork
App::codefork refuses the plan, nothing was written:
  B.txt (from A.txt) already exists
```

- **Nothing is overwritten.** A rename onto an existing file is refused. So
  are two files that would get the same name, renames that form a cycle,
  and a new path that needs a directory where a file already is.
- **Rename chains work.** When one rename frees a path for another, they run
  in a safe order.
- **The config stays put.** `fork.conf` inside the tree is never rewritten or
  renamed.
- **Files stay the same files.** New content is written into the existing
  file, so owner, group, mode and hard links are kept, even when codefork
  runs as root in Docker. Executables stay executable and private files stay
  private.
- **Bytes stay bytes.** Contents are never decoded or re-encoded, so UTF-8,
  Latin-1 and binary files come out exactly as they went in, apart from your
  replacements.
- **Directories follow.** Old directories that a rename leaves empty are
  removed, and an empty directory whose name matches a rule is renamed.

codefork has no undo. Commit before you `apply`, and `git reset --hard` is
your undo.

## From Perl

```perl
use App::codefork;

my $fork    = App::codefork->new( config => 'fork.conf', dir => 'path/to/tree' );
my $changes = $fork->collect_changes;   # the plan, nothing touched yet
print $fork->generate_diff($changes);   # unified diff
$fork->apply_changes($changes);         # write it
```

## Upgrading from 0.001

Version 1.000 replaced the old option-based CLI. `--config`, `--dir` and
`--debug` are gone:

```bash
codefork --config fork.conf --debug   # 0.001
CODEFORK_DEBUG=1 codefork fork.conf    # 1.000 and later
```

## Copyright

Copyright (C) 2014–2026 Torsten Raudssus. This is free software; you can
redistribute it and/or modify it under the same terms as the Perl 5
programming language system itself.
