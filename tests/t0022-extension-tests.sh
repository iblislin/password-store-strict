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
# time, so these tests exercise the per-store directory. It is the same code
# path in cmd_extension; what differs is only which of the two lookups matches.

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

test_done
