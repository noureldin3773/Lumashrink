#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import subprocess
import threading
import tkinter as tk
from datetime import datetime, timedelta
from pathlib import Path
from tkinter import filedialog, messagebox, ttk
from urllib.parse import unquote, urlparse

from compress_image import (
    collect_input_files,
    format_processing_result,
    human_size,
    parse_size_to_bytes,
    process_one_file,
)

try:
    from tkinterdnd2 import DND_FILES, TkinterDnD

    TKDND_AVAILABLE = True
except ModuleNotFoundError:
    DND_FILES = None
    TkinterDnD = None
    TKDND_AVAILABLE = False


PALETTE = {
    "window": "#F7F8FA",
    "surface": "#FFFFFF",
    "surface_soft": "#F1F4F8",
    "surface_emphasis": "#EEF3FA",
    "text": "#0F172A",
    "muted": "#5B6475",
    "line": "#D6DEE8",
    "accent": "#0A66F0",
    "accent_press": "#084CB5",
    "danger": "#B42332",
    "success": "#237A4A",
}

FONT_FAMILY = "SF Pro Text"
MONO_FAMILY = "SF Mono"
APP_SESSION_PATH = Path.home() / "Library" / "Application Support" / "ImageCompressor" / "session.json"
APP_LOG_DIR = Path.home() / "Library" / "Logs" / "ImageCompressorTk"
PRESET_MAP = {"WhatsApp": "150kb", "Email": "300kb", "Web": "500kb", "Archive": "2mb"}


