# A local replacement for `pass` that removes the implicit `show` shorthand.
#
# WHY THIS PACKAGE EXISTS: `show` is upstream pass's DEFAULT subcommand, so a
# bare `pass <entry>` prints that credential with no keyword naming the action.
# That leaves the subcommand space open-ended -- the safe operations are a small
# closed set (ls, find, help, version) while the dangerous one is "any entry
# path" -- and no prefix pattern separates the two. Closing the set is what lets
# a shell-history grep, and an LLM agent's permission rule, tell a name listing
# apart from a secret read. See the fork's commit for the full rationale.
#
# WHY IT REPLACES `pass` RATHER THAN INSTALLING ALONGSIDE IT: leaving the
# unpatched binary reachable at a known absolute path makes the control
# advisory, not real.
#
# WHY THE PACKAGE IS NOT NAMED `pass`: a locally built package sharing a
# repository package's name is silently replaced by the repo version on the next
# `pacman -Syu`, with nothing in the output distinguishing it from any other
# bump. `conflicts=('pass')` is a structural block instead of an IgnorePkg line
# that can be edited away or lost in a pacman.conf.pacnew merge.

pkgname=pass-strict
pkgver=1.7.4
pkgrel=1
_tag="$pkgver-strict1"
pkgdesc='Stores, retrieves, generates and synchronizes passwords securely - local build requiring an explicit `show`'
arch=('any')
url='https://github.com/iblislin/password-store-strict'
license=('GPL2')
depends=('bash' 'gnupg' 'tree')
optdepends=('git: for Git support'
            'dmenu: for passmenu'
            'xdotool: to type passwords with passmenu'
            'wl-clipboard: for Wayland clipboard support')
provides=("pass=$pkgver" 'passmenu')
conflicts=('pass' 'passmenu')
replaces=('pass' 'passmenu')
source=("$pkgname::git+https://github.com/iblislin/password-store-strict.git#tag=$_tag")
sha256sums=('SKIP')

package() {
	cd "$srcdir/$pkgname"
	# Upstream's install target covers /usr/bin/pass, the man page and the bash
	# completion only. The other four files the Arch `pass` package owns are
	# installed by hand below, so this package's file list matches it exactly.
	make DESTDIR="$pkgdir" PREFIX=/usr WITH_BASHCOMP=yes install
	install -Dm755 contrib/dmenu/passmenu "$pkgdir/usr/bin/passmenu"
	install -Dm644 src/completion/pass.zsh-completion "$pkgdir/usr/share/zsh/site-functions/_pass"
	install -Dm644 src/completion/pass.fish-completion "$pkgdir/usr/share/fish/vendor_completions.d/pass.fish"
	install -Dm644 contrib/vim/redact_pass.vim "$pkgdir/usr/share/vim/vimfiles/plugin/redact_pass.vim"
}
