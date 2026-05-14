"""Jinja2 prompt loader. Templates live next to this file in `prompts/`."""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Any

from jinja2 import Environment, FileSystemLoader, StrictUndefined, select_autoescape

_PROMPTS_DIR = Path(__file__).parent / "prompts"


@lru_cache(maxsize=1)
def _env() -> Environment:
    return Environment(
        loader=FileSystemLoader(str(_PROMPTS_DIR)),
        autoescape=select_autoescape(default=False),
        undefined=StrictUndefined,
        trim_blocks=True,
        lstrip_blocks=True,
        keep_trailing_newline=False,
    )


def render(template_name: str, **ctx: Any) -> str:
    """Render `prompts/<template_name>` with the given context."""
    template = _env().get_template(template_name)
    return template.render(**ctx)


def system_prompt() -> str:
    """The static system prompt — same across every decision."""
    return render("system.j2")
