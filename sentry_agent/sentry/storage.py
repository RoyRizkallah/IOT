"""SQLite-backed persistence for the orchestrator.

Stores three logs (events, decisions, chat) and the latest state as
JSON-in-a-cell. The schema deliberately keeps one column for the full
Pydantic JSON dump so it survives model changes — pulling a row gives
you the model back via `Model.model_validate_json(payload)`.

The orchestrator hydrates its in-memory deques from this DB on startup,
persists every new event/decision/chat as it happens, and writes the
latest state on every heartbeat. Replay over MQTT serves whatever is in
those deques (which are now disk-backed).

Why aiosqlite: blocking sqlite3 calls would block the asyncio loop on a
slow disk write; aiosqlite hands them to a thread pool. Cheap and right.
"""

from __future__ import annotations

import logging
from pathlib import Path

import aiosqlite

from .models import (
    AgentDecision,
    ChatMessage,
    SecurityEvent,
    SecurityState,
)

logger = logging.getLogger(__name__)


_SCHEMA = """
CREATE TABLE IF NOT EXISTS events (
    id        TEXT PRIMARY KEY,
    timestamp TEXT NOT NULL,
    payload   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp DESC);

CREATE TABLE IF NOT EXISTS decisions (
    id        TEXT PRIMARY KEY,
    timestamp TEXT NOT NULL,
    payload   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_decisions_timestamp ON decisions(timestamp DESC);

CREATE TABLE IF NOT EXISTS chat_messages (
    id        TEXT PRIMARY KEY,
    timestamp TEXT NOT NULL,
    role      TEXT NOT NULL,
    payload   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_chat_timestamp ON chat_messages(timestamp ASC);

-- Single-row table holding the latest state. Always upsert id=1.
CREATE TABLE IF NOT EXISTS state_latest (
    id        INTEGER PRIMARY KEY CHECK (id = 1),
    timestamp TEXT NOT NULL,
    payload   TEXT NOT NULL
);
"""


class Storage:
    """Async wrapper around an SQLite database.

    Single connection, single writer (the orchestrator). Reads on startup
    are small (last N rows), writes are one row at a time — no risk of
    contention worth pooling for. `aiosqlite` already serialises queries
    on the connection's worker thread.
    """

    def __init__(self, db_path: str | Path):
        self._path = Path(db_path)
        self._conn: aiosqlite.Connection | None = None

    # ───────────────────────── lifecycle ──────────────────────────────

    async def connect(self) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = await aiosqlite.connect(str(self._path))
        # Write-ahead logging: better concurrent read while we write.
        await self._conn.execute("PRAGMA journal_mode=WAL;")
        await self._conn.execute("PRAGMA synchronous=NORMAL;")
        await self._conn.executescript(_SCHEMA)
        await self._conn.commit()
        logger.info("Storage open: %s", self._path)

    async def close(self) -> None:
        if self._conn is not None:
            await self._conn.close()
            self._conn = None

    # ───────────────────────── writes ─────────────────────────────────

    async def record_event(self, ev: SecurityEvent) -> None:
        await self._exec(
            "INSERT OR REPLACE INTO events (id, timestamp, payload) VALUES (?, ?, ?)",
            (ev.id, ev.timestamp.isoformat(), ev.model_dump_json()),
        )

    async def record_decision(self, d: AgentDecision) -> None:
        await self._exec(
            "INSERT OR REPLACE INTO decisions (id, timestamp, payload) VALUES (?, ?, ?)",
            (d.id, d.timestamp.isoformat(), d.model_dump_json()),
        )

    async def record_chat(self, m: ChatMessage) -> None:
        await self._exec(
            "INSERT OR REPLACE INTO chat_messages "
            "(id, timestamp, role, payload) VALUES (?, ?, ?, ?)",
            (m.id, m.timestamp.isoformat(), m.role, m.model_dump_json()),
        )

    async def record_state(self, s: SecurityState) -> None:
        await self._exec(
            "INSERT OR REPLACE INTO state_latest "
            "(id, timestamp, payload) VALUES (1, ?, ?)",
            (s.last_update.isoformat(), s.model_dump_json()),
        )

    # ───────────────────────── reads ──────────────────────────────────

    async def recent_events(self, limit: int = 50) -> list[SecurityEvent]:
        rows = await self._fetch(
            "SELECT payload FROM events ORDER BY timestamp DESC LIMIT ?",
            (limit,),
        )
        return [SecurityEvent.model_validate_json(r[0]) for r in rows]

    async def recent_decisions(self, limit: int = 50) -> list[AgentDecision]:
        rows = await self._fetch(
            "SELECT payload FROM decisions ORDER BY timestamp DESC LIMIT ?",
            (limit,),
        )
        return [AgentDecision.model_validate_json(r[0]) for r in rows]

    async def recent_chat(self, limit: int = 50) -> list[ChatMessage]:
        # Return chronological for display; "recent" = last N by time.
        rows = await self._fetch(
            "SELECT payload FROM ("
            "  SELECT timestamp, payload FROM chat_messages "
            "  ORDER BY timestamp DESC LIMIT ?"
            ") ORDER BY timestamp ASC",
            (limit,),
        )
        return [ChatMessage.model_validate_json(r[0]) for r in rows]

    async def latest_state(self) -> SecurityState | None:
        rows = await self._fetch("SELECT payload FROM state_latest WHERE id=1", ())
        if not rows:
            return None
        return SecurityState.model_validate_json(rows[0][0])

    # ───────────────────────── stats / housekeeping ───────────────────

    async def counts(self) -> dict[str, int]:
        out: dict[str, int] = {}
        for table in ("events", "decisions", "chat_messages"):
            rows = await self._fetch(f"SELECT COUNT(*) FROM {table}", ())
            out[table] = rows[0][0]
        return out

    async def prune(
        self,
        *,
        max_events: int = 5000,
        max_decisions: int = 5000,
        max_chat: int = 5000,
    ) -> None:
        """Keep tables bounded so the DB doesn't grow forever.

        Cheap to call periodically; usually a no-op."""
        await self._prune_table("events", max_events)
        await self._prune_table("decisions", max_decisions)
        await self._prune_table("chat_messages", max_chat)

    async def _prune_table(self, table: str, max_rows: int) -> None:
        await self._exec(
            f"DELETE FROM {table} WHERE id NOT IN ("
            f"  SELECT id FROM {table} ORDER BY timestamp DESC LIMIT ?"
            ")",
            (max_rows,),
        )

    # ───────────────────────── internals ──────────────────────────────

    async def _exec(self, sql: str, params: tuple) -> None:
        if self._conn is None:
            raise RuntimeError("Storage.connect() not called")
        await self._conn.execute(sql, params)
        await self._conn.commit()

    async def _fetch(self, sql: str, params: tuple) -> list[tuple]:
        if self._conn is None:
            raise RuntimeError("Storage.connect() not called")
        async with self._conn.execute(sql, params) as cur:
            return await cur.fetchall()
