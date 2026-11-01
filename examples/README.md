# Examples

Run these from the repository checkout after [installing Showback](../docs/getting-started.md).

## Settings: first run

```sh
open "$HOME/Applications/Showback.app"
```

Wait for Settings, then:

```sh
showback validate examples/showback-demo.json
showback run examples/showback-demo.json --mute
```

[showback-demo.json](showback-demo.json) points at the model and voice picker without changing preferences. Remove `--mute` for live narration. Output defaults to `~/Movies/Showback/`.

## Browser walkthrough

[browser-demo.json](browser-demo.json) operates a local WebKit page: reset, sign in, check the welcome message, then explain it. The fixture simulates account state; it does not authenticate with a service. [The page](../Tests/Fixtures/browser.html) is local and uses safe test data.

Build the controlled fixtures and start their temporary virtual display in one terminal:

```sh
./scripts/build-fixtures.sh
.local/gui/virtual-display --width 1280 --height 800 --scale 1 --place left --seconds 3600
```

Keep that process running. It prints a display ID. In another terminal, from the checkout, replace `DISPLAY_ID` below with that printed ID:

```sh
export SHOWBACK_TEST_DISPLAY=DISPLAY_ID
open -n '.local/gui/Showback Browser Fixture.app' --args --display "$SHOWBACK_TEST_DISPLAY" --page "$PWD/Tests/Fixtures/browser.html"
```

Once the fixture is visible:

```sh
showback validate examples/browser-demo.json
showback run examples/browser-demo.json --mute
```

The fixture refuses the physical primary display. The virtual-display helper uses a private macOS API for development only and is not shipped in Showback. Quit the fixture before stopping the display process with Ctrl+C. For a shared QA machine, follow the ownership-lock procedure in [verification](../docs/verification.md).

## Native walkthrough

With the same virtual display running:

```sh
open -n '.local/gui/Showback Fixture.app' --args --display "$SHOWBACK_TEST_DISPLAY"
```

Wait for the window, then:

```sh
showback validate examples/native-demo.json
showback run examples/native-demo.json --mute
```

[native-demo.json](native-demo.json) operates native AppKit controls and records checked results. It changes only the fixture's test state.

## Your app

Use the [script contract](../docs/scripts.md) and [agent skill](../skills/showback/SKILL.md). Replace app/window names and selectors with values observed in your running app. These examples are not universal selectors for other applications.

Use one-window capture unless the demo intentionally spans windows. Select a display explicitly for multi-app demos; everything on that display can be recorded. Existing output bundles are not overwritten.
