import asyncio
import hmac
import io
import math
import os
import time
import wave
from collections import deque


from fastapi import FastAPI, HTTPException, Request
from shazamio import Shazam

from artwork import cover_art_hex

app = FastAPI()
recognizer = Shazam()
MAX_BYTES = 512_000


PUBLIC_MODE = os.environ.get("LEGACY_SHAZAM_PUBLIC") == "1"
PUBLIC_WINDOW_SECONDS = 60
PUBLIC_REQUESTS_PER_WINDOW = 30
_public_requests = deque()


def authorize(request: Request):
    token = os.environ.get("LEGACY_SHAZAM_TOKEN")
    if token:
        provided = request.headers.get("x-relay-token", "").encode()
        if hmac.compare_digest(provided, token.encode()):
            return
        raise HTTPException(403, "Invalid relay token")
    if not PUBLIC_MODE:
        raise HTTPException(403, "Relay is not configured for public use")

    now = time.monotonic()
    while _public_requests and now - _public_requests[0] >= PUBLIC_WINDOW_SECONDS:
        _public_requests.popleft()
    if len(_public_requests) >= PUBLIC_REQUESTS_PER_WINDOW:
        retry_after = max(1, math.ceil(PUBLIC_WINDOW_SECONDS - (now - _public_requests[0])))
        raise HTTPException(429, "The relay is busy. Try again shortly.",
                            headers={"Retry-After": str(retry_after)})
    _public_requests.append(now)



@app.get("/health")
async def health():
    return {"ok": True}


@app.post("/recognize")
async def recognize(request: Request):
    authorize(request)
    if request.headers.get("content-type") != "audio/wav":
        raise HTTPException(415, "Send a WAV recording")

    audio = bytearray()
    async for chunk in request.stream():
        if len(audio) + len(chunk) > MAX_BYTES:
            raise HTTPException(413, "Recording is too large")
        audio.extend(chunk)
    try:
        with wave.open(io.BytesIO(audio), "rb") as wav:
            if (wav.getnchannels() != 1 or wav.getsampwidth() != 2
                    or wav.getframerate() != 16000 or not 16000 <= wav.getnframes() <= 160000):
                raise ValueError("Unexpected WAV format")
            if len(wav.readframes(wav.getnframes())) != wav.getnframes() * 2:
                raise ValueError("Truncated WAV")
    except (EOFError, wave.Error, ValueError):
        raise HTTPException(400, "Invalid recording")

    try:
        result = await asyncio.wait_for(recognizer.recognize(bytes(audio)), timeout=22)
    except TimeoutError:
        raise HTTPException(504, "Recognition timed out")
    except Exception:
        raise HTTPException(502, "Recognition service unavailable")

    track = result.get("track")
    if not track:
        return {"matched": False}
    title, artist = track.get("title"), track.get("subtitle")
    if not isinstance(title, str) or not title or not isinstance(artist, str) or not artist:
        raise HTTPException(502, "Recognition returned incomplete track information")
    return {"matched": True, "title": title, "artist": artist, "artwork": await cover_art_hex(track)}

