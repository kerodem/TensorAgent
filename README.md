# MultiLLMTerminal (Windowed In-App Orchestrator)

A native macOS app that runs multiple CLI LLM processes in parallel inside one unified 3x2 terminal grid.

## Interface contract

Main window intentionally shows only:
- one system orchestrator statline
- one top-right `Settings` button
- the 6 in-app terminal panes

No other main-window controls/buttons are shown.

## Terminal behavior

- Each pane is a real PTY-backed process running in-app.
- Click any pane and type directly.
- Font is Menlo.
- Panes run in parallel and are isolated from each other.

## Run

```bash
cd /path/to/multi-llm-terminal
swift run MultiLLMTerminal
```

## Settings

Use the top-right `Settings` button to configure:
- working directory
- safety checks
- unsafe shell command override (off by default)
- auto-launch behavior (off by default)
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
