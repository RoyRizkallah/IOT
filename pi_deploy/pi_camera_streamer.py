#!/usr/bin/env python3
"""
SentryAgent — Raspberry Pi camera streamer.

Captures JPEG frames from the Pi camera and pushes them over a WebSocket to the
camera relay running on the PC, which the mobile app then views.

  Pi camera  ->  ws://<PC>:8000/ws/camera/stream  ->  relay  ->  app

RUN (use the venv python):
  /home/pi/iot-demo/venv/bin/python3 -u pi_camera_streamer.py

Works with either picamera2 (libcamera, modern Pi OS) or OpenCV/USB webcam.
Falls back gracefully if no camera is present.
"""
from __future__ import annotations

import asyncio
import io
import time

# ── Config ────────────────────────────────────────────────────────────────
RELAY_HOST = "192.168.137.1"     # the PC running the camera relay
RELAY_PORT = 8000
RELAY_PATH = "/ws/camera/stream"
FPS = 10
JPEG_QUALITY = 60
FRAME_WIDTH = 640
FRAME_HEIGHT = 480

RELAY_URL = f"ws://{RELAY_HOST}:{RELAY_PORT}{RELAY_PATH}"

# ── Camera init: try picamera2, then OpenCV, else simulated ─────────────────
_camera_kind = None
_picam = None
_cv_cap = None

try:
    from picamera2 import Picamera2

    _picam = Picamera2()
    _config = _picam.create_video_configuration(
        main={"size": (FRAME_WIDTH, FRAME_HEIGHT), "format": "RGB888"}
    )
    _picam.configure(_config)
    _picam.start()
    time.sleep(1)
    _camera_kind = "picamera2"
    print("Camera: picamera2 initialized.")
except Exception as e:  # noqa: BLE001
    print(f"picamera2 unavailable ({e}); trying OpenCV...")
    try:
        import cv2

        _cv_cap = cv2.VideoCapture(0)
        _cv_cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
        _cv_cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
        if _cv_cap.isOpened():
            _camera_kind = "opencv"
            print("Camera: OpenCV/USB webcam initialized.")
        else:
            _cv_cap = None
            print("No OpenCV camera found.")
    except Exception as e2:  # noqa: BLE001
        print(f"OpenCV unavailable ({e2}). Camera in simulation mode.")


def grab_jpeg() -> bytes | None:
    """Return one JPEG frame, or None if no camera."""
    if _camera_kind == "picamera2":
        from PIL import Image

        arr = _picam.capture_array()
        img = Image.fromarray(arr)
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=JPEG_QUALITY)
        return buf.getvalue()
    if _camera_kind == "opencv":
        import cv2

        ok, frame = _cv_cap.read()
        if not ok:
            return None
        ok, enc = cv2.imencode(".jpg", frame,
                               [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY])
        return enc.tobytes() if ok else None
    # simulated: a tiny generated placeholder frame
    try:
        from PIL import Image, ImageDraw

        img = Image.new("RGB", (FRAME_WIDTH, FRAME_HEIGHT), (20, 20, 28))
        d = ImageDraw.Draw(img)
        d.text((20, 20), f"SIM CAMERA {time.strftime('%H:%M:%S')}", fill=(0, 220, 160))
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=JPEG_QUALITY)
        return buf.getvalue()
    except Exception:  # noqa: BLE001
        return None


async def stream() -> None:
    import websockets

    delay = 1.0 / FPS
    while True:
        try:
            print(f"Connecting to relay {RELAY_URL} ...")
            async with websockets.connect(RELAY_URL, max_size=None) as ws:
                print("Connected to camera relay. Streaming frames.")
                while True:
                    frame = grab_jpeg()
                    if frame:
                        await ws.send(frame)
                    await asyncio.sleep(delay)
        except Exception as e:  # noqa: BLE001
            print(f"Relay connection lost ({e}); retrying in 3s.")
            await asyncio.sleep(3)


if __name__ == "__main__":
    try:
        asyncio.run(stream())
    except KeyboardInterrupt:
        print("\nStopping camera streamer.")
