#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
import threading
import time
import tkinter as tk
import zipfile
from dataclasses import dataclass
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
    from PIL import Image, ImageTk

    PIL_UI_AVAILABLE = True
except ModuleNotFoundError:
    Image = None
    ImageTk = None
    PIL_UI_AVAILABLE = False

try:
    from tkinterdnd2 import DND_FILES, TkinterDnD

    TKDND_AVAILABLE = True
except ModuleNotFoundError:
    DND_FILES = None
    TkinterDnD = None
    TKDND_AVAILABLE = False


PALETTE = {
    "window": "#EEF2F8",
    "window_2": "#F8FAFD",
    "glass": "#FFFFFF",
    "glass_soft": "#F7F9FD",
    "glass_alt": "#EEF4FC",
    "text": "#111827",
    "muted": "#647084",
    "faint": "#8B95A7",
    "line": "#D8E1EC",
    "line_strong": "#BFD0E4",
    "accent": "#1677FF",
    "accent_2": "#5AC8FA",
    "accent_press": "#0A56C2",
    "danger": "#C2414B",
    "success": "#16885A",
    "warning": "#A96912",
    "shadow": "#CAD5E4",
}

TOKENS = {
    "space_1": 4,
    "space_2": 8,
    "space_3": 12,
    "space_4": 16,
    "space_5": 20,
    "space_6": 24,
    "space_7": 32,
    "radius_sm": 8,
    "radius_md": 14,
    "radius_lg": 22,
    "duration_fast": 120,
    "duration_base": 180,
    "duration_slow": 320,
}

FONT_FAMILY = "SF Pro Text"
DISPLAY_FAMILY = "SF Pro Display"
MONO_FAMILY = "SF Mono"
APP_SESSION_PATH = Path.home() / "Library" / "Application Support" / "ImageCompressor" / "session.json"
APP_LOG_DIR = Path.home() / "Library" / "Logs" / "ImageCompressorTk"

PRESET_MAP = {
    "Website Ready": ("500kb", "Safari-ready images", "High", "75-92%"),
    "AI Artwork": ("2mb", "Preserve painterly detail", "Ultra", "45-70%"),
    "Social Media": ("900kb", "Clean feed exports", "High", "65-85%"),
    "Ultra Quality": ("4mb", "Gentle compression", "Ultra", "25-55%"),
    "Portfolio Mode": ("1.5mb", "Crisp case-study images", "Premium", "55-80%"),
    "Framer/Webflow": ("350kb", "Fast landing pages", "High", "80-95%"),
    "Fast Export": ("150kb", "Tiny shareable files", "Balanced", "88-98%"),
}

PRESETS = [
    ("Fast Export", "150kb", "Tiny shareable files", "⚡"),
    ("AI Artwork", "2mb", "Preserve painterly detail", "✦"),
    ("Social Media", "900kb", "Clean feed exports", "◐"),
    ("Ultra Quality", "4mb", "Gentle compression", "◆"),
    ("Portfolio Mode", "1.5mb", "Crisp case-study images", "▣"),
    ("Framer/Webflow", "350kb", "Fast landing pages", "⌘"),
]

PRESET_QUALITY = {
    "Fast Export": "Balanced",
    "AI Artwork": "Ultra",
    "Social Media": "High",
    "Ultra Quality": "Ultra",
    "Portfolio Mode": "Premium",
    "Framer/Webflow": "High",
}

PRESET_SAVINGS = {
    "Fast Export": "88-98%",
    "AI Artwork": "45-70%",
    "Social Media": "65-85%",
    "Ultra Quality": "25-55%",
    "Portfolio Mode": "55-80%",
    "Framer/Webflow": "80-95%",
}


@dataclass
class QueueRow:
    path: Path
    frame: tk.Frame
    thumb_label: tk.Label
    name_var: tk.StringVar
    meta_var: tk.StringVar
    state_var: tk.StringVar
    saved_var: tk.StringVar
    progress: ttk.Progressbar
    thumbnail: object | None = None
    output_size: int | None = None
    state: str = "Queued"


