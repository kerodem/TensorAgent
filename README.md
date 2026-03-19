# MultiLLMTerminal (Windowed In-App Orchestrator)

A native macOS app that runs multiple CLI LLM processes in parallel inside one unified 3x2 terminal grid.

## Interface contract

Main window intentionally shows only:
- a 5-second ASCII launch splash before app load
- top label: `tensoragent0.0.1pa`
- one system orchestrator statline
- one live CPU/memory resource monitor line
- one top-right `Settings` button
- the 6 in-app terminal panes

No other main-window controls/buttons are shown.

## Terminal behavior

- Each pane is a real PTY-backed process running in-app.
- Click any pane and type directly.
- Font is Menlo.
- Panes run in parallel and are isolated from each other.
- Type `,help,,` in any pane to print the built-in help index and docs link.

## Run

```bash
cd /path/to/multi-llm-terminal
swift run MultiLLMTerminal
```

## CLI Wrapper (tensoragent)

When using the terminal wrapper (`tensoragent ...`):
- a 5-second ASCII boot splash is shown before launch
- `tensoragent0.0.1pa` is printed at top of each pane
- tmux sessions show version text in the top status bar
- typing `,help,,` in pane shells prints a basic help index ending with `https://blacktensor.net/docs`

## Settings

Use the top-right `Settings` button to configure:
- working directory
- safety checks
- unsafe shell command override (off by default)
- auto-launch behavior
- per-pane provider/model/args/custom command

Closing Settings automatically applies and relaunches the orchestration grid.

## Providers

Loaded from:
1. `~/Library/Application Support/MultiLLMTerminal/providers.json`
2. fallback local `providers.json`

Fields used:
- `id`, `name`, `description`
- `commandTemplate`, `defaultModel`
- `binary`, `authCommand`, `authNotes`
