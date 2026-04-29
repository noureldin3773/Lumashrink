#!/usr/bin/env python3

from __future__ import annotations

import argparse
import subprocess
import threading
import tkinter as tk
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
    "bg": "#2B3038",
    "card": "#313741",
    "soft": "#243244",
    "soft_alt": "#39414D",
    "accent": "#65B8FF",
    "accent_dark": "#3F95F0",
    "text": "#F8FAFC",
    "muted": "#CBD5E1",
    "line": "#475062",
    "success": "#34D399",
    "warning": "#FBBF24",
    "danger": "#FCA5A5",
    "log_bg": "#141A23",
    "log_fg": "#D8F3FF",
    "hint_bg": "#4C3F16",
    "note_bg": "#1D2634",
}

FONT_FAMILY = "Helvetica Neue"


class CompressorApp:
    def __init__(self) -> None:
        self.root = TkinterDnD.Tk() if TKDND_AVAILABLE else tk.Tk()
        self.root.title("Image Compressor")
        self.root.geometry("1240x920")
        self.root.minsize(1080, 780)
        self.root.configure(bg=PALETTE["bg"])

        self.selected_inputs: list[Path] = []
        self.last_output_folder: Path | None = None
        self.max_size_var = tk.StringVar(value="150kb")
        self.format_var = tk.StringVar(value="auto")
        self.name_mode_var = tk.StringVar(value="suffix")
        self.suffix_var = tk.StringVar(value="-compressed")
        self.output_dir_var = tk.StringVar(value="")
        self.status_var = tk.StringVar(
            value="Everything runs locally on your Mac. Add files and press Compress Now."
        )
        self.save_mode_hint_var = tk.StringVar()
        self.queue_stats_var = tk.StringVar()
        self.target_card_var = tk.StringVar()
        self.mode_card_var = tk.StringVar()
        self.file_hint_var = tk.StringVar()
        self.is_running = False

        self.style = ttk.Style(self.root)
        self._configure_style()
        self._build_ui()
        self._bind_shortcuts()

        for var in (self.max_size_var, self.format_var, self.name_mode_var):
            var.trace_add("write", self._refresh_dashboard)

        self._update_save_mode_ui()
        self._refresh_file_list()
        self._append_log("Ready. Add files or folders to begin.")
        self._schedule_window_activation()

    def _configure_style(self) -> None:
        try:
            self.style.theme_use("clam")
        except tk.TclError:
            pass

        self.style.configure(
            "App.TCombobox",
            padding=6,
            foreground=PALETTE["text"],
            fieldbackground=PALETTE["card"],
            background=PALETTE["card"],
            bordercolor=PALETTE["line"],
            lightcolor=PALETTE["line"],
            darkcolor=PALETTE["line"],
            arrowcolor=PALETTE["text"],
        )
        self.style.map(
            "App.TCombobox",
            fieldbackground=[("readonly", PALETTE["card"])],
            background=[("readonly", PALETTE["card"])],
            foreground=[("readonly", PALETTE["text"])],
            selectbackground=[("readonly", PALETTE["card"])],
            selectforeground=[("readonly", PALETTE["text"])],
        )
        self.style.configure(
            "App.Horizontal.TProgressbar",
            thickness=10,
            background=PALETTE["accent"],
            troughcolor=PALETTE["soft"],
            bordercolor=PALETTE["soft"],
            lightcolor=PALETTE["accent"],
            darkcolor=PALETTE["accent"],
        )

    def _bind_shortcuts(self) -> None:
        self.root.bind("<Delete>", lambda _event: self._remove_selected())
        self.root.bind("<BackSpace>", lambda _event: self._remove_selected())
        self.root.bind("<Command-Return>", lambda _event: self._start_compression())
        self.root.bind("<Double-Button-1>", self._maybe_reveal_selected_file)

    def _build_ui(self) -> None:
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)

        shell = tk.Frame(self.root, bg=PALETTE["bg"], padx=22, pady=20)
        shell.grid(row=0, column=0, sticky="nsew")
        shell.columnconfigure(0, weight=1)
        shell.rowconfigure(3, weight=1)

        self._build_hero(shell)
        self._build_metrics(shell)

        top = tk.Frame(shell, bg=PALETTE["bg"])
        top.grid(row=2, column=0, sticky="nsew", pady=(0, 16))
        top.columnconfigure(0, weight=5)
        top.columnconfigure(1, weight=4)
        top.rowconfigure(0, weight=1)

        self._build_sources_panel(top)
        self._build_settings_panel(top)

        bottom = tk.Frame(shell, bg=PALETTE["bg"])
        bottom.grid(row=3, column=0, sticky="nsew")
        bottom.columnconfigure(0, weight=11)
        bottom.columnconfigure(1, weight=9)
        bottom.rowconfigure(0, weight=1)

        self._build_queue_panel(bottom)
        self._build_log_panel(bottom)
        self._build_footer(shell)

    def _build_hero(self, parent: tk.Frame) -> None:
        hero = tk.Frame(
            parent,
            bg=PALETTE["accent"],
            padx=24,
            pady=22,
            highlightthickness=0,
        )
        hero.grid(row=0, column=0, sticky="ew", pady=(0, 14))
        hero.columnconfigure(0, weight=1)

        badge = tk.Label(
            hero,
            text="Local app | Best quality under target",
            bg=PALETTE["soft"],
            fg=PALETTE["accent"],
            font=(FONT_FAMILY, 10, "bold"),
            padx=12,
            pady=6,
        )
        badge.grid(row=0, column=0, sticky="w")

        title = tk.Label(
            hero,
            text="Compress big images into lightweight files you can actually share",
            bg=PALETTE["accent"],
            fg="white",
            font=(FONT_FAMILY, 22, "bold"),
            anchor="w",
            justify="left",
        )
        title.grid(row=1, column=0, sticky="w", pady=(14, 8))

        subtitle = tk.Label(
            hero,
            text=(
                "The app lowers compression first and only shrinks dimensions when it has to. "
                "A target like 150kb is aggressive, so this aims for the best visual result "
                "under the limit while keeping the whole workflow local."
            ),
            bg=PALETTE["accent"],
            fg="#E0F2FE",
            font=(FONT_FAMILY, 11),
            wraplength=1080,
            justify="left",
            anchor="w",
        )
        subtitle.grid(row=2, column=0, sticky="w")

    def _build_metrics(self, parent: tk.Frame) -> None:
        metrics = tk.Frame(parent, bg=PALETTE["bg"])
        metrics.grid(row=1, column=0, sticky="ew", pady=(0, 16))
        metrics.columnconfigure(0, weight=1)
        metrics.columnconfigure(1, weight=1)
        metrics.columnconfigure(2, weight=1)

        self._build_metric_card(metrics, 0, "Queued", self.queue_stats_var)
        self._build_metric_card(metrics, 1, "Target", self.target_card_var)
        self._build_metric_card(metrics, 2, "Output", self.mode_card_var)

    def _build_metric_card(
        self, parent: tk.Frame, column: int, label: str, value_var: tk.StringVar
    ) -> None:
        card = tk.Frame(
            parent,
            bg=PALETTE["card"],
            padx=18,
            pady=16,
            highlightthickness=1,
            highlightbackground=PALETTE["line"],
        )
        card.grid(row=0, column=column, sticky="nsew", padx=(0 if column == 0 else 8, 0))
        parent.columnconfigure(column, weight=1)

        tk.Label(
            card,
            text=label,
            bg=PALETTE["card"],
            fg=PALETTE["muted"],
            font=(FONT_FAMILY, 10, "bold"),
        ).grid(row=0, column=0, sticky="w")

        tk.Label(
            card,
            textvariable=value_var,
            bg=PALETTE["card"],
            fg=PALETTE["text"],
            font=(FONT_FAMILY, 16, "bold"),
            justify="left",
            anchor="w",
        ).grid(row=1, column=0, sticky="w", pady=(8, 0))

    def _build_sources_panel(self, parent: tk.Frame) -> None:
        card = self._make_card(
            parent,
            row=0,
            column=0,
            title="1. Add your images",
            subtitle=(
                "Drag files or folders into the drop zone. You can also add files manually, "
                "remove selected items, or clear the queue."
            ),
            padx=(0, 10),
        )
        card.rowconfigure(2, weight=1)

        drop_area = tk.Frame(
            card,
            bg=PALETTE["soft_alt"],
            padx=24,
            pady=28,
            highlightthickness=2,
            highlightbackground=PALETTE["accent"],
        )
        drop_area.grid(row=2, column=0, sticky="nsew", pady=(4, 16))
        drop_area.columnconfigure(0, weight=1)
        drop_area.rowconfigure(0, weight=1)

        drop_title = tk.Label(
            drop_area,
            text="Drop images here",
            bg=PALETTE["soft_alt"],
            fg=PALETTE["text"],
            font=(FONT_FAMILY, 20, "bold"),
        )
        drop_title.grid(row=0, column=0, sticky="n", pady=(10, 8))

        drop_copy = (
            "Drag JPG, PNG, WebP, TIFF, or whole folders into this area."
            if TKDND_AVAILABLE
            else "Drag-and-drop support is optional. Use Add Files or Add Folder below."
        )
        drop_body = tk.Label(
            drop_area,
            text=drop_copy,
            bg=PALETTE["soft_alt"],
            fg=PALETTE["muted"],
            font=(FONT_FAMILY, 12),
            wraplength=540,
            justify="center",
        )
        drop_body.grid(row=1, column=0, sticky="n", pady=(0, 14))

        if TKDND_AVAILABLE:
            for widget in (drop_area, drop_title, drop_body):
                widget.drop_target_register(DND_FILES)
                widget.dnd_bind("<<Drop>>", self._handle_drop)

        buttons = tk.Frame(card, bg=PALETTE["card"])
        buttons.grid(row=3, column=0, sticky="ew")
        buttons.columnconfigure(0, weight=1)
        buttons.columnconfigure(1, weight=1)
        buttons.columnconfigure(2, weight=1)
        buttons.columnconfigure(3, weight=1)

        self._make_button(buttons, "Add Files", self._pick_files).grid(
            row=0, column=0, sticky="ew", padx=(0, 8)
        )
        self._make_button(buttons, "Add Folder", self._pick_folder).grid(
            row=0, column=1, sticky="ew", padx=(0, 8)
        )
        self._make_button(buttons, "Remove Selected", self._remove_selected).grid(
            row=0, column=2, sticky="ew", padx=(0, 8)
        )
        self._make_button(buttons, "Clear All", self._clear_files, kind="danger").grid(
            row=0, column=3, sticky="ew"
        )

        tk.Label(
            card,
            textvariable=self.file_hint_var,
            bg=PALETTE["card"],
            fg=PALETTE["muted"],
            font=(FONT_FAMILY, 11),
            anchor="w",
            justify="left",
        ).grid(row=4, column=0, sticky="w", pady=(14, 0))

    def _build_settings_panel(self, parent: tk.Frame) -> None:
        card = self._make_card(
            parent,
            row=0,
            column=1,
            title="2. Choose how to save",
            subtitle=(
                "Set your max size, pick an output format, then choose whether to add a "
                "suffix, keep the same name in another folder, or overwrite the original."
            ),
        )
        card.columnconfigure(1, weight=1)

        self._add_field_label(card, 2, "Target size")
        self.target_entry = self._make_entry(card, self.max_size_var)
        self.target_entry.grid(row=2, column=1, sticky="ew", pady=5)

        preset_row = tk.Frame(card, bg=PALETTE["card"])
        preset_row.grid(row=3, column=1, sticky="w", pady=(0, 10))
        for index, value in enumerate(("150kb", "300kb", "500kb")):
            self._make_button(
                preset_row,
                value.upper(),
                command=lambda chosen=value: self.max_size_var.set(chosen),
                kind="subtle",
            ).grid(row=0, column=index, padx=(0, 8))

        self._add_field_label(card, 4, "Format")
        self.format_box = ttk.Combobox(
            card,
            textvariable=self.format_var,
            values=("auto", "keep", "jpeg", "png", "webp"),
            state="readonly",
            style="App.TCombobox",
        )
        self.format_box.grid(row=4, column=1, sticky="ew", pady=5)

        self._add_field_label(card, 5, "Save mode")
        self.name_mode_box = ttk.Combobox(
            card,
            textvariable=self.name_mode_var,
            values=("suffix", "same-name", "overwrite"),
            state="readonly",
            style="App.TCombobox",
        )
        self.name_mode_box.grid(row=5, column=1, sticky="ew", pady=5)
        self.name_mode_box.bind(
            "<<ComboboxSelected>>", lambda _event: self._update_save_mode_ui()
        )

        self._add_field_label(card, 6, "Suffix")
        self.suffix_entry = self._make_entry(card, self.suffix_var)
        self.suffix_entry.grid(row=6, column=1, sticky="ew", pady=5)

        self._add_field_label(card, 7, "Output folder")
        folder_row = tk.Frame(card, bg=PALETTE["card"])
        folder_row.grid(row=7, column=1, sticky="ew", pady=5)
        folder_row.columnconfigure(0, weight=1)

        self.output_dir_entry = self._make_entry(folder_row, self.output_dir_var)
        self.output_dir_entry.grid(row=0, column=0, sticky="ew", padx=(0, 8))
        self.browse_button = self._make_button(
            folder_row,
            "Choose",
            self._choose_output_folder,
            kind="subtle",
        )
        self.browse_button.grid(row=0, column=1, padx=(0, 8))
        self.clear_output_button = self._make_button(
            folder_row,
            "Clear",
            lambda: self.output_dir_var.set(""),
            kind="subtle",
        )
        self.clear_output_button.grid(row=0, column=2)

        hint_box = tk.Frame(
            card,
            bg=PALETTE["hint_bg"],
            padx=14,
            pady=10,
            highlightthickness=1,
            highlightbackground="#7C6A22",
        )
        hint_box.grid(row=8, column=0, columnspan=2, sticky="ew", pady=(14, 10))
        tk.Label(
            hint_box,
            textvariable=self.save_mode_hint_var,
            bg=PALETTE["hint_bg"],
            fg=PALETTE["warning"],
            font=(FONT_FAMILY, 11),
            justify="left",
            wraplength=420,
        ).grid(row=0, column=0, sticky="w")

        note_box = tk.Frame(
            card,
            bg=PALETTE["note_bg"],
            padx=14,
            pady=10,
            highlightthickness=1,
            highlightbackground=PALETTE["line"],
        )
        note_box.grid(row=9, column=0, columnspan=2, sticky="ew", pady=(0, 6))
        tk.Label(
            note_box,
            text=(
                "Tip: Compressing a 12 MB image down to 150 KB can require both stronger "
                "compression and smaller dimensions. This app always tries the highest quality "
                "that still fits the target."
            ),
            bg=PALETTE["note_bg"],
            fg=PALETTE["text"],
            font=(FONT_FAMILY, 11),
            justify="left",
            wraplength=420,
        ).grid(row=0, column=0, sticky="w")

    def _build_queue_panel(self, parent: tk.Frame) -> None:
        card = self._make_card(
            parent,
            row=0,
            column=0,
            title="3. Review the queue",
            subtitle="Double-click any queued file to reveal it in Finder.",
            padx=(0, 10),
        )
        card.rowconfigure(2, weight=1)

        self.queue_heading_var = tk.StringVar(value="No files queued yet.")
        tk.Label(
            card,
            textvariable=self.queue_heading_var,
            bg=PALETTE["card"],
            fg=PALETTE["muted"],
            font=(FONT_FAMILY, 11),
            anchor="w",
        ).grid(row=2, column=0, sticky="w", pady=(4, 10))

        list_frame = tk.Frame(
            card,
            bg=PALETTE["card"],
            highlightthickness=1,
            highlightbackground=PALETTE["line"],
        )
        list_frame.grid(row=3, column=0, sticky="nsew")
        list_frame.columnconfigure(0, weight=1)
        list_frame.rowconfigure(0, weight=1)
        card.rowconfigure(3, weight=1)

        self.file_list = tk.Listbox(
            list_frame,
            height=12,
            bg=PALETTE["log_bg"],
            fg=PALETTE["text"],
            selectbackground=PALETTE["accent"],
            selectforeground="white",
            borderwidth=0,
            highlightthickness=0,
            activestyle="none",
            font=("Menlo", 11),
        )
        self.file_list.grid(row=0, column=0, sticky="nsew")

        file_scroll = tk.Scrollbar(
            list_frame,
            orient="vertical",
            command=self.file_list.yview,
            bg=PALETTE["soft"],
            troughcolor=PALETTE["bg"],
            activebackground=PALETTE["accent"],
        )
        file_scroll.grid(row=0, column=1, sticky="ns")
        self.file_list.configure(yscrollcommand=file_scroll.set)

    def _build_log_panel(self, parent: tk.Frame) -> None:
        card = self._make_card(
            parent,
            row=0,
            column=1,
            title="4. Follow the results",
            subtitle="Every file writes a line here so you can see what changed.",
        )
        card.rowconfigure(2, weight=1)

        self.log_text = tk.Text(
            card,
            height=12,
            wrap="word",
            state="disabled",
            bg=PALETTE["log_bg"],
            fg=PALETTE["log_fg"],
            insertbackground="white",
            relief="flat",
            borderwidth=0,
            highlightthickness=0,
            padx=14,
            pady=14,
            font=("Menlo", 11),
        )
        self.log_text.grid(row=2, column=0, sticky="nsew", pady=(6, 0))

        log_scroll = tk.Scrollbar(
            card,
            orient="vertical",
            command=self.log_text.yview,
            bg=PALETTE["soft"],
            troughcolor=PALETTE["bg"],
            activebackground=PALETTE["accent"],
        )
        log_scroll.grid(row=2, column=1, sticky="ns", pady=(6, 0))
        self.log_text.configure(yscrollcommand=log_scroll.set)

    def _build_footer(self, parent: tk.Frame) -> None:
        footer = tk.Frame(
            parent,
            bg=PALETTE["card"],
            padx=18,
            pady=16,
            highlightthickness=1,
            highlightbackground=PALETTE["line"],
        )
        footer.grid(row=4, column=0, sticky="ew", pady=(16, 0))
        footer.columnconfigure(0, weight=2)
        footer.columnconfigure(1, weight=1)
        footer.columnconfigure(2, weight=0)

        left = tk.Frame(footer, bg=PALETTE["card"])
        left.grid(row=0, column=0, sticky="ew", padx=(0, 16))
        left.columnconfigure(0, weight=1)

        tk.Label(
            left,
            textvariable=self.status_var,
            bg=PALETTE["card"],
            fg=PALETTE["text"],
            font=(FONT_FAMILY, 12, "bold"),
            justify="left",
            anchor="w",
            wraplength=700,
        ).grid(row=0, column=0, sticky="ew")

        self.progress = ttk.Progressbar(
            left,
            mode="indeterminate",
            style="App.Horizontal.TProgressbar",
        )
        self.progress.grid(row=1, column=0, sticky="ew", pady=(12, 0))

        action_bar = tk.Frame(footer, bg=PALETTE["card"])
        action_bar.grid(row=0, column=2, sticky="e")

        self.open_output_button = self._make_button(
            action_bar,
            "Open Output Folder",
            self._open_output_folder,
            kind="subtle",
        )
        self.open_output_button.grid(row=0, column=0, padx=(0, 10))
        self.open_output_button.config(state="disabled")

        self.compress_button = self._make_button(
            action_bar,
            "Compress Now",
            self._start_compression,
            kind="primary",
            padx=26,
            pady=12,
        )
        self.compress_button.grid(row=0, column=1)

    def _make_card(
        self,
        parent: tk.Frame,
        row: int,
        column: int,
        title: str,
        subtitle: str,
        padx: tuple[int, int] = (0, 0),
    ) -> tk.Frame:
        card = tk.Frame(
            parent,
            bg=PALETTE["card"],
            padx=18,
            pady=18,
            highlightthickness=1,
            highlightbackground=PALETTE["line"],
        )
        card.grid(row=row, column=column, sticky="nsew", padx=padx)
        card.columnconfigure(0, weight=1)
        card.rowconfigure(0, weight=0)

        tk.Label(
            card,
            text=title,
            bg=PALETTE["card"],
            fg=PALETTE["text"],
            font=(FONT_FAMILY, 16, "bold"),
            anchor="w",
        ).grid(row=0, column=0, sticky="w")

        tk.Label(
            card,
            text=subtitle,
            bg=PALETTE["card"],
            fg=PALETTE["muted"],
            font=(FONT_FAMILY, 11),
            wraplength=560 if column == 0 else 460,
            justify="left",
            anchor="w",
        ).grid(row=1, column=0, sticky="w", pady=(6, 14))
        return card

    def _add_field_label(self, parent: tk.Frame, row: int, text: str) -> None:
        tk.Label(
            parent,
            text=text,
            bg=PALETTE["card"],
            fg=PALETTE["text"],
            font=(FONT_FAMILY, 11, "bold"),
            anchor="w",
        ).grid(row=row, column=0, sticky="w", pady=5, padx=(0, 12))

    def _make_entry(self, parent: tk.Widget, textvariable: tk.StringVar) -> tk.Entry:
        return tk.Entry(
            parent,
            textvariable=textvariable,
            bg=PALETTE["card"],
            fg=PALETTE["text"],
            insertbackground=PALETTE["text"],
            relief="flat",
            borderwidth=0,
            highlightthickness=1,
            highlightbackground=PALETTE["line"],
            highlightcolor=PALETTE["accent"],
            font=(FONT_FAMILY, 12),
        )

    def _make_button(
        self,
        parent: tk.Widget,
        text: str,
        command,
        kind: str = "secondary",
        padx: int = 16,
        pady: int = 10,
    ) -> tk.Button:
        styles = {
            "primary": {
                "bg": PALETTE["accent"],
                "fg": "white",
                "activebackground": PALETTE["accent_dark"],
                "activeforeground": "white",
            },
            "secondary": {
                "bg": "#3D4552",
                "fg": PALETTE["text"],
                "activebackground": "#475164",
                "activeforeground": PALETTE["text"],
            },
            "subtle": {
                "bg": "#404754",
                "fg": PALETTE["text"],
                "activebackground": "#4B5464",
                "activeforeground": PALETTE["text"],
            },
            "danger": {
                "bg": "#5B3840",
                "fg": PALETTE["danger"],
                "activebackground": "#6A3E48",
                "activeforeground": PALETTE["danger"],
            },
        }
        colors = styles[kind]
        return tk.Button(
            parent,
            text=text,
            command=command,
            relief="flat",
            borderwidth=0,
            highlightthickness=0,
            cursor="hand2",
            disabledforeground="#94A3B8",
            font=(FONT_FAMILY, 11, "bold"),
            padx=padx,
            pady=pady,
            **colors,
        )

    def _choose_output_folder(self) -> None:
        selected = filedialog.askdirectory()
        if selected:
            self.output_dir_var.set(selected)

    def _pick_files(self) -> None:
        filenames = filedialog.askopenfilenames(
            title="Select images",
            filetypes=[
                ("Supported images", "*.jpg *.jpeg *.png *.webp *.bmp *.tif *.tiff"),
                ("All files", "*.*"),
            ],
        )
        if filenames:
            self._add_inputs([Path(name) for name in filenames])

    def _pick_folder(self) -> None:
        folder = filedialog.askdirectory(title="Select a folder")
        if folder:
            self._add_inputs([Path(folder)])

    def _clear_files(self) -> None:
        self.selected_inputs.clear()
        self._refresh_file_list()
        self.status_var.set("Queue cleared. Add new files whenever you are ready.")

    def _remove_selected(self) -> None:
        selected_indexes = list(self.file_list.curselection())
        if not selected_indexes:
            return

        for index in reversed(selected_indexes):
            del self.selected_inputs[index]

        self._refresh_file_list()
        self.status_var.set("Removed the selected item(s) from the queue.")

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
        if added:
            self.status_var.set(f"Added {added} file(s) to the queue.")
        else:
            self.status_var.set("No supported image files were found in that selection.")

    def _refresh_file_list(self) -> None:
        self.file_list.delete(0, tk.END)

        total_size = 0
        for path in self.selected_inputs:
            try:
                total_size += path.stat().st_size
            except OSError:
                pass

            display_size = human_size(path.stat().st_size) if path.exists() else "Missing"
            self.file_list.insert(
                tk.END,
                f"{path.name} | {display_size} | {path.parent}",
            )

        queue_count = len(self.selected_inputs)
        if queue_count:
            self.queue_heading_var.set(
                "Review the list below before you start compressing."
            )
            self.file_hint_var.set(
                "Tip: Use same-name mode plus an output folder if you want the compressed file "
                "to keep the original filename safely."
            )
            self.queue_stats_var.set(
                f"{queue_count} file(s)\n{human_size(total_size)} total"
            )
        else:
            self.queue_heading_var.set("No files queued yet.")
            self.file_hint_var.set(
                "Nothing is queued yet. Add files, add a folder, or drag images into the drop zone."
            )
            self.queue_stats_var.set("0 file(s)\n0 B total")

        self._refresh_dashboard()

    def _refresh_dashboard(self, *_args) -> None:
        raw_target = self.max_size_var.get().strip()
        try:
            target_text = f"{human_size(parse_size_to_bytes(raw_target))} max"
        except ValueError:
            target_text = raw_target or "Set a target"

        self.target_card_var.set(target_text)
        self.mode_card_var.set(
            f"{self.name_mode_var.get()}\n{self.format_var.get()} format"
        )

    def _set_entry_enabled(self, entry: tk.Entry, enabled: bool) -> None:
        entry.configure(state="normal" if enabled else "disabled")
        entry.configure(
            disabledbackground="#EEF2F8",
            disabledforeground="#7C8594",
            bg=PALETTE["card"],
        )

    def _update_save_mode_ui(self) -> None:
        mode = self.name_mode_var.get()

        if mode == "suffix":
            self._set_entry_enabled(self.suffix_entry, True)
            self._set_entry_enabled(self.output_dir_entry, True)
            self.browse_button.config(state="normal")
            self.clear_output_button.config(state="normal")
            self.save_mode_hint_var.set(
                "Suffix mode creates a new file like photo-compressed.jpg. "
                "If you leave the output folder empty, the app saves next to the original."
            )
        elif mode == "same-name":
            self._set_entry_enabled(self.suffix_entry, False)
            self._set_entry_enabled(self.output_dir_entry, True)
            self.browse_button.config(state="normal")
            self.clear_output_button.config(state="normal")
            self.save_mode_hint_var.set(
                "Same-name mode keeps the original filename but saves it into another folder. "
                "Pick an output folder so the source file stays safe."
            )
        else:
            if self.format_var.get() == "auto":
                self.format_var.set("keep")
            self._set_entry_enabled(self.suffix_entry, False)
            self._set_entry_enabled(self.output_dir_entry, False)
            self.browse_button.config(state="disabled")
            self.clear_output_button.config(state="disabled")
            self.save_mode_hint_var.set(
                "Overwrite mode replaces the original file in place. Keeping the original format "
                "is the safest option for this mode."
            )

        self._refresh_dashboard()

    def _append_log(self, text: str) -> None:
        self.log_text.configure(state="normal")
        self.log_text.insert(tk.END, text + "\n")
        self.log_text.see(tk.END)
        self.log_text.configure(state="disabled")

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

        try:
            subprocess.Popen(
                ["osascript", "-e", 'tell application "Python" to activate'],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
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
            messagebox.showerror(
                "Output folder required",
                "Choose an output folder for same-name mode, or use overwrite mode instead.",
            )
            return

        if self.name_mode_var.get() != "overwrite" and output_text:
            output_argument = Path(output_text).expanduser()
            try:
                output_argument.mkdir(parents=True, exist_ok=True)
                output_argument = output_argument.resolve()
            except OSError as error:
                messagebox.showerror(
                    "Invalid output folder",
                    f"Could not use the chosen output folder.\n\n{error}",
                )
                return

        args = argparse.Namespace(
            max_size=self.max_size_var.get().strip(),
            format=self.format_var.get().strip(),
            name_mode=self.name_mode_var.get().strip(),
            suffix=self.suffix_var.get(),
            min_quality=35,
            max_quality=95,
            min_side=320,
            keep_metadata=False,
            background="FFFFFF",
        )

        files = collect_input_files(self.selected_inputs)
        if not files:
            messagebox.showerror(
                "No supported files", "The current queue does not contain supported images."
            )
            return

        self.last_output_folder = None
        self.open_output_button.config(state="disabled")
        self._append_log("")
        self._append_log(f"Starting compression for {len(files)} file(s)...")
        self.status_var.set("Compressing your images now...")
        self._set_running(True)

        worker = threading.Thread(
            target=self._run_compression,
            args=(files, output_argument, args),
            daemon=True,
        )
        worker.start()

    def _run_compression(
        self,
        files: list[Path],
        output_argument: Path | None,
        args: argparse.Namespace,
    ) -> None:
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
                    self.root.after(
                        0,
                        self._append_log,
                        f"[ERROR] {file_path.name} | {error}",
                    )
        finally:
            summary = (
                f"Finished. {len(files) - failures} succeeded, {failures} had issues."
                if failures
                else f"Finished. {len(files)} file(s) processed successfully."
            )
            folder_to_open = None
            if written_paths:
                folder_to_open = (
                    output_argument
                    if output_argument is not None and output_argument.is_dir()
                    else written_paths[0].parent
                )
            self.root.after(
                0,
                self._finish_run,
                summary,
                folder_to_open,
            )

    def _finish_run(self, summary: str, folder_to_open: Path | None) -> None:
        self.status_var.set(summary)
        self._append_log(summary)
        self._set_running(False)

        if folder_to_open is not None:
            self.last_output_folder = folder_to_open
            self.open_output_button.config(state="normal")
            self._append_log(f"Output folder: {folder_to_open}")

    def _open_output_folder(self) -> None:
        if self.last_output_folder is None:
            return
        try:
            subprocess.Popen(["open", str(self.last_output_folder)])
        except Exception as error:
            self._append_log(f"[ERROR] Could not open output folder: {error}")

    def run(self) -> None:
        self.root.mainloop()


def main() -> None:
    app = CompressorApp()
    app.run()


if __name__ == "__main__":
    main()
