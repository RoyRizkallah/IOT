"""Camera relay server.

The Raspberry Pi camera streamer (`raspberry_files/pi_camera_streamer.py`)
opens a WebSocket to ``/ws/camera/stream`` and pushes binary JPEG frames. A
single Pi is the *producer*; the mobile app (and browsers) are *viewers*.

This module is a tiny fan-out hub:

    Pi  --(JPEG)-->  /ws/camera/stream  -->  FrameHub  -->  /ws/camera/view  -->  app
                                                       -->  /stream.mjpeg    -->  browser
                                                       -->  /snapshot.jpg    -->  browser

It keeps only the latest frame in memory (no buffering / recording) so a
late-joining viewer always gets the current picture immediately. Frames are
forwarded as-is; we never decode the JPEG, which keeps the relay cheap.

Run it standalone:

    sentry camera-relay --host 0.0.0.0 --port 8000

The Pi then streams to it with:

    python3 pi_camera_streamer.py --host <LAPTOP_IP> --port 8000
"""

from __future__ import annotations

import asyncio
import base64
import logging
import time

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse, JSONResponse, Response, StreamingResponse

logger = logging.getLogger("sentry.camera")

# A valid 1x1 black JPEG shown to viewers before the first real frame arrives,
# so the app never has to render empty/invalid bytes.
_PLACEHOLDER_JPEG = base64.b64decode(
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof"
    "Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwh"
    "MjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAAR"
    "CAABAAEDASIAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAACP/EABQQAQAAAAAAAAAAAAAA"
    "AAAAAAD/xAAUAQEAAAAAAAAAAAAAAAAAAAAA/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAwD"
    "AQACEQMRAD8AfwD/2Q=="
)


class FrameHub:
    """Holds the latest JPEG frame and the set of connected viewers."""

    def __init__(self) -> None:
        self.latest: bytes | None = None
        self.viewers: set[WebSocket] = set()
        self.frame_count: int = 0
        self.last_frame_at: float | None = None
        self.producer_connected: bool = False
        # Set whenever a new frame arrives — lets MJPEG/long-poll viewers wait.
        self._new_frame = asyncio.Event()

    def is_live(self, *, stale_after_s: float = 5.0) -> bool:
        return (
            self.producer_connected
            and self.last_frame_at is not None
            and (time.time() - self.last_frame_at) < stale_after_s
        )

    async def publish(self, frame: bytes) -> None:
        self.latest = frame
        self.frame_count += 1
        self.last_frame_at = time.time()
        self._new_frame.set()
        self._new_frame.clear()

        dead: list[WebSocket] = []
        for v in list(self.viewers):
            try:
                await v.send_bytes(frame)
            except Exception:
                dead.append(v)
        for v in dead:
            self.viewers.discard(v)

    async def wait_for_frame(self, timeout: float = 1.0) -> bytes | None:
        try:
            await asyncio.wait_for(self._new_frame.wait(), timeout=timeout)
        except TimeoutError:
            return None
        return self.latest

    def status(self) -> dict:
        return {
            "producer_connected": self.producer_connected,
            "live": self.is_live(),
            "viewers": len(self.viewers),
            "frame_count": self.frame_count,
            "last_frame_at": self.last_frame_at,
        }


def create_app() -> FastAPI:  # noqa: PLR0915 - one function wires all routes
    app = FastAPI(title="SentryAgent Camera Relay", version="1.0.0")
    hub = FrameHub()
    app.state.hub = hub

    # ── Producer: the Raspberry Pi pushes JPEG frames here ──────────────
    @app.websocket("/ws/camera/stream")
    async def camera_stream(ws: WebSocket) -> None:
        await ws.accept()
        hub.producer_connected = True
        logger.info("Camera producer connected (%s)", ws.client)
        try:
            while True:
                frame = await ws.receive_bytes()
                if frame:
                    await hub.publish(frame)
        except WebSocketDisconnect:
            logger.info("Camera producer disconnected")
        except Exception as e:  # noqa: BLE001
            logger.warning("Camera producer error: %s", e)
        finally:
            hub.producer_connected = False

    # ── Viewers: the mobile app connects here and receives each frame ───
    @app.websocket("/ws/camera/view")
    async def camera_view(ws: WebSocket) -> None:
        await ws.accept()
        hub.viewers.add(ws)
        logger.info("Viewer connected (now %d)", len(hub.viewers))
        try:
            # Send whatever we have right now so the screen isn't blank.
            await ws.send_bytes(hub.latest or _PLACEHOLDER_JPEG)
            # The producer task pushes frames to us; here we just keep the
            # socket open and drain any keepalive pings from the client.
            while True:
                await ws.receive_text()
        except WebSocketDisconnect:
            pass
        except Exception:  # noqa: BLE001
            pass
        finally:
            hub.viewers.discard(ws)
            logger.info("Viewer disconnected (now %d)", len(hub.viewers))

    # ── Browser-friendly helpers (handy for quick demos / debugging) ────
    @app.get("/snapshot.jpg")
    async def snapshot() -> Response:
        return Response(
            content=hub.latest or _PLACEHOLDER_JPEG, media_type="image/jpeg"
        )

    @app.get("/stream.mjpeg")
    async def mjpeg() -> StreamingResponse:
        async def gen():
            boundary = b"--frame"
            while True:
                frame = await hub.wait_for_frame(timeout=2.0)
                if frame is None:
                    frame = hub.latest or _PLACEHOLDER_JPEG
                yield boundary + b"\r\n"
                yield b"Content-Type: image/jpeg\r\n"
                yield f"Content-Length: {len(frame)}\r\n\r\n".encode()
                yield frame + b"\r\n"

        return StreamingResponse(
            gen(), media_type="multipart/x-mixed-replace; boundary=frame"
        )

    @app.get("/status")
    async def status() -> JSONResponse:
        return JSONResponse(hub.status())

    @app.get("/healthz")
    async def healthz() -> JSONResponse:
        return JSONResponse({"ok": True})

    @app.get("/", response_class=HTMLResponse)
    async def index() -> str:
        return (
            "<html><head><title>SentryAgent Camera Relay</title>"
            "<style>body{background:#0b0f17;color:#e6edf6;font-family:system-ui;"
            "text-align:center;padding:24px}img{max-width:90vw;border-radius:12px;"
            "border:1px solid #1d2840}</style></head><body>"
            "<h2>SentryAgent Camera Relay</h2>"
            "<p>Live MJPEG preview (also at <code>/stream.mjpeg</code>):</p>"
            "<img src='/stream.mjpeg' alt='camera'/>"
            "<p>App viewers connect to <code>/ws/camera/view</code>. "
            "Pi streams to <code>/ws/camera/stream</code>.</p>"
            "</body></html>"
        )

    return app


def run(host: str = "0.0.0.0", port: int = 8000, log_level: str = "info") -> None:
    import uvicorn  # noqa: PLC0415 - heavy optional dep, imported on demand

    uvicorn.run(create_app(), host=host, port=port, log_level=log_level)
