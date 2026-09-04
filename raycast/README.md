# Raccoon for Raycast

> Looking for the Raycast **Store extension** (TypeScript, rich views)? It lives in
> [`../raycast-extension`](../raycast-extension). This folder is the zero-build alternative.

Every `rcc` subcommand as a [Raycast Script Command](https://github.com/raycast/script-commands).
No build step, no npm, no extension store — Raycast runs the shell scripts directly.

## Install

1. `brew install thousandflowers/tap/rcc`
2. Raycast → **Settings → Extensions → Script Commands → Add Directories**
3. Pick `raccoon/raycast/commands`

All commands then appear in Raycast root search under the **Raccoon** package.
Disable the ones you don't want in the same settings pane.

## Modes

Every command uses `fullOutput`: the report is rendered in a Raycast window with colors
stripped via `NO_COLOR=1`. Nothing opens a Terminal.

Commands that never need root also carry `RCC_NO_PROMPT=1`, so they can never raise a Touch ID
dialog. The privileged ones (`audit`, `upgrade`, `apps`, `fleet`) are left able to ask once,
since running a Script Command is always deliberate. For a gated, streaming version of those,
use the Store extension in [`../raycast-extension`](../raycast-extension) instead.

## Regenerating

The command list is derived from `rcc --help`, not hardcoded. After adding a new
subcommand to `rcc`:

```sh
./raycast/generate.sh
```

Which commands need root is detected by grepping the matching `bin/<cmd>.sh` for `sudo`.
