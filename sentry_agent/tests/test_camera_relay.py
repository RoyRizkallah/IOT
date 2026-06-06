"""Camera relay fan-out.

A frame pushed by the (Pi) producer must reach a connected (app) viewer, and
the browser-friendly HTTP endpoints must work even before any frame arrives.
"""

from __future__ import annotations

from fastapi.testclient import TestClient

from sentry.camera.relay import create_app


def test_relay_forwards_frame_to_viewer() -> None:
    client = TestClient(create_app())
    fake_jpeg = b"\xff\xd8hello-from-pi\xff\xd9"

    with client.websocket_connect("/ws/camera/view") as viewer:
        # The viewer gets an immediate placeholder so the screen is never blank.
        first = viewer.receive_bytes()
        assert first[:2] == b"\xff\xd8"

        with client.websocket_connect("/ws/camera/stream") as producer:
            producer.send_bytes(fake_jpeg)
            forwarded = viewer.receive_bytes()
            assert forwarded == fake_jpeg


def test_snapshot_status_and_health() -> None:
    client = TestClient(create_app())

    snap = client.get("/snapshot.jpg")
    assert snap.status_code == 200
    assert snap.headers["content-type"] == "image/jpeg"
    assert snap.content[:2] == b"\xff\xd8"

    status = client.get("/status").json()
    assert status["viewers"] == 0
    assert status["producer_connected"] is False
    assert status["live"] is False

    assert client.get("/healthz").json() == {"ok": True}

    index = client.get("/")
    assert index.status_code == 200
    assert "Camera Relay" in index.text


def test_status_tracks_producer_and_viewers() -> None:
    client = TestClient(create_app())
    with client.websocket_connect("/ws/camera/stream") as producer:
        producer.send_bytes(b"\xff\xd8x\xff\xd9")
        status = client.get("/status").json()
        assert status["producer_connected"] is True
        assert status["frame_count"] >= 1
