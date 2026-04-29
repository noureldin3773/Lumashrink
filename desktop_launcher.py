#!/usr/bin/env python3

from __future__ import annotations

import datetime as dt
import os
import sys
import traceback
from pathlib import Path


def log_message(log_file: Path, message: str) -> None:
    timestamp = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with log_file.open("a", encoding="utf-8") as handle:
        handle.write(f"[{timestamp}] {message}\n")


def add_venv_site_packages(project_dir: Path) -> None:
    candidates = sorted(project_dir.glob(".venv/lib/python*/site-packages"))
    for candidate in candidates:
        resolved = str(candidate.resolve())
        if resolved not in sys.path:
            sys.path.insert(0, resolved)


def show_error_dialog(message: str) -> None:
    try:
        import tkinter as tk
        from tkinter import messagebox

        root = tk.Tk()
        root.withdraw()
        messagebox.showerror("Image Compressor", message)
        root.destroy()
    except Exception:
        pass


def main() -> int:
    project_dir = Path(__file__).resolve().parent
    log_file = Path.home() / "Library" / "Logs" / "Image Compressor.log"
    log_file.parent.mkdir(parents=True, exist_ok=True)

    try:
        os.environ.setdefault("TK_SILENCE_DEPRECATION", "1")
        log_message(log_file, f"Launcher starting from {project_dir}")
        os.chdir(project_dir)
        log_message(log_file, f"Current working directory set to {Path.cwd()}")
        add_venv_site_packages(project_dir)
        sys.path.insert(0, str(project_dir))
        from compress_image_app import main as app_main

        log_message(log_file, "GUI bootstrap loaded successfully")
        app_main()
        log_message(log_file, "GUI exited normally")
        return 0
    except Exception:
        details = traceback.format_exc()
        with log_file.open("a", encoding="utf-8") as handle:
            handle.write(details)
            if not details.endswith("\n"):
                handle.write("\n")
        show_error_dialog(
            "The desktop launcher could not start.\n\n"
            f"Details were written to:\n{log_file}"
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
