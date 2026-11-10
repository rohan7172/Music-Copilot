import json
import os

import pytest
from fastapi.testclient import TestClient

from app import catalog
from app.main import app


def _song(track_id, title="My Funny Valentine", artist="Chet Baker", preview=True, **extra):
    r = {
        "kind": "song",
        "trackId": track_id,
        "trackName": title,
        "artistName": artist,
        "collectionName": "Chet Baker Sings",
        "artworkUrl100": "https://is1-ssl.mzstatic.com/a/100x100bb.jpg",
        "trackTimeMillis": 139065,
    }
    if preview:
        r["previewUrl"] = f"https://audio-ssl.itunes.apple.com/p/{track_id}.m4a"
    r.update(extra)
    return r


def _fetcher(results, audio=b"AUDIO"):
    calls = []

    def fetch(url):
        calls.append(url)
        if url.endswith(".m4a"):
            return audio
        return json.dumps({"results": results}).encode()

    fetch.calls = calls
    return fetch


def test_search_parses_tracks():
    tracks = catalog.search("valentine", fetch=_fetcher([_song(1)]))
    assert tracks == [
        {
            "id": 1,
            "title": "My Funny Valentine",
            "artist": "Chet Baker",
            "album": "Chet Baker Sings",
            "artwork": "https://is1-ssl.mzstatic.com/a/200x200bb.jpg",
            "duration": 139.065,
        }
    ]


def test_search_drops_tracks_without_a_preview_and_repeats():
    results = [_song(1, preview=False), _song(2), _song(3), _song(4, title="Blue Room")]
    tracks = catalog.search("chet", fetch=_fetcher(results))
    assert [t["id"] for t in tracks] == [2, 4]


def test_search_query_is_encoded():
    fetch = _fetcher([])
    catalog.search("rock & roll", fetch=fetch)
    assert "term=rock+%26+roll" in fetch.calls[0]


def test_search_failure_is_a_catalog_error():
    def broken(url):
        raise OSError("offline")

    with pytest.raises(catalog.CatalogError):
        catalog.search("x", fetch=broken)


def test_preview_downloads_the_clip():
    fetch = _fetcher([_song(7)])
    path, track, url = catalog.preview(7, fetch=fetch)
    try:
        assert open(path, "rb").read() == b"AUDIO"
        assert track["id"] == 7 and url.endswith("/7.m4a")
        assert fetch.calls[0].endswith("lookup?id=7")
    finally:
        os.remove(path)


def test_preview_only_downloads_from_apple():
    evil = _song(7, previewUrl="https://evil.example/itunes.apple.com.m4a")
    with pytest.raises(catalog.CatalogError):
        catalog.preview(7, fetch=_fetcher([evil]))
    plain = _song(7, previewUrl="http://audio-ssl.itunes.apple.com/p.m4a")
    with pytest.raises(catalog.CatalogError):
        catalog.preview(7, fetch=_fetcher([plain]))


def test_preview_of_unknown_track():
    with pytest.raises(LookupError):
        catalog.preview(7, fetch=_fetcher([]))


def test_search_endpoint_rejects_an_empty_query():
    assert TestClient(app).get("/search", params={"q": "  "}).status_code == 400


def test_search_endpoint(monkeypatch):
    monkeypatch.setattr(catalog, "search", lambda q: [{"id": 1, "title": q}])
    response = TestClient(app).get("/search", params={"q": "valentine"})
    assert response.json() == {"results": [{"id": 1, "title": "valentine"}]}


def test_analyze_track_needs_an_id():
    assert TestClient(app).post("/analyze_track", json={}).status_code == 400


def test_analyze_track_unknown_song(monkeypatch):
    def missing(track_id):
        raise LookupError("no preview")

    monkeypatch.setattr(catalog, "preview", missing)
    assert TestClient(app).post("/analyze_track", json={"id": 5}).status_code == 404
