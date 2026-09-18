# password-store-strict

A fork of [password-store](https://www.passwordstore.org/) (`pass`) by Jason A.
Donenfeld, with **three behavioural changes**, all closing the same hole from
different sides — *no invocation may read a secret without a keyword naming the
action*:

1. the implicit `show` shorthand is refused, so `pass <entry>` does not print;
2. `ls` and `list` refuse a leaf, so a listing spelling cannot decrypt;
3. extensions require the explicit `ext` keyword, so an installed extension
   cannot add an unknown spelling that reads.

Everything else — the store format, the GPG handling, the completions,
`passmenu` — is upstream's, unmodified.

Upstream's own `README`, man page and `COPYING` are kept in the tree. Licence is
unchanged: **GPL-2.0-or-later**.

```console
$ pass ls                       # unchanged — lists names
$ pass ls svc/                  # unchanged — lists names under a directory
$ pass show svc/token           # unchanged — reads the secret

$ pass svc/token
pass: refusing the implicit "show" shorthand.

Write the subcommand explicitly:

    pass show svc/token

$ pass ls svc/token
pass: "ls" lists names; it does not read secrets.

    pass show svc/token

$ pass otp svc/token            # even with pass-otp installed
pass: refusing the implicit "show" shorthand.
...
    pass ext otp svc/token
```

Bare `pass` still lists the whole store, as upstream does.

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

That table is also only half the problem, and the half that is easy to miss:
**`ls` is in the safe column because of what it is named, not because of what it
does.** Upstream routes `show`, `ls` and `list` to one function, which decrypts
whenever the path resolves to a file — so `pass ls svc/token` is a full read
wearing a listing's name, and a rule that allows listings while gating reads has
separated nothing. Change 2 is what makes the safe column true.

Together the two changes close the set. After them, every read of a secret
carries the `show` keyword, so `pass show` is greppable in history and matchable
by a rule — and `ls` means what it says.

## The changes

Both are in `src/password-store.sh`.

**1 — the implicit shorthand.** One function, `cmd_extension_or_show`. The
extension lookup still runs first and is untouched; only the show fallback is
replaced, and the refusal exits non-zero so a caller can branch on it.

| Before | After |
|---|---|
| `pass svc/token` | `pass show svc/token` |
| `pass -c svc/token` | `pass show -c svc/token` |

**2 — the listing spellings.** The dispatcher sets `LISTING_ONLY=1` for `ls` and
`list` before calling `cmd_show`, and `cmd_show`'s file branch refuses when it is
set, naming `show` as the replacement. Directory listings and bare `pass ls` are
untouched.

| Before | After |
|---|---|
| `pass ls svc/token` (decrypted) | `pass show svc/token` |
| `pass list svc/token` (decrypted) | `pass show svc/token` |

Two details of that second change are load-bearing:

- the guard sits **inside `cmd_show`**, not in a parallel `cmd_list`, so the
  `getopt` block above it is not duplicated — a second copy would drift, and the
  drift would be silent;
- `LISTING_ONLY=0` is initialised at the dispatcher rather than left unset,
  because an unset variable tests false and would reopen the hole for any future
  caller reaching `cmd_show` by another route.

**3 — extensions.** Upstream's fallback ran the extension lookup *first* and
`show` second, so `pass <name>` executed an extension whenever one existed. An
extension is arbitrary code that may print a secret, and its **name is not
knowable to whoever writes the permission rules** — there is no set to
enumerate. The fallback now refuses; `pass ext <name>` is the explicit spelling,
and an unknown name fails loudly there rather than reaching a read.

The case that motivates it is easy to miss: an extension under the **system**
extension directory (`/usr/lib/password-store/extensions`) runs even when
`PASSWORD_STORE_ENABLE_EXTENSIONS` is unset, because that variable gates only
the per-store directory. So installing a package such as `pass-otp` silently
added a spelling that reads a secret, carried no keyword, and matched no rule —
and nothing about the config looked any different afterwards.

| Before | After |
|---|---|
| `pass otp svc/token` | `pass ext otp svc/token` |

**Bare `pass` was also restored.** With no argument the path is empty, so
`cmd_show` can only reach its directory branch — it is a listing and nothing
else. Change 1 had swept it into the refusal, which bought no safety and broke
upstream's most common invocation.

### What the earlier releases got wrong

Worth stating plainly, because the fix is only meaningful next to it. Tag
`1.7.4-strict1` shipped change 1 alone and claimed — in this README, and in the
program's own refusal message — that *every read of a secret carries the `show`
keyword*. That was false for a month: `pass ls svc/token` and
`pass list svc/token` both still decrypted.

Change 2, in `1.7.4-strict2`, closed that. But strict2 was not the end either:
an audit of the same question — *which spellings reach plaintext without a
keyword?* — then found the extension fallback, which is the same shape again and
was measured to print with `PASSWORD_STORE_ENABLE_EXTENSIONS` unset. Change 3,
in `1.7.4-strict3`, closes it.

Two lessons, neither of them about `pass`:

- **The claim lived in two places and both were wrong in the same way** — this
  README and the program's own refusal message. Fixing either alone would have
  left the other asserting it. If you audit this fork, audit the refusal
  messages against the code, not against this file.
- **Two of the three holes were invisible because nothing about the
  configuration changed.** `ls` was already in an allowlist; the system
  extension directory is empty until some package fills it. A guard whose
  absence looks identical to its presence needs a behavioural test, which is why
  each change here has one (`tests/t0020`–`t0022`).

## Using it with Claude Code permissions

This is what the fork was built for. With the closed subcommand set, a rule can
distinguish a name listing from a secret read:

```json
{
  "permissions": {
    "allow": [
      "Bash(pass)",
      "Bash(pass ls *)",
      "Bash(pass list *)",
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
      "Bash(pass init *)",
      "Bash(pass ext *)"
    ]
  }
}
```

**`pass grep` belongs in `ask`, not `allow`.** It is one character from `find`,
and it *decrypts every entry* to search their contents.

**`list` needs its own entry.** It is an alias of `ls`, and a rule matching
`pass ls *` does not match `pass list *`. Leaving it out is not dangerous here —
the residual is the refusal, not a read — but it is a prompt you did not intend.

**`pass ext *` belongs in `ask`, whatever the extension does.** It is the one
subcommand whose behaviour this repository does not control.

### Why enumerating subcommands is sound here, and is not on upstream

The list above does not need to be complete, and that is the whole point of the
fork. Anything it misses — a typo, an unknown subcommand, a bare entry path, the
name of an installed extension — now hits the refusal and exits non-zero. **The
residual of the enumeration is a loud failure, not a printed credential.**

That sentence was false in `strict1` (via `ls`) and again in `strict2` (via
extensions). It is worth re-testing rather than trusting, which is what
`tests/t0021` and `tests/t0022` are for.

On upstream `pass` the same list would be unsound: the residual there is `show`,
so a single omission is a silent secret read. That is why a blanket rule over
every `pass` invocation is the only safe option without this change.

This soundness is a property of the *fork*, not of the rule list, so it has to be
re-checked whenever either side moves. A tripwire is worth having: on Arch,
`pacman -Q pass` must report `pass-strict` at `1.7.4-2` or later. If the
distribution package ever returns, a blanket `Bash(pass *)` in `ask` is the only
safe form again, and it must go back the same day.

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

`PKGBUILD` builds from the git **tag**, so a source change is not shipped until
the tag moves and `pkgrel` bumps. That also means a successful `makepkg` says
nothing about what is on any branch — check the branch separately.

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

Listing walks the directory tree and never decrypts, so a fixture needs no GPG
key at all — the refusals all fire before `gpg` is reached:

```console
$ D=$(mktemp -d); mkdir -p "$D/svc"; echo 0 > "$D/.gpg-id"; : > "$D/svc/token.gpg"
$ PASSWORD_STORE_DIR="$D" pass ls                 # lists svc/token
$ PASSWORD_STORE_DIR="$D" pass ls svc             # lists the directory
$ PASSWORD_STORE_DIR="$D" pass ls svc/token       # refused, exit 1
$ PASSWORD_STORE_DIR="$D" pass list svc/token     # refused, exit 1
$ PASSWORD_STORE_DIR="$D" pass svc/token          # refused, exit 1
$ PASSWORD_STORE_DIR="$D" pass                    # lists the whole store
$ PASSWORD_STORE_DIR="$D" pass show svc/token     # reaches gpg, leaks nothing
```

That last line is the control: without it, a suite in which everything is
refused cannot tell a working guard from a broken `pass`.

The repository's own suite covers all three changes —
`tests/t0020-show-tests.sh`, `tests/t0021-list-tests.sh` and
`tests/t0022-extension-tests.sh`:

```console
$ make test
```
