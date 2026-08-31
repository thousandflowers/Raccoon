# hero.tape - the image at the top of the README.
#
# Ownership: vhs owns docs/gifs/hero.gif and nothing else. Remotion owns every
# docs/gifs/rcc-<id>.gif. There is no hero fixture, so the two sets cannot
# collide. Run this from docs/tapes/:  vhs hero.tape
#
# The GIF this replaces showed the recording machine's full home path and two
# personal Homebrew taps, because it was a raw screen recording of a real
# session. Everything under Hide below exists so that cannot happen again:
# the shell gets a throwaway HOME and a prompt with no user, host or path in
# it, and rcc is reached through a symlink inside that HOME rather than by
# typing a real path. No absolute path appears in this file either.
#
# Pre-flight, before recording. It must print nothing:
#   H=$(mktemp -d); HOME="$H" ../../rcc disk |
#     grep -nE '/Users/|@|quetzalcoatl|lampone'; rm -rf "$H"
# The GIF can only show what the terminal printed, so a clean capture here is
# a clean set of frames. Re-run it if the demo command below is changed.

Output ../gifs/hero.gif

Set Shell "bash"
Set Theme "Ayu Mirage"
Set FontSize 22
Set Width 1500
Set Height 1200
Set Padding 40
Set Framerate 20
Set PlaybackSpeed 1.0

Hide
# Resolve rcc while the real cwd is still known, then leave it behind.
Type "REPO=$PWD/../.." Enter
Type "export HOME=$(mktemp -d)" Enter
Type "mkdir -p $HOME/bin $HOME/.raccoon" Enter
Type "touch $HOME/.raccoon/onboarded" Enter
# rcc resolves its own directory with readlink -f, so a symlink is safe.
Type "ln -s $REPO/rcc $HOME/bin/rcc" Enter
Type "export PATH=$HOME/bin:$PATH" Enter
Type "cd $HOME" Enter
# The default prompt prints user@host. This one prints neither.
Type "export PS1='$ ' PROMPT_COMMAND=" Enter
Type "clear" Enter
Show

# The whole cycle: menu, a command, its result, back to the menu.
Type "rcc" Sleep 400ms Enter
Sleep 1500ms

# Down five times: audit, upgrade, apps, backup, trash, then disk. The cursor
# crossing from Maintenance into System is what shows the categories exist.
Down Sleep 180ms
Down Sleep 180ms
Down Sleep 180ms
Down Sleep 180ms
Down Sleep 180ms

Enter
Sleep 4000ms