class CompressorApp:
    def __init__(self) -> None:
        self.root = TkinterDnD.Tk() if TKDND_AVAILABLE else tk.Tk()
        self.root.title("Image Compressor")
        self.root.geometry("1220x860")
        self.root.minsize(980, 720)
        self.root.configure(bg=PALETTE["window"])

        self.selected_inputs: list[Path] = []
        self.last_output_folder: Path | None = None
        self.max_size_var = tk.StringVar(value="150kb")
        self.format_var = tk.StringVar(value="auto")
        self.name_mode_var = tk.StringVar(value="suffix")
        self.suffix_var = tk.StringVar(value="-compressed")
        self.output_dir_var = tk.StringVar(value="")
        self.status_var = tk.StringVar(value="Drop images, then press Compress.")
        self.is_running = False
        self.show_activity_var = tk.BooleanVar(value=False)
        self.show_advanced_var = tk.BooleanVar(value=False)
        self.current_log_file = self._prepare_log_file()

        self.style = ttk.Style(self.root)
        self._configure_style()
        self._build_ui()
        self._bind_shortcuts()

        self._update_save_mode_ui()
        self._refresh_file_list()
        self._append_log("Ready. Add files or folders to begin.")
        self._restore_session_prompted()
        self._schedule_window_activation()

    def _prepare_log_file(self) -> Path:
        APP_LOG_DIR.mkdir(parents=True, exist_ok=True)
        cutoff = datetime.now() - timedelta(days=30)
        for p in APP_LOG_DIR.glob("run-*.log"):
            try:
                if datetime.fromtimestamp(p.stat().st_mtime) < cutoff:
                    p.unlink(missing_ok=True)
            except OSError:
                pass
        path = APP_LOG_DIR / f"run-{datetime.now().strftime('%Y-%m-%d_%H-%M-%S')}.log"
        path.touch(exist_ok=True)
        return path

    def _configure_style(self) -> None:
        try:
            self.style.theme_use("clam")
        except tk.TclError:
            pass
        self.style.configure(
            "App.TCombobox",
            padding=7,
            foreground=PALETTE["text"],
            fieldbackground=PALETTE["surface"],
            background=PALETTE["surface"],
            bordercolor=PALETTE["line"],
            lightcolor=PALETTE["line"],
            darkcolor=PALETTE["line"],
            arrowcolor=PALETTE["text"],
        )
        self.style.configure(
            "App.Horizontal.TProgressbar",
            thickness=8,
            background=PALETTE["accent"],
            troughcolor=PALETTE["surface_soft"],
            bordercolor=PALETTE["surface_soft"],
        )

    def _bind_shortcuts(self) -> None:
        self.root.bind("<Delete>", lambda _event: self._remove_selected())
        self.root.bind("<BackSpace>", lambda _event: self._remove_selected())
        self.root.bind("<Command-Return>", lambda _event: self._start_compression())
        self.root.bind("<Double-Button-1>", self._maybe_reveal_selected_file)

    def _build_ui(self) -> None:
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)

        frame = tk.Frame(self.root, bg=PALETTE["window"], padx=28, pady=24)
        frame.grid(row=0, column=0, sticky="nsew")
        frame.columnconfigure(0, weight=1)
        frame.rowconfigure(1, weight=1)

        self._build_topbar(frame)
        self._build_workspace(frame)

    def _build_topbar(self, parent: tk.Frame) -> None:
        bar = tk.Frame(parent, bg=PALETTE["window"])
        bar.grid(row=0, column=0, sticky="ew", pady=(0, 22))
        bar.columnconfigure(0, weight=1)

        left = tk.Frame(bar, bg=PALETTE["window"])
        left.grid(row=0, column=0, sticky="w")

        tk.Label(
            left,
            text="Image Compressor",
            bg=PALETTE["window"],
            fg=PALETTE["text"],
            font=(FONT_FAMILY, 24, "bold"),
        ).grid(row=0, column=0, sticky="w")
        tk.Label(
            left,
            text="Upload, compress, and export with less noise.",
            bg=PALETTE["window"],
            fg=PALETTE["muted"],
            font=(FONT_FAMILY, 12),
        ).grid(row=1, column=0, sticky="w", pady=(4, 0))

        right = tk.Frame(bar, bg=PALETTE["window"])
        right.grid(row=0, column=1, sticky="e")
        self._make_button(right, "Options", self._toggle_advanced, kind="subtle").grid(row=0, column=0, padx=(0, 10))
        self._make_button(right, "Activity", self._toggle_activity, kind="subtle").grid(row=0, column=1)

    def _build_workspace(self, parent: tk.Frame) -> None:
        area = tk.Frame(parent, bg=PALETTE["window"])
        area.grid(row=1, column=0, sticky="nsew")
        area.columnconfigure(0, weight=1)
        area.rowconfigure(0, weight=1)

        main = tk.Frame(area, bg=PALETTE["surface"], padx=28, pady=24, highlightthickness=1, highlightbackground=PALETTE["line"])
        main.grid(row=0, column=0, sticky="nsew")
        main.columnconfigure(0, weight=1)

        self._build_drop_zone(main)
        self._build_file_queue(main)
        self._build_primary_actions(main)
        self._build_advanced_section(main)
        self._build_activity(main)

    def _build_drop_zone(self, parent: tk.Frame) -> None:
        drop = tk.Frame(parent, bg=PALETTE["surface_emphasis"], padx=24, pady=34, highlightthickness=1, highlightbackground=PALETTE["line"])
        drop.grid(row=0, column=0, sticky="ew")
        drop.columnconfigure(0, weight=1)

        tk.Label(drop, text="Drop images here", bg=PALETTE["surface_emphasis"], fg=PALETTE["text"], font=(FONT_FAMILY, 30, "bold")).grid(row=0, column=0)
        subtitle = "Drag JPG, PNG, WebP, TIFF, or folders." if TKDND_AVAILABLE else "Use Add Files or Add Folder below."
        tk.Label(drop, text=subtitle, bg=PALETTE["surface_emphasis"], fg=PALETTE["muted"], font=(FONT_FAMILY, 13)).grid(row=1, column=0, pady=(8, 20))

        actions = tk.Frame(drop, bg=PALETTE["surface_emphasis"])
        actions.grid(row=2, column=0)
        self._make_button(actions, "Add Files", self._pick_files).grid(row=0, column=0, padx=(0, 10))
        self._make_button(actions, "Add Folder", self._pick_folder, kind="secondary").grid(row=0, column=1)

        if TKDND_AVAILABLE:
            for widget in (drop,):
                widget.drop_target_register(DND_FILES)
                widget.dnd_bind("<<Drop>>", self._handle_drop)

    def _build_file_queue(self, parent: tk.Frame) -> None:
        self.queue_heading_var = tk.StringVar(value="No files queued yet.")
        tk.Label(parent, textvariable=self.queue_heading_var, bg=PALETTE["surface"], fg=PALETTE["muted"], font=(FONT_FAMILY, 12)).grid(row=1, column=0, sticky="w", pady=(22, 10))

        list_frame = tk.Frame(parent, bg=PALETTE["surface_soft"], highlightthickness=1, highlightbackground=PALETTE["line"])
        list_frame.grid(row=2, column=0, sticky="nsew")
        list_frame.columnconfigure(0, weight=1)
        list_frame.rowconfigure(0, weight=1)
        parent.rowconfigure(2, weight=1)

        self.file_list = tk.Listbox(
            list_frame,
            height=10,
            bg=PALETTE["surface_soft"],
            fg=PALETTE["text"],
            selectbackground="#DCEBFF",
            selectforeground=PALETTE["text"],
            borderwidth=0,
            highlightthickness=0,
            activestyle="none",
            font=(MONO_FAMILY, 11),
        )
        self.file_list.grid(row=0, column=0, sticky="nsew")
        tk.Scrollbar(list_frame, orient="vertical", command=self.file_list.yview).grid(row=0, column=1, sticky="ns")

        list_actions = tk.Frame(parent, bg=PALETTE["surface"])
        list_actions.grid(row=3, column=0, sticky="w", pady=(10, 0))
        self._make_button(list_actions, "Remove Selected", self._remove_selected, kind="subtle").grid(row=0, column=0, padx=(0, 8))
        self._make_button(list_actions, "Clear", self._clear_files, kind="danger").grid(row=0, column=1)

    def _build_primary_actions(self, parent: tk.Frame) -> None:
        bar = tk.Frame(parent, bg=PALETTE["surface"])
        bar.grid(row=4, column=0, sticky="ew", pady=(22, 0))
        bar.columnconfigure(0, weight=1)

        tk.Label(bar, textvariable=self.status_var, bg=PALETTE["surface"], fg=PALETTE["text"], font=(FONT_FAMILY, 13, "bold"), anchor="w").grid(row=0, column=0, sticky="w")

        self.progress = ttk.Progressbar(bar, mode="indeterminate", style="App.Horizontal.TProgressbar")
        self.progress.grid(row=1, column=0, sticky="ew", pady=(10, 14))

        actions = tk.Frame(bar, bg=PALETTE["surface"])
        actions.grid(row=2, column=0, sticky="e")
        self.open_output_button = self._make_button(actions, "Open Output", self._open_output_folder, kind="subtle")
        self.open_output_button.grid(row=0, column=0, padx=(0, 10))
        self.open_output_button.config(state="disabled")
        self.compress_button = self._make_button(actions, "Compress", self._start_compression, kind="primary", padx=28, pady=12)
        self.compress_button.grid(row=0, column=1)

    def _build_advanced_section(self, parent: tk.Frame) -> None:
        self.advanced_frame = tk.Frame(parent, bg=PALETTE["surface"], pady=16)
        self.advanced_frame.grid(row=5, column=0, sticky="ew")
        self.advanced_frame.columnconfigure(1, weight=1)
        self._add_field_label(self.advanced_frame, 0, "Target size")
        self.target_entry = self._make_entry(self.advanced_frame, self.max_size_var)
        self.target_entry.grid(row=0, column=1, sticky="ew", pady=4)

        preset_row = tk.Frame(self.advanced_frame, bg=PALETTE["surface"])
        preset_row.grid(row=1, column=1, sticky="w", pady=(2, 10))
        for i, (label, value) in enumerate(PRESET_MAP.items()):
            self._make_button(preset_row, label, lambda chosen=value: self.max_size_var.set(chosen), kind="subtle", padx=10, pady=7).grid(row=0, column=i, padx=(0, 7))

        self._add_field_label(self.advanced_frame, 2, "Format")
        self.format_box = ttk.Combobox(self.advanced_frame, textvariable=self.format_var, values=("auto", "keep", "jpeg", "png", "webp"), state="readonly", style="App.TCombobox")
        self.format_box.grid(row=2, column=1, sticky="ew", pady=4)

        self._add_field_label(self.advanced_frame, 3, "Save mode")
        self.name_mode_box = ttk.Combobox(self.advanced_frame, textvariable=self.name_mode_var, values=("suffix", "same-name", "overwrite"), state="readonly", style="App.TCombobox")
        self.name_mode_box.grid(row=3, column=1, sticky="ew", pady=4)
        self.name_mode_box.bind("<<ComboboxSelected>>", lambda _event: self._update_save_mode_ui())

        self._add_field_label(self.advanced_frame, 4, "Suffix")
        self.suffix_entry = self._make_entry(self.advanced_frame, self.suffix_var)
        self.suffix_entry.grid(row=4, column=1, sticky="ew", pady=4)

        self._add_field_label(self.advanced_frame, 5, "Output folder")
        folder_row = tk.Frame(self.advanced_frame, bg=PALETTE["surface"])
        folder_row.grid(row=5, column=1, sticky="ew", pady=4)
        folder_row.columnconfigure(0, weight=1)
        self.output_dir_entry = self._make_entry(folder_row, self.output_dir_var)
        self.output_dir_entry.grid(row=0, column=0, sticky="ew", padx=(0, 8))
        self.browse_button = self._make_button(folder_row, "Choose", self._choose_output_folder, kind="subtle", padx=10, pady=7)
        self.browse_button.grid(row=0, column=1, padx=(0, 8))
        self.clear_output_button = self._make_button(folder_row, "Clear", lambda: self.output_dir_var.set(""), kind="subtle", padx=10, pady=7)
        self.clear_output_button.grid(row=0, column=2)

        self._set_advanced_visible(False)

    def _build_activity(self, parent: tk.Frame) -> None:
        self.activity_frame = tk.Frame(parent, bg=PALETTE["surface"], pady=14)
        self.activity_frame.grid(row=6, column=0, sticky="nsew")
        self.activity_frame.columnconfigure(0, weight=1)
        self.activity_frame.rowconfigure(1, weight=1)
        tk.Label(self.activity_frame, text="Activity", bg=PALETTE["surface"], fg=PALETTE["muted"], font=(FONT_FAMILY, 12, "bold")).grid(row=0, column=0, sticky="w", pady=(0, 8))

        self.log_text = tk.Text(self.activity_frame, height=8, wrap="word", state="disabled", bg=PALETTE["surface_soft"], fg=PALETTE["text"], relief="flat", borderwidth=0, highlightthickness=1, highlightbackground=PALETTE["line"], padx=12, pady=10, font=(MONO_FAMILY, 11))
        self.log_text.grid(row=1, column=0, sticky="nsew")
        self._set_activity_visible(False)

    def _add_field_label(self, parent: tk.Widget, row: int, text: str) -> None:
        tk.Label(parent, text=text, bg=PALETTE["surface"], fg=PALETTE["muted"], font=(FONT_FAMILY, 11)).grid(row=row, column=0, sticky="w", padx=(0, 12), pady=4)

    def _make_entry(self, parent: tk.Widget, textvariable: tk.StringVar) -> tk.Entry:
        return tk.Entry(parent, textvariable=textvariable, bg=PALETTE["surface"], fg=PALETTE["text"], insertbackground=PALETTE["text"], relief="flat", borderwidth=0, highlightthickness=1, highlightbackground=PALETTE["line"], highlightcolor=PALETTE["accent"], font=(FONT_FAMILY, 12))

    def _make_button(self, parent: tk.Widget, text: str, command, kind: str = "secondary", padx: int = 16, pady: int = 10) -> tk.Button:
        styles = {
            "primary": {"bg": PALETTE["accent"], "fg": "white", "activebackground": PALETTE["accent_press"], "activeforeground": "white"},
            "secondary": {"bg": "#E9EEF6", "fg": PALETTE["text"], "activebackground": "#DDE7F4", "activeforeground": PALETTE["text"]},
            "subtle": {"bg": PALETTE["surface_soft"], "fg": PALETTE["text"], "activebackground": "#E6EDF7", "activeforeground": PALETTE["text"]},
            "danger": {"bg": "#FDECEE", "fg": PALETTE["danger"], "activebackground": "#F8DCDF", "activeforeground": PALETTE["danger"]},
        }
        button = tk.Button(parent, text=text, command=command, relief="flat", borderwidth=0, highlightthickness=0, cursor="hand2", disabledforeground="#98A2B3", font=(FONT_FAMILY, 11, "bold"), padx=padx, pady=pady, **styles[kind])
        button.bind("<Return>", lambda _event: command())
        button.bind("<space>", lambda _event: command())
        return button

    def _toggle_advanced(self) -> None:
        self._set_advanced_visible(not self.show_advanced_var.get())

    def _toggle_activity(self) -> None:
        self._set_activity_visible(not self.show_activity_var.get())

    def _set_advanced_visible(self, visible: bool) -> None:
        self.show_advanced_var.set(visible)
        if visible:
            self.advanced_frame.grid()
        else:
            self.advanced_frame.grid_remove()

    def _set_activity_visible(self, visible: bool) -> None:
        self.show_activity_var.set(visible)
        if visible:
            self.activity_frame.grid()
        else:
            self.activity_frame.grid_remove()

    def _choose_output_folder(self) -> None:
        selected = filedialog.askdirectory()
        if selected:
            self.output_dir_var.set(selected)

    def _pick_files(self) -> None:
        filenames = filedialog.askopenfilenames(title="Select images", filetypes=[("Supported images", "*.jpg *.jpeg *.png *.webp *.bmp *.tif *.tiff"), ("All files", "*.*")])
        if filenames:
            self._add_inputs([Path(name) for name in filenames])

    def _pick_folder(self) -> None:
        folder = filedialog.askdirectory(title="Select a folder")
        if folder:
            self._add_inputs([Path(folder)])

    def _clear_files(self) -> None:
        self.selected_inputs.clear()
        self._refresh_file_list()
        self.status_var.set("Queue cleared.")

    def _remove_selected(self) -> None:
        selected_indexes = list(self.file_list.curselection())
        if not selected_indexes:
            return
        for index in reversed(selected_indexes):
            del self.selected_inputs[index]
        self._refresh_file_list()
        self.status_var.set("Removed selected item(s).")

    def _maybe_reveal_selected_file(self, event: tk.Event) -> None:
        if event.widget is self.file_list:
            self._reveal_selected_file()

    def _reveal_selected_file(self) -> None:
        selection = self.file_list.curselection()
        if not selection:
            return
        path = self.selected_inputs[selection[0]]
        try:
            subprocess.Popen(["open", "-R", str(path)])
        except Exception as error:
            self._append_log(f"[ERROR] Could not reveal {path.name}: {error}")

    def _parse_drop_items(self, raw_data: str) -> list[Path]:
        candidates: list[Path] = []
        for item in self.root.tk.splitlist(raw_data):
            text = item.strip()
            if text.startswith("file://"):
                parsed = urlparse(text)
                text = unquote(parsed.path)
            candidates.append(Path(text))
        return candidates

    def _handle_drop(self, event: tk.Event) -> None:
        self._add_inputs(self._parse_drop_items(event.data))

    def _add_inputs(self, paths: list[Path]) -> None:
        existing = {path.resolve() for path in self.selected_inputs}
        added = 0
        for path in paths:
            expanded = path.expanduser()
            if not expanded.exists():
                continue
            for file_path in collect_input_files([expanded.resolve()]):
                resolved = file_path.resolve()
                if resolved not in existing:
                    self.selected_inputs.append(resolved)
                    existing.add(resolved)
                    added += 1
        self._refresh_file_list()
        self.status_var.set(f"Added {added} file(s)." if added else "No supported image files found.")

    def _refresh_file_list(self) -> None:
        self.file_list.delete(0, tk.END)
        for path in self.selected_inputs:
            display_size = human_size(path.stat().st_size) if path.exists() else "Missing"
            self.file_list.insert(tk.END, f"{path.name} | {display_size} | {path.parent}")
        self.queue_heading_var.set(
            f"{len(self.selected_inputs)} file(s) ready." if self.selected_inputs else "No files queued yet."
        )

    def _set_entry_enabled(self, entry: tk.Entry, enabled: bool) -> None:
        entry.configure(state="normal" if enabled else "disabled")
        entry.configure(disabledbackground="#EEF2F6", disabledforeground="#7D8796", bg=PALETTE["surface"])

    def _update_save_mode_ui(self) -> None:
        mode = self.name_mode_var.get()
        if mode == "suffix":
            self._set_entry_enabled(self.suffix_entry, True)
            self._set_entry_enabled(self.output_dir_entry, True)
            self.browse_button.config(state="normal")
            self.clear_output_button.config(state="normal")
        elif mode == "same-name":
            self._set_entry_enabled(self.suffix_entry, False)
            self._set_entry_enabled(self.output_dir_entry, True)
            self.browse_button.config(state="normal")
            self.clear_output_button.config(state="normal")
        else:
            if self.format_var.get() == "auto":
                self.format_var.set("keep")
            self._set_entry_enabled(self.suffix_entry, False)
            self._set_entry_enabled(self.output_dir_entry, False)
            self.browse_button.config(state="disabled")
            self.clear_output_button.config(state="disabled")

    def _append_log(self, text: str) -> None:
        self.log_text.configure(state="normal")
        self.log_text.insert(tk.END, text + "\n")
        self.log_text.see(tk.END)
        self.log_text.configure(state="disabled")
        try:
            with self.current_log_file.open("a", encoding="utf-8") as handle:
                handle.write(f"{datetime.now().isoformat()} {text}\n")
        except OSError:
            pass

    def _schedule_window_activation(self) -> None:
        self.root.after(50, self._activate_window)
        self.root.after(250, self._activate_window)

    def _activate_window(self) -> None:
        try:
            self.root.deiconify()
            self.root.lift()
            self.root.focus_force()
            self.root.attributes("-topmost", True)
            self.root.after(150, lambda: self.root.attributes("-topmost", False))
        except Exception:
            pass

    def _set_running(self, running: bool) -> None:
        self.is_running = running
        self.root.config(cursor="watch" if running else "")
        self.compress_button.config(state="disabled" if running else "normal")
        if running:
            self.progress.start(10)
        else:
            self.progress.stop()

    def _start_compression(self) -> None:
        if self.is_running:
            return
        if not self.selected_inputs:
            messagebox.showerror("No files", "Add at least one image or folder first.")
            return
        try:
            parse_size_to_bytes(self.max_size_var.get().strip())
        except ValueError as error:
            messagebox.showerror("Invalid target size", str(error))
            return

        output_argument = None
        output_text = self.output_dir_var.get().strip()
        if self.name_mode_var.get() == "same-name" and not output_text:
            messagebox.showerror("Output folder required", "Choose an output folder for same-name mode, or use overwrite mode.")
            return

        if self.name_mode_var.get() != "overwrite" and output_text:
            output_argument = Path(output_text).expanduser()
            try:
                output_argument.mkdir(parents=True, exist_ok=True)
                output_argument = output_argument.resolve()
            except OSError as error:
                messagebox.showerror("Invalid output folder", f"Could not use the chosen output folder.\n\n{error}")
                return

        args = argparse.Namespace(max_size=self.max_size_var.get().strip(), format=self.format_var.get().strip(), name_mode=self.name_mode_var.get().strip(), suffix=self.suffix_var.get(), min_quality=35, max_quality=95, min_side=320, keep_metadata=False, background="FFFFFF")
        files = collect_input_files(self.selected_inputs)
        if not files:
            messagebox.showerror("No supported files", "The current queue does not contain supported images.")
            return

        self.last_output_folder = None
        self.open_output_button.config(state="disabled")
        self._save_session()
        self._append_log("")
        self._append_log(f"Starting compression for {len(files)} file(s)...")
        self.status_var.set("Compressing...")
        self._set_running(True)

        threading.Thread(target=self._run_compression, args=(files, output_argument, args), daemon=True).start()

    def _run_compression(self, files: list[Path], output_argument: Path | None, args: argparse.Namespace) -> None:
        failures = 0
        written_paths: list[Path] = []
        try:
            for file_path in files:
                try:
                    result = process_one_file(file_path, output_argument, args)
                    written_paths.append(result.output_path)
                    for line in format_processing_result(result):
                        self.root.after(0, self._append_log, line)
                    if not result.met_target:
                        failures += 1
                except Exception as error:
                    failures += 1
                    self.root.after(0, self._append_log, f"[ERROR] {file_path.name} | {error}")
        finally:
            summary = f"Finished. {len(files) - failures} succeeded, {failures} had issues." if failures else f"Finished. {len(files)} file(s) processed successfully."
            folder_to_open = output_argument if (written_paths and output_argument is not None and output_argument.is_dir()) else (written_paths[0].parent if written_paths else None)
            self.root.after(0, self._finish_run, summary, folder_to_open)

    def _finish_run(self, summary: str, folder_to_open: Path | None) -> None:
        self.status_var.set(summary)
        self._append_log(summary)
        self._set_running(False)
        if folder_to_open is not None:
            self.last_output_folder = folder_to_open
            self.open_output_button.config(state="normal")
            self._append_log(f"Output folder: {folder_to_open}")
        self._notify_completion(summary)

    def _open_output_folder(self) -> None:
        if self.last_output_folder is None:
            return
        try:
            subprocess.Popen(["open", str(self.last_output_folder)])
        except Exception as error:
            self._append_log(f"[ERROR] Could not open output folder: {error}")

    def _notify_completion(self, summary: str) -> None:
        try:
            subprocess.Popen(["osascript", "-e", f'display notification "{summary}" with title "Image Compressor"'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

    def _save_session(self) -> None:
        APP_SESSION_PATH.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "inputs": [str(path) for path in self.selected_inputs],
            "max_size": self.max_size_var.get(),
            "format": self.format_var.get(),
            "name_mode": self.name_mode_var.get(),
            "suffix": self.suffix_var.get(),
            "output_dir": self.output_dir_var.get(),
        }
        APP_SESSION_PATH.write_text(json.dumps(payload), encoding="utf-8")

    def _restore_session_prompted(self) -> None:
        if not APP_SESSION_PATH.exists():
            return
        if not messagebox.askyesno("Restore Session", "Restore your previous queue and settings?"):
            return
        try:
            payload = json.loads(APP_SESSION_PATH.read_text(encoding="utf-8"))
        except Exception:
            return
        self.selected_inputs = [Path(p) for p in payload.get("inputs", []) if Path(p).exists()]
        self.max_size_var.set(payload.get("max_size", "150kb"))
        self.format_var.set(payload.get("format", "auto"))
        self.name_mode_var.set(payload.get("name_mode", "suffix"))
        self.suffix_var.set(payload.get("suffix", "-compressed"))
        self.output_dir_var.set(payload.get("output_dir", ""))
        self._update_save_mode_ui()
        self._refresh_file_list()

    def run(self) -> None:
        self.root.mainloop()


def main() -> None:
    app = CompressorApp()
    app.run()


if __name__ == "__main__":
    main()
