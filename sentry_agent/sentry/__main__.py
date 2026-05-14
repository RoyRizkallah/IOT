"""CLI entrypoint.

Examples:
    sentry decide tests/fixtures/3am_back_door.json
    sentry serve  --broker-host localhost
    sentry mock   --scenario suspicious
    sentry version
"""

from __future__ import annotations

import asyncio
import json
import logging
import sys
from pathlib import Path

import typer
from rich.console import Console
from rich.logging import RichHandler
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from . import __version__
from .agent import DecisionEngine
from .chat import ChatService
from .config import Config
from .llm.ollama import OllamaClient, OllamaUnavailableError
from .models import AgentDecision, DecisionRequest, ThreatLevel
from .mqtt.bus import MqttBus
from .orchestrator import Orchestrator
from .sensors.mock import MockSensorPublisher
from .storage import Storage

app = typer.Typer(
    no_args_is_help=True,
    add_completion=False,
    help="SentryAgent — local-LLM home security agent.",
)

# `safe_box=True` keeps panel borders to ASCII-safe glyphs on the legacy
# Windows console (cp1252) while still looking great in Windows Terminal.
console = Console(safe_box=True)


# ─────────────────────────────────────────────────────────────────────────────
# Commands
# ─────────────────────────────────────────────────────────────────────────────


@app.command()
def version() -> None:
    """Print the package version."""
    console.print(f"[bold cyan]sentry_agent[/bold cyan] v{__version__}")


@app.command()
def decide(
    fixture: Path = typer.Argument(  # noqa: B008
        ...,
        exists=True,
        readable=True,
        help="Path to a JSON file containing a DecisionRequest.",
    ),
    config_path: Path = typer.Option(  # noqa: B008
        Path("config.yaml"),
        "--config",
        "-c",
        help="Config file. Defaults to ./config.yaml.",
    ),
    raw: bool = typer.Option(
        False,
        "--raw",
        help="Print the AgentDecision as JSON (for piping into another process).",
    ),
) -> None:
    """Run the agent on a single event fixture and print the decision."""
    cfg = _load_config(config_path)
    _setup_logging(cfg.logging.level, cfg.logging.rich_console)

    with open(fixture, encoding="utf-8") as f:
        req = DecisionRequest.model_validate(json.load(f))

    if not raw:
        _print_request_summary(req)

    decision = asyncio.run(_run_decide(cfg, req))

    if raw:
        # JSON mode: only print the decision, nothing else (so it's pipeable)
        print(decision.model_dump_json(indent=2))
    else:
        _print_decision(decision)


@app.command()
def serve(
    config_path: Path = typer.Option(  # noqa: B008
        Path("config.yaml"),
        "--config",
        "-c",
        help="Config file. Defaults to ./config.yaml.",
    ),
    broker_host: str | None = typer.Option(
        None,
        "--broker-host",
        help="MQTT broker host (overrides config / SENTRY_MQTT_HOST).",
    ),
    broker_port: int | None = typer.Option(
        None,
        "--broker-port",
        help="MQTT broker port (overrides config / SENTRY_MQTT_PORT).",
    ),
    ollama_url: str | None = typer.Option(
        None,
        "--ollama-url",
        help="Ollama base URL (overrides config / SENTRY_OLLAMA_BASE_URL).",
    ),
) -> None:
    """Run the agent orchestrator. Subscribes to sensor topics, runs the
    LLM on warning+ events, and publishes decisions back to MQTT."""
    cfg = _load_config(config_path)
    if broker_host:
        cfg.mqtt.host = broker_host
    if broker_port:
        cfg.mqtt.port = broker_port
    if ollama_url:
        cfg.llm.base_url = ollama_url

    _setup_logging(cfg.logging.level, cfg.logging.rich_console)

    console.print(
        Panel(
            Text.from_markup(
                f"[bold]Broker[/bold]  {cfg.mqtt.host}:{cfg.mqtt.port}\n"
                f"[bold]Ollama[/bold]  {cfg.llm.base_url}\n"
                f"[bold]Model [/bold]  {cfg.llm.model}\n"
                f"[bold]DB    [/bold]  {cfg.storage.db_path}",
            ),
            title="SentryAgent · serve",
            border_style="cyan",
        )
    )
    asyncio.run(_run_serve(cfg))


