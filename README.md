# TensorAgent - multi-agentic AI harmonization & orchestration via CLI 

CLI-LLM orchestrator that allows for the parallel running of multiple agent models at once in one window via tmux. Allows for better monitoring of tasks instead of consistent context switching from one terminal window to another.

## features

- default linking with Gemini, Claude Code, Codex, and an optional extra window
- windows are resizable
- direct click-to-type process

<img width="1115" height="956" alt="image" src="https://github.com/user-attachments/assets/72af2b7c-8154-43fb-a0f5-cccf3da58d27" />


## Terminal behavior

- each pane is a real PTY-backed process running in-app
- click any pane and type directly.
- panes run in parallel and are isolated from each other.
- Type `,help,,` in any pane to print the built-in help index and docs link.

## Run

```bash
curl -fsSL https://install.blacktensor.net | bash && sudo ln -sf ~/.tensoragent/tensoragent /usr/local/bin/tensoragent
```
after installation completes, run  ```tensoragent orchestrate```  to run TensorAgent.

## CLI Wrapper (tensoragent)

when using the terminal wrapper (`tensoragent ...`):
- a 5-second centered ASCII boot splash is shown before launch
- `tensoragent0.0.1pa` is printed at top of each pane
- tmux sessions show version text in the top status bar
- typing `,help,,` in pane shells prints a basic help index

## Settings

use the top-right `Settings` button to configure:
- working directory
- safety checks
- unsafe shell command override (off by default)
- auto-launch behavior
- per-pane provider/model/args/custom command

closing settings automatically applies and relaunches the orchestration grid.


