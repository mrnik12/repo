import asyncio
import re
from urllib.parse import urljoin, urlsplit, urlunsplit

import aiohttp

_RELEASE_TYPES = {"Album", "Single", "EP"}
_VERSION = re.compile(
    r"(?:[\[(]|\s[-–—:]\s)\s*[^)\]]*"
    r"\b(?:re-?mix|mix|live|acoustic|unplugged|demo|instrumental|karaoke|"
    r"version|edit|remaster(?:ed)?|sped up|slowed|re-?recorded)\b",
    re.IGNORECASE,
)
_COLLECTION = re.compile(r"\b(?:best\s+of|greatest\s+hits|anthology|compilation)\b", re.I)
_MBID = re.compile(r"[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}")
_ISRC = re.compile(r"[A-Z]{2}[A-Z0-9]{3}[0-9]{7}")
_API_ERRORS = (aiohttp.ClientError, TimeoutError, ValueError)
_query_lock = asyncio.Lock()
_next_query = 0.0


def original_release_groups(track, recordings):
    candidates = {}
    title = track["title"].casefold().strip()
    for recording in recordings:
        if recording.get("title", "").casefold().strip() != title:
            continue
        for release in recording.get("releases", ()):
            group = release.get("release-group") or {}
            group_id = group.get("id", "")
            date = release.get("date") or ""
            if (release.get("status") != "Official"
                    or group.get("primary-type") not in _RELEASE_TYPES
                    or group.get("secondary-types")
                    or _COLLECTION.search(group.get("title", ""))
                    or not _MBID.fullmatch(group_id)
                    or not re.fullmatch(r"\d{4}(?:-\d{2}){0,2}", date)):
                continue
            candidates[group_id] = min(date, candidates.get(group_id, date))
    return sorted(candidates, key=candidates.__getitem__)


async def _recordings_for_isrc(session, isrc):
    global _next_query
    loop = asyncio.get_running_loop()
    async with _query_lock:
        await asyncio.sleep(max(0, _next_query - loop.time()))
        _next_query = loop.time() + 1.05
    async with session.get(
        "https://musicbrainz.org/ws/2/recording/",
        params={"query": f"isrc:{isrc}", "fmt": "json", "limit": "25"},
        allow_redirects=False,
    ) as response:
        if response.status != 200:
            return ()
        return (await response.json()).get("recordings") or ()


async def _image_hex(session, url):
    for _ in range(4):
        parsed = urlsplit(url)
        host = parsed.netloc
        if not (
            re.fullmatch(r"is[0-9]+-ssl\.mzstatic\.com", host)
            or host == "coverartarchive.org"
            or re.fullmatch(r"(?:[a-z0-9-]+\.)*archive\.org", host)
        ):
            return None
        url = urlunsplit(parsed._replace(scheme="https"))
        async with session.get(url, allow_redirects=False) as response:
            if response.status in {301, 302, 303, 307, 308} and response.headers.get("Location"):
                url = urljoin(url, response.headers["Location"])
                continue
            if response.status != 200 or response.content_type not in {"image/jpeg", "image/png"}:
                return None
            art = bytearray()
            async for chunk in response.content.iter_chunked(16384):
                if len(art) + len(chunk) > 256_000:
                    return None
                art.extend(chunk)
            if art.startswith((b"\xff\xd8\xff", b"\x89PNG\r\n\x1a\n")):
                return art.hex()
            return None
    return None


async def original_cover_hex(track):
    isrc = track.get("isrc")
    if not isinstance(isrc, str) or not _ISRC.fullmatch(isrc) or _VERSION.search(track["title"]):
        return None
    try:
        async with asyncio.timeout(5), aiohttp.ClientSession(
            headers={"User-Agent": "LegacyShazamRelay/0.3.3 (iOS 6 compatibility project)"},
        ) as session:
            recordings = await _recordings_for_isrc(session, isrc)
            for group in original_release_groups(track, recordings)[:3]:
                art = await _image_hex(session, f"https://coverartarchive.org/release-group/{group}/front-250")
                if art:
                    return art
    except _API_ERRORS:
        pass
    return None


async def cover_art_hex(track):
    art = await original_cover_hex(track)
    if art:
        return art
    images = track.get("images")
    if not isinstance(images, dict):
        return None
    try:
        async with asyncio.timeout(3.5), aiohttp.ClientSession() as session:
            for field in ("coverart", "coverarthq"):
                url = images.get(field)
                if isinstance(url, str):
                    art = await _image_hex(session, url)
                    if art:
                        return art
    except _API_ERRORS:
        pass
    return None

