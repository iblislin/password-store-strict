#!/usr/bin/env bash

test_description='Test that ls/list refuse to read a secret'
cd "$(dirname "$0")"
. ./setup.sh

# Upstream routes `show`, `ls` and `list` to one function, whose file branch
# decrypts and prints. So `pass ls svc/token` is a full read wearing a
# listing's name. This build splits them: the listing spellings refuse a leaf
# and name `show` as the replacement.
#
# The reason this is worth a behavioural test rather than a code comment is
# that the property protects something outside pass entirely -- a permission
# rule that matches command strings can allow `pass ls *` while gating
# `pass show *`, believing it has separated a name listing from a secret read.
# If this split ever regresses, that config silently permits reads again, and
# nothing in the config would look different.

test_expect_success 'Set up a store with a leaf and a directory' '
	"$PASS" init $KEY1 &&
	"$PASS" generate svc/token 20 &&
	"$PASS" generate toplevel 20
'

test_expect_success '"ls" refuses a leaf' '
	test_must_fail "$PASS" ls svc/token
'

test_expect_success '"list" refuses a leaf' '
	test_must_fail "$PASS" list svc/token
'

test_expect_success '"ls" refuses a leaf at the store root' '
	test_must_fail "$PASS" ls toplevel
'

test_expect_success 'The refusal never prints the secret' '
	secret="$("$PASS" show svc/token)" &&
	[[ -n $secret ]] &&
	! "$PASS" ls svc/token 2>&1 | grep -qF -- "$secret"
'

# The guard sits textually ABOVE the clip/qrcode branch in cmd_show, which is
# what makes these refuse rather than silently copying to the selection. That
# placement is load-bearing and was untested: move the guard into the plain
# print branch and every other case in this file still passes, while
# `pass ls -c <leaf>` puts the password on the clipboard under a rule that
# allows `pass ls *`.
test_expect_success '"ls" refuses a leaf with --clip' '
	test_must_fail "$PASS" ls --clip svc/token &&
	test_must_fail "$PASS" ls -c svc/token
'

test_expect_success '"ls" refuses a leaf with --qrcode' '
	test_must_fail "$PASS" ls --qrcode svc/token &&
	test_must_fail "$PASS" ls -q svc/token
'

test_expect_success '"list" refuses a leaf with --clip' '
	test_must_fail "$PASS" list -c svc/token
'

test_expect_success 'The --clip refusal never prints the secret either' '
	secret="$("$PASS" show svc/token)" &&
	[[ -n $secret ]] &&
	! "$PASS" ls -c svc/token 2>&1 | grep -qF -- "$secret"
'

test_expect_success 'The refusal names show as the replacement' '
	"$PASS" ls svc/token 2>&1 | grep -q " show svc/token"
'

test_expect_success '"ls" still lists the whole store' '
	"$PASS" ls | grep -q "svc"
'

test_expect_success '"ls" still lists a directory' '
	"$PASS" ls svc | grep -q "token"
'

test_expect_success '"ls" still lists a directory with a trailing slash' '
	"$PASS" ls svc/ | grep -q "token"
'

test_expect_success '"list" still lists a directory' '
	"$PASS" list svc | grep -q "token"
'

# CONTROL. Without this the whole file is satisfied by a build where `ls` is
# broken outright, and by one where every subcommand refuses everything.
test_expect_success 'CONTROL: "show" still reads the leaf' '
	[[ -n $("$PASS" show svc/token) ]]
'

# STRICT: bare `pass` is a listing and nothing else -- with no argument the path
# is empty, so cmd_show can only reach its directory branch. strict1 swept it
# into the implicit-show refusal, which bought no safety and broke upstream's
# most common invocation. Untested, that regression shipped for a whole release.
test_expect_success 'bare "pass" lists the store' '
	"$PASS" | grep -q "Password Store"
'

test_expect_success 'bare "pass" exits zero' '
	"$PASS" >/dev/null
'

test_done