class CompressorApp:
    def __init__(self) -> None:
        self.root = TkinterDnD.Tk() if TKDND_AVAILABLE else tk.Tk()
        self.root.title("LumaShrink")
        self.root.geometry("1360x900")
        self.root.minsize(1040, 760)
        self.root.configure(bg=PALETTE["window"])

        self.selected_inputs: list[Path] = []
        self.queue_rows: dict[Path, QueueRow] = {}
        self.preview_image_ref: object | None = None
        self.last_output_folder: Path | None = None
        self.max_size_var = tk.StringVar(value="150kb")
        self.format_var = tk.StringVar(value="best_quality")
        self.name_mode_var = tk.StringVar(value="same-name")
        self.suffix_var = tk.StringVar(value="_compressed")
        self.output_dir_var = tk.StringVar(value="")
        self.status_var = tk.StringVar(value="Drop files anywhere to begin.")
        self.smart_hint_var = tk.StringVar(value="Website Ready is recommended for balanced web exports.")
        self.total_saved_var = tk.StringVar(value="0 B")
        self.ratio_var = tk.StringVar(value="0%")
        self.files_done_var = tk.StringVar(value="0 / 0")
        self.eta_var = tk.StringVar(value="Ready")
        self.queue_total_var = tk.StringVar(value="0 B queued")
        self.queue_compressed_var = tk.StringVar(value="0 B estimated")
        self.queue_saved_var = tk.StringVar(value="0 B saved")
        self.queue_count_var = tk.StringVar(value="0 files")
        self.preview_title_var = tk.StringVar(value="Before / After Preview")
        self.preview_hint_var = tk.StringVar(value="Select a queued image to inspect compression detail.")
        self.preview_meta_var = tk.StringVar(value="")
        self.processing_speed_var = tk.StringVar(value="Idle")
        self.session_badge_var = tk.StringVar(value="Starting session")
        self.progress_caption_var = tk.StringVar(value="Preparing the queue.")
        self.batch_count_var = tk.StringVar(value="0 / 0 done")
        self.batch_rate_var = tk.StringVar(value="- files/s")
        self.batch_eta_var = tk.StringVar(value="ETA -")
        self.batch_savings_var = tk.StringVar(value="")
        self.min_side_var = tk.StringVar(value="320")
        self.min_quality_var = tk.IntVar(value=20)
        self.max_quality_var = tk.IntVar(value=100)
        self.keep_metadata_var = tk.BooleanVar(value=False)
        self.custom_size_var = tk.StringVar(value="150")
        self.custom_unit_var = tk.StringVar(value="kb")
        self.active_preset_name = "Fast Export"
        self.is_running = False
        self._stop_requested = False
        self.show_activity_var = tk.BooleanVar(value=True)
        self.show_advanced_var = tk.BooleanVar(value=True)
        self.current_log_file = self._prepare_log_file()
        self.run_started_at = 0.0
        self.run_total_files = 0
        self.run_completed = 0
        self.run_source_bytes = 0
        self.run_output_bytes = 0
        self.preset_cards: dict[str, tk.Frame] = {}
        self.compressed_outputs: list[Path] = []

        self.style = ttk.Style(self.root)
        self._configure_style()
        self._build_ui()
        self._bind_shortcuts()

        self._highlight_active_preset()
        self._update_save_mode_ui()
        self._refresh_file_list()
        self._append_log("Ready. Add files or folders to begin.")
        self._restore_session_prompted()
        self._schedule_window_activation()
        self._start_ambient_motion()

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
            padding=9,
            foreground=PALETTE["text"],
            fieldbackground=PALETTE["glass"],
            background=PALETTE["glass"],
            bordercolor=PALETTE["line"],
            lightcolor=PALETTE["line"],
            darkcolor=PALETTE["line"],
            arrowcolor=PALETTE["text"],
        )
        self.style.configure(
            "App.Horizontal.TProgressbar",
            thickness=9,
            background=PALETTE["accent"],
            troughcolor="#E5ECF6",
            bordercolor="#E5ECF6",
            lightcolor=PALETTE["accent_2"],
            darkcolor=PALETTE["accent"],
        )
        self.style.configure(
            "Mini.Horizontal.TProgressbar",
            thickness=5,
            background=PALETTE["success"],
            troughcolor="#E9EEF5",
            bordercolor="#E9EEF5",
        )

    def _bind_shortcuts(self) -> None:
        self.root.bind("<Delete>", lambda _event: self._remove_selected())
        self.root.bind("<BackSpace>", lambda _event: self._remove_selected())
        self.root.bind("<Command-Return>", lambda _event: self._start_compression())
        self.root.bind("<Double-Button-1>", self._maybe_reveal_selected_file)
        self.root.bind("<Configure>", self._handle_resize)

    def _build_ui(self) -> None:
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)

        self.shell = tk.Frame(self.root, bg=PALETTE["window"], padx=28, pady=22)
        self.shell.grid(row=0, column=0, sticky="nsew")
        self.shell.columnconfigure(0, weight=1)
        self.shell.rowconfigure(1, weight=1)

        self._build_topbar(self.shell)
        self._build_workspace(self.shell)

    def _build_logo_mark(self, parent: tk.Widget) -> tk.Canvas:
        frame = tk.Frame(parent, bg=PALETTE["window"], width=44, height=44)
        frame.pack_propagate(False)
        canvas = tk.Canvas(frame, width=44, height=44, bg=PALETTE["window"], highlightthickness=0, borderwidth=0)
        canvas.pack(fill="both", expand=True)
        canvas.create_rectangle(3, 3, 41, 41, outline=PALETTE["accent"], width=2, fill="#EAF3FF")
        canvas.create_oval(11, 10, 18, 17, fill=PALETTE["accent"], outline="")
        canvas.create_line(8, 31, 17, 21, 23, 27, 30, 18, 36, 31, smooth=True, fill=PALETTE["accent"], width=2)
        return frame

    def _build_topbar(self, parent: tk.Frame) -> None:
        bar = tk.Frame(parent, bg=PALETTE["window"])
        bar.grid(row=0, column=0, sticky="ew", pady=(0, 18))
        bar.columnconfigure(0, weight=1)

        left = tk.Frame(bar, bg=PALETTE["window"])
        left.grid(row=0, column=0, sticky="w")
        self._build_logo_mark(left).grid(row=0, column=0, rowspan=2, padx=(0, 12))
        title_box = tk.Frame(left, bg=PALETTE["window"])
        title_box.grid(row=0, column=1, sticky="w")
        tk.Label(title_box, text="LumaShrink", bg=PALETTE["window"], fg=PALETTE["text"], font=(DISPLAY_FAMILY, 26, "bold")).grid(row=0, column=0, sticky="w")
        tk.Label(title_box, text="Premium local compression for creators, portfolios, and fast web launches.", bg=PALETTE["window"], fg=PALETTE["muted"], font=(FONT_FAMILY, 12)).grid(row=1, column=0, sticky="w", pady=(3, 0))

        right = tk.Frame(bar, bg=PALETTE["window"])
        right.grid(row=0, column=1, sticky="e")
        tk.Label(right, textvariable=self.session_badge_var, bg="#F4F7FC", fg=PALETTE["muted"], font=(FONT_FAMILY, 11, "bold"), padx=11, pady=7, highlightthickness=1, highlightbackground=PALETTE["line"]).grid(row=0, column=0, padx=(0, 10))
        self._make_button(right, "New", self._new_session, kind="glass").grid(row=0, column=1)

    def _build_workspace(self, parent: tk.Frame) -> None:
        self.workspace = tk.Frame(parent, bg=PALETTE["window"])
        self.workspace.grid(row=1, column=0, sticky="nsew")
        self.workspace.columnconfigure(0, weight=7)
        self.workspace.columnconfigure(1, weight=4, minsize=380)
        self.workspace.rowconfigure(0, weight=1)

        self.main = tk.Frame(self.workspace, bg=PALETTE["window"])
        self.main.grid(row=0, column=0, sticky="nsew", padx=(0, 18))
        self.main.columnconfigure(0, weight=1)
        self.main.rowconfigure(2, weight=1)

        self._build_drop_zone(self.main)
        self._build_metrics(self.main)
        self._build_file_queue(self.main)

        side_holder = tk.Frame(self.workspace, bg=PALETTE["window"])
        side_holder.grid(row=0, column=1, sticky="nsew")
        side_holder.columnconfigure(0, weight=1)
        side_holder.rowconfigure(0, weight=1)

        self.side_canvas = tk.Canvas(side_holder, bg=PALETTE["window"], highlightthickness=0, borderwidth=0)
        self.side_canvas.grid(row=0, column=0, sticky="nsew")
        side_scroll = tk.Scrollbar(side_holder, orient="vertical", command=self.side_canvas.yview)
        side_scroll.grid(row=0, column=1, sticky="ns")
        self.side_canvas.configure(yscrollcommand=side_scroll.set)
        self.side = tk.Frame(self.side_canvas, bg=PALETTE["window"])
        self.side_window = self.side_canvas.create_window((0, 0), window=self.side, anchor="nw")
        self.side.bind("<Configure>", self._update_side_scroll_region)
        self.side_canvas.bind("<Configure>", self._fit_side_width)
        self.side.columnconfigure(0, weight=1)

        self._build_settings_card(self.side)
        self._build_preview_panel(self.side)
        self._build_progress_card(self.side)
        self._build_controls(self.side)
        self._build_activity(self.side)

    def _update_side_scroll_region(self, _event: tk.Event | None = None) -> None:
        self.side_canvas.configure(scrollregion=self.side_canvas.bbox("all"))

    def _fit_side_width(self, event: tk.Event) -> None:
        self.side_canvas.itemconfigure(self.side_window, width=event.width)

    def _make_glass_panel(self, parent: tk.Widget, padx: int, pady: int) -> tk.Frame:
        panel = tk.Frame(parent, bg=PALETTE["glass"], padx=padx, pady=pady, highlightthickness=1, highlightbackground="#FFFFFF")
        panel.configure(relief="flat")
        return panel

    def _build_drop_zone(self, parent: tk.Frame) -> None:
        self.drop = self._make_glass_panel(parent, padx=24, pady=24)
        self.drop.grid(row=0, column=0, sticky="ew")
        self.drop.configure(bg=PALETTE["glass_alt"], highlightbackground=PALETTE["line_strong"])
        self.drop.columnconfigure(0, weight=1)

        self.drop_icon_var = tk.StringVar(value="◇")
        icon = tk.Label(self.drop, textvariable=self.drop_icon_var, bg=PALETTE["glass_alt"], fg=PALETTE["accent"], font=(DISPLAY_FAMILY, 40, "bold"))
        icon.grid(row=0, column=0)
        tk.Label(self.drop, text="Drop files anywhere", bg=PALETTE["glass_alt"], fg=PALETTE["text"], font=(DISPLAY_FAMILY, 28, "bold")).grid(row=1, column=0)
        subtitle = "Images and videos stay local while LumaShrink prepares creator-ready exports." if TKDND_AVAILABLE else "Use Upload files below. Drag-and-drop support needs tkinterdnd2."
        tk.Label(self.drop, text=subtitle, bg=PALETTE["glass_alt"], fg=PALETTE["muted"], font=(FONT_FAMILY, 13), wraplength=560, justify="center").grid(row=2, column=0, pady=(8, 8))

        actions = tk.Frame(self.drop, bg=PALETTE["glass_alt"])
        actions.grid(row=3, column=0, pady=(6, 10))
        self._make_button(actions, "Upload files", self._pick_files, kind="primary").grid(row=0, column=0, padx=(0, 10))
        self._make_button(actions, "Add Folder", self._pick_folder, kind="secondary").grid(row=0, column=1)
        tk.Label(self.drop, textvariable=self.smart_hint_var, bg=PALETTE["glass_alt"], fg=PALETTE["accent"], font=(FONT_FAMILY, 11, "bold")).grid(row=4, column=0, pady=(6, 0))

        self.drop.bind("<Enter>", lambda _event: self._set_drop_active(True))
        self.drop.bind("<Leave>", lambda _event: self._set_drop_active(False))
        if TKDND_AVAILABLE:
            self.drop.drop_target_register(DND_FILES)
            self.drop.dnd_bind("<<DropEnter>>", lambda event: self._set_drop_active(True))
            self.drop.dnd_bind("<<DropLeave>>", lambda event: self._set_drop_active(False))
            self.drop.dnd_bind("<<Drop>>", self._handle_drop)

    def _build_metrics(self, parent: tk.Frame) -> None:
        stats = tk.Frame(parent, bg=PALETTE["window"])
        stats.grid(row=1, column=0, sticky="ew", pady=(18, 18))
        for i in range(4):
            stats.columnconfigure(i, weight=1)

        data = [
            ("Total Saved", self.total_saved_var, PALETTE["success"]),
            ("Compression Ratio", self.ratio_var, PALETTE["accent"]),
            ("Files Processed", self.files_done_var, PALETTE["text"]),
            ("Estimated Time", self.eta_var, PALETTE["warning"]),
        ]
        for col, (label, variable, accent) in enumerate(data):
            card = tk.Frame(stats, bg=PALETTE["glass"], padx=14, pady=13, highlightthickness=1, highlightbackground="#FFFFFF")
            card.grid(row=0, column=col, sticky="ew", padx=(0 if col == 0 else 7, 0 if col == 3 else 7))
            tk.Label(card, text=label, bg=PALETTE["glass"], fg=PALETTE["muted"], font=(FONT_FAMILY, 10, "bold")).grid(row=0, column=0, sticky="w")
            tk.Label(card, textvariable=variable, bg=PALETTE["glass"], fg=accent, font=(DISPLAY_FAMILY, 22, "bold")).grid(row=1, column=0, sticky="w", pady=(3, 0))

    def _build_file_queue(self, parent: tk.Frame) -> None:
        self.queue_card = self._make_glass_panel(parent, padx=0, pady=0)
        self.queue_card.configure(bg=PALETTE["glass"])
        self.queue_card.grid(row=2, column=0, sticky="nsew")
        self.queue_card.columnconfigure(0, weight=1)
        self.queue_card.rowconfigure(2, weight=1)

        header = tk.Frame(self.queue_card, bg=PALETTE["glass"], padx=20, pady=16)
        header.grid(row=0, column=0, sticky="ew")
        header.columnconfigure(0, weight=1)
        head_left = tk.Frame(header, bg=PALETTE["glass"])
        head_left.grid(row=0, column=0, sticky="w")
        tk.Label(head_left, text="Compression Queue", bg=PALETTE["glass"], fg=PALETTE["text"], font=(DISPLAY_FAMILY, 18, "bold")).grid(row=0, column=0, sticky="w")
        tk.Label(head_left, text="Add files to see thumbnails, savings estimates, and live progress.", bg=PALETTE["glass"], fg=PALETTE["muted"], font=(FONT_FAMILY, 11)).grid(row=1, column=0, sticky="w", pady=(3, 0))
        head_right = tk.Frame(header, bg=PALETTE["glass"])
        head_right.grid(row=0, column=1, sticky="e")
        tk.Label(head_right, textvariable=self.queue_count_var, bg=PALETTE["accent"], fg="white", font=(FONT_FAMILY, 11, "bold"), padx=11, pady=6).grid(row=0, column=0, padx=(0, 8))
        self._make_button(head_right, "Upload", self._pick_files, kind="secondary", padx=12, pady=7).grid(row=0, column=1)

        qmetrics = tk.Frame(self.queue_card, bg=PALETTE["glass"], padx=20, pady=10)
        qmetrics.grid(row=1, column=0, sticky="ew")
        for i, var in enumerate((self.queue_total_var, self.queue_compressed_var, self.queue_saved_var)):
            tk.Label(qmetrics, textvariable=var, bg=PALETTE["glass_soft"], fg=PALETTE["muted"], font=(FONT_FAMILY, 11, "bold"), padx=10, pady=6, highlightthickness=1, highlightbackground=PALETTE["line"]).grid(row=0, column=i, padx=(0 if i == 0 else 6, 0), sticky="w")

        holder = tk.Frame(self.queue_card, bg=PALETTE["glass_soft"])
        holder.grid(row=2, column=0, sticky="nsew")
        holder.columnconfigure(0, weight=1)
        holder.rowconfigure(0, weight=1)

        self.queue_canvas = tk.Canvas(holder, bg=PALETTE["glass_soft"], borderwidth=0, highlightthickness=0)
        self.queue_canvas.grid(row=0, column=0, sticky="nsew")
        scrollbar = tk.Scrollbar(holder, orient="vertical", command=self.queue_canvas.yview)
        scrollbar.grid(row=0, column=1, sticky="ns")
        self.queue_canvas.configure(yscrollcommand=scrollbar.set)
        self.queue_frame = tk.Frame(self.queue_canvas, bg=PALETTE["glass_soft"], padx=10, pady=10)
        self.queue_window = self.queue_canvas.create_window((0, 0), window=self.queue_frame, anchor="nw")
        self.queue_frame.bind("<Configure>", self._update_queue_scroll_region)
        self.queue_canvas.bind("<Configure>", self._fit_queue_width)

        list_actions = tk.Frame(self.queue_card, bg=PALETTE["glass"], padx=20, pady=12)
        list_actions.grid(row=3, column=0, sticky="w")
        self._make_button(list_actions, "Remove Selected", self._remove_selected, kind="glass", padx=12, pady=7).grid(row=0, column=0, padx=(0, 8))
        self._make_button(list_actions, "Clear", self._clear_files, kind="danger", padx=12, pady=7).grid(row=0, column=1)

    def _build_settings_card(self, parent: tk.Frame) -> None:
        card = self._make_glass_panel(parent, padx=18, pady=18)
        card.grid(row=0, column=0, sticky="ew", pady=(0, 18))
        card.columnconfigure(0, weight=1)

        head = tk.Frame(card, bg=PALETTE["glass"])
        head.grid(row=0, column=0, sticky="ew")
        tk.Label(head, text="Creator Presets", bg=PALETTE["glass"], fg=PALETTE["text"], font=(DISPLAY_FAMILY, 18, "bold")).grid(row=0, column=0, sticky="w")
        tk.Label(head, text="Choose the export intent. Advanced controls stay available below.", bg=PALETTE["glass"], fg=PALETTE["muted"], font=(FONT_FAMILY, 11)).grid(row=1, column=0, sticky="w", pady=(3, 12))

        self.preset_grid = tk.Frame(card, bg=PALETTE["glass"])
        self.preset_grid.grid(row=1, column=0, sticky="ew", pady=(0, 12))
        for i in range(2):
            self.preset_grid.columnconfigure(i, weight=1)
        for index, (label, target, desc, icon) in enumerate(PRESETS):
            self.preset_cards[label] = self._make_preset_card(self.preset_grid, label, target, desc, icon)
            self.preset_cards[label].grid(row=index // 2, column=index % 2, sticky="ew", padx=(0 if index % 2 == 0 else 5, 5 if index % 2 == 0 else 0), pady=(0, 8))
        custom_card = self._make_preset_card(self.preset_grid, "Custom", "", "Set your own target", "⋯")
        custom_card.grid(row=len(PRESETS) // 2, column=0, columnspan=2, sticky="ew", pady=(0, 8))
        self.preset_cards["Custom"] = custom_card

        self.custom_size_row = tk.Frame(card, bg=PALETTE["glass"])
        self.custom_size_row.grid(row=2, column=0, sticky="ew", pady=(0, 12))
        self.custom_size_row.columnconfigure(0, weight=1)
        self.custom_size_entry = self._make_entry(self.custom_size_row, self.custom_size_var)
        self.custom_size_entry.grid(row=0, column=0, sticky="ew", padx=(0, 8))
        self.custom_unit_box = ttk.Combobox(self.custom_size_row, textvariable=self.custom_unit_var, values=("b", "kb", "mb"), state="readonly", style="App.TCombobox", width=6)
        self.custom_unit_box.grid(row=0, column=1)
        self.custom_unit_box.bind("<<ComboboxSelected>>", lambda _e: self._apply_custom_size())
        self.custom_size_entry.bind("<KeyRelease>", lambda _e: self._apply_custom_size())
        self.custom_size_row.grid_remove()

        settings = tk.Frame(card, bg=PALETTE["glass"])
        settings.grid(row=3, column=0, sticky="ew")
        settings.columnconfigure(1, weight=1)

        self._add_field_label(settings, 0, "Output Format")
        self.format_box = ttk.Combobox(settings, textvariable=self.format_var, values=("auto", "keep", "jpeg", "png", "webp", "best_quality"), state="readonly", style="App.TCombobox")
        self.format_box.grid(row=0, column=1, sticky="ew", pady=4)

        self._add_field_label(settings, 1, "Min Side")
        self.min_side_box = ttk.Combobox(settings, textvariable=self.min_side_var, values=("160", "320", "480", "640", "800"), state="readonly", style="App.TCombobox")
        self.min_side_box.grid(row=1, column=1, sticky="ew", pady=4)

        self._add_field_label(settings, 2, "Quality Range")
        range_row = tk.Frame(settings, bg=PALETTE["glass"])
        range_row.grid(row=2, column=1, sticky="ew", pady=4)
        range_row.columnconfigure(0, weight=1)
        range_row.columnconfigure(3, weight=1)
        self.min_quality_scale = tk.Scale(range_row, from_=1, to=100, orient="horizontal", variable=self.min_quality_var, bg=PALETTE["glass"], fg=PALETTE["muted"], troughcolor="#DDE7F3", highlightthickness=0, activebackground=PALETTE["accent"], command=lambda _v: self._on_min_quality_change(), width=10)
        self.min_quality_scale.grid(row=0, column=0, sticky="ew", padx=(0, 8))
        self.min_quality_label = tk.Label(range_row, text=str(self.min_quality_var.get()), bg=PALETTE["glass"], fg=PALETTE["muted"], font=(FONT_FAMILY, 11, "bold"), width=3)
        self.min_quality_label.grid(row=0, column=1, padx=(0, 6))
        tk.Label(range_row, text="-", bg=PALETTE["glass"], fg=PALETTE["muted"], font=(FONT_FAMILY, 11, "bold")).grid(row=0, column=2, padx=(0, 6))
        self.max_quality_scale = tk.Scale(range_row, from_=1, to=100, orient="horizontal", variable=self.max_quality_var, bg=PALETTE["glass"], fg=PALETTE["muted"], troughcolor="#DDE7F3", highlightthickness=0, activebackground=PALETTE["accent"], command=lambda _v: self._on_max_quality_change(), width=10)
        self.max_quality_scale.grid(row=0, column=3, sticky="ew", padx=(6, 8))
        self.max_quality_label = tk.Label(range_row, text=str(self.max_quality_var.get()), bg=PALETTE["glass"], fg=PALETTE["muted"], font=(FONT_FAMILY, 11, "bold"), width=3)
        self.max_quality_label.grid(row=0, column=4)

        self._add_field_label(settings, 3, "Naming")
        self.name_mode_box = ttk.Combobox(settings, textvariable=self.name_mode_var, values=("suffix", "same-name", "overwrite"), state="readonly", style="App.TCombobox")
        self.name_mode_box.grid(row=3, column=1, sticky="ew", pady=4)
        self.name_mode_box.bind("<<ComboboxSelected>>", lambda _event: self._update_save_mode_ui())

        self._add_field_label(settings, 4, "Suffix")
        self.suffix_entry = self._make_entry(settings, self.suffix_var)
        self.suffix_entry.grid(row=4, column=1, sticky="ew", pady=4)

        self._add_field_label(settings, 5, "Output folder")
        folder_row = tk.Frame(settings, bg=PALETTE["glass"])
        folder_row.grid(row=5, column=1, sticky="ew", pady=4)
        folder_row.columnconfigure(0, weight=1)
        self.output_dir_entry = self._make_entry(folder_row, self.output_dir_var)
        self.output_dir_entry.grid(row=0, column=0, sticky="ew", padx=(0, 8))
        self.browse_button = self._make_button(folder_row, "Choose", self._choose_output_folder, kind="glass", padx=10, pady=8)
        self.browse_button.grid(row=0, column=1, padx=(0, 8))
        self.clear_output_button = self._make_button(folder_row, "Clear", lambda: self.output_dir_var.set(""), kind="glass", padx=10, pady=8)
        self.clear_output_button.grid(row=0, column=2)

        meta_row = tk.Frame(card, bg=PALETTE["glass"])
        meta_row.grid(row=6, column=0, sticky="w", pady=(10, 0))
        self.keep_meta_check = tk.Checkbutton(meta_row, text="Keep metadata", variable=self.keep_metadata_var, bg=PALETTE["glass"], fg=PALETTE["text"], activebackground=PALETTE["glass"], activeforeground=PALETTE["text"], selectcolor=PALETTE["glass"], font=(FONT_FAMILY, 12), highlightthickness=0, bd=0)
        self.keep_meta_check.grid(row=0, column=0, sticky="w")

    def _make_preset_card(self, parent: tk.Frame, name: str, target: str, desc: str, icon: str) -> tk.Frame:
        card = tk.Frame(parent, bg=PALETTE["glass_soft"], padx=10, pady=9, highlightthickness=1, highlightbackground=PALETTE["line"], cursor="hand2")
        card.columnconfigure(1, weight=1)
        quality = PRESET_QUALITY.get(name, "Manual")
        savings = PRESET_SAVINGS.get(name, "Varies")
        icon_lbl = tk.Label(card, text=icon, bg=PALETTE["glass_soft"], fg=PALETTE["accent"], font=(DISPLAY_FAMILY, 16, "bold"))
        icon_lbl.grid(row=0, column=0, rowspan=2, padx=(0, 8))
        tk.Label(card, text=name, bg=PALETTE["glass_soft"], fg=PALETTE["text"], font=(FONT_FAMILY, 12, "bold")).grid(row=0, column=1, sticky="w")
        tk.Label(card, text=desc, bg=PALETTE["glass_soft"], fg=PALETTE["muted"], font=(FONT_FAMILY, 10)).grid(row=1, column=1, sticky="w")
        tk.Label(card, text=f"{quality} · {savings}" if target else savings, bg=PALETTE["glass_soft"], fg=PALETTE["accent_press"], font=(FONT_FAMILY, 10, "bold")).grid(row=2, column=0, columnspan=2, sticky="w", pady=(3, 0))
        card.bind("<Button-1>", lambda _event, n=name, t=target: self._apply_preset(n, t))
        for child in card.winfo_children():
            child.bind("<Button-1>", lambda _event, n=name, t=target: self._apply_preset(n, t))
        return card

    def _highlight_active_preset(self) -> None:
        for name, card in self.preset_cards.items():
            active = name == self.active_preset_name
            card.configure(bg="#EAF3FF" if active else PALETTE["glass_soft"], highlightbackground=PALETTE["accent"] if active else PALETTE["line"])
            for child in card.winfo_children():
                if isinstance(child, tk.Label):
                    child.configure(bg="#EAF3FF" if active else PALETTE["glass_soft"])

    def _build_preview_panel(self, parent: tk.Frame) -> None:
        preview = self._make_glass_panel(parent, padx=18, pady=18)
        preview.grid(row=1, column=0, sticky="ew", pady=(0, 18))
        preview.columnconfigure(0, weight=1)

        head = tk.Frame(preview, bg=PALETTE["glass"])
        head.grid(row=0, column=0, sticky="ew")
        head.columnconfigure(0, weight=1)
        tk.Label(head, text="Before / After Preview", bg=PALETTE["glass"], fg=PALETTE["text"], font=(DISPLAY_FAMILY, 18, "bold")).grid(row=0, column=0, sticky="w")
        tk.Label(head, textvariable=self.preview_hint_var, bg=PALETTE["glass"], fg=PALETTE["muted"], font=(FONT_FAMILY, 11)).grid(row=1, column=0, sticky="w", pady=(3, 10))
        self._make_button(head, "Zoom", self._open_preview_source, kind="glass", padx=12, pady=7).grid(row=0, column=1, sticky="e")

        if self.preview_meta_var.get():
            tk.Label(preview, textvariable=self.preview_meta_var, bg=PALETTE["glass"], fg=PALETTE["muted"], font=(FONT_FAMILY, 11), anchor="w").grid(row=1, column=0, sticky="ew", pady=(0, 8))

        self.preview_canvas = tk.Canvas(preview, height=288, bg="#EAF0F8", highlightthickness=1, highlightbackground=PALETTE["line"], borderwidth=0)
        self.preview_canvas.grid(row=2, column=0, sticky="ew")
        self.preview_canvas.create_text(180, 144, text="Preview will appear here", fill=PALETTE["faint"], font=(FONT_FAMILY, 13, "bold"), tags=("empty",))
        self.preview_canvas.bind("<Configure>", lambda _event: self._redraw_preview())

        tools = tk.Frame(preview, bg=PALETTE["glass"])
        tools.grid(row=3, column=0, sticky="ew", pady=(12, 0))
        tools.columnconfigure(0, weight=1)
        tk.Label(tools, text="Reveal", bg=PALETTE["glass"], fg=PALETTE["muted"], font=(FONT_FAMILY, 11, "bold")).grid(row=0, column=0, sticky="w")
        self.compare_var = tk.DoubleVar(value=56)
        self.compare_label = tk.Label(tools, text="56%", bg=PALETTE["glass"], fg=PALETTE["muted"], font=(FONT_FAMILY, 11, "bold"))
        self.compare_label.grid(row=0, column=2, padx=(8, 0))
        tk.Scale(tools, from_=0, to=100, orient="horizontal", variable=self.compare_var, bg=PALETTE["glass"], fg=PALETTE["muted"], troughcolor="#DDE7F3", highlightthickness=0, activebackground=PALETTE["accent"], command=lambda _value: self._on_compare_change(), width=10).grid(row=0, column=1, sticky="ew", padx=(8, 8))

    def _build_progress_card(self, parent: tk.Frame) -> None:
        self.progress_card = self._make_glass_panel(parent, padx=18, pady=16)
        self.progress_card.configure(highlightbackground="#BFD0E4")
        self.progress_card.grid(row=2, column=0, sticky="ew", pady=(0, 18))
        self.progress_card.columnconfigure(0, weight=1)

        head = tk.Frame(self.progress_card, bg=PALETTE["glass"])
        head.grid(row=0, column=0, sticky="ew")
        head.columnconfigure(0, weight=1)
        tk.Label(head, text="Progress", bg=PALETTE["glass"], fg=PALETTE["text"], font=(DISPLAY_FAMILY, 18, "bold")).grid(row=0, column=0, sticky="w")
        tk.Label(head, textvariable=self.progress_caption_var, bg=PALETTE["glass"], fg=PALETTE["muted"], font=(FONT_FAMILY, 11)).grid(row=1, column=0, sticky="w", pady=(3, 10))

        self.progress = ttk.Progressbar(self.progress_card, mode="determinate", maximum=100, style="App.Horizontal.TProgressbar")
        self.progress.grid(row=1, column=0, sticky="ew", pady=(0, 10))

        stats = tk.Frame(self.progress_card, bg=PALETTE["glass"])
        stats.grid(row=2, column=0, sticky="ew")
        stat_items = ((self.batch_count_var, PALETTE["text"]), (self.batch_rate_var, PALETTE["muted"]), (self.batch_eta_var, PALETTE["muted"]))
        for i, (var, color) in enumerate(stat_items):
            tk.Label(stats, textvariable=var, bg=PALETTE["glass"], fg=color, font=(FONT_FAMILY, 11, "bold")).grid(row=0, column=i, padx=(0 if i == 0 else 14, 0), sticky="w")
        tk.Label(stats, textvariable=self.batch_savings_var, bg=PALETTE["glass"], fg=PALETTE["success"], font=(FONT_FAMILY, 11, "bold")).grid(row=0, column=3, sticky="e")

    def _build_controls(self, parent: tk.Frame) -> None:
        bar = tk.Frame(parent, bg=PALETTE["window"])
        bar.grid(row=3, column=0, sticky="ew", pady=(0, 18))
        bar.columnconfigure(0, weight=1)
        bar.columnconfigure(1, weight=1)
        bar.columnconfigure(2, weight=1)
        bar.columnconfigure(3, weight=1)
        self.compress_button = self._make_button(bar, "\u25B6  Compress Queue", self._start_compression, kind="primary", padx=14, pady=11)
        self.compress_button.grid(row=0, column=0, sticky="ew", padx=(0, 8))
        self.stop_button = self._make_button(bar, "\u25A0  Stop", self._stop_compression, kind="danger", padx=14, pady=11)
        self.stop_button.grid(row=0, column=1, sticky="ew", padx=(0, 8))
        self.stop_button.config(state="disabled")
        self.clear_files_button = self._make_button(bar, "Clear all", self._clear_files, kind="glass", padx=14, pady=11)
        self.clear_files_button.grid(row=0, column=2, sticky="ew", padx=(0, 8))
        self.download_all_button = self._make_button(bar, "Download all", self._download_all, kind="success", padx=14, pady=11)
        self.download_all_button.grid(row=0, column=3, sticky="ew")
        self.download_all_button.config(state="disabled")

    def _build_activity(self, parent: tk.Frame) -> None:
        self.activity_frame = self._make_glass_panel(parent, padx=18, pady=16)
        self.activity_frame.grid(row=4, column=0, sticky="ew")
        self.activity_frame.columnconfigure(0, weight=1)

        head = tk.Frame(self.activity_frame, bg=PALETTE["glass"])
        head.grid(row=0, column=0, sticky="ew")
        head.columnconfigure(0, weight=1)
        head_left = tk.Frame(head, bg=PALETTE["glass"])
        head_left.grid(row=0, column=0, sticky="w")
        tk.Label(head_left, text="Processing Timeline", bg=PALETTE["glass"], fg=PALETTE["text"], font=(DISPLAY_FAMILY, 18, "bold")).grid(row=0, column=0, sticky="w")
        tk.Label(head_left, text="Clean run notes with advanced detail when you need it.", bg=PALETTE["glass"], fg=PALETTE["muted"], font=(FONT_FAMILY, 11)).grid(row=1, column=0, sticky="w", pady=(3, 0))
        self._make_button(head, "Clear", self._clear_log, kind="glass", padx=12, pady=7).grid(row=0, column=1, sticky="e")

        self.log_text = tk.Text(self.activity_frame, height=9, wrap="word", state="disabled", bg=PALETTE["glass_soft"], fg=PALETTE["text"], relief="flat", borderwidth=0, highlightthickness=1, highlightbackground=PALETTE["line"], padx=12, pady=10, font=(MONO_FAMILY, 11))
        self.log_text.grid(row=1, column=0, sticky="ew", pady=(10, 0))

    def _add_field_label(self, parent: tk.Widget, row: int, text: str) -> None:
        tk.Label(parent, text=text, bg=PALETTE["glass"], fg=PALETTE["muted"], font=(FONT_FAMILY, 11, "bold")).grid(row=row, column=0, sticky="w", padx=(0, 12), pady=4)

    def _make_entry(self, parent: tk.Widget, textvariable: tk.StringVar) -> tk.Entry:
        return tk.Entry(parent, textvariable=textvariable, bg=PALETTE["glass_soft"], fg=PALETTE["text"], insertbackground=PALETTE["text"], relief="flat", borderwidth=0, highlightthickness=1, highlightbackground=PALETTE["line"], highlightcolor=PALETTE["accent"], font=(FONT_FAMILY, 12))

    def _make_button(self, parent: tk.Widget, text: str, command, kind: str = "secondary", padx: int = 16, pady: int = 10) -> tk.Button:
        styles = {
            "primary": {"bg": PALETTE["accent"], "fg": "white", "activebackground": PALETTE["accent_press"], "activeforeground": "white"},
            "secondary": {"bg": "#E9F0FA", "fg": PALETTE["text"], "activebackground": "#DCE8F7", "activeforeground": PALETTE["text"]},
            "glass": {"bg": "#F7F9FD", "fg": PALETTE["text"], "activebackground": "#EAF1FA", "activeforeground": PALETTE["text"]},
            "danger": {"bg": "#FFF0F1", "fg": PALETTE["danger"], "activebackground": "#FADDE1", "activeforeground": PALETTE["danger"]},
            "success": {"bg": "#E6F6EF", "fg": PALETTE["success"], "activebackground": "#D4EFE3", "activeforeground": PALETTE["success"]},
        }
        button = tk.Button(parent, text=text, command=command, relief="flat", borderwidth=0, highlightthickness=1, highlightbackground="#FFFFFF", cursor="hand2", disabledforeground="#98A2B3", font=(FONT_FAMILY, 11, "bold"), padx=padx, pady=pady, **styles[kind])
        button.bind("<Return>", lambda _event: command())
        button.bind("<space>", lambda _event: command())
        button.bind("<Enter>", lambda _event: button.configure(highlightbackground=PALETTE["line_strong"]))
        button.bind("<Leave>", lambda _event: button.configure(highlightbackground="#FFFFFF"))
        return button

    def _apply_preset(self, name: str, target: str) -> None:
        self.active_preset_name = name
        if name == "Custom":
            self.custom_size_row.grid()
            self._apply_custom_size()
            self.smart_hint_var.set("Custom target set. Adjust the value and unit above.")
        else:
            self.custom_size_row.grid_remove()
            self.max_size_var.set(target)
            self.smart_hint_var.set(f"{name} preset: target {target} for {self._saving_label(name)} savings.")
        self._highlight_active_preset()
        self._refresh_file_list()

    def _saving_label(self, name: str) -> str:
        return PRESET_SAVINGS.get(name, "varied")

    def _apply_custom_size(self) -> None:
        value = self.custom_size_var.get().strip()
        if value:
            self.max_size_var.set(f"{value}{self.custom_unit_var.get()}")

    def _on_min_quality_change(self) -> None:
        value = self.min_quality_var.get()
        if value > self.max_quality_var.get():
            self.max_quality_var.set(value)
            if hasattr(self, "max_quality_label"):
                self.max_quality_label.configure(text=str(value))
        if hasattr(self, "min_quality_label"):
            self.min_quality_label.configure(text=str(value))

    def _on_max_quality_change(self) -> None:
        value = self.max_quality_var.get()
        if value < self.min_quality_var.get():
            self.min_quality_var.set(value)
            if hasattr(self, "min_quality_label"):
                self.min_quality_label.configure(text=str(value))
        if hasattr(self, "max_quality_label"):
            self.max_quality_label.configure(text=str(value))

    def _on_compare_change(self) -> None:
        self.compare_label.configure(text=f"{int(self.compare_var.get())}%")
        self._draw_compare_overlay()

    def _new_session(self) -> None:
        self._clear_files()
        self.compressed_outputs.clear()
        self.last_output_folder = None
        self.session_badge_var.set("New session")
        self.download_all_button.config(state="disabled")
        self.status_var.set("Started a fresh session.")
        self._append_log("New session started.")

    def _clear_log(self) -> None:
        self.log_text.configure(state="normal")
        self.log_text.delete("1.0", tk.END)
        self.log_text.configure(state="disabled")

    def _stop_compression(self) -> None:
        if self.is_running:
            self._stop_requested = True
            self.status_var.set("Stopping after current file...")
            self._append_log("Stop requested.")

    def _download_all(self) -> None:
        outputs = [p for p in self.compressed_outputs if p.exists()]
        if not outputs:
            if self.last_output_folder and self.last_output_folder.exists():
                try:
                    subprocess.Popen(["open", str(self.last_output_folder)])
                except Exception:
                    pass
            return
        try:
            zip_path = Path(tempfile.gettempdir()) / f"luma-compressed-{datetime.now().strftime('%Y%m%d_%H%M%S')}.zip"
            with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
                for path in outputs:
                    zf.write(str(path), arcname=path.name)
            subprocess.Popen(["open", "-R", str(zip_path)])
            self._append_log(f"Packaged {len(outputs)} file(s) into {zip_path.name}")
        except Exception as error:
            self._append_log(f"[ERROR] Could not package outputs: {error}")

    def _set_drop_active(self, active: bool) -> None:
        self.drop.configure(bg="#E9F5FF" if active else PALETTE["glass_alt"], highlightbackground=PALETTE["accent"] if active else PALETTE["line_strong"])
        self.drop_icon_var.set("◆" if active else "◇")
        for child in self.drop.winfo_children():
            if isinstance(child, tk.Label) or isinstance(child, tk.Frame):
                child.configure(bg="#E9F5FF" if active else PALETTE["glass_alt"])

    def _start_ambient_motion(self) -> None:
        self._ambient_tick = 0
        self._animate_drop_icon()

    def _animate_drop_icon(self) -> None:
        if not self.is_running:
            self._ambient_tick += 1
            self.drop_icon_var.set("◇" if self._ambient_tick % 2 else "◈")
        self.root.after(1400, self._animate_drop_icon)

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
        self.queue_rows.clear()
        self._refresh_file_list()
        self.status_var.set("Queue cleared.")
        self.compressed_outputs = []
        self.last_output_folder = None
        self.download_all_button.config(state="disabled")
        self.session_badge_var.set("Queue cleared")
        self._clear_preview()

    def _remove_selected(self) -> None:
        selected = getattr(self, "selected_path", None)
        if selected and selected in self.selected_inputs:
            self.selected_inputs.remove(selected)
            self.queue_rows.pop(selected, None)
            self.selected_path = None
            self._refresh_file_list()
            self.status_var.set("Removed selected item.")

    def _maybe_reveal_selected_file(self, event: tk.Event) -> None:
        if getattr(self, "selected_path", None):
            self._reveal_selected_file()

    def _reveal_selected_file(self) -> None:
        path = getattr(self, "selected_path", None)
        if path is None:
            return
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
        self._set_drop_active(False)
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
        self._update_smart_hint()

    def _refresh_file_list(self) -> None:
        for child in self.queue_frame.winfo_children():
            child.destroy()
        self.queue_rows.clear()
        if not self.selected_inputs:
            empty = tk.Label(self.queue_frame, text="Your queue is empty. Drop images to see previews, estimated savings, and per-file progress.", bg=PALETTE["glass_soft"], fg=PALETTE["muted"], font=(FONT_FAMILY, 13), pady=34)
            empty.grid(row=0, column=0, sticky="ew")
        for index, path in enumerate(self.selected_inputs):
            self._create_queue_row(index, path)
        self._update_queue_metrics()
        self._update_queue_scroll_region()

    def _create_queue_row(self, index: int, path: Path) -> None:
        frame = tk.Frame(self.queue_frame, bg=PALETTE["glass"], padx=12, pady=10, highlightthickness=1, highlightbackground=PALETTE["line"])
        frame.grid(row=index, column=0, sticky="ew", pady=(0, 8))
        frame.columnconfigure(1, weight=1)
        name_var = tk.StringVar(value=path.name)
        size = path.stat().st_size if path.exists() else 0
        estimated = self._estimate_output_bytes(size)
        meta_var = tk.StringVar(value=f"{human_size(size)} → {human_size(estimated)} estimated  •  {path.parent}")
        state_var = tk.StringVar(value="Queued")
        saved_var = tk.StringVar(value=f"{self._saving_percent(size, estimated)}% saved")

        thumb = tk.Label(frame, text="IMG", width=7, height=4, bg="#E8EEF7", fg=PALETTE["faint"], font=(FONT_FAMILY, 10, "bold"))
        thumb.grid(row=0, column=0, rowspan=3, sticky="nsw", padx=(0, 12))
        thumbnail = self._load_thumbnail(path, (58, 58))
        if thumbnail is not None:
            thumb.configure(image=thumbnail, text="")
        tk.Label(frame, textvariable=name_var, bg=PALETTE["glass"], fg=PALETTE["text"], font=(FONT_FAMILY, 13, "bold")).grid(row=0, column=1, sticky="w")
        tk.Label(frame, textvariable=meta_var, bg=PALETTE["glass"], fg=PALETTE["muted"], font=(FONT_FAMILY, 11), wraplength=560, justify="left").grid(row=1, column=1, sticky="w", pady=(3, 5))
        progress = ttk.Progressbar(frame, mode="determinate", maximum=100, style="Mini.Horizontal.TProgressbar")
        progress.grid(row=2, column=1, sticky="ew")
        tk.Label(frame, textvariable=saved_var, bg=PALETTE["glass"], fg=PALETTE["success"], font=(FONT_FAMILY, 12, "bold")).grid(row=0, column=2, sticky="e", padx=(12, 0))
        tk.Label(frame, textvariable=state_var, bg=PALETTE["glass"], fg=PALETTE["accent_press"], font=(FONT_FAMILY, 11, "bold")).grid(row=1, column=2, sticky="e", padx=(12, 0))
        row = QueueRow(path=path, frame=frame, thumb_label=thumb, name_var=name_var, meta_var=meta_var, state_var=state_var, saved_var=saved_var, progress=progress, thumbnail=thumbnail)
        self.queue_rows[path] = row
        frame.bind("<Button-1>", lambda _event, chosen=path: self._select_row(chosen))
        for child in frame.winfo_children():
            child.bind("<Button-1>", lambda _event, chosen=path: self._select_row(chosen))

    def _select_row(self, path: Path) -> None:
        self.selected_path = path
        for row_path, row in self.queue_rows.items():
            row.frame.configure(highlightbackground=PALETTE["accent"] if row_path == path else PALETTE["line"])
        self._show_preview(path)

    def _load_thumbnail(self, path: Path, size: tuple[int, int]) -> object | None:
        if not PIL_UI_AVAILABLE:
            return None
        try:
            with Image.open(path) as image:
                image.thumbnail(size)
                return ImageTk.PhotoImage(image.copy())
        except Exception:
            return None

    def _show_preview(self, path: Path) -> None:
        if path.exists():
            self.preview_hint_var.set(f"{path.name}  ·  {human_size(path.stat().st_size)} original → {human_size(self._estimate_output_bytes(path.stat().st_size))} estimated")
        else:
            self.preview_hint_var.set("Missing source file.")
        self.preview_canvas.delete("all")
        self.preview_image_ref = None
        if not PIL_UI_AVAILABLE:
            self.preview_canvas.create_text(180, 144, text="Preview needs Pillow", fill=PALETTE["faint"], font=(FONT_FAMILY, 13, "bold"), tags=("empty",))
            return
        try:
            with Image.open(path) as image:
                image.thumbnail((360, 260))
                self.preview_image_ref = ImageTk.PhotoImage(image.copy())
            self._redraw_preview()
        except Exception:
            self._clear_preview()

    def _draw_compare_overlay(self) -> None:
        self.preview_canvas.delete("compare")
        width = max(1, self.preview_canvas.winfo_width())
        height = max(1, self.preview_canvas.winfo_height())
        x = int(width * (self.compare_var.get() / 100))
        self.preview_canvas.create_rectangle(0, 0, x, height, fill="", outline=PALETTE["accent"], width=2, tags=("compare",))
        self.preview_canvas.create_line(x, 12, x, height - 12, fill=PALETTE["accent"], width=2, tags=("compare",))
        self.preview_canvas.create_text(max(54, x - 48), 22, text="Original", fill=PALETTE["accent_press"], font=(FONT_FAMILY, 10, "bold"), tags=("compare",))
        self.preview_canvas.create_text(min(width - 60, x + 58), 22, text="Compressed", fill=PALETTE["success"], font=(FONT_FAMILY, 10, "bold"), tags=("compare",))

    def _redraw_preview(self) -> None:
        self.preview_canvas.delete("all")
        self.preview_canvas.delete("compare")
        width = max(1, self.preview_canvas.winfo_width())
        height = max(1, self.preview_canvas.winfo_height())
        if self.preview_image_ref is None:
            self.preview_canvas.create_text(width // 2, height // 2, text="Preview will appear here", fill=PALETTE["faint"], font=(FONT_FAMILY, 13, "bold"))
            return
        self.preview_canvas.create_image(width // 2, height // 2, image=self.preview_image_ref)
        self._draw_compare_overlay()

    def _clear_preview(self) -> None:
        self.preview_hint_var.set("Select a queued image to inspect compression detail.")
        self.preview_image_ref = None
        self.preview_canvas.delete("all")
        width = max(1, self.preview_canvas.winfo_width())
        height = max(1, self.preview_canvas.winfo_height())
        self.preview_canvas.create_text(width // 2, height // 2, text="Preview will appear here", fill=PALETTE["faint"], font=(FONT_FAMILY, 13, "bold"))

    def _open_preview_source(self) -> None:
        path = getattr(self, "selected_path", None)
        if path:
            subprocess.Popen(["open", str(path)])

    def _estimate_output_bytes(self, source_size: int) -> int:
        try:
            target = parse_size_to_bytes(self.max_size_var.get())
        except ValueError:
            target = 500 * 1024
        return max(1, min(source_size, target))

    def _saving_percent(self, source_size: int, output_size: int) -> int:
        if source_size <= 0:
            return 0
        return max(0, min(99, round((1 - output_size / source_size) * 100)))

    def _update_queue_metrics(self) -> None:
        total = sum(path.stat().st_size for path in self.selected_inputs if path.exists())
        compressed = sum(row.output_size if row.output_size is not None else self._estimate_output_bytes(path.stat().st_size if path.exists() else 0) for path, row in self.queue_rows.items())
        saved = max(0, total - compressed)
        self.queue_total_var.set(f"{human_size(total)} queued")
        self.queue_compressed_var.set(f"{human_size(compressed)} estimated")
        self.queue_saved_var.set(f"{human_size(saved)} saved")
        self.queue_count_var.set(f"{len(self.selected_inputs)} file{'s' if len(self.selected_inputs) != 1 else ''}")

    def _update_smart_hint(self) -> None:
        suffixes = {path.suffix.lower() for path in self.selected_inputs}
        if ".png" in suffixes:
            self.smart_hint_var.set("Smart hint: PNG artwork detected. AI Artwork or Portfolio Mode will preserve detail.")
        elif len(self.selected_inputs) >= 8:
            self.smart_hint_var.set("Smart hint: Batch export detected. Framer/Webflow is tuned for fast web delivery.")
        elif suffixes:
            self.smart_hint_var.set("Smart hint: Fast Export delivers tiny shareable files with great savings.")
        else:
            self.smart_hint_var.set("Smart preset: Fast Export for tiny shareable files.")

    def _update_queue_scroll_region(self, _event: tk.Event | None = None) -> None:
        self.queue_canvas.configure(scrollregion=self.queue_canvas.bbox("all"))

    def _fit_queue_width(self, event: tk.Event) -> None:
        self.queue_canvas.itemconfigure(self.queue_window, width=event.width)

    def _handle_resize(self, _event: tk.Event) -> None:
        self._update_side_scroll_region()
        if self.preview_image_ref is not None:
            self._redraw_preview()

    def _set_entry_enabled(self, entry: tk.Entry, enabled: bool) -> None:
        entry.configure(state="normal" if enabled else "disabled")
        entry.configure(disabledbackground="#EEF2F6", disabledforeground="#7D8796", bg=PALETTE["glass_soft"])

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
        self.stop_button.config(state="normal" if running else "disabled")
        if not running:
            self.progress["value"] = 100 if self.run_total_files and self.run_completed >= self.run_total_files else (self.run_completed / max(1, self.run_total_files)) * 100

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

        chosen_format = self.format_var.get().strip()
        compress_format = "webp" if chosen_format == "best_quality" else chosen_format
        self._active_format = chosen_format
        args = argparse.Namespace(max_size=self.max_size_var.get().strip(), format=compress_format, name_mode=self.name_mode_var.get().strip(), suffix=self.suffix_var.get(), min_quality=self.min_quality_var.get(), max_quality=self.max_quality_var.get(), min_side=int(self.min_side_var.get()), keep_metadata=bool(self.keep_metadata_var.get()), background="FFFFFF")
        files = collect_input_files(self.selected_inputs)
        if not files:
            messagebox.showerror("No supported files", "The current queue does not contain supported images.")
            return

        self.last_output_folder = None
        self.compressed_outputs = []
        self.download_all_button.config(state="disabled")
        self._stop_requested = False
        self._save_session()
        self._append_log("")
        self._append_log(f"Starting compression for {len(files)} file(s) with {self.active_preset_name} preset...")
        self.session_badge_var.set("Compressing")
        self.status_var.set("Compressing with creator preset...")
        self.progress_caption_var.set(f"Optimizing {len(files)} file(s).")
        self.run_started_at = time.time()
        self.run_total_files = len(files)
        self.run_completed = 0
        self.run_source_bytes = 0
        self.run_output_bytes = 0
        self.files_done_var.set(f"0 / {len(files)}")
        self.eta_var.set("Calculating")
        self.batch_count_var.set(f"0 / {len(files)} done")
        self.batch_rate_var.set("- files/s")
        self.batch_eta_var.set("ETA -")
        self.batch_savings_var.set("")
        self.processing_speed_var.set("Preparing queue")
        for row in self.queue_rows.values():
            row.state = "Queued"
            row.state_var.set("Queued")
            row.progress["value"] = 0
        self._set_running(True)
        threading.Thread(target=self._run_compression, args=(files, output_argument, args), daemon=True).start()

    def _run_compression(self, files: list[Path], output_argument: Path | None, args: argparse.Namespace) -> None:
        failures = 0
        written_paths: list[Path] = []
        stopped = False
        try:
            for index, file_path in enumerate(files, start=1):
                if self._stop_requested:
                    stopped = True
                    break
                self.root.after(0, self._mark_row_processing, file_path)
                try:
                    result = process_one_file(file_path, output_argument, args)
                    if result.output_path and getattr(self, "_active_format", "") == "best_quality" and result.output_path.suffix.lower() == ".webp":
                        png_path = result.output_path.with_suffix(".png")
                        try:
                            if png_path.exists():
                                png_path.unlink()
                            result.output_path.rename(png_path)
                            result.output_path = png_path
                        except Exception:
                            pass
                    if result.output_path:
                        written_paths.append(result.output_path)
                    for line in format_processing_result(result):
                        self.root.after(0, self._append_log, line)
                    if not result.met_target:
                        failures += 1
                    self.root.after(0, self._mark_row_complete, file_path, result.source_size, result.output_size, result.met_target, index, result.output_path)
                except Exception as error:
                    failures += 1
                    self.root.after(0, self._mark_row_error, file_path, str(error), index)
                    self.root.after(0, self._append_log, f"[ERROR] {file_path.name} | {error}")
        finally:
            if stopped:
                summary = f"Stopped. {index - 1} of {len(files)} file(s) processed."
            else:
                summary = f"Finished. {len(files) - failures} succeeded, {failures} had issues." if failures else f"Finished. {len(files)} file(s) processed successfully."
            folder_to_open = output_argument if (written_paths and output_argument is not None and output_argument.is_dir()) else (written_paths[0].parent if written_paths else None)
            self.root.after(0, self._finish_run, summary, folder_to_open, written_paths)

    def _mark_row_processing(self, path: Path) -> None:
        row = self.queue_rows.get(path)
        if row:
            row.state = "Processing"
            row.state_var.set("Processing")
            row.frame.configure(bg="#F2F8FF", highlightbackground=PALETTE["accent"])
            for child in row.frame.winfo_children():
                if isinstance(child, tk.Label):
                    child.configure(bg="#F2F8FF")
            row.progress["value"] = 42
        self.status_var.set(f"Optimizing {path.name}...")

    def _mark_row_complete(self, path: Path, source_size: int, output_size: int, met_target: bool, index: int, output_path: Path | None = None) -> None:
        row = self.queue_rows.get(path)
        self.run_completed = index
        self.run_source_bytes += source_size
        self.run_output_bytes += output_size
        if output_path and output_path.exists():
            self.compressed_outputs.append(output_path)
        if row:
            row.output_size = output_size
            row.state = "Complete" if met_target else "Best effort"
            row.state_var.set(row.state)
            row.saved_var.set(f"{self._saving_percent(source_size, output_size)}% saved")
            row.meta_var.set(f"{human_size(source_size)} → {human_size(output_size)}  •  {path.parent}")
            row.progress["value"] = 100
            row.frame.configure(bg="#F4FBF7", highlightbackground="#BDE5CF")
            for child in row.frame.winfo_children():
                if isinstance(child, tk.Label):
                    child.configure(bg="#F4FBF7")
        self._update_live_metrics()

    def _mark_row_error(self, path: Path, error: str, index: int) -> None:
        row = self.queue_rows.get(path)
        self.run_completed = index
        if row:
            row.state = "Needs attention"
            row.state_var.set("Needs attention")
            row.meta_var.set(error)
            row.progress["value"] = 100
            row.frame.configure(bg="#FFF6F7", highlightbackground="#F0B8C0")
            for child in row.frame.winfo_children():
                if isinstance(child, tk.Label):
                    child.configure(bg="#FFF6F7")
        self._update_live_metrics()

    def _update_live_metrics(self) -> None:
        elapsed = max(0.1, time.time() - self.run_started_at)
        saved = max(0, self.run_source_bytes - self.run_output_bytes)
        ratio = self._saving_percent(self.run_source_bytes, self.run_output_bytes) if self.run_source_bytes else 0
        per_file = elapsed / max(1, self.run_completed)
        remaining = max(0, self.run_total_files - self.run_completed)
        eta_seconds = int(per_file * remaining)
        speed = self.run_output_bytes / elapsed
        self.total_saved_var.set(human_size(saved))
        self.ratio_var.set(f"{ratio}%")
        self.files_done_var.set(f"{self.run_completed} / {self.run_total_files}")
        self.eta_var.set(f"{eta_seconds}s" if remaining else "Done")
        self.processing_speed_var.set(f"{human_size(int(speed))}/s output")
        self.batch_count_var.set(f"{self.run_completed} / {self.run_total_files} done")
        self.batch_rate_var.set(f"{round(self.run_completed / max(0.1, elapsed), 2)} files/s")
        self.batch_eta_var.set(f"ETA {eta_seconds}s" if remaining else "Done")
        self.batch_savings_var.set(f"{human_size(saved)} saved ({ratio}%)" if self.run_completed else "")
        self.progress["value"] = (self.run_completed / max(1, self.run_total_files)) * 100
        self._update_queue_metrics()

    def _finish_run(self, summary: str, folder_to_open: Path | None, written_paths: list[Path] | None = None) -> None:
        self.status_var.set(summary)
        self.progress_caption_var.set(summary)
        self._append_log(summary)
        self._set_running(False)
        self._update_live_metrics()
        if folder_to_open is not None:
            self.last_output_folder = folder_to_open
        if self.compressed_outputs:
            self.download_all_button.config(state="normal")
            self.session_badge_var.set("Ready to download")
        else:
            self.session_badge_var.set("Session ready")
        if folder_to_open is not None:
            self._append_log(f"Output folder: {folder_to_open}")
        self._notify_completion(summary)

    def _notify_completion(self, summary: str) -> None:
        try:
            subprocess.Popen(["osascript", "-e", f'display notification "{summary}" with title "LumaShrink"'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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
        self._update_smart_hint()

    def run(self) -> None:
        self.root.mainloop()


def main() -> None:
    app = CompressorApp()
    app.run()


if __name__ == "__main__":
    main()
