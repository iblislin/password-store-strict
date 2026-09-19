#!/usr/bin/env bash

test_description='Test that extensions require the explicit ext keyword'
cd "$(dirname "$0")"
. ./setup.sh

# Upstream routes an unknown subcommand to cmd_extension first and to cmd_show
# second, so `pass <name>` runs an extension if one exists. An extension is
# arbitrary code that may print a secret, and its name is not knowable to
# whoever writes a permission rule -- there is no closed set to enumerate.
#
# The case that motivated this is the system extension directory: extensions
# there run even when PASSWORD_STORE_ENABLE_EXTENSIONS is unset, because that
# variable gates only the per-store directory. So installing a package such as
# pass-otp silently adds a spelling that reads a secret, carries no keyword, and
# matches no rule. Nothing about the config looks different afterwards, which is
# why this needs a behavioural test rather than a comment.
#
# SYSTEM_EXTENSION_DIR is empty in the source tree and only filled in at install
# time. Most of these tests therefore exercise the per-store directory -- but
# that is NOT sufficient on its own: a regression restoring the fallback for the
# system path only would leave every per-store assertion green, and the system
# path is precisely the one that needs no opt-in and that a distribution package
# fills. The last block builds an install-shaped copy, the same substitution the
# Makefile performs, so both lookups are covered in both directions.

test_expect_success 'Set up a store and a store-local extension' '
	"$PASS" init $KEY1 &&
	"$PASS" generate cred1 20 &&
	mkdir -p "$PASSWORD_STORE_DIR/.extensions" &&
	printf "#!/usr/bin/env bash\necho EXTENSION_RAN\n" > "$PASSWORD_STORE_DIR/.extensions/probe.bash" &&
	chmod +x "$PASSWORD_STORE_DIR/.extensions/probe.bash"
'

test_expect_success 'The implicit form refuses even when the extension exists' '
	PASSWORD_STORE_ENABLE_EXTENSIONS=true test_must_fail "$PASS" probe
'

test_expect_success 'The refusal never runs the extension' '
	! PASSWORD_STORE_ENABLE_EXTENSIONS=true "$PASS" probe 2>&1 | grep -q EXTENSION_RAN
'

test_expect_success 'The refusal names the ext keyword' '
	PASSWORD_STORE_ENABLE_EXTENSIONS=true "$PASS" probe 2>&1 | grep -q "pass ext probe"
'

test_expect_success 'CONTROL: the explicit ext keyword still runs it' '
	[[ $(PASSWORD_STORE_ENABLE_EXTENSIONS=true "$PASS" ext probe) == "EXTENSION_RAN" ]]
'

test_expect_success 'ext refuses a name with no extension behind it' '
	PASSWORD_STORE_ENABLE_EXTENSIONS=true test_must_fail "$PASS" ext nosuchextension
'

test_expect_success 'ext with no argument is a usage error, not a read' '
	test_must_fail "$PASS" ext
'

test_expect_success 'ext does not become a back door to show' '
	PASSWORD_STORE_ENABLE_EXTENSIONS=true test_must_fail "$PASS" ext cred1
'

test_expect_success 'CONTROL: show still reads the secret' '
	[[ -n $("$PASS" show cred1) ]]
'

# Exit status. Upstream's cmd_extension ended in an unconditional `return 0`,
# so a failing extension reported success to anything scripting around pass --
# and "no such extension" and "the extension failed" were indistinguishable.
# The sentinel makes them separable; these pin all three outcomes.
test_expect_success 'Set up extensions with known exit statuses' '
	printf "#!/usr/bin/env bash\nexit 42\n" > "$PASSWORD_STORE_DIR/.extensions/failing.bash" &&
	chmod +x "$PASSWORD_STORE_DIR/.extensions/failing.bash" &&
	printf "#!/usr/bin/env bash\nexit 0\n" > "$PASSWORD_STORE_DIR/.extensions/okext.bash" &&
	chmod +x "$PASSWORD_STORE_DIR/.extensions/okext.bash"
'

test_expect_success 'A failing extension propagates its exit status' '
	PASSWORD_STORE_ENABLE_EXTENSIONS=true "$PASS" ext failing
	state=$?
	[[ $state -eq 42 ]]
'

test_expect_success 'CONTROL: a succeeding extension still exits zero' '
	PASSWORD_STORE_ENABLE_EXTENSIONS=true "$PASS" ext okext
'

test_expect_success 'A missing extension is distinguishable from a failing one' '
	PASSWORD_STORE_ENABLE_EXTENSIONS=true "$PASS" ext nosuchextension
	state=$?
	[[ $state -ne 0 ]] && [[ $state -ne 42 ]]
'

# The system extension directory. This is the case change 3 exists for: it runs
# regardless of PASSWORD_STORE_ENABLE_EXTENSIONS, because that variable gates
# only the per-store directory. Build an install-shaped copy the way the
# Makefile does, so the lookup that a pass-otp package would populate is
# actually exercised.
test_expect_success 'Set up an install-shaped pass with a system extension' '
	mkdir -p sysext-dir &&
	printf "#!/usr/bin/env bash\necho SYSTEM_EXTENSION_RAN\n" > sysext-dir/sysprobe.bash &&
	chmod +x sysext-dir/sysprobe.bash &&
	sed "s:^SYSTEM_EXTENSION_DIR=.*:SYSTEM_EXTENSION_DIR=\"$(pwd)/sysext-dir\":" "$PASS" > pass-sysext &&
	chmod +x pass-sysext &&
	grep -q "^SYSTEM_EXTENSION_DIR=\"$(pwd)/sysext-dir\"$" pass-sysext
'

test_expect_success 'CONTROL: the system extension is reachable at all' '
	[[ $(./pass-sysext ext sysprobe) == "SYSTEM_EXTENSION_RAN" ]]
'

test_expect_success 'A system extension does NOT run without the ext keyword' '
	test_must_fail ./pass-sysext sysprobe
'

test_expect_success 'The system-extension refusal never runs it' '
	! ./pass-sysext sysprobe 2>&1 | grep -q SYSTEM_EXTENSION_RAN
'

test_expect_success 'The system extension is gated even with extensions disabled' '
	PASSWORD_STORE_ENABLE_EXTENSIONS=false test_must_fail ./pass-sysext sysprobe
'

test_done
