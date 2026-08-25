Output ../gifs/rcc-audit.gif
Set Theme "Ayu Mirage"
Set FontSize 28
Set Width 1400
# 20 rows: the terminal itself does the cropping, so the frame lands on the
# Summary block and the prompt without piping the output through tail.
Set Height 766
Set Padding 48
Set Framerate 20
Set PlaybackSpeed 1.0
Hide
Type "cd $HOME/Raccoon" Enter
Type 'rcc() { $HOME/Raccoon/docs/gif-helpers/demo-audit.sh "${@:2}"; }' Enter
Type "clear" Enter
Show

Type "rcc audit --deep --dry-run" Sleep 400ms Enter
# Hidden wait: the audit takes ~4s, and none of it should become dead frames.
# Not Wait+Screen - it stalls the recording once the output scrolls, which it
# does at 20 rows.
Hide
Sleep 15s
Show
Sleep 300ms
Type "N" Enter
Sleep 3s
