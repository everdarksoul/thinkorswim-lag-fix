# thinkorswim-lag-fix

![license](https://img.shields.io/badge/license-MIT-blue)
![platform](https://img.shields.io/badge/platform-macOS%20%C2%B7%20Apple%20Silicon%20%7C%20Intel-black)
![tested](https://img.shields.io/badge/tested-thinkorswim%201993.3.1-green)
![java](https://img.shields.io/badge/Java%20agent-JDK%2011%2B-orange)

**A 2 KB Java agent that fixes thinkorswim lag on macOS** — the rainbow wheel during
market open, the stuttering chart scroll, the fans roaring at 5,000 RPM — by silently
swapping one un-acceleratable rendering filter for a GPU-friendly one, at launch,
without modifying a single byte of any thinkorswim file. Plus the full-screen menu-bar
fix for the macOS menu bar that sits on top of your chart.

## Sounds familiar? The thinkorswim symptoms this fixes

- ☐ The **rainbow wheel / beachball** appears the moment you scroll, zoom, or switch chart layouts
- ☐ Chart redraws lag behind your input — candles jump, watchlists repaint late
- ☐ **thinkorswim pins one or more CPU cores** in Activity Monitor while you're just *looking* at a chart
- ☐ Your MacBook's fans spin up hard during trading hours and the battery drains fast
- ☐ It feels worse on **Apple Silicon + Retina** — more pixels for the CPU to chew per frame
- ☐ In full screen, the **macOS menu bar won't hide** and covers the top of your chart

If you checked more than one box, the root cause below is almost certainly yours — and
the fix is one line in a text file.

## Root cause: one hardcoded `RenderingHint` nobody can turn off

Inside thinkorswim's chart engine
(`com.devexperts.toschart.GraphicsUtils.enableAntialiasing()`), every repaint
configures Java2D with `RenderingHints.VALUE_INTERPOLATION_BICUBIC`.

**Bicubic resampling is a software-only loop in Java2D — the accelerated pixel
pipelines cannot run it.** So the entire chart surface takes a CPU detour on the
`AWT-EventQueue` thread for *every frame*: millions of bicubic samples per repaint at
Retina resolution, serialized onto the single thread Swing uses for input, layout, and
painting alike. Your input queues behind that work. That is your beachball — the app
isn't frozen, it's faithfully rendering every pixel the slow, hard-coded way.

Bicubic interpolation exists for scaling *photographs*. A chart is lines, candles, and
text — where **bilinear**, the filter GPUs run natively in hardware, is visually
indistinguishable — and, unlike bicubic, Java2D can hand it straight to the GPU.

### Why you can't just change it yourself

| Obvious attempt | Why it fails |
|---|---|
| Flip a setting | There is none — the constant is hardcoded, no system property overrides it |
| Patch the `.jar` | thinkorswim's jars are **signed**; one modified byte fails integrity checks — and every update redownloads them anyway |
| Disable antialiasing | Sure, and your charts look like 1998 |

## The fix: rewrite the constant *in memory*, once, at class load

`BilinearAgent` is a standard Java instrumentation agent: a `premain` hook that
registers a `ClassFileTransformer`. The instant thinkorswim loads `GraphicsUtils`,
the agent rewrites the constant-pool entry `VALUE_INTERPOLATION_BICUBIC` →
`VALUE_INTERPOLATION_BILINEAR` in the class bytes **in memory**, before the first
chart ever paints:

- ✅ **No vendor file is ever touched** — jar signatures stay valid, updates install normally
- ✅ **Survives thinkorswim auto-updates** — the patch is re-applied at every launch, whatever version TOS ships
- ✅ **Antialiasing stays ON** — only the resample filter changes; lines, candles, and text render exactly as before
- ✅ **Fail-safe by design** — if a future thinkorswim build renames the class or constant, the agent logs a warning and the app runs 100% stock
- ✅ **One-line uninstall**, zero background processes, zero network, zero telemetry

## Install

### Option A — script (recommended)

```sh
git clone https://github.com/everdarksoul/thinkorswim-lag-fix.git
cd thinkorswim-lag-fix
./install.sh
```

The script builds the agent (any JDK 11+ — Homebrew `openjdk` works), backs up
`thinkorswim.vmoptions`, drops the jar into `~/thinkorswim/agent/`, and appends the
`-javaagent` line exactly once, no matter how many times you run it.
Then **fully quit thinkorswim with `⌘Q`** (not just close the window) and reopen.

### Option B — no JDK needed, three commands

Download [`bilinear-agent.jar` from the latest release](https://github.com/everdarksoul/thinkorswim-lag-fix/releases/latest),
then:

```sh
mkdir -p ~/thinkorswim/agent
cp ~/Downloads/bilinear-agent.jar ~/thinkorswim/agent/
echo "-javaagent:$HOME/thinkorswim/agent/bilinear-agent.jar" >> ~/thinkorswim/thinkorswim.vmoptions
```

(`$HOME` expands, giving Java the absolute path it requires.)

### Option C — you already know the drill

The entire fix is this one line, last, in `~/thinkorswim/thinkorswim.vmoptions`:

```
-javaagent:/Users/you/thinkorswim/agent/bilinear-agent.jar
```

## Verify it's working

**1 — the jar itself is valid** (any JDK):

```sh
java -javaagent:./bilinear-agent.jar -version 2>&1 | grep BilinearAgent
# [BilinearAgent] loaded
```

That executes `premain` for real — manifest, paths, permissions, all good.

**2 — your running thinkorswim actually has it loaded** (macOS, no JDK needed):

```sh
PID=$(pgrep -f "thinkorswim.app/Contents/MacOS/JavaApplicationStub" | head -1)
lsof -p "$PID" 2>/dev/null | grep bilinear-agent
# JavaAppli  876  sar  6r  REG  ...  /Users/you/thinkorswim/agent/bilinear-agent.jar
```

An open file descriptor on the agent jar = it's inside the live JVM. With a JDK
installed, `jcmd "$PID" VM.command_line` prints the full JVM command line, ending in
`-javaagent:…/bilinear-agent.jar`.

> Heads-up: thinkorswim's install4j launcher creates the JVM **in-process**, so
> `-javaagent` (and every other JVM flag) never shows up in `ps` or Activity Monitor.
> `lsof` / `jcmd` is the reliable window into what the JVM actually received.

**3 — the behavioral check**: open a dense multi-chart layout and scroll hard —
before, the beachball; after, fluid. When stderr is visible (e.g. started from a
terminal), the agent also announces itself on launch:
`[BilinearAgent] patched com/devexperts/toschart/GraphicsUtils: INTERPOLATION_BICUBIC
-> INTERPOLATION_BILINEAR` — or a warning telling you it stepped aside because TOS
changed internals, in which case you're on stock rendering with nothing broken.

## Full-screen menu bar fix (macOS)

Separate, independent quirk. thinkorswim's full-screen window is a Java/AWT window
that macOS doesn't fully recognize as a first-class full-screen citizen, so the system
menu bar can stay **pinned over your chart** — or behave inconsistently between Spaces.
Two ways out:

**System Settings → Desktop & Dock → Menu bar → Automatically hide and show the menu
bar → _In Full Screen Only_** (or _Always_)

or from a terminal:

```sh
defaults write NSGlobalDomain _HIHideMenuBar -bool true
killall Dock
```

Going the other way — the menu bar now hides *everywhere* and you want it back —
restore factory behavior:

```sh
defaults delete NSGlobalDomain _HIHideMenuBar
defaults delete NSGlobalDomain AppleMenuBarVisibleInFullscreen
killall Dock
```

What those two keys mean, precisely:

- `_HIHideMenuBar` — `true` = the menu bar auto-hides everywhere (desktop included)
- `AppleMenuBarVisibleInFullscreen` — `true` = the menu bar is **pinned, never hides**
  in full-screen apps; `false`/absent = full-screen apps may hide it

> ⚠️ Both are **system-wide** settings that affect every application, not just
> thinkorswim. Prefer the System Settings panel if you don't want to edit defaults by
> hand. This section is macOS-only; the Java agent itself works everywhere.

## Build from source

```sh
javac --release 11 -d build/classes src/BilinearAgent.java
jar cfm bilinear-agent.jar MANIFEST.MF -C build/classes .
# …or just:
./build.sh        # builds AND smoke-tests that premain runs
```

Any JDK ≥ 11. The agent is compiled to class-file version 55 so it loads on every JRE
thinkorswim has ever bundled.

## Uninstall

```sh
./uninstall.sh
```

…or delete the `-javaagent:` line from `thinkorswim.vmoptions` and remove
`~/thinkorswim/agent/bilinear-agent.jar`. Restart thinkorswim.

## How the bytecode patch works (for the curious)

Java class files store identifiers in a **constant pool**: every UTF-8 entry is
`u2 length ‖ bytes`, and the format contains no absolute offsets anywhere — so entries
can be spliced in place with simple tail-shifting.

`GraphicsUtils.class` reaches `RenderingHints.VALUE_INTERPOLATION_BICUBIC` through such
an entry. The agent scans the incoming class bytes for the exact *length-prefixed*
sequence `VALUE_INTERPOLATION_BICUBIC` (the match includes its own 2-byte length
prefix, so it can never collide with a shorter constant that merely shares a prefix),
then splices in `VALUE_INTERPOLATION_BILINEAR` — two bytes longer — growing the length
prefix and shifting the tail. Field lookup resolves normally, just to the *other*
static constant. Total cost: one scan of one class file, once per launch, before any
chart exists to be slow.

```
before:  … u2 25 | V A L U E _ I N T E R P O L A T I O N _ B I C U B I C …
after:   … u2 27 | V A L U E _ I N T E R P O L A T I O N _ B I L I N E A R …
```

## FAQ

**Does it hurt chart quality?**
Candles, axes, and text are vector-drawn — unaffected. Only the bitmap resampling
filter changes, and bilinear vs. bicubic is not a difference you can spot at real chart
scales. What you *will* notice is that motion stays smooth while the old path was
spending a core resampling.

**Will a thinkorswim update undo it?**
Updates occasionally rewrite `thinkorswim.vmoptions` — rerun `./install.sh` (idempotent,
takes two seconds). The agent itself never needs updating: it patches whatever TOS
ships at load time, and warns instead of breaking if internals move.

**Is this touching my account, orders, or data?**
No. It doesn't touch data, feeds, orders, or a single vendor file — it's a local
rendering preference applied in memory at class load, like a graphics-driver setting.
No network, no background daemon, nothing to trust after you quit the app.

**Does it work on Windows / Linux?**
Yes — same one line in the `thinkorswim.vmoptions` inside your install folder (use an
absolute path). Only the menu-bar section above is Mac-specific.

**Where does it put things?**
Exactly two: `~/thinkorswim/agent/bilinear-agent.jar`, and one line appended to
`~/thinkorswim/thinkorswim.vmoptions`. Nothing in `/Library`, no LaunchAgents, no
login items.

## Tested configuration

| | |
|---|---|
| thinkorswim | 1993.3.1 (current, October 2026) |
| macOS | 27.0 (26A428) · Apple Silicon, Retina |
| Build JDK | OpenJDK 21 (Homebrew) → `--release 11` bytecode |
| Mechanism | in-memory `ClassFileTransformer`, no retransformation, no jar edits |

## Disclaimer

Not affiliated with, endorsed by, or connected to Charles Schwab, thinkorswim, or
devexperts (whose chart library this agent patches *in memory* at runtime). Provided
as-is, without warranty of any kind — the "risk" is one line in a text file that a
backup sits next to. See LICENSE.

## License

MIT © [everdarksoul](https://github.com/everdarksoul)

*If this saved your market open, drop a ⭐ star — it's how other traders find it.*
