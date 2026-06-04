[Skip to content](https://github.com/openclaw/Peekaboo/blob/main/README.md#start-of-content)

You signed in with another tab or window. [Reload](https://github.com/openclaw/Peekaboo/blob/main/README.md) to refresh your session.You signed out in another tab or window. [Reload](https://github.com/openclaw/Peekaboo/blob/main/README.md) to refresh your session.You switched accounts on another tab or window. [Reload](https://github.com/openclaw/Peekaboo/blob/main/README.md) to refresh your session.Dismiss alert

{{ message }}

[openclaw](https://github.com/openclaw)/ **[Peekaboo](https://github.com/openclaw/Peekaboo)** Public

- [Notifications](https://github.com/login?return_to=%2Fopenclaw%2FPeekaboo) You must be signed in to change notification settings
- [Fork\\
342](https://github.com/login?return_to=%2Fopenclaw%2FPeekaboo)
- [Star\\
4.6k](https://github.com/login?return_to=%2Fopenclaw%2FPeekaboo)


## Collapse file tree

## Files

main

Search this repository(forward slash)` forward slash/`

/

# README.md

Copy path

Blame

More file actions

Blame

More file actions

## Latest commit

[![steipete](https://avatars.githubusercontent.com/u/58493?v=4&size=40)](https://github.com/steipete)[steipete](https://github.com/openclaw/Peekaboo/commits?author=steipete)

[docs: document input delivery modes](https://github.com/openclaw/Peekaboo/commit/3be1dc7ef2d098669df6dc8cb08e690788028bf4)

success

3 days agoMay 31, 2026

[3be1dc7](https://github.com/openclaw/Peekaboo/commit/3be1dc7ef2d098669df6dc8cb08e690788028bf4) · 3 days agoMay 31, 2026

## History

[History](https://github.com/openclaw/Peekaboo/commits/main/README.md)

Open commit details

[View commit history for this file.](https://github.com/openclaw/Peekaboo/commits/main/README.md) History

170 lines (139 loc) · 10.6 KB

/

# README.md

Top

## File metadata and controls

- Preview

- Code

- Blame


170 lines (139 loc) · 10.6 KB

[Raw](https://github.com/openclaw/Peekaboo/raw/refs/heads/main/README.md)

Copy raw file

Download raw file

Outline

Edit and raw actions

# Peekaboo 🫣 - Mac automation that sees the screen and does the clicks.

[Permalink: Peekaboo 🫣 - Mac automation that sees the screen and does the clicks.](https://github.com/openclaw/Peekaboo/blob/main/README.md#peekaboo----mac-automation-that-sees-the-screen-and-does-the-clicks)

[![Peekaboo Banner](https://github.com/openclaw/Peekaboo/raw/main/assets/peekaboo.png)](https://github.com/openclaw/Peekaboo/blob/main/assets/peekaboo.png)

[![npm package](https://camo.githubusercontent.com/06f983927b8ecf7e31f783c38e435bcd8444d9c6f7d1fd94b3ebe8e645544f44/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f6e706d5f7061636b6167652d332e332e302d627269676874677265656e3f6c6f676f3d6e706d266c6f676f436f6c6f723d7768697465267374796c653d666c61742d737175617265)](https://www.npmjs.com/package/@steipete/peekaboo)[![License: MIT](https://camo.githubusercontent.com/eae27181195ae787828362d9992141457fef77034061abf9587788b6fcac697c/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f4c6963656e73652d4d49542d6666643630613f7374796c653d666c61742d737175617265)](https://opensource.org/licenses/MIT)[![macOS 15.0+ (Sequoia)](https://camo.githubusercontent.com/012c40f05512cb0d8e772e4cfe2aa8e386dc3aec88a758bcacc34edb87b2673a/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f6d61634f532d31352e302532425f28536571756f6961292d3030373864373f6c6f676f3d6170706c65266c6f676f436f6c6f723d7768697465267374796c653d666c61742d737175617265)](https://www.apple.com/macos/)[![Swift 6.2](https://camo.githubusercontent.com/d398caa3c72827ef2e3d17adb0f89f6f3a954115b8b58f9a6f5ca17ea6edbf28/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f53776966742d362e322d4630353133383f6c6f676f3d7377696674266c6f676f436f6c6f723d7768697465267374796c653d666c61742d737175617265)](https://swift.org/)[![node >=22](https://camo.githubusercontent.com/ee0b04a25632d091d343e0ae22acda424bc9d9f989a6e42e2edde9bc5a56e3f0/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f6e6f64652d25334525334432322e302e302d3265613434663f6c6f676f3d6e6f64652e6a73266c6f676f436f6c6f723d7768697465267374796c653d666c61742d737175617265)](https://nodejs.org/)[![Download macOS](https://camo.githubusercontent.com/31afe50cf8a87aabb72d099508e903007338d14c761ff917754028387118c8fa/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f446f776e6c6f61642d6d61634f532d3030303030303f6c6f676f3d6170706c65266c6f676f436f6c6f723d7768697465267374796c653d666c61742d737175617265)](https://github.com/steipete/peekaboo/releases/latest)[![Homebrew](https://camo.githubusercontent.com/525da1f460afe2c9e953023088ea2880f821b686fa5c408e18ebefc17efdb5ce/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f486f6d65627265772d73746569706574652532467461702d6232386636323f6c6f676f3d686f6d6562726577266c6f676f436f6c6f723d7768697465267374796c653d666c61742d737175617265)](https://github.com/steipete/homebrew-tap)[![Ask DeepWiki](https://camo.githubusercontent.com/2db54e97cb0e3c43121504735a9be28db62a330a722aa14be3fee6ca64cd13a7/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f41736b2d4465657057696b692d3030383863633f7374796c653d666c61742d737175617265)](https://deepwiki.com/steipete/peekaboo)

Peekaboo brings high-fidelity screen capture, AI analysis, and complete GUI automation to macOS. Version 3 adds native agent flows and multi-screen automation across the CLI and MCP server.

## What you get

[Permalink: What you get](https://github.com/openclaw/Peekaboo/blob/main/README.md#what-you-get)

- Pixel-accurate captures (windows, screens, menu bar) with optional Retina 2x scaling.
- Natural-language agent that chains Peekaboo tools (see, click, type, scroll, hotkey, menu, window, app, dock, space).
- Action-first UI automation for routine clicks/scrolls, with background process-targeted input by default when a target is known.
- Direct accessibility tools for settable values and named actions (`set-value`, `perform-action`).
- Menu and menubar discovery with structured JSON; no clicks required.
- Multi-provider AI through Tachikoma, including hosted, local, and OpenAI-/Anthropic-compatible providers.
- MCP server for Codex, Claude Code, and Cursor plus a native CLI; the same tools in both.
- Configurable, testable workflows with reproducible sessions and strict typing.
- Requires macOS Screen Recording + Accessibility permissions (see [docs/permissions.md](https://github.com/openclaw/Peekaboo/blob/main/docs/permissions.md)).

## Install

[Permalink: Install](https://github.com/openclaw/Peekaboo/blob/main/README.md#install)

- macOS app + CLI (Homebrew):



```
brew install steipete/tap/peekaboo
```

- MCP server (Node 22+, no global install needed):



```
npx -y @steipete/peekaboo
```


## Quick start

[Permalink: Quick start](https://github.com/openclaw/Peekaboo/blob/main/README.md#quick-start)

```
# Capture full screen at Retina scale and save to Desktop
peekaboo image --mode screen --retina --path ~/Desktop/screen.png

# Click a button by label (captures, resolves, and clicks in one go)
peekaboo see --app Safari --json | jq -r '.data.snapshot_id' | read SNAPSHOT
peekaboo click --on "Reload this page" --snapshot "$SNAPSHOT"

# Directly set a text field value when the accessibility value is settable
peekaboo set-value --on T1 --value "hello" --snapshot "$SNAPSHOT"

# Invoke a named accessibility action on an element
peekaboo perform-action --on B1 --action AXPress --snapshot "$SNAPSHOT"

# Run a natural-language automation
peekaboo agent "Open Notes and create a TODO list with three items"

# Run as an MCP server (Codex, Claude Code, Cursor)
npx -y @steipete/peekaboo

# Minimal MCP client config snippet:
# {
#   "mcpServers": {
#     "peekaboo": {
#       "command": "npx",
#       "args": ["-y", "@steipete/peekaboo"],
#       "env": {
#         "PEEKABOO_AI_PROVIDERS": "openai/gpt-5.5,anthropic/claude-opus-4-7"
#       }
#     }
#   }
# }
```

## Shell completions

[Permalink: Shell completions](https://github.com/openclaw/Peekaboo/blob/main/README.md#shell-completions)

Peekaboo can generate shell-native completions directly from the same Commander
metadata that powers CLI help and docs:

```
# Current shell (recommended)
eval "$(peekaboo completions $SHELL)"

# Explicit shells
eval "$(peekaboo completions zsh)"
eval "$(peekaboo completions bash)"
peekaboo completions fish | source
```

For persistent setup and troubleshooting, see
[docs/commands/completions.md](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/completions.md).

## Background vs foreground input

[Permalink: Background vs foreground input](https://github.com/openclaw/Peekaboo/blob/main/README.md#background-vs-foreground-input)

`click`, `type`, `press`, `hotkey`, and `paste` default to **background** delivery when Peekaboo can resolve a target process from `--app`, `--pid`, `--window-id`, or snapshot metadata. Background delivery posts process-targeted input without making the target app frontmost, so scripts can interact with Safari, Notes, Terminal, etc. without stealing focus.

Use `--foreground` when the app only accepts input in its focused key window, when you need a real foreground mouse event, or when you are intentionally driving the current focus. Focus flags such as `--space-switch` and `--bring-to-current-space` also imply foreground delivery. Background input requires Event Synthesizing permission for the process that sends the event; run `peekaboo permissions request-event-synthesizing` if `permissions status` reports it missing.

```
# Background: target Safari without activating it
peekaboo click "Address and search bar" --app Safari
peekaboo type "github.com/openclaw/Peekaboo" --app Safari --return

# Foreground: focus Safari first for apps/fields that reject background input
peekaboo click "Address and search bar" --app Safari --foreground
peekaboo type "github.com/openclaw/Peekaboo" --app Safari --return --foreground
```

| Command | Key flags / subcommands | What it does |
| --- | --- | --- |
| [see](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/see.md) | `--app`, `--mode screen/window`, `--retina`, `--json` | Capture and annotate UI, return snapshot + element IDs |
| [click](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/click.md) | `--on <id/query>`, `--snapshot`, `--wait-for`, `--coords`, `--foreground` | Click by element ID, label, or coordinates |
| [type](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/type.md) | `--text`, `--clear`, `--profile`, `--delay`, `--foreground` | Enter text with pacing options |
| [set-value](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/set-value.md) | `--on <id/query>`, `--value`, `--snapshot` | Directly set a settable accessibility value |
| [perform-action](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/perform-action.md) | `--on <id/query>`, `--action`, `--snapshot` | Invoke a named accessibility action |
| [press](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/press.md) | key names, `--count`, `--delay`, `--hold`, `--foreground` | Special keys and sequences |
| [hotkey](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/hotkey.md) | combos like `cmd,shift,t`, `--foreground` | Modifier combos (cmd/ctrl/alt/shift) |
| [paste](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/paste.md) | text/file/image payloads, `--restore-delay-ms`, `--foreground` | Paste with clipboard restore |
| [scroll](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/scroll.md) | `--on <id>`, `--direction up/down`, `--amount` | Scroll views or elements |
| [swipe](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/swipe.md) | `--from/--to`, `--duration`, `--steps` | Smooth gesture-style drags |
| [drag](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/drag.md) | `--from/--to`, modifiers, Dock/Trash targets | Drag-and-drop between elements/coords |
| [move](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/move.md) | `--to <id/coords>`, `--screen-index` | Position the cursor without clicking |
| [window](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/window.md) | `list`, `move`, `resize`, `focus`, `set-bounds` | Move/resize/focus windows and Spaces |
| [app](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/app.md) | `launch`, `quit`, `relaunch`, `switch`, `list` | Launch, quit, relaunch, switch apps |
| [space](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/space.md) | `list`, `switch`, `move-window` | List or switch macOS Spaces |
| [menu](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/menu.md) | `list`, `list-all`, `click`, `click-extra` | List/click app menus and extras |
| [menubar](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/menubar.md) | `list`, `click` | Target status-bar items by name/index |
| [dock](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/dock.md) | `launch`, `right-click`, `hide`, `show`, `list` | Interact with Dock items |
| [dialog](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/dialog.md) | `list`, `click`, `input`, `file`, `dismiss` | Drive system dialogs (open/save/etc.) |
| [image](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/image.md) | `--mode screen/window/menu`, `--retina`, `--analyze` | Screenshot screen/window/menu bar (+analyze) |
| [list](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/list.md) | `apps`, `windows`, `screens`, `menubar`, `permissions` | Enumerate apps, windows, screens, permissions |
| [tools](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/tools.md) | `--verbose`, `--json`, `--no-sort` | Inspect native Peekaboo tools |
| [completions](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/completions.md) | `[shell]` | Generate zsh/bash/fish completion scripts from Commander metadata |
| [config](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/config.md) | `init`, `show`, `add`, `login`, `models` | Manage credentials/providers/settings |
| [permissions](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/permissions.md) | `status`, `grant`, `request-event-synthesizing` | Check/grant required macOS permissions |
| [run](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/run.md) | `.peekaboo.json`, `--output`, `--no-fail-fast` | Execute `.peekaboo.json` automation scripts |
| [sleep](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/sleep.md) | `--duration` (ms) | Millisecond delays between steps |
| [clean](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/clean.md) | `--all-snapshots`, `--older-than`, `--snapshot` | Prune snapshots and caches |
| [agent](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/agent.md) | `--model`, `--dry-run`, `--resume`, `--max-steps`, audio | Natural-language multi-step automation |
| [mcp](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/mcp.md) | `serve` (default) | Run Peekaboo as an MCP server |

## Models and providers

[Permalink: Models and providers](https://github.com/openclaw/Peekaboo/blob/main/README.md#models-and-providers)

Peekaboo's provider list changes with Tachikoma and the tested model catalog. See
[docs/providers.md](https://github.com/openclaw/Peekaboo/blob/main/docs/providers.md) for the current provider reference, including OpenAI, Anthropic, xAI/Grok,
Google Gemini, MiniMax, Ollama, LM Studio, and compatible custom endpoints.

Set providers via `PEEKABOO_AI_PROVIDERS` or `peekaboo config add`.

## Learn more

[Permalink: Learn more](https://github.com/openclaw/Peekaboo/blob/main/README.md#learn-more)

- Command reference: [docs/commands/](https://github.com/openclaw/Peekaboo/blob/main/docs/commands)
- Platform support: [docs/platform-support.md](https://github.com/openclaw/Peekaboo/blob/main/docs/platform-support.md)
- Architecture: [docs/ARCHITECTURE.md](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md)
- Building from source: [docs/building.md](https://github.com/openclaw/Peekaboo/blob/main/docs/building.md)
- Testing guide: [docs/testing/tools.md](https://github.com/openclaw/Peekaboo/blob/main/docs/testing/tools.md)
- MCP setup: [docs/commands/mcp.md](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/mcp.md)
- Permissions: [docs/permissions.md](https://github.com/openclaw/Peekaboo/blob/main/docs/permissions.md)
- Ollama/local models: [docs/ollama.md](https://github.com/openclaw/Peekaboo/blob/main/docs/ollama.md)
- Agent chat loop: [docs/agent-chat.md](https://github.com/openclaw/Peekaboo/blob/main/docs/agent-chat.md)
- Service API reference: [docs/service-api-reference.md](https://github.com/openclaw/Peekaboo/blob/main/docs/service-api-reference.md)

## Community

[Permalink: Community](https://github.com/openclaw/Peekaboo/blob/main/README.md#community)

- [PeekabooWin](https://github.com/FelixKruger/PeekabooWin) — Windows-first rewrite of the Peekaboo automation loop (JavaScript + PowerShell) by [@FelixKruger](https://github.com/FelixKruger)
- [PeekabooX](https://github.com/nordbyte/PeekabooX) — Linux-first rewrite of the Peekaboo automation loop (Rust + Python) by [@nordbyte](https://github.com/nordbyte)

## Development basics

[Permalink: Development basics](https://github.com/openclaw/Peekaboo/blob/main/README.md#development-basics)

- Requirements: see [docs/platform-support.md](https://github.com/openclaw/Peekaboo/blob/main/docs/platform-support.md). Node 22+ is only needed for the npm MCP wrapper and pnpm helper scripts.
- Install deps: `pnpm install` then `pnpm run build:cli` or `pnpm run test:safe`.
- Lint/format: `pnpm run lint && pnpm run format`.

## License

[Permalink: License](https://github.com/openclaw/Peekaboo/blob/main/README.md#license)

MIT

You can’t perform that action at this time.