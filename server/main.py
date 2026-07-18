#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
import os
import shutil
import tempfile
import threading
import time
import uuid
import zipfile
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from datetime import datetime, timedelta
from io import BytesIO
from pathlib import Path
from typing import Literal, Optional

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse, Response, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field, field_validator

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import compress_image
import compress_video

STATIC_DIR = Path(__file__).parent / "static"
SESSION_BASE = Path(tempfile.gettempdir()) / "ic-sessions"
MAX_WORKERS = max(2, os.cpu_count() or 4)
FREE_FILE_LIMIT = int(os.getenv("LUMASHRINK_FREE_FILE_LIMIT", "3"))
MAX_UPLOAD_BYTES = int(os.getenv("LUMASHRINK_MAX_UPLOAD_MB", "50")) * 1024 * 1024
CHECKOUT_URL = os.getenv("LUMASHRINK_CHECKOUT_URL", "").strip()
DOWNLOAD_URL = os.getenv("LUMASHRINK_DOWNLOAD_URL", "").strip()
SESSION_RATE_LIMIT = int(os.getenv("LUMASHRINK_SESSION_RATE_LIMIT", "12"))
UPLOAD_RATE_LIMIT = int(os.getenv("LUMASHRINK_UPLOAD_RATE_LIMIT", "36"))
SUPPORTED_EXTENSIONS = {
    "jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif", "heic", "heif",
    "mp4", "mov", "avi", "mkv", "webm", "m4v", "wmv", "flv",
}
executor = ThreadPoolExecutor(max_workers=MAX_WORKERS)
_MAIN_LOOP: asyncio.AbstractEventLoop | None = None
_RATE_BUCKETS: dict[str, deque[float]] = {}
_RATE_LOCK = threading.Lock()


@asynccontextmanager
async def lifespan(_app: FastAPI):
    global _MAIN_LOOP
    _MAIN_LOOP = asyncio.get_event_loop()
    SESSION_BASE.mkdir(parents=True, exist_ok=True)
    try:
        yield
    finally:
        for session in sessions.values():
            session.cleanup()
        sessions.clear()
        executor.shutdown(wait=False, cancel_futures=True)


app = FastAPI(title="LumaShrink", docs_url=None, redoc_url=None, lifespan=lifespan)

class Session:
    def __init__(self, session_id: str):
        self.id = session_id
        self.dir = SESSION_BASE / session_id
        self.uploads_dir = self.dir / "uploads"
        self.compressed_dir = self.dir / "compressed"
        self.dir.mkdir(parents=True, exist_ok=True)
        self.uploads_dir.mkdir(parents=True, exist_ok=True)
        self.compressed_dir.mkdir(parents=True, exist_ok=True)

        self.files: list[FileEntry] = []
        self.settings = CompressionSettings()
        self.created_at = datetime.now()
        self._compress_task: asyncio.Task | None = None
        self._ws_connections: list[WebSocket] = []
        self._stop_event = threading.Event()

    def add_file(self, filename: str, original_path: Path) -> FileEntry:
        entry = FileEntry(
            file_id=str(uuid.uuid4())[:8],
            filename=filename,
            original_path=original_path,
        )
        self.files.append(entry)
        return entry

    def file_by_id(self, file_id: str) -> Optional[FileEntry]:
        for f in self.files:
            if f.file_id == file_id:
                return f
        return None

    def reset_file_statuses(self):
        self._stop_event.clear()
        for f in self.files:
            f.status = "queued"
            f.compressed_path = None
            f.output_size = None

    def cleanup(self):
        if self.dir.exists():
            shutil.rmtree(self.dir, ignore_errors=True)


class FileEntry:
    def __init__(self, file_id: str, filename: str, original_path: Path):
        self.file_id = file_id
        self.filename = filename
        self.original_path = original_path
        self.source_size = original_path.stat().st_size
        self.status = "queued"
        self.compressed_path: Path | None = None
        self.output_size: int | None = None
        self.detail: str | None = None