@app.command()
def mock(
    config_path: Path = typer.Option(  # noqa: B008
        Path("config.yaml"),
        "--config",
        "-c",
        help="Config file. Defaults to ./config.yaml.",
    ),
    broker_host: str | None = typer.Option(
        None,
        "--broker-host",
        help="MQTT broker host (overrides config / SENTRY_MQTT_HOST).",
    ),
    broker_port: int | None = typer.Option(
        None,
        "--broker-port",
        help="MQTT broker port.",
    ),
    scenario: str = typer.Option(
        "default",
        "--scenario",
        "-s",
        help="One of: default | suspicious | flapping.",
    ),
    speed: float = typer.Option(
        1.0,
        "--speed",
        help="Time scale (2.0 = twice as fast).",
    ),
) -> None:
    """Run a mock sensor publisher. Use this in place of the Pi until the
    real hardware is on the network."""
    if scenario not in ("default", "suspicious", "flapping"):
        raise typer.BadParameter(
            "scenario must be one of: default | suspicious | flapping"
        )
    cfg = _load_config(config_path)
    if broker_host:
        cfg.mqtt.host = broker_host
    if broker_port:
        cfg.mqtt.port = broker_port

    _setup_logging(cfg.logging.level, cfg.logging.rich_console)

    console.print(
        Panel(
            Text.from_markup(
                f"[bold]Broker  [/bold] {cfg.mqtt.host}:{cfg.mqtt.port}\n"
                f"[bold]Scenario[/bold] {scenario}\n"
                f"[bold]Speed   [/bold] x{speed:g}",
            ),
            title="SentryAgent · mock sensors",
            border_style="cyan",
        )
    )
    asyncio.run(_run_mock(cfg, scenario, speed))


# ─────────────────────────────────────────────────────────────────────────────
# Async core
# ─────────────────────────────────────────────────────────────────────────────


async def _run_serve(cfg: Config) -> None:
    bus = MqttBus(
        host=cfg.mqtt.host,
        port=cfg.mqtt.port,
        client_id="sentry-orchestrator",
    )
    llm = OllamaClient(
        model=cfg.llm.model,
        base_url=cfg.llm.base_url,
        request_timeout_s=cfg.llm.request_timeout_s,
    )
    try:
        await llm.ensure_model_available()
        engine = DecisionEngine(
            llm=llm,
            max_format_retries=cfg.agent.max_tool_call_retries,
            temperature=cfg.llm.temperature,
            max_tokens=cfg.llm.max_tokens,
            hard_alert_threshold=cfg.agent.hard_alert_threshold,
        )
        chat = ChatService(
            llm=llm,
            max_format_retries=cfg.agent.max_tool_call_retries,
            temperature=0.4,
            max_tokens=cfg.llm.max_tokens,
        )
        storage = Storage(cfg.storage.db_path)
        await storage.connect()
        try:
            orch = Orchestrator(
                bus=bus,
                engine=engine,
                chat=chat,
                storage=storage,
                history_window=cfg.agent.history_window_size,
                history_load_limit=cfg.storage.history_load_limit,
            )
            await orch.run()
        finally:
            await storage.close()
    finally:
        await llm.aclose()


async def _run_mock(cfg: Config, scenario: str, speed: float) -> None:
    bus = MqttBus(
        host=cfg.mqtt.host,
        port=cfg.mqtt.port,
        client_id="sentry-mock-sensors",
    )
    pub = MockSensorPublisher(
        bus=bus,
        scenario=scenario,  # type: ignore[arg-type]
        speed=speed,
    )
    await pub.run()


def _load_config(path: Path) -> Config:
    return Config.load(path) if path.exists() else Config.default()


async def _run_decide(cfg: Config, req: DecisionRequest) -> AgentDecision:
    if cfg.llm.provider != "ollama":
        raise typer.BadParameter(
            f"Provider '{cfg.llm.provider}' is not implemented yet. "
            "Only 'ollama' is supported in this build."
        )

    llm = OllamaClient(
        model=cfg.llm.model,
        base_url=cfg.llm.base_url,
        request_timeout_s=cfg.llm.request_timeout_s,
    )
    try:
        await llm.ensure_model_available()
        engine = DecisionEngine(
            llm=llm,
            max_format_retries=cfg.agent.max_tool_call_retries,
            temperature=cfg.llm.temperature,
            max_tokens=cfg.llm.max_tokens,
            hard_alert_threshold=cfg.agent.hard_alert_threshold,
        )
        with console.status(
            f"[bold cyan]Reasoning with {cfg.llm.model}...[/bold cyan]",
            spinner="dots",
        ):
            decision = await engine.decide(req)
        return decision
    except OllamaUnavailableError as e:
        console.print(
            Panel(
                Text(str(e), style="red"),
                title="Ollama not reachable",
                border_style="red",
            )
        )
        sys.exit(2)
    finally:
        await llm.aclose()


