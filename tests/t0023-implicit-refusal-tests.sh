#!/usr/bin/env bash

test_description='Test that the implicit show shorthand is refused'
cd "$(dirname "$0")"
. ./setup.sh

# This covers change 1 -- the fork's headline guarantee, that `pass <entry>`
# does not print a credential.
#
# It existed for two releases with NO test at all. t0020-show-tests.sh was
# byte-identical to upstream's, and every assertion in it spells `show`
# explicitly, so reverting the dispatcher's `*)` arm to upstream's
# cmd_extension_or_show would have restored the silent read with the whole
# suite green. The README meanwhile claimed all three changes were covered.
#
# That is the same failure this repository keeps paying for: a guard whose
# absence looks identical to its presence. The controls at the bottom are what
# stop this file from being satisfied by a build where `pass` is simply broken.

test_expect_success 'Set up a store with a leaf' '
	"$PASS" init $KEY1 &&
	"$PASS" generate svc/token 20
'

test_expect_success 'The implicit form is refused' '
	test_must_fail "$PASS" svc/token
'

test_expect_success 'The implicit form with -c is refused' '
	test_must_fail "$PASS" -c svc/token
'

test_expect_success 'The implicit form never prints the secret' '
	secret="$("$PASS" show svc/token)" &&
	[[ -n $secret ]] &&
	! "$PASS" svc/token 2>&1 | grep -qF -- "$secret"
'

# Deliberately NOT here: a "the -c form never prints the secret" check. The
# clipboard path never writes the secret to stdout, so such a test passes
# whether the guard is present or not -- it was green against a mutant with
# change 1 reverted, which is the definition of not a control. Worse, under
# that mutant it hangs: clip() forks and holds the pipe open for CLIP_TIME.
# The refusal itself is pinned by 'The implicit form with -c is refused' above.

test_expect_success 'The refusal names show as the replacement' '
	"$PASS" svc/token 2>&1 | grep -q "pass show svc/token"
'

test_expect_success 'The refusal names ext for the extension case' '
	"$PASS" svc/token 2>&1 | grep -q "pass ext svc/token"
'

test_expect_success 'A nonexistent entry is refused the same way, not reported as missing' '
	test_must_fail "$PASS" no/such/entry &&
	"$PASS" no/such/entry 2>&1 | grep -q "refusing the implicit"
'

# CONTROL. Without these the file is satisfied by a build where every
# invocation fails, which is the failure mode that would hide a broken pass.
test_expect_success 'CONTROL: show still reads the leaf' '
	[[ -n $("$PASS" show svc/token) ]]
'

test_expect_success 'CONTROL: bare pass still lists the store' '
	"$PASS" | grep -q "Password Store"
'

test_done