class CompressionSettings(BaseModel):
    max_size: str = "150kb"
    output_format: Literal["auto", "keep", "jpeg", "png", "webp", "best_quality"] = "auto"
    name_mode: Literal["suffix", "same-name", "overwrite"] = "suffix"
    suffix: str = "_compressed"
    min_quality: int = Field(default=20, ge=1, le=100)
    max_quality: int = Field(default=100, ge=1, le=100)
    min_side: int = Field(default=320, ge=64, le=8192)
    keep_metadata: bool = False
    background: str = Field(default="FFFFFF", pattern=r"^[0-9A-Fa-f]{6}$")

    @field_validator("max_size")
    @classmethod
    def valid_max_size(cls, value: str) -> str:
        try:
            if compress_image.parse_size_to_bytes(value) <= 0:
                raise ValueError
        except Exception as exc:
            raise ValueError("max_size must be a positive size such as 150kb or 2mb") from exc
        return value

    @field_validator("max_quality")
    @classmethod
    def valid_quality_range(cls, value: int, info):
        minimum = info.data.get("min_quality", 1)
        if value < minimum:
            raise ValueError("max_quality must be greater than or equal to min_quality")
        return value

    def to_namespace(self) -> argparse.Namespace:
        ns = argparse.Namespace()
        # Keep compatibility with older clients without mislabeling WebP bytes as PNG.
        fmt = self.output_format
        if fmt == "best_quality":
            fmt = "webp"
        ns.max_size = self.max_size
        ns.format = fmt
        ns.name_mode = self.name_mode
        ns.suffix = self.suffix
        ns.min_quality = self.min_quality
        ns.max_quality = self.max_quality
        ns.min_side = self.min_side
        ns.keep_metadata = self.keep_metadata
        ns.background = self.background
        ns.keep_dimensions = False
        return ns


sessions: dict[str, Session] = {}


def _check_rate(request: Request, bucket: str, limit: int, window_seconds: int = 3600):
    host = request.client.host if request.client else "unknown"
    key = f"{bucket}:{host}"
    now = time.monotonic()
    cutoff = now - window_seconds
    with _RATE_LOCK:
        timestamps = _RATE_BUCKETS.setdefault(key, deque())
        while timestamps and timestamps[0] < cutoff:
            timestamps.popleft()
        if len(timestamps) >= limit:
            retry_after = max(1, int(window_seconds - (now - timestamps[0])))
            raise HTTPException(
                status_code=429,
                detail="Too many trial requests. Please wait and try again.",
                headers={"Retry-After": str(retry_after)},
            )
        timestamps.append(now)


async def _save_upload(upload: UploadFile, destination: Path) -> int:
    size = 0
    try:
        with destination.open("wb") as output:
            while chunk := await upload.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_UPLOAD_BYTES:
                    max_mb = MAX_UPLOAD_BYTES // (1024 * 1024)
                    raise HTTPException(
                        status_code=413,
                        detail=f"{Path(upload.filename or 'upload').name} is larger than the {max_mb} MB web-trial limit.",
                    )
                output.write(chunk)
    except Exception:
        destination.unlink(missing_ok=True)
        raise
    if size == 0:
        destination.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail=f"{Path(upload.filename or 'upload').name} is empty.")
    return size

def _cleanup_old_sessions():
    now = datetime.now()
    expired = [sid for sid, s in sessions.items()
               if now - s.created_at > timedelta(hours=2)]
    for sid in expired:
        s = sessions.pop(sid, None)
        if s:
            s.cleanup()

app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


@app.middleware("http")
async def launch_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    if request.url.path.startswith("/api/"):
        response.headers["Cache-Control"] = "no-store"
    return response

@app.get("/")
async def landing():
    return FileResponse(str(STATIC_DIR / "landing.html"), media_type="text/html")

@app.get("/app")
async def app_root():
    return FileResponse(str(STATIC_DIR / "index.html"), media_type="text/html")


@app.get("/privacy")
async def privacy():
    return FileResponse(str(STATIC_DIR / "privacy.html"), media_type="text/html")


@app.get("/terms")
async def terms():
    return FileResponse(str(STATIC_DIR / "terms.html"), media_type="text/html")


@app.get("/support")
async def support():
    return FileResponse(str(STATIC_DIR / "support.html"), media_type="text/html")


@app.get("/buy")
async def buy_pro():
    if not CHECKOUT_URL:
        return RedirectResponse(url="/support?topic=checkout-setup", status_code=303)
    return RedirectResponse(url=CHECKOUT_URL, status_code=302)


@app.get("/download")
async def download_desktop():
    if not DOWNLOAD_URL:
        return RedirectResponse(url="/support?topic=download", status_code=303)
    return RedirectResponse(url=DOWNLOAD_URL, status_code=302)


@app.get("/api/config")
async def public_config():
    return {
        "free_file_limit": FREE_FILE_LIMIT,
        "max_upload_mb": MAX_UPLOAD_BYTES // (1024 * 1024),
        "checkout_ready": bool(CHECKOUT_URL),
        "download_ready": bool(DOWNLOAD_URL),
    }


@app.get("/health")
async def health():
    return {"status": "ok", "product": "LumaShrink"}


@app.get("/health/ready")
async def launch_readiness():
    checks = {
        "checkout_configured": bool(CHECKOUT_URL),
        "download_configured": bool(DOWNLOAD_URL),
        "ffmpeg_available": shutil.which("ffmpeg") is not None and shutil.which("ffprobe") is not None,
    }
    ready = all(checks.values())
    return JSONResponse(
        status_code=200 if ready else 503,
        content={"status": "ready" if ready else "configuration_required", "checks": checks},
    )


@app.post("/api/session")
async def create_session(request: Request):
    _check_rate(request, "session", SESSION_RATE_LIMIT)
    _cleanup_old_sessions()
    session_id = str(uuid.uuid4())[:12]
    sessions[session_id] = Session(session_id)
    return {"session_id": session_id}


@app.post("/api/session/{session_id}/upload")
async def upload_files(request: Request, session_id: str, files: list[UploadFile] = File(...)):
    _check_rate(request, "upload", UPLOAD_RATE_LIMIT)
    session = sessions.get(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    available_slots = max(0, FREE_FILE_LIMIT - len(session.files))
    if len(files) > available_slots:
        raise HTTPException(
            status_code=413,
            detail=f"The free web trial supports {FREE_FILE_LIMIT} files per session. Pro removes the queue limit.",
        )

    prepared: list[tuple[UploadFile, str]] = []
    for f in files:
        safe_name = Path(f.filename or "upload").name
        ext = Path(safe_name).suffix.lower().lstrip(".")
        if ext not in SUPPORTED_EXTENSIONS:
            raise HTTPException(status_code=415, detail=f"{safe_name} is not a supported image or video.")
        prepared.append((f, safe_name))

    entries = []
    for f, safe_name in prepared:
        dest = session.uploads_dir / f"{uuid.uuid4().hex[:8]}-{safe_name}"
        await _save_upload(f, dest)
        entry = session.add_file(safe_name, dest)
        entries.append({
            "file_id": entry.file_id,
            "filename": entry.filename,
            "source_size": entry.source_size,
            "status": entry.status,
        })
    return {"files": entries}


@app.get("/api/session/{session_id}/files")
async def list_files(session_id: str):
    session = sessions.get(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    return {
        "files": [
            {
                "file_id": f.file_id,
                "filename": f.filename,
                "source_size": f.source_size,
                "output_size": f.output_size,
                "status": f.status,
                "detail": f.detail,
            }
            for f in session.files
        ]
    }


@app.patch("/api/session/{session_id}/settings")
async def update_settings(session_id: str, settings: CompressionSettings):
    session = sessions.get(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    session.settings = settings
    return {"ok": True}


@app.get("/api/session/{session_id}/settings")
async def get_settings(session_id: str):
    session = sessions.get(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    return session.settings.model_dump()


async def _broadcast(session: Session, message: dict):
    for ws in session._ws_connections[:]:
        try:
            await ws.send_json(message)
        except Exception:
            session._ws_connections.remove(ws)


def _run_compression(session: Session):
    settings = session.settings
    ns = settings.to_namespace()
    total = len(session.files)
    start_time = time.time()

    total_source = sum(f.source_size for f in session.files)

    # Compute per-session worker count based on avg file size
    avg_mb = (total_source / max(total, 1)) / (1024 * 1024)
    cpu_count = os.cpu_count() or 4
    if avg_mb >= 40:
        max_workers = 2
    elif avg_mb >= 12:
        max_workers = 3
    elif avg_mb >= 6:
        max_workers = 4
    elif avg_mb >= 3:
        max_workers = 6
    else:
        max_workers = cpu_count
    max_workers = max(1, min(max_workers, min(total, os.cpu_count() or 4)))
    _broadcast_sync(session, {"type": "log", "line": f"[BATCH] Using {max_workers} parallel worker(s)"})

    lock = threading.Lock()
    completed = 0
    total_output = 0
    recent_times: deque = deque(maxlen=5)

    video_exts = {"mp4", "mov", "avi", "mkv", "webm", "m4v", "wmv", "flv"}

    def process_one(entry: FileEntry):
        nonlocal completed, total_output, recent_times

        if session._stop_event.is_set():
            entry.status = "skipped"
            entry.detail = "Stopped before processing"
            with lock:
                completed += 1
            _broadcast_sync(session, {
                "type": "file_status",
                "file_id": entry.file_id,
                "status": entry.status,
                "detail": entry.detail,
            })
            return

        entry.status = "processing"
        entry.detail = None
        _broadcast_sync(session, {
            "type": "file_status",
            "file_id": entry.file_id,
            "status": "processing",
        })

        try:
            ext = entry.filename.rsplit(".", 1)[-1].lower()

            if ext in video_exts:
                target_bytes = compress_video.parse_size(settings.max_size)
                output_name = f"{Path(entry.filename).stem}_compressed.mp4"
                output_path = session.compressed_dir / output_name
                success, lines = compress_video.compress_video(
                    entry.original_path, output_path, target_bytes
                )
                for line in lines:
                    _broadcast_sync(session, {"type": "log", "line": f"[{entry.file_id}] {line}"})
                entry.compressed_path = output_path if success and output_path.exists() else None
                entry.output_size = output_path.stat().st_size if output_path.exists() else 0
                if not success:
                    entry.status = "failed"
                    entry.detail = "Video compression failed. Review the processing log."
                elif entry.output_size > target_bytes:
                    entry.status = "best_effort"
                    entry.detail = "The requested target was too small for the video duration."
                else:
                    entry.status = "done"
            else:
                result = compress_image.process_one_file(
                    entry.original_path,
                    session.compressed_dir,
                    ns,
                )
                for line in compress_image.format_processing_result(result):
                    _broadcast_sync(session, {"type": "log", "line": f"[{entry.file_id}] {line}"})

                entry.status = {
                    "OK": "done",
                    "UNCHANGED": "skipped",
                    "BEST EFFORT": "best_effort",
                }.get(result.status, "done")
                entry.compressed_path = result.output_path
                entry.output_size = result.output_size
                entry.detail = result.detail

        except Exception as e:
            entry.status = "failed"
            entry.detail = str(e)
            _broadcast_sync(session, {
                "type": "log",
                "line": f"[{entry.file_id}] [ERROR] {e}",
            })

        with lock:
            completed += 1
            total_output += entry.output_size or 0
            now = time.time()
            recent_times.append(now)

            # Adaptive ETA: sliding window once we have enough samples
            if len(recent_times) >= 3:
                window_elapsed = recent_times[-1] - recent_times[0]
                window_rate = (len(recent_times) - 1) / max(window_elapsed, 0.001)
                rate = window_rate
            else:
                elapsed = max(now - start_time, 0.001)
                rate = completed / elapsed

            remaining = max(total - completed, 0)
            eta = rate > 0 and remaining / rate or 0
            savings_pct = ((total_source - total_output) / max(total_source, 1)) * 100

        _broadcast_sync(session, {
            "type": "file_status",
            "file_id": entry.file_id,
            "status": entry.status,
            "output_size": entry.output_size,
            "detail": entry.detail,
        })
        _broadcast_sync(session, {
            "type": "batch_stats",
            "completed": completed,
            "total": total,
            "files_per_sec": round(rate, 2),
            "eta_secs": round(eta, 1),
            "total_source": total_source,
            "total_output": total_output,
            "savings_pct": round(savings_pct, 1),
        })

    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        list(pool.map(process_one, session.files))

    error_count = sum(1 for f in session.files if f.status == "failed")
    warning_count = sum(1 for f in session.files if f.status == "best_effort")
    stopped_count = sum(1 for f in session.files if f.detail == "Stopped before processing")
    savings_pct = ((total_source - total_output) / max(total_source, 1)) * 100
    if error_count > 0:
        summary = f"Finished with {error_count} error(s). Review the log for details."
    elif stopped_count > 0:
        summary = f"Stopped. {stopped_count} queued file(s) were not processed."
    elif warning_count > 0:
        summary = f"Finished. {warning_count} file(s) reached BEST EFFORT."
    else:
        summary = f"Finished. {total} file(s) processed successfully."

    _broadcast_sync(session, {
        "type": "batch_complete",
        "summary": summary,
        "total_source": total_source,
        "total_output": total_output,
        "savings_pct": round(savings_pct, 1),
    })


def _broadcast_sync(session: Session, message: dict):
    loop = _MAIN_LOOP
    if loop is None:
        return
    for ws in session._ws_connections[:]:
        try:
            asyncio.run_coroutine_threadsafe(ws.send_json(message), loop)
        except Exception:
            try:
                session._ws_connections.remove(ws)
            except ValueError:
                pass


@app.post("/api/session/{session_id}/compress")
async def start_compression(session_id: str):
    session = sessions.get(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    if not session.files:
        raise HTTPException(status_code=400, detail="No files to compress")
    if session._compress_task and not session._compress_task.done():
        raise HTTPException(status_code=409, detail="Compression is already running")

    session.reset_file_statuses()
    loop = asyncio.get_event_loop()
    session._compress_task = asyncio.ensure_future(
        _run_compression_async(session, loop)
    )
    return {"ok": True}


async def _run_compression_async(session: Session, loop):
    await _broadcast(session, {"type": "batch_start", "total": len(session.files)})
    await loop.run_in_executor(executor, _run_compression, session)


@app.post("/api/session/{session_id}/stop")
async def stop_compression(session_id: str):
    session = sessions.get(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    session._stop_event.set()
    return {"ok": True}


@app.get("/api/session/{session_id}/raw/{file_id}")
async def raw_file(session_id: str, file_id: str):
    session = sessions.get(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    entry = session.file_by_id(file_id)
    if not entry or not entry.original_path.exists():
        raise HTTPException(status_code=404, detail="File not found")
    return FileResponse(
        str(entry.original_path),
        filename=entry.filename,
        media_type="application/octet-stream",
    )


@app.get("/api/session/{session_id}/download/{file_id}")
async def download_file(session_id: str, file_id: str):
    session = sessions.get(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    entry = session.file_by_id(file_id)
    if not entry or not entry.compressed_path or not entry.compressed_path.exists():
        raise HTTPException(status_code=404, detail="File not found or not compressed")
    return FileResponse(
        str(entry.compressed_path),
        filename=entry.compressed_path.name,
        media_type="application/octet-stream",
    )


@app.get("/api/session/{session_id}/download-all")
async def download_all(session_id: str):
    session = sessions.get(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    buf = BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for entry in session.files:
            if entry.compressed_path and entry.compressed_path.exists():
                arcname = entry.compressed_path.name
                zf.write(str(entry.compressed_path), arcname)
    buf.seek(0)
    return StreamingResponse(
        buf,
        media_type="application/zip",
        headers={"Content-Disposition": f"attachment; filename=compressed-{session_id}.zip"},
    )


@app.delete("/api/session/{session_id}")
async def delete_session(session_id: str):
    session = sessions.pop(session_id, None)
    if session:
        session.cleanup()
    return {"ok": True}


@app.websocket("/api/session/{session_id}/ws")
async def websocket_endpoint(websocket: WebSocket, session_id: str):
    session = sessions.get(session_id)
    if not session:
        await websocket.close(code=4004)
        return

    await websocket.accept()
    session._ws_connections.append(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        pass
    finally:
        if websocket in session._ws_connections:
            session._ws_connections.remove(websocket)


@app.post("/api/preview")
async def preview_image(
    request: Request,
    file: UploadFile = File(...),
    max_size: str = Form("150kb"),
    quality: int = Form(100, ge=1, le=100),
):
    _check_rate(request, "preview", UPLOAD_RATE_LIMIT)
    try:
        if compress_image.parse_size_to_bytes(max_size) <= 0:
            raise ValueError
    except Exception as exc:
        raise HTTPException(status_code=422, detail="Invalid preview target size.") from exc
    ext = file.filename.rsplit(".", 1)[-1].lower() if file.filename and "." in file.filename else ""
    if ext not in {"jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif", "heic", "heif"}:
        raise HTTPException(status_code=415, detail="Preview supports image files only.")

    with tempfile.TemporaryDirectory(prefix="lumashrink-preview-") as tmp_dir:
        tmp_input = Path(tmp_dir) / f"input.{ext}"
        await _save_upload(file, tmp_input)

        ns = argparse.Namespace()
        ns.max_size = max_size
        ns.format = "keep"
        ns.name_mode = "suffix"
        ns.suffix = f"_preview_{uuid.uuid4().hex[:6]}"
        ns.min_quality = 1
        ns.max_quality = quality
        ns.min_side = 320
        ns.keep_metadata = False
        ns.background = "FFFFFF"
        ns.keep_dimensions = True

        result = compress_image.process_one_file(tmp_input, None, ns)
        if result.output_path and result.output_path.exists():
            data = result.output_path.read_bytes()
            return Response(
                content=data,
                media_type=f"image/{result.output_format or 'jpeg'}",
                headers={
                    "X-Original-Size": str(result.source_size),
                    "X-Output-Size": str(result.output_size),
                    "X-Quality": str(result.quality or quality),
                },
            )
        raise HTTPException(status_code=500, detail="Preview failed")
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=os.getenv("LUMASHRINK_HOST", "127.0.0.1"),
        port=int(os.getenv("LUMASHRINK_PORT", "8000")),
        reload=os.getenv("LUMASHRINK_RELOAD", "0") == "1",
    )
