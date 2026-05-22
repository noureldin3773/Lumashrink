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
from datetime import datetime, timedelta
from io import BytesIO
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, File, Form, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, Response, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import compress_image
import compress_video

app = FastAPI(title="Image Compressor")

STATIC_DIR = Path(__file__).parent / "static"
SESSION_BASE = Path(tempfile.gettempdir()) / "ic-sessions"
MAX_WORKERS = max(2, os.cpu_count() or 4)
executor = ThreadPoolExecutor(max_workers=MAX_WORKERS)
_MAIN_LOOP: asyncio.AbstractEventLoop | None = None

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
    output_format: str = "auto"
    name_mode: str = "suffix"
    suffix: str = "_compressed"
    min_quality: int = 20
    max_quality: int = 100
    min_side: int = 320
    keep_metadata: bool = False
    background: str = "FFFFFF"

    def to_namespace(self) -> argparse.Namespace:
        ns = argparse.Namespace()
        # "best_quality" means process as webp but deliver as .png
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

def _cleanup_old_sessions():
    now = datetime.now()
    expired = [sid for sid, s in sessions.items()
               if now - s.created_at > timedelta(hours=2)]
    for sid in expired:
        s = sessions.pop(sid, None)
        if s:
            s.cleanup()

@app.on_event("startup")
async def startup():
    global _MAIN_LOOP
    _MAIN_LOOP = asyncio.get_event_loop()
    SESSION_BASE.mkdir(parents=True, exist_ok=True)

@app.on_event("shutdown")
async def shutdown():
    for s in sessions.values():
        s.cleanup()
    sessions.clear()


app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

@app.get("/")
async def landing():
    return FileResponse(str(STATIC_DIR / "landing.html"), media_type="text/html")

@app.get("/app")
async def app_root():
    return FileResponse(str(STATIC_DIR / "index.html"), media_type="text/html")


@app.post("/api/session")
async def create_session():
    _cleanup_old_sessions()
    session_id = str(uuid.uuid4())[:12]
    sessions[session_id] = Session(session_id)
    return {"session_id": session_id}


@app.post("/api/session/{session_id}/upload")
async def upload_files(session_id: str, files: list[UploadFile] = File(...)):
    session = sessions.get(session_id)
    if not session:
        return {"error": "Session not found"}, 404

    entries = []
    for f in files:
        dest = session.uploads_dir / f.filename
        content = await f.read()
        dest.write_bytes(content)
        entry = session.add_file(f.filename, dest)
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
        return {"error": "Session not found"}, 404
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
        return {"error": "Session not found"}, 404
    session.settings = settings
    return {"ok": True}


@app.get("/api/session/{session_id}/settings")
async def get_settings(session_id: str):
    session = sessions.get(session_id)
    if not session:
        return {"error": "Session not found"}, 404
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
                entry.status = "done"
                entry.compressed_path = output_path
                entry.output_size = output_path.stat().st_size if output_path.exists() else 0
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

                # Rename .webp to .png when best_quality is selected
                if settings.output_format == "best_quality" and result.output_path and result.output_path.suffix.lower() == ".webp":
                    png_path = result.output_path.with_suffix(".png")
                    try:
                        if png_path.exists():
                            png_path.unlink()
                        result.output_path.rename(png_path)
                        entry.compressed_path = png_path
                    except Exception:
                        pass

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
    savings_pct = ((total_source - total_output) / max(total_source, 1)) * 100
    if error_count > 0:
        summary = f"Finished with {error_count} error(s). Review the log for details."
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
        return {"error": "Session not found"}, 404

    if not session.files:
        return {"error": "No files to compress"}, 400

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
        return {"error": "Session not found"}, 404
    if session._compress_task and not session._compress_task.done():
        session._compress_task.cancel()
    return {"ok": True}


@app.get("/api/session/{session_id}/raw/{file_id}")
async def raw_file(session_id: str, file_id: str):
    session = sessions.get(session_id)
    if not session:
        return {"error": "Session not found"}, 404
    entry = session.file_by_id(file_id)
    if not entry or not entry.original_path.exists():
        return {"error": "File not found"}, 404
    return FileResponse(
        str(entry.original_path),
        filename=entry.filename,
        media_type="application/octet-stream",
    )


@app.get("/api/session/{session_id}/download/{file_id}")
async def download_file(session_id: str, file_id: str):
    session = sessions.get(session_id)
    if not session:
        return {"error": "Session not found"}, 404
    entry = session.file_by_id(file_id)
    if not entry or not entry.compressed_path or not entry.compressed_path.exists():
        return {"error": "File not found or not compressed"}, 404
    # When best_quality is used, the file on disk is .png; ensure download name matches
    is_bq = session.settings.output_format == "best_quality"
    dl_name = entry.filename
    if is_bq:
        stem = Path(dl_name).stem
        dl_name = f"{stem}.png"
    return FileResponse(
        str(entry.compressed_path),
        filename=dl_name,
        media_type="application/octet-stream",
    )


@app.get("/api/session/{session_id}/download-all")
async def download_all(session_id: str):
    session = sessions.get(session_id)
    if not session:
        return {"error": "Session not found"}, 404

    buf = BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for entry in session.files:
            if entry.compressed_path and entry.compressed_path.exists():
                arcname = entry.compressed_path.name
                # When best_quality, file on disk is already .png
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
    file: UploadFile = File(...),
    max_size: str = Form("150kb"),
    quality: int = Form(80),
):
    suffix = f"_preview_{uuid.uuid4().hex[:6]}"
    suffix_path = Path(tempfile.mktemp(suffix=".jpg"))
    tmp_input: Path | None = None
    try:
        ext = file.filename.rsplit(".", 1)[-1].lower() if file.filename else "jpg"

        content = await file.read()
        tmp_input = suffix_path.with_stem(suffix_path.stem + "_input").with_suffix(f".{ext}")
        tmp_input.write_bytes(content)

        ns = argparse.Namespace()
        ns.max_size = max_size
        ns.format = "keep"
        ns.name_mode = "suffix"
        ns.suffix = "_preview"
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
        return {"error": "Preview failed"}, 500
    finally:
        suffix_path.unlink(missing_ok=True)
        if tmp_input is not None:
            tmp_input.unlink(missing_ok=True)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
