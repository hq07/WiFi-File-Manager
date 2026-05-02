# Video Streaming with Range Request Support

## Problem

The `/api/files/preview` endpoint streams the entire file as HTTP 200 with no Range request support. This forces the Android video player (ExoPlayer) to download the full video before playback, making seeking impossible and causing long waits for large files (especially iCloud files that may need to sync first).

## Solution

Replace `StreamingResponse` with Starlette's `FileResponse` in the preview endpoint. `FileResponse` natively supports HTTP Range requests (206 Partial Content), enabling progressive streaming and seeking.

## Changes

### Server (`server/main.py`)

**Preview endpoint (line 112-120):**

- Import `FileResponse` from `starlette.responses`
- Replace `StreamingResponse(open(path, "rb"), media_type=content_type)` with `FileResponse(path, media_type=content_type)`
- `FileResponse` automatically provides:
  - `Accept-Ranges: bytes` response header
  - Parsing of `Range: bytes=start-end` request header
  - HTTP 206 Partial Content responses with `Content-Range` header
  - Proper `Content-Length` for the served range

**Download endpoint:** No changes. Full-file download behavior is correct for downloads.

### Client (Android Flutter)

No changes required. ExoPlayer (used by `video_player`) automatically detects `Accept-Ranges: bytes` and enables range-request-based seeking and progressive loading.

## Scope

Single-line change in `server/main.py`. No new dependencies. No client changes.