# ─────────────────────────────────────────────────────────────────────────────
# Pretty printing
# ─────────────────────────────────────────────────────────────────────────────


def _print_request_summary(req: DecisionRequest) -> None:
    e = req.triggering_event
    s = req.current_state

    header = Text()
    header.append("TRIGGERING EVENT\n", style="bold yellow")
    header.append(f"  sensor   : {e.sensor.value}\n")
    header.append(
        f"  severity : {e.severity.value.upper()}\n",
        style=_severity_style(e.severity),
    )
    header.append(f"  message  : {e.message}\n")
    header.append(f"  time     : {e.timestamp.isoformat()}\n")
    header.append("\nCURRENT STATE\n", style="bold")
    header.append(f"  armed       : {s.armed}\n")
    header.append(
        f"  threat score: {s.threat_score}/10 ({s.level.value.upper()})\n",
        style=_severity_style(s.level),
    )
    header.append(f"  last update : {s.last_update.isoformat()}\n")

    if req.recent_events:
        header.append(
            f"\nRECENT EVENTS ({len(req.recent_events)})\n", style="bold"
        )
        for ev in req.recent_events[:5]:
            header.append(
                f"  - {ev.timestamp.isoformat()} | {ev.sensor.value:<11} "
                f"| {ev.severity.value:<7} | {ev.message}\n",
                style="dim",
            )
        if len(req.recent_events) > 5:
            header.append(
                f"  ... and {len(req.recent_events) - 5} more\n", style="dim"
            )

    console.print(Panel(header, title="Decision Request", border_style="cyan"))


def _print_decision(d: AgentDecision) -> None:
    sev_style = _severity_style(d.severity)
    action_color = _action_color(d.final_action)

    body = Text()
    body.append(f"{d.summary}\n\n", style="bold")
    body.append("CONTEXT  ", style="bold dim")
    body.append(f"{d.context}\n\n")
    body.append("REASONING  ", style="bold dim")
    body.append(f"{d.reasoning}\n\n")
    body.append("ACTION  ", style="bold dim")
    body.append(f"{d.final_action}", style=f"bold {action_color}")
    body.append(f" — {d.final_action_reason}\n")

    console.print(
        Panel(
            body,
            title=f"[{sev_style}]●[/{sev_style}] {d.severity.value.upper()} · decision {d.id}",
            border_style=sev_style,
        )
    )

    if d.tools_called:
        table = Table(
            title="Tool calls",
            show_header=True,
            header_style="bold cyan",
            border_style="dim",
        )
        table.add_column("#", style="dim", width=3)
        table.add_column("Tool", style="cyan")
        table.add_column("Args", overflow="fold")
        table.add_column("Result", overflow="fold")
        for i, t in enumerate(d.tools_called, 1):
            table.add_row(str(i), t.name, t.args_summary, t.result_summary)
        console.print(table)


def _severity_style(s: ThreatLevel) -> str:
    return {
        ThreatLevel.safe: "green",
        ThreatLevel.warning: "yellow",
        ThreatLevel.alert: "red",
    }[s]


def _action_color(action: str) -> str:
    return {
        "ignore": "dim",
        "log": "white",
        "auto_resolve": "green",
        "notify_user": "yellow",
        "request_confirmation": "yellow",
        "trigger_siren": "red",
    }.get(action, "white")


def _setup_logging(level: str, rich_console: bool) -> None:
    handler: logging.Handler
    if rich_console:
        handler = RichHandler(
            console=console,
            show_time=False,
            show_path=False,
            markup=False,
            rich_tracebacks=True,
        )
        fmt = "%(message)s"
    else:
        handler = logging.StreamHandler()
        fmt = "%(asctime)s %(levelname)s %(name)s: %(message)s"

    logging.basicConfig(
        level=level.upper(),
        format=fmt,
        handlers=[handler],
        force=True,
    )
    # Quiet down httpx — its INFO is too chatty.
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)


if __name__ == "__main__":
    app()
