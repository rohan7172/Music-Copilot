"""Finding a song by name: Apple's public iTunes Search API.

It needs no account or key, and each track comes with Apple's official
30-second preview clip, which is what gets analysed. The app sends only a
track id; the server looks the preview up itself, so a client can never
point the server at an arbitrary address.
"""

import json
import tempfile
import urllib.parse
import urllib.request
from collections.abc import Callable
from urllib.parse import urlparse

Fetch = Callable[[str], bytes]

_SEARCH = "https://itunes.apple.com/search"
_LOOKUP = "https://itunes.apple.com/lookup"
_PREVIEW_HOSTS = ("itunes.apple.com", "mzstatic.com")
_TIMEOUT = 10


class CatalogError(Exception):
    """Apple couldn't be reached, or answered with something unusable."""


def _fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "MusicCopilot/1.0"})
    with urllib.request.urlopen(request, timeout=_TIMEOUT) as response:
        return response.read()


def _json(url: str, fetch: Fetch) -> dict:
    try:
        return json.loads(fetch(url))
    except Exception as e:
        raise CatalogError(f"iTunes search failed: {e}") from e


def _track(r: dict) -> dict | None:
    """The fields the app shows, or None for a result with no preview."""
    if r.get("kind") not in (None, "song") or not r.get("previewUrl") or "trackId" not in r:
        return None
    artwork = r.get("artworkUrl100") or r.get("artworkUrl60")
    return {
        "id": r["trackId"],
        "title": r.get("trackName", ""),
        "artist": r.get("artistName", ""),
        "album": r.get("collectionName"),
        # Apple's artwork URLs carry their size; ask for a sharper one.
        "artwork": artwork.replace("100x100", "200x200") if artwork else None,
        "duration": (r.get("trackTimeMillis") or 0) / 1000 or None,
    }


def search(query: str, limit: int = 8, fetch: Fetch = _fetch) -> list[dict]:
    params = urllib.parse.urlencode(
        {"term": query, "media": "music", "entity": "song", "limit": limit * 2}
    )
    results = _json(f"{_SEARCH}?{params}", fetch).get("results", [])
    tracks, seen = [], set()
    for r in results:
        t = _track(r)
        if t is None:
            continue
        # The same recording often appears on several albums.
        key = (t["title"].lower(), t["artist"].lower())
        if key in seen:
            continue
        seen.add(key)
        tracks.append(t)
    return tracks[:limit]


def _apple_host(url: str) -> bool:
    parsed = urlparse(url)
    host = parsed.hostname or ""
    return parsed.scheme == "https" and any(
        host == h or host.endswith("." + h) for h in _PREVIEW_HOSTS
    )


def preview(track_id: int, fetch: Fetch = _fetch) -> tuple[str, dict, str]:
    """Downloads a track's preview clip; returns (path, track, preview_url)."""
    results = _json(f"{_LOOKUP}?id={int(track_id)}", fetch).get("results", [])
    raw = next((r for r in results if r.get("trackId") == int(track_id)), None)
    track = _track(raw) if raw else None
    if track is None:
        raise LookupError("That song has no preview to analyse")
    url = raw["previewUrl"]
    if not _apple_host(url):
        raise CatalogError("Preview isn't hosted by Apple")
    try:
        audio = fetch(url)
    except Exception as e:
        raise CatalogError(f"Couldn't download the preview: {e}") from e
    # Kept on disk: a song job reads it later, as with an upload.
    with tempfile.NamedTemporaryFile(suffix=".m4a", delete=False) as tmp:
        tmp.write(audio)
    return tmp.name, track, url
