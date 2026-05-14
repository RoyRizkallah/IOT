"""Typed config loader. YAML in, dataclasses out.

Each field can also be overridden by an environment variable. This is
how the Docker setup injects `SENTRY_MQTT_HOST=broker` and
`SENTRY_OLLAMA_BASE_URL=http://host.docker.internal:11434` without
needing a file in the image.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

import yaml


@dataclass
class LLMConfig:
    provider: str = "ollama"
    model: str = "qwen2.5:7b-instruct"
    base_url: str = "http://localhost:11434"
    temperature: float = 0.2
    max_tokens: int = 800
    request_timeout_s: float = 90.0


@dataclass
class AgentConfig:
    history_window_size: int = 12
    max_tool_call_retries: int = 2
    hard_alert_threshold: int = 7


@dataclass
class MqttConfig:
    enabled: bool = False
    host: str = "localhost"
    port: int = 1883
    topic_prefix: str = "home"


@dataclass
class LoggingConfig:
    level: str = "INFO"
    rich_console: bool = True


@dataclass
class StorageConfig:
    """SQLite persistence — mandatory in production but easy to point at
    `:memory:` for tests."""

    db_path: str = "data/sentry.db"
    history_load_limit: int = 50
    prune_max_rows: int = 5000


@dataclass
class Config:
    llm: LLMConfig
    agent: AgentConfig
    mqtt: MqttConfig
    logging: LoggingConfig
    storage: StorageConfig

    @classmethod
    def load(cls, path: str | Path) -> Config:
        with open(path, encoding="utf-8") as f:
            raw = yaml.safe_load(f) or {}
        cfg = cls(
            llm=LLMConfig(**(raw.get("llm") or {})),
            agent=AgentConfig(**(raw.get("agent") or {})),
            mqtt=MqttConfig(**(raw.get("mqtt") or {})),
            logging=LoggingConfig(**(raw.get("logging") or {})),
            storage=StorageConfig(**(raw.get("storage") or {})),
        )
        cfg.apply_env_overrides()
        return cfg

    @classmethod
    def default(cls) -> Config:
        cfg = cls(
            llm=LLMConfig(),
            agent=AgentConfig(),
            mqtt=MqttConfig(),
            logging=LoggingConfig(),
            storage=StorageConfig(),
        )
        cfg.apply_env_overrides()
        return cfg

    def apply_env_overrides(self) -> None:
        """Pick up `SENTRY_*` env vars. Docker injects these to point the
        process at the broker / Ollama running on the host or in another
        container, without baking a config file into the image."""
        if v := os.getenv("SENTRY_MQTT_HOST"):
            self.mqtt.host = v
        if v := os.getenv("SENTRY_MQTT_PORT"):
            self.mqtt.port = int(v)
        if v := os.getenv("SENTRY_MQTT_ENABLED"):
            self.mqtt.enabled = v.lower() in ("1", "true", "yes")
        if v := os.getenv("SENTRY_OLLAMA_BASE_URL"):
            self.llm.base_url = v
        if v := os.getenv("SENTRY_OLLAMA_MODEL"):
            self.llm.model = v
        if v := os.getenv("SENTRY_LOG_LEVEL"):
            self.logging.level = v
        if v := os.getenv("SENTRY_DB_PATH"):
            self.storage.db_path = v
