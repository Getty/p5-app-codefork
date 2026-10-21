# App::codefork

World's dumbest code forker.

Performs systematic text replacements across an entire directory tree — both
filenames and file contents. Intended for forking a codebase by renaming a
project, module, or namespace throughout.

## Safe by default

codefork does **not** modify files by default. It shows a unified diff of
what would change, so you can review before applying.

## Quick start with Docker

```bash
# Preview changes (fork.conf in current directory)
docker run --rm -v "$PWD:/work" raudssus/codefork

# Apply changes
docker run --rm -v "$PWD:/work" raudssus/codefork apply

# Save diff to file
docker run --rm -v "$PWD:/work" raudssus/codefork output patch.diff
```

## Install from CPAN

```bash
cpanm App::codefork
```

## Usage

```bash
# Preview changes (default config: fork.conf)
codefork

# Preview with a different config
codefork other.conf

# Apply changes
codefork apply
codefork apply other.conf

# Save diff to file (compatible with patch -p1)
codefork output patch.diff
codefork output other.conf patch.diff
```

## Config format

Create a `fork.conf` with one replacement rule per line:

```
HomeHive|AqHive
homehive|aqhive
hh%ah
```

- `from|to` — regex replacement (`s/from/to/g`) in filenames and contents
- `from%to` — whole-word replacement in contents only (matches only where no letter or digit comes directly before or after it; the start and end of a file count as a boundary)

## Debug

```bash
CODEFORK_DEBUG=1 codefork

# or with Docker
docker run --rm -e CODEFORK_DEBUG=1 -v "$PWD:/work" raudssus/codefork
```

## Build Docker image locally

```bash
docker build -t codefork .
```

## Upgrade from pre-1.000

The old `--config`, `--dir`, and `--debug` flags are gone. Use positional
commands instead:

```bash
# Old (no longer works):
codefork --config fork.conf --debug

# New:
CODEFORK_DEBUG=1 codefork fork.conf
```
