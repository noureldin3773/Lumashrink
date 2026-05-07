import os
import threading
import webbrowser
from pathlib import Path
from typing import Any, Optional

import tkinter as tk
from tkinter import messagebox, simpledialog, scrolledtext

from src.apply_package import create_apply_package
from src.config_loader import load_markdown_files
from src.google_sheets import export_jobs_to_google_sheets
from src.job_link_extractor import extract_job_from_url
from src.main import DATA_DIR, OUTPUTS_DIR, load_current_cv, main as run_full_pipeline, prepare_job

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None


Job = dict[str, Any]
APPLICATIONS_DIR = OUTPUTS_DIR / "applications"


class DesktopLauncher:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("Remote Job Hunter")
        self.root.geometry("1100x760")
        self.root.minsize(980, 700)
        self.root.configure(bg="#f3f6fb")

        self.job_link_var = tk.StringVar()
        self.company_var = tk.StringVar()
        self.title_var = tk.StringVar()
        self.source_var = tk.StringVar()
        self.location_var = tk.StringVar()
        self.salary_var = tk.StringVar()
        self.force_regenerate_var = tk.BooleanVar(value=False)
        self.use_ai_var = tk.BooleanVar(value=True)
        self.status_var = tk.StringVar(value="Ready")

        self._build_ui()

    def _build_ui(self) -> None:
        outer = tk.Frame(self.root, bg="#f3f6fb")
        outer.pack(fill="both", expand=True, padx=18, pady=14)

        tk.Label(outer, text="Remote Job Hunter", bg="#f3f6fb", fg="#0f172a", font=("Helvetica", 26, "bold")).pack(anchor="w")
        tk.Label(
            outer,
            text="Paste a job link, extract details, and generate a complete application package.",
            bg="#f3f6fb",
            fg="#334155",
            font=("Helvetica", 11),
        ).pack(anchor="w", pady=(2, 12))

        top_card = self._card(outer)
        top_card.pack(fill="x")

        top_row = tk.Frame(top_card, bg="#ffffff")
        top_row.pack(fill="x")
        tk.Label(top_row, text="Job Link", bg="#ffffff", fg="#1f2937", font=("Helvetica", 10, "bold")).pack(anchor="w")
        link_row = tk.Frame(top_row, bg="#ffffff")
        link_row.pack(fill="x", pady=(4, 0))
        self.link_entry = tk.Entry(
            link_row,
            textvariable=self.job_link_var,
            bg="#f8fafc",
            fg="#0f172a",
            insertbackground="#0f172a",
            relief="solid",
            bd=1,
            font=("Helvetica", 12),
        )
        self.link_entry.pack(side="left", fill="x", expand=True, ipady=9)
        self._btn(link_row, "Extract From Link", self._run_extract_from_link, primary=True).pack(side="left", padx=(10, 0))

        action_card = self._card(outer)
        action_card.pack(fill="x", pady=(10, 0))
        actions = tk.Frame(action_card, bg="#ffffff")
        actions.pack(fill="x")
        self._btn(actions, "Generate Application", self._run_generate_application, primary=True).pack(side="left")
        self._btn(actions, "Run Full Job Search", self._run_full_job_search, primary=False).pack(side="left", padx=(8, 0))
        self._btn(actions, "Open Applications Folder", self._open_applications_folder, primary=False).pack(side="right")
        self._btn(actions, "Open Google Sheet", self._open_google_sheet, primary=False).pack(side="right", padx=(0, 8))

        flags = tk.Frame(action_card, bg="#ffffff")
        flags.pack(fill="x", pady=(10, 0))
        tk.Checkbutton(flags, text="Use AI", variable=self.use_ai_var, bg="#ffffff", fg="#0f172a", font=("Helvetica", 10)).pack(side="left")
        tk.Checkbutton(flags, text="Force Regenerate", variable=self.force_regenerate_var, bg="#ffffff", fg="#0f172a", font=("Helvetica", 10)).pack(side="left", padx=(14, 0))

        center = tk.Frame(outer, bg="#f3f6fb")
        center.pack(fill="both", expand=True, pady=(10, 0))

        left = self._card(center)
        left.pack(side="left", fill="both", expand=False)
        right = self._card(center)
        right.pack(side="left", fill="both", expand=True, padx=(10, 0))

        self._field(left, "Company", self.company_var)
        self._field(left, "Job Title", self.title_var)
        self._field(left, "Source", self.source_var)
        self._field(left, "Location", self.location_var)
        self._field(left, "Salary", self.salary_var)

        tk.Label(right, text="Job Description", bg="#ffffff", fg="#1f2937", font=("Helvetica", 11, "bold")).pack(anchor="w")
        self.description_text = scrolledtext.ScrolledText(
            right,
            height=14,
            wrap="word",
            bg="#f8fafc",
            fg="#0f172a",
            insertbackground="#0f172a",
            relief="solid",
            bd=1,
            font=("Helvetica", 11),
        )
        self.description_text.pack(fill="both", expand=True, pady=(6, 0))

        log_card = self._card(outer)
        log_card.pack(fill="both", expand=True, pady=(10, 0))
        tk.Label(log_card, textvariable=self.status_var, bg="#ffffff", fg="#0f766e", font=("Helvetica", 11, "bold")).pack(anchor="w")
        self.log_text = scrolledtext.ScrolledText(
            log_card,
            height=7,
            wrap="word",
            bg="#0b1220",
            fg="#dbeafe",
            insertbackground="#dbeafe",
            relief="flat",
            font=("Menlo", 10),
        )
        self.log_text.pack(fill="both", expand=True, pady=(8, 0))

    def _card(self, parent: tk.Widget) -> tk.Frame:
        return tk.Frame(parent, bg="#ffffff", highlightthickness=1, highlightbackground="#dbe4ef", padx=12, pady=12)

    def _field(self, parent: tk.Widget, label: str, var: tk.StringVar) -> None:
        tk.Label(parent, text=label, bg="#ffffff", fg="#334155", font=("Helvetica", 10, "bold")).pack(anchor="w", pady=(2, 2))
        tk.Entry(parent, textvariable=var, bg="#f8fafc", fg="#0f172a", insertbackground="#0f172a", relief="solid", bd=1, font=("Helvetica", 10), width=36).pack(fill="x", ipady=7, pady=(0, 8))

    def _btn(self, parent: tk.Widget, text: str, command: Any, primary: bool) -> tk.Button:
        if primary:
            return tk.Button(parent, text=text, command=command, bg="#2563eb", fg="#ffffff", activebackground="#1d4ed8", activeforeground="#ffffff", relief="flat", padx=12, pady=8, font=("Helvetica", 10, "bold"), cursor="hand2")
        return tk.Button(parent, text=text, command=command, bg="#e8eef8", fg="#1f2937", activebackground="#dbe4f2", activeforeground="#0f172a", relief="flat", padx=12, pady=8, font=("Helvetica", 10), cursor="hand2")

    def _set_status(self, text: str) -> None:
        self.status_var.set(text)
        self._append_log(text)

    def _append_log(self, text: str) -> None:
        self.log_text.insert("end", f"{text}\n")
        self.log_text.see("end")

    def _run_extract_from_link(self) -> None:
        threading.Thread(target=self._extract_from_link, daemon=True).start()

    def _run_generate_application(self) -> None:
        threading.Thread(target=self._generate_application, daemon=True).start()

    def _run_full_job_search(self) -> None:
        threading.Thread(target=self._full_job_search, daemon=True).start()

    def _extract_from_link(self) -> None:
        link = self.job_link_var.get().strip()
        if not link:
            messagebox.showwarning("Missing Job Link", "Please provide a job link first.")
            return
        self._set_status("Extracting details...")
        extracted = extract_job_from_url(link)
        if extracted.get("title"):
            self.title_var.set(str(extracted.get("title", "")))
        if extracted.get("company"):
            self.company_var.set(str(extracted.get("company", "")))
        if extracted.get("location"):
            self.location_var.set(str(extracted.get("location", "")))
        if extracted.get("salary"):
            self.salary_var.set(str(extracted.get("salary", "")))
        if extracted.get("description"):
            self.description_text.delete("1.0", "end")
            self.description_text.insert("1.0", str(extracted.get("description", "")))
        if extracted.get("needs_manual_description", False):
            self._set_status("Partial extraction. Please paste full description.")
            messagebox.showinfo("Manual Description Needed", "Could not confidently extract full description. Please paste it manually.")
        else:
            self._set_status("Extraction complete.")

    def _build_job_payload(self) -> Optional[Job]:
        link = self.job_link_var.get().strip()
        if not link:
            messagebox.showwarning("Missing Job Link", "Please provide a job link.")
            return None
        extracted = extract_job_from_url(link)
        manual_description = self.description_text.get("1.0", "end").strip()
        description = manual_description or extracted.get("description", "")
        if not description:
            pasted = simpledialog.askstring("Job Description", "Paste the job description:")
            description = str(pasted or "").strip()
            if not description:
                messagebox.showwarning("Missing Description", "Job description is required.")
                return None
        return {
            "company": self.company_var.get().strip() or extracted.get("company", "") or "Unknown Company",
            "title": self.title_var.get().strip() or extracted.get("title", "") or "Product Designer",
            "link": link,
            "source": self.source_var.get().strip() or "Direct Link",
            "location": self.location_var.get().strip() or extracted.get("location", ""),
            "salary": self.salary_var.get().strip() or extracted.get("salary", ""),
            "description": description,
            "force_regenerate": self.force_regenerate_var.get(),
            "force_ai": self.use_ai_var.get(),
        }

    def _generate_application(self) -> None:
        try:
            self._set_status("Generating application...")
            job = self._build_job_payload()
            if not job:
                return
            configs = load_markdown_files(DATA_DIR)
            current_cv = load_current_cv()
            profile_config = {"skills": configs.get("skills", ""), "cv_profile": configs.get("cv_profile", "")}
            prepared = prepare_job(job, configs, profile_config, current_cv)
            prepared["apply_package_path"] = str(create_apply_package(prepared))
            export_jobs_to_google_sheets([prepared])
            self._set_status("Application generated successfully.")
            messagebox.showinfo("Success", "Application generated successfully")
        except Exception as error:
            self._set_status("Generation failed.")
            messagebox.showerror("Error", f"{type(error).__name__}: {error}")

    def _full_job_search(self) -> None:
        try:
            self._set_status("Running full job search...")
            run_full_pipeline()
            self._set_status("Full job search completed.")
            messagebox.showinfo("Success", "Full job search completed")
        except Exception as error:
            self._set_status("Full job search failed.")
            messagebox.showerror("Error", f"{type(error).__name__}: {error}")

    def _open_google_sheet(self) -> None:
        if load_dotenv is not None:
            load_dotenv()
        sheet_id = os.getenv("GOOGLE_SHEET_ID", "").strip()
        if not sheet_id:
            messagebox.showwarning("Missing GOOGLE_SHEET_ID", "Set GOOGLE_SHEET_ID in .env first.")
            return
        webbrowser.open(f"https://docs.google.com/spreadsheets/d/{sheet_id}")

    def _open_applications_folder(self) -> None:
        APPLICATIONS_DIR.mkdir(parents=True, exist_ok=True)
        webbrowser.open(APPLICATIONS_DIR.as_uri())


def main() -> None:
    root = tk.Tk()
    DesktopLauncher(root)
    root.mainloop()
