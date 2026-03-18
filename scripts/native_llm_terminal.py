#!/usr/bin/env python3
"""Launch and orchestrate multiple LLM CLIs in native macOS terminals or tmux.

This tool intentionally avoids custom UI. Sessions run in:
- macOS Terminal windows/tabs, or
- tmux windows/panes (terminal-only multiplexing).
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class Provider:
    id: str
    name: str
    description: str
    command_template: str
    default_model: str
    binary: str
    auth_command: str
    auth_notes: str

    @staticmethod
    def from_json(payload: dict) -> "Provider":
        return Provider(
            id=str(payload.get("id", "")).strip(),
            name=str(payload.get("name", "")).strip(),
            description=str(payload.get("description", "")).strip(),
            command_template=str(payload.get("commandTemplate", "")).strip(),
            default_model=str(payload.get("defaultModel", "")).strip(),
            binary=str(payload.get("binary", "")).strip(),
            auth_command=str(payload.get("authCommand", "")).strip(),
            auth_notes=str(payload.get("authNotes", "")).strip(),
        )

    def resolved_binary(self) -> str:
        if self.binary:
            return self.binary
        first = self.command_template.split(" ", 1)[0].strip()
        return first


@dataclass(frozen=True)
class LaunchSpec:
    title: str
    provider_id: str
    cwd: str
    command: str


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    providers, providers_path = load_providers(args.providers_file)

    if args.command == "list":
        print(f"Providers file: {providers_path}")
        for provider in providers.values():
            auth = provider.auth_command or "(no auth command)"
            print(f"- {provider.id}: {provider.name}")
            print(f"  binary: {provider.resolved_binary() or '(none)'}")
            print(f"  auth:   {auth}")
        return 0

    if args.command == "auth":
        provider = get_provider_or_die(providers, args.provider)
        if not provider.auth_command:
            fail(f"Provider '{provider.id}' has no authCommand configured.")

        if not args.allow_unsafe_shell:
            ensure_safe_shell_fragment(
                provider.auth_command,
                context=f"auth command for provider '{provider.id}'",
            )

        if not args.skip_safety and not args.dry_run:
            ensure_provider_binary(provider)

        spec = LaunchSpec(
            title=args.title or f"{provider.name} auth",
            provider_id=provider.id,
            cwd=resolve_cwd(args.cwd),
            command=provider.auth_command,
        )
        launch_specs([spec], mode=args.mode, tmux_session=args.tmux_session, dry_run=args.dry_run)
        return 0

    if args.command == "run":
        provider = get_provider_or_die(providers, args.provider)
        if not args.skip_safety and not args.dry_run:
            ensure_provider_binary(provider)

        command = render_provider_command(
            provider,
            model=args.model,
            extra_args=args.extra_args,
            allow_unsafe_shell=args.allow_unsafe_shell,
        )
        spec = LaunchSpec(
            title=args.title or default_title(provider, args.model),
            provider_id=provider.id,
            cwd=resolve_cwd(args.cwd),
            command=command,
        )
        launch_specs([spec], mode=args.mode, tmux_session=args.tmux_session, dry_run=args.dry_run)
        return 0

    if args.command == "run-custom":
        if not args.allow_custom:
            fail("Refusing custom command. Pass --allow-custom to acknowledge risk.")
        if not args.allow_unsafe_shell:
            fail("run-custom requires --allow-unsafe-shell due direct shell execution risk.")

        spec = LaunchSpec(
            title=args.title or "custom",
            provider_id="custom",
            cwd=resolve_cwd(args.cwd),
            command=args.custom_command,
        )
        launch_specs([spec], mode=args.mode, tmux_session=args.tmux_session, dry_run=args.dry_run)
        return 0

    if args.command == "run-many":
        specs: list[LaunchSpec] = []

        for item in args.providers:
            provider_id, model = parse_provider_model(item)
            provider = get_provider_or_die(providers, provider_id)

            if not args.skip_safety and not args.dry_run:
                ensure_provider_binary(provider)

            command = render_provider_command(
                provider,
                model=model,
                extra_args=args.extra_args,
                allow_unsafe_shell=args.allow_unsafe_shell,
            )
            specs.append(
                LaunchSpec(
                    title=default_title(provider, model),
                    provider_id=provider.id,
                    cwd=resolve_cwd(args.cwd),
                    command=command,
                )
            )

        launch_specs(specs, mode=args.mode, tmux_session=args.tmux_session, dry_run=args.dry_run)
        return 0

    if args.command == "workflow":
        targets = args.providers or default_workflow_targets(
            providers,
            include_local=args.include_local,
        )
        specs: list[LaunchSpec] = []

        for item in targets:
            provider_id, model = parse_provider_model(item)
            provider = get_provider_or_die(providers, provider_id)

            if not args.skip_safety and not args.dry_run:
                ensure_provider_binary(provider)

            specs.append(
                LaunchSpec(
                    title=default_title(provider, model),
                    provider_id=provider.id,
                    cwd=resolve_cwd(args.cwd),
                    command=render_provider_command(
                        provider,
                        model=model,
                        extra_args=args.extra_args,
                        allow_unsafe_shell=args.allow_unsafe_shell,
                    ),
                )
            )

        if args.auth_first:
            auth_specs = build_auth_specs(
                providers,
                specs,
                cwd=resolve_cwd(args.cwd),
                allow_unsafe_shell=args.allow_unsafe_shell,
            )
            if auth_specs:
                auth_tmux_session = f"{args.tmux_session}-auth" if args.tmux_session else ""
                launch_specs(
                    auth_specs,
                    mode=args.auth_mode,
                    tmux_session=auth_tmux_session,
                    dry_run=args.dry_run,
                )

        launch_specs(specs, mode=args.mode, tmux_session=args.tmux_session, dry_run=args.dry_run)
        return 0

    if args.command == "orchestrate":
        cwd = resolve_cwd(args.cwd)
        targets = args.providers or default_workflow_targets(
            providers,
            include_local=args.include_local,
        )
        specs: list[LaunchSpec] = []

        for item in targets:
            provider_id, model = parse_provider_model(item)
            provider = get_provider_or_die(providers, provider_id)

            if not args.skip_safety and not args.dry_run:
                ensure_provider_binary(provider)

            specs.append(
                LaunchSpec(
                    title=default_title(provider, model),
                    provider_id=provider.id,
                    cwd=cwd,
                    command=render_provider_command(
                        provider,
                        model=model,
                        extra_args=args.extra_args,
                        allow_unsafe_shell=args.allow_unsafe_shell,
                    ),
                )
            )

        if args.max_panes > 0:
            specs = specs[: args.max_panes]

        if not specs:
            fail("No providers selected to orchestrate.")

        if args.max_panes > 0 and len(specs) < args.max_panes:
            for idx in range(len(specs) + 1, args.max_panes + 1):
                specs.append(
                    LaunchSpec(
                        title=f"idle-{idx}",
                        provider_id="idle",
                        cwd=cwd,
                        command="printf '[idle pane]\\n'; exec zsh -l",
                    )
                )

        if args.auth_first:
            auth_specs = build_auth_specs(
                providers,
                specs,
                cwd=cwd,
                allow_unsafe_shell=args.allow_unsafe_shell,
            )
            if auth_specs:
                auth_tmux_session = f"{args.session_name}-auth" if args.session_name else ""
                launch_specs(
                    auth_specs,
                    mode=args.auth_mode,
                    tmux_session=auth_tmux_session,
                    dry_run=args.dry_run,
                )

        launch_orchestrator_grid(
            specs=specs,
            session_name=args.session_name,
            attach=not args.detached,
            dry_run=args.dry_run,
        )
        return 0

    if args.command == "orchestrate-status":
        print_orchestrator_status(args.session_name)
        return 0

    if args.command == "orchestrate-send":
        send_to_orchestrator(
            session_name=args.session_name,
            target=args.target,
            text=args.text,
            press_enter=not args.no_enter,
        )
        return 0

    if args.command == "orchestrate-stop":
        stop_orchestrator(args.session_name)
        return 0

    parser.print_help()
    return 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="native_llm_terminal.py",
        description="Launch Claude/Codex/Gemini/local LLM CLIs in native Terminal or tmux.",
    )
    parser.add_argument(
        "--providers-file",
        default="",
        help="Optional providers.json path. Defaults to app support file, then repo providers.json.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    list_parser = subparsers.add_parser("list", help="List configured providers.")
    list_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="No-op for list command; kept for consistent CLI flags.",
    )

    auth_parser = subparsers.add_parser("auth", help="Open auth/login command in a native terminal.")
    auth_parser.add_argument("provider", help="Provider id (e.g. claude, codex, gemini).")
    add_shared_launch_args(auth_parser)

    run_parser = subparsers.add_parser("run", help="Run a single provider session.")
    run_parser.add_argument("provider", help="Provider id.")
    run_parser.add_argument("--model", default="", help="Model override.")
    run_parser.add_argument("--extra-args", default="", help="Additional raw CLI args.")
    add_shared_launch_args(run_parser)

    custom_parser = subparsers.add_parser("run-custom", help="Run a custom command (explicit opt-in).")
    custom_parser.add_argument("--custom-command", required=True, help="Full shell command to run.")
    custom_parser.add_argument("--allow-custom", action="store_true", help="Required safety acknowledgement.")
    add_shared_launch_args(custom_parser)

    many_parser = subparsers.add_parser(
        "run-many",
        help="Run multiple providers at once. Syntax: provider or provider:model",
    )
    many_parser.add_argument("providers", nargs="+", help="Example: claude codex gemini ollama:llama3.2")
    many_parser.add_argument("--extra-args", default="", help="Additional raw CLI args for every provider.")
    add_shared_launch_args(many_parser)

    workflow_parser = subparsers.add_parser(
        "workflow",
        help="All-in-one parallel workflow launch for multiple provider CLIs.",
    )
    workflow_parser.add_argument(
        "--providers",
        nargs="*",
        default=[],
        help="Provider list (provider or provider:model). Defaults to claude codex gemini.",
    )
    workflow_parser.add_argument(
        "--include-local",
        action="store_true",
        help="Include local runtimes (ollama/lmstudio) in default workflow target set.",
    )
    workflow_parser.add_argument("--extra-args", default="", help="Additional raw CLI args for every provider.")
    workflow_parser.add_argument(
        "--auth-first",
        action="store_true",
        help="Launch provider auth sessions before running workflow sessions.",
    )
    workflow_parser.add_argument(
        "--auth-mode",
        choices=["terminal-window", "terminal-tab", "tmux", "tmux-panes"],
        default="terminal-tab",
        help="Launch mode for auth sessions when --auth-first is enabled.",
    )
    add_shared_launch_args(workflow_parser, default_mode="tmux-panes")

    orchestrate_parser = subparsers.add_parser(
        "orchestrate",
        help="Start unified multi-pane tmux orchestration (terminal-native wrapper UI).",
    )
    orchestrate_parser.add_argument(
        "--providers",
        nargs="*",
        default=[],
        help="Provider list (provider or provider:model). Defaults to claude codex gemini.",
    )
    orchestrate_parser.add_argument(
        "--include-local",
        action="store_true",
        help="Include local runtimes (ollama/lmstudio) in default provider set.",
    )
    orchestrate_parser.add_argument("--extra-args", default="", help="Additional raw CLI args for every provider.")
    orchestrate_parser.add_argument("--cwd", default="", help="Working directory (defaults to current directory).")
    orchestrate_parser.add_argument(
        "--session-name",
        default="",
        help="tmux session name for orchestration grid (auto-generated if empty).",
    )
    orchestrate_parser.add_argument(
        "--max-panes",
        type=int,
        default=6,
        help="Total pane count (default: 6). If fewer providers are selected, idle panes fill the grid.",
    )
    orchestrate_parser.add_argument(
        "--auth-first",
        action="store_true",
        help="Launch provider auth sessions before starting orchestration panes.",
    )
    orchestrate_parser.add_argument(
        "--auth-mode",
        choices=["terminal-window", "terminal-tab", "tmux", "tmux-panes"],
        default="terminal-tab",
        help="Launch mode for auth sessions when --auth-first is enabled.",
    )
    orchestrate_parser.add_argument(
        "--detached",
        action="store_true",
        help="Create orchestration session without attaching to it.",
    )
    orchestrate_parser.add_argument("--skip-safety", action="store_true", help="Skip binary presence checks.")
    orchestrate_parser.add_argument(
        "--allow-unsafe-shell",
        action="store_true",
        help="Allow shell metacharacters in provider templates/args/auth commands.",
    )
    orchestrate_parser.add_argument("--dry-run", action="store_true", help="Print commands without launching.")

    orchestrate_status_parser = subparsers.add_parser(
        "orchestrate-status",
        help="Show pane/process status for an orchestration session.",
    )
    orchestrate_status_parser.add_argument(
        "--session-name",
        default="",
        required=True,
        help="tmux session name to inspect.",
    )

    orchestrate_send_parser = subparsers.add_parser(
        "orchestrate-send",
        help="Send input to one pane or all panes in an orchestration session.",
    )
    orchestrate_send_parser.add_argument(
        "--session-name",
        default="",
        required=True,
        help="tmux session name.",
    )
    orchestrate_send_parser.add_argument(
        "--target",
        default="all",
        help="Pane target: 'all', pane index (0-based), or tmux pane id.",
    )
    orchestrate_send_parser.add_argument(
        "--text",
        required=True,
        help="Text to send to selected pane(s).",
    )
    orchestrate_send_parser.add_argument(
        "--no-enter",
        action="store_true",
        help="Do not send Enter after text.",
    )

    orchestrate_stop_parser = subparsers.add_parser(
        "orchestrate-stop",
        help="Stop (kill) an orchestration tmux session.",
    )
    orchestrate_stop_parser.add_argument(
        "--session-name",
        default="",
        required=True,
        help="tmux session name to stop.",
    )

    return parser


def add_shared_launch_args(parser: argparse.ArgumentParser, default_mode: str = "terminal-window") -> None:
    parser.add_argument(
        "--mode",
        choices=["terminal-window", "terminal-tab", "tmux", "tmux-panes"],
        default=default_mode,
        help="Launch mode.",
    )
    parser.add_argument("--cwd", default="", help="Working directory (defaults to current directory).")
    parser.add_argument("--title", default="", help="Terminal title label.")
    parser.add_argument("--tmux-session", default="", help="tmux session name (tmux mode only).")
    parser.add_argument("--skip-safety", action="store_true", help="Skip binary presence checks.")
    parser.add_argument(
        "--allow-unsafe-shell",
        action="store_true",
        help="Allow shell metacharacters in provider templates/args/auth commands.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print commands without launching.")


def load_providers(override_path: str) -> tuple[dict[str, Provider], Path]:
    if override_path:
        path = Path(override_path).expanduser()
        providers = read_provider_file(path)
        return providers, path

    app_support = Path.home() / "Library/Application Support/MultiLLMTerminal/providers.json"
    repo_default = Path(__file__).resolve().parents[1] / "providers.json"

    default_providers = read_provider_file(repo_default, required=False)

    if app_support.exists():
        user_providers = read_provider_file(app_support)
        merged = merge_provider_maps(default_providers, user_providers)
        return merged, app_support

    if default_providers:
        return default_providers, repo_default

    fail(
        "No providers.json found. Checked:\n"
        + f"- {app_support}\n"
        + f"- {repo_default}"
    )


def read_provider_file(path: Path, required: bool = True) -> dict[str, Provider]:
    if not path.exists():
        if required:
            fail(f"Providers file not found: {path}")
        return {}

    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        fail(f"Failed to read providers file '{path}': {exc}")

    if not isinstance(raw, list):
        fail(f"Providers file must contain a JSON array: {path}")

    providers: dict[str, Provider] = {}
    for item in raw:
        if not isinstance(item, dict):
            continue
        provider = Provider.from_json(item)
        if provider.id and provider.command_template:
            providers[provider.id] = provider

    if required and not providers:
        fail(f"No valid providers found in: {path}")

    return providers


def merge_provider_maps(defaults: dict[str, Provider], user: dict[str, Provider]) -> dict[str, Provider]:
    merged: dict[str, Provider] = {}

    for provider_id, user_provider in user.items():
        merged[provider_id] = merge_provider(defaults.get(provider_id), user_provider)

    for provider_id, default_provider in defaults.items():
        if provider_id not in merged:
            merged[provider_id] = default_provider

    return merged


def merge_provider(default_provider: Provider | None, user_provider: Provider) -> Provider:
    if default_provider is None:
        return user_provider

    return Provider(
        id=user_provider.id,
        name=user_provider.name or default_provider.name,
        description=user_provider.description or default_provider.description,
        command_template=user_provider.command_template or default_provider.command_template,
        default_model=user_provider.default_model or default_provider.default_model,
        binary=user_provider.binary or default_provider.binary,
        auth_command=user_provider.auth_command or default_provider.auth_command,
        auth_notes=user_provider.auth_notes or default_provider.auth_notes,
    )


def get_provider_or_die(providers: dict[str, Provider], provider_id: str) -> Provider:
    provider = providers.get(provider_id)
    if provider is None:
        available = ", ".join(sorted(providers.keys()))
        fail(f"Unknown provider '{provider_id}'. Available: {available}")
    return provider


def resolve_cwd(raw: str) -> str:
    cwd = raw.strip() if raw.strip() else os.getcwd()
    path = Path(cwd).expanduser().resolve()

    if not path.exists():
        fail(f"Working directory does not exist: {path}")
    if not path.is_dir():
        fail(f"Working directory is not a directory: {path}")

    return str(path)


def parse_provider_model(value: str) -> tuple[str, str]:
    if ":" not in value:
        return value, ""
    provider_id, model = value.split(":", 1)
    return provider_id.strip(), model.strip()


def default_workflow_targets(providers: dict[str, Provider], include_local: bool) -> list[str]:
    targets: list[str] = []

    for provider_id in ["claude", "codex", "gemini"]:
        if provider_id in providers:
            targets.append(provider_id)

    if include_local:
        if "ollama" in providers:
            targets.append("ollama")
        if "lmstudio" in providers:
            targets.append("lmstudio")

    if not targets:
        targets = list(sorted(providers.keys()))

    return targets


def build_auth_specs(
    providers: dict[str, Provider],
    run_specs: list[LaunchSpec],
    cwd: str,
    allow_unsafe_shell: bool,
) -> list[LaunchSpec]:
    specs: list[LaunchSpec] = []
    seen: set[str] = set()

    for run_spec in run_specs:
        provider = providers.get(run_spec.provider_id)
        if provider is None or not provider.auth_command:
            continue
        if provider.id in seen:
            continue
        if not allow_unsafe_shell:
            ensure_safe_shell_fragment(
                provider.auth_command,
                context=f"auth command for provider '{provider.id}'",
            )

        seen.add(provider.id)
        specs.append(
            LaunchSpec(
                title=f"{provider.name} auth",
                provider_id=provider.id,
                cwd=cwd,
                command=provider.auth_command,
            )
        )

    return specs


def default_title(provider: Provider, model: str) -> str:
    use_model = (model or provider.default_model).strip()
    return provider.name if not use_model else f"{provider.name}:{use_model}"


def render_provider_command(
    provider: Provider,
    model: str,
    extra_args: str,
    allow_unsafe_shell: bool,
) -> str:
    command = provider.command_template
    selected_model = (model or provider.default_model).strip()

    if not allow_unsafe_shell:
        ensure_safe_shell_fragment(
            command,
            context=f"command template for provider '{provider.id}'",
        )

    if "{model}" in command:
        if not selected_model:
            fail(f"Provider '{provider.id}' requires a model value.")
        command = command.replace("{model}", shlex.quote(selected_model))

    rendered = command.strip()
    if extra_args.strip():
        if not allow_unsafe_shell:
            ensure_safe_shell_fragment(
                extra_args,
                context="extra args",
            )
        rendered = f"{rendered} {extra_args.strip()}"

    if not rendered:
        fail(f"Provider '{provider.id}' rendered an empty command.")

    return rendered


def ensure_provider_binary(provider: Provider) -> None:
    binary = provider.resolved_binary().strip()
    if not binary:
        return

    if "/" in binary:
        path = Path(binary).expanduser()
        if not (path.exists() and os.access(path, os.X_OK)):
            fail(f"Provider '{provider.id}' binary is not executable: {binary}")
        return

    if shutil.which(binary) is None:
        fail(
            f"Provider '{provider.id}' requires '{binary}' in PATH. "
            "Install/authenticate the CLI first or pass --skip-safety."
        )


def ensure_safe_shell_fragment(fragment: str, context: str) -> None:
    blocked_markers = (";", "|", "&", "`", "$(", ">", "<", "\n", "\r")
    if any(marker in fragment for marker in blocked_markers):
        fail(
            f"{context} contains blocked shell metacharacters. "
            "Pass --allow-unsafe-shell only if you trust this command."
        )


def launch_specs(specs: Iterable[LaunchSpec], mode: str, tmux_session: str, dry_run: bool) -> None:
    specs = list(specs)
    if not specs:
        fail("No sessions to launch.")

    if mode in {"terminal-window", "terminal-tab"}:
        ensure_terminal_available()
        for spec in specs:
            launch_terminal(spec, force_new_window=(mode == "terminal-window"), dry_run=dry_run)
        return

    if mode == "tmux":
        launch_tmux(specs, session_name=tmux_session, dry_run=dry_run)
        return

    if mode == "tmux-panes":
        launch_tmux_panes(specs, session_name=tmux_session, dry_run=dry_run)
        return

    fail(f"Unsupported mode: {mode}")


def ensure_terminal_available() -> None:
    if shutil.which("osascript") is None:
        fail("osascript is required for terminal-window/terminal-tab mode.")


def launch_terminal(spec: LaunchSpec, force_new_window: bool, dry_run: bool) -> None:
    wrapped = wrap_shell_command(spec)

    if dry_run:
        mode = "terminal-window" if force_new_window else "terminal-tab"
        print(f"[{mode}] {spec.title}")
        print(f"  cwd: {spec.cwd}")
        print(f"  cmd: {spec.command}")
        return

    if force_new_window:
        subprocess.run(["open", "-na", "Terminal"], check=True)
        time.sleep(0.25)

    run_osascript(wrapped)


def run_osascript(command: str) -> None:
    command_literal = json.dumps(command)
    subprocess.run(
        [
            "osascript",
            "-e",
            'tell application "Terminal" to activate',
            "-e",
            f'tell application "Terminal" to do script {command_literal}',
        ],
        check=True,
    )


def wrap_shell_command(spec: LaunchSpec) -> str:
    title_label = shlex.quote(spec.title)
    provider_label = shlex.quote(spec.provider_id)
    cwd_label = shlex.quote(spec.cwd)
    cwd_part = shlex.quote(spec.cwd)

    return (
        f"cd {cwd_part} && "
        f"clear && "
        f"echo '[session] title=' {title_label} ' provider=' {provider_label} && "
        f"echo '[session] cwd=' {cwd_label} && "
        f"{spec.command}; "
        "rc=$?; "
        "echo; "
        "echo '[session] process exited with code' $rc; "
        "exec zsh -l"
    )


def launch_tmux(specs: list[LaunchSpec], session_name: str, dry_run: bool) -> None:
    session = session_name.strip() or f"multi-llm-{int(time.time())}"

    if dry_run:
        print(f"[tmux] session: {session}")
        for spec in specs:
            print(f"  window: {spec.title}")
            print(f"    cwd: {spec.cwd}")
            print(f"    cmd: {spec.command}")
        return

    if shutil.which("tmux") is None:
        fail("tmux mode requested but tmux is not installed.")

    for index, spec in enumerate(specs):
        shell_cmd = wrap_shell_command(spec)
        window_name = sanitize_tmux_name(spec.title)

        if index == 0:
            subprocess.run(
                ["tmux", "new-session", "-d", "-s", session, "-n", window_name, shell_cmd],
                check=True,
            )
        else:
            subprocess.run(
                ["tmux", "new-window", "-t", session, "-n", window_name, shell_cmd],
                check=True,
            )

    subprocess.run(["tmux", "attach-session", "-t", session], check=True)


def launch_tmux_panes(specs: list[LaunchSpec], session_name: str, dry_run: bool) -> None:
    session = session_name.strip() or f"multi-llm-{int(time.time())}"

    if dry_run:
        print(f"[tmux-panes] session: {session}")
        for idx, spec in enumerate(specs, start=1):
            print(f"  pane {idx}: {spec.title}")
            print(f"    cwd: {spec.cwd}")
            print(f"    cmd: {spec.command}")
        return

    if shutil.which("tmux") is None:
        fail("tmux-panes mode requested but tmux is not installed.")

    first = specs[0]
    subprocess.run(
        ["tmux", "new-session", "-d", "-s", session, "-n", "llms", wrap_shell_command(first)],
        check=True,
    )

    for idx, spec in enumerate(specs[1:], start=1):
        split_flag = "-h" if idx % 2 else "-v"
        subprocess.run(
            ["tmux", "split-window", split_flag, "-t", f"{session}:0", wrap_shell_command(spec)],
            check=True,
        )
        subprocess.run(["tmux", "select-layout", "-t", f"{session}:0", "tiled"], check=True)

    subprocess.run(["tmux", "set-option", "-t", session, "remain-on-exit", "on"], check=True)
    subprocess.run(["tmux", "attach-session", "-t", session], check=True)


def launch_orchestrator_grid(
    specs: list[LaunchSpec],
    session_name: str,
    attach: bool,
    dry_run: bool,
) -> None:
    session = session_name.strip() or f"llm-grid-{int(time.time())}"

    if dry_run:
        print(f"[orchestrate] session: {session}")
        print("layout: 3x2 tiled pane grid")
        for index, spec in enumerate(specs, start=1):
            print(f"  pane {index}: {spec.title}")
            print(f"    cwd: {spec.cwd}")
            print(f"    cmd: {spec.command}")
        print(f"attach: {'yes' if attach else 'no'}")
        return

    ensure_tmux_installed_for_orchestrator()

    if tmux_has_session(session):
        fail(f"tmux session '{session}' already exists. Use a different --session-name or stop it first.")

    first = specs[0]
    run_tmux(["new-session", "-d", "-s", session, "-n", "agents", wrap_shell_command(first)])
    pane_ids = [run_tmux(["display-message", "-p", "-t", f"{session}:0.0", "#{pane_id}"], capture=True)]

    for index, spec in enumerate(specs[1:], start=1):
        split_flag = "-h" if index % 2 else "-v"
        pane_id = run_tmux(
            ["split-window", split_flag, "-t", f"{session}:0", "-P", "-F", "#{pane_id}", wrap_shell_command(spec)],
            capture=True,
        )
        pane_ids.append(pane_id)
        run_tmux(["select-layout", "-t", f"{session}:0", "tiled"])

    run_tmux(["set-option", "-t", session, "remain-on-exit", "on"])
    run_tmux(["set-option", "-t", session, "mouse", "on"])
    run_tmux(["set-option", "-t", session, "pane-border-status", "top"])
    run_tmux(["set-option", "-t", session, "pane-border-format", "#{pane_index} #{pane_title}"])
    run_tmux(["set-option", "-t", session, "status-left", f"[orchestrator:{session}] "])
    run_tmux(["set-option", "-t", session, "status-right", "%Y-%m-%d %H:%M"])

    for pane_id, spec in zip(pane_ids, specs):
        run_tmux(["select-pane", "-t", pane_id, "-T", sanitize_tmux_name(spec.title)])

    run_tmux(["select-layout", "-t", f"{session}:0", "tiled"])

    if attach:
        subprocess.run(["tmux", "attach-session", "-t", session], check=True)
    else:
        print(f"Started orchestration session '{session}' (detached).")
        print(f"Attach with: tmux attach-session -t {session}")


def print_orchestrator_status(session_name: str) -> None:
    session = session_name.strip()
    if not session:
        fail("--session-name is required.")

    ensure_tmux_installed_for_orchestrator()

    if not tmux_has_session(session):
        fail(f"tmux session '{session}' not found.")

    rows = run_tmux(
        [
            "list-panes",
            "-t",
            session,
            "-F",
            "#{pane_index}\t#{pane_id}\t#{pane_title}\t#{pane_current_command}\t#{pane_dead}\t#{pane_pid}",
        ],
        capture=True,
    )

    print(f"orchestrator session: {session}")
    print("pane\tpane_id\ttitle\tcommand\tdead\tpid")
    for row in rows.splitlines():
        print(row)


def send_to_orchestrator(session_name: str, target: str, text: str, press_enter: bool) -> None:
    session = session_name.strip()
    if not session:
        fail("--session-name is required.")

    ensure_tmux_installed_for_orchestrator()

    if not tmux_has_session(session):
        fail(f"tmux session '{session}' not found.")

    targets: list[str]
    requested = target.strip() if target.strip() else "all"

    if requested == "all":
        pane_rows = run_tmux(["list-panes", "-t", session, "-F", "#{pane_id}"], capture=True)
        targets = [row.strip() for row in pane_rows.splitlines() if row.strip()]
    elif requested.isdigit():
        targets = [f"{session}:0.{requested}"]
    else:
        targets = [requested]

    for pane_target in targets:
        run_tmux(["send-keys", "-t", pane_target, text])
        if press_enter:
            run_tmux(["send-keys", "-t", pane_target, "Enter"])

    print(f"sent input to {len(targets)} pane(s)")


def stop_orchestrator(session_name: str) -> None:
    session = session_name.strip()
    if not session:
        fail("--session-name is required.")

    ensure_tmux_installed_for_orchestrator()

    if not tmux_has_session(session):
        fail(f"tmux session '{session}' not found.")

    run_tmux(["kill-session", "-t", session])
    print(f"stopped session '{session}'")


def ensure_tmux_installed_for_orchestrator() -> None:
    if shutil.which("tmux") is None:
        fail("tmux is required for orchestration mode. Install tmux and retry.")


def tmux_has_session(session_name: str) -> bool:
    result = subprocess.run(
        ["tmux", "has-session", "-t", session_name],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode == 0


def run_tmux(args: list[str], capture: bool = False) -> str:
    result = subprocess.run(
        ["tmux", *args],
        capture_output=capture,
        text=True,
        check=False,
    )

    if result.returncode != 0:
        stderr = result.stderr.strip() if result.stderr else ""
        message = f"tmux {' '.join(args)} failed with code {result.returncode}"
        if stderr:
            message += f": {stderr}"
        fail(message)

    return result.stdout.strip() if capture else ""


def sanitize_tmux_name(name: str) -> str:
    cleaned = "".join(ch if ch.isalnum() or ch in {"-", "_", ":"} else "-" for ch in name)
    return cleaned[:40] or "session"


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


if __name__ == "__main__":
    raise SystemExit(main())
