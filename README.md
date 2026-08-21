# password-store-strict

A fork of [password-store](https://www.passwordstore.org/) (`pass`) by Jason A.
Donenfeld, with **one behavioural change**: the implicit `show` shorthand is
refused. Everything else — the store format, the GPG handling, the completions,
`passmenu` — is upstream's, unmodified.

Upstream's own `README`, man page and `COPYING` are kept in the tree. Licence is
unchanged: **GPL-2.0-or-later**.

```console
$ pass ls                       # unchanged
$ pass show svc/token           # unchanged
$ pass svc/token
pass: refusing the implicit "show" shorthand.

Write the subcommand explicitly:

    pass show svc/token
```

## Why

In upstream `pass`, `show` is the **default** subcommand. So `pass svc/token`
prints that credential with no keyword naming the action, and the consequence is
structural:

| | |
|---|---|
| **safe** operations | a small **closed** set — `ls`, `find`, `help`, `version` |
| **dangerous** operation | `pass <any entry path>` — an **open** set |

No prefix pattern separates an entry path from a subcommand, because an entry
path can be any string. That has two costs.

**For a human**, a distracted `pass gitlab/deploy-token` prints a live secret to
the terminal, and shell history records something that reads like a path rather
than a credential read.

**For a machine**, it means an allowlist cannot be written. If you share a shell
with an LLM coding agent, you may want name listings to run freely while any
secret read stops for confirmation — and with an open dangerous set there is no
pattern that expresses that. You are left gating *every* `pass` invocation,
including the harmless ones.

This fork closes the set. After it, every read of a secret carries the `show`
keyword, so `pass show` is greppable in history and matchable by a rule.

## The change

One function, `cmd_extension_or_show` in `src/password-store.sh`. The extension
lookup still runs first and is untouched; only the show fallback is replaced, and
the refusal exits non-zero so a caller can branch on it.

Two forms stop working, both with the same fix — add `show`:

| Before | After |
|---|---|
| `pass svc/token` | `pass show svc/token` |
| `pass -c svc/token` | `pass show -c svc/token` |

## Using it with Claude Code permissions

This is what the fork was built for. With the closed subcommand set, a rule can
distinguish a name listing from a secret read:

```json
{
  "permissions": {
    "allow": [
      "Bash(pass)",
      "Bash(pass ls *)",
      "Bash(pass find *)",
      "Bash(pass help)",
      "Bash(pass version)"
    ],
    "ask": [
      "Bash(pass show *)",
      "Bash(pass grep *)",
      "Bash(pass insert *)",
      "Bash(pass edit *)",
      "Bash(pass generate *)",
      "Bash(pass rm *)",
      "Bash(pass mv *)",
      "Bash(pass cp *)",
      "Bash(pass git *)",
      "Bash(pass init *)"
    ]
  }
}
```

⚠️ **`pass grep` belongs in `ask`, not `allow`.** It is one character from
`find`, and it *decrypts every entry* to search their contents.

### Why enumerating subcommands is sound here, and is not on upstream

The list above does not need to be complete, and that is the whole point of the
fork. Anything it misses — a typo, an unknown subcommand, a bare entry path —
now hits the refusal and exits non-zero. **The residual of the enumeration is a
loud failure, not a printed credential.**

On upstream `pass` the same list would be unsound: the residual there is `show`,
so a single omission is a silent secret read. That is why a blanket rule over
every `pass` invocation is the only safe option without this change.

### Two things worth knowing about the rules

Both were measured rather than assumed, on Claude Code 2.1.231:

- **`ask` beats `allow`.** Rules evaluate deny → ask → allow, first match wins,
  and *specificity does not change that order*. A blanket `Bash(pass *)` in `ask`
  therefore cannot be carved out by adding a narrower `allow` rule — nor by a
  `PreToolUse` hook returning `allow`, which loses to an `ask` rule the same way.
  Narrowing the `ask` list, as above, is what works.
- **Rules match inside compound commands.** `pass ls; pass show svc/token` is
  refused: the matcher inspects sub-commands, so the second one hits
  `Bash(pass show *)` even though the command *begins* with an allowed form.

## Installing

`PKGBUILD` in this repo builds an Arch package that **replaces** `pass`:

```console
$ makepkg -si
```

It is named `pass-strict` with `conflicts=('pass')`, deliberately:

- **Replaces** rather than installing alongside, because leaving the unpatched
  binary reachable at a known absolute path makes the whole thing advisory.
- **Not named `pass`**, because a locally built package sharing a repository
  package's name is silently replaced by the repo version on the next
  `pacman -Syu`, with nothing in the output distinguishing it from any other
  upgrade. A `conflicts` entry is a structural block; an `IgnorePkg` line is a
  config entry that can be edited away or lost in a `pacman.conf.pacnew` merge.

Its file list is matched against `pacman -Ql pass`, so `passmenu`, the bash, zsh
and fish completions and `redact_pass.vim` are all still installed.

### Rolling back

```console
$ sudo pacman -S pass          # offers to remove pass-strict
```

Offline, from the package cache:

```console
$ sudo pacman -U /var/cache/pacman/pkg/pass-1.7.4-7-any.pkg.tar.zst
```

## Staying in sync with upstream

`upstream` points at `https://git.zx2c4.com/password-store`. Because the change
is a commit rather than a patch file, a conflict during a merge is a normal git
conflict in one function, not a patch that mysteriously stops applying:

```console
$ git fetch upstream
$ git merge <new upstream tag>
```

## Testing without touching a real store

`ls` and `find` walk the directory tree and never decrypt, so a fixture needs no
GPG key at all:

```console
$ D=$(mktemp -d); mkdir -p "$D/svc"; echo 0 > "$D/.gpg-id"; : > "$D/svc/token.gpg"
$ PASSWORD_STORE_DIR="$D" pass ls              # lists svc/token
$ PASSWORD_STORE_DIR="$D" pass svc/token       # refused, exit 1
$ PASSWORD_STORE_DIR="$D" pass show svc/token  # reaches gpg, leaks nothing
```
