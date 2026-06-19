#!/usr/bin/env python3
"""Read audit output on stdin; exit 0 iff every box line (+/| prefix, ANSI
stripped) has the same display width. Guards against the ragged-report bug."""
import re
import sys

ansi = re.compile("\x1b\\[[0-9;]*m")
widths = set()
for line in sys.stdin:
    clean = ansi.sub("", line.rstrip("\n"))
    if clean and clean[0] in "+|":  # "" in "+|" is True in Python — guard it
        widths.add(len(clean))

if len(widths) <= 1:
    print("OK")
    sys.exit(0)
print("RAGGED:" + str(sorted(widths)))
sys.exit(1)
