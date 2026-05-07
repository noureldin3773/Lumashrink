import argparse
import csv
import json
import os
import re
import traceback
from datetime import datetime, date
from pathlib import Path
from typing import Any

from src.apply_package import create_apply_package
from src.config_loader import load_markdown_files
from src.cover_exporter import export_cover_letter
from src.cv_exporter import CV_DOCX_FILENAME, CV_PDF_FILENAME, export_cv_to_docx, export_pdf_from_docx
from src.cv_tailor import tailor_cv
from src.cv_validator import validate_cv
from src.fit_score import calculate_fit_score
from src.generator import generate_application, generate_application_with_ai
from src.google_sheets import export_jobs_to_google_sheets, update_job_fields_in_google_sheet
from src.job_link_extractor import extract_job_from_description, extract_job_from_url
from src.main import DATA_DIR, OUTPUTS_DIR, load_current_cv, main as run_full_pipeline
from src.polish import polish_application
from src.review_report import generate_review_report
from src.scoring import score_job
from src.special_instructions import detect_special_instructions

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None


Job = dict[str, Any]
ROOT_DIR = Path(__file__).resolve().parents[1]
LAUNCHER_LOG_PATH = ROOT_DIR / "outputs" / "logs" / "launcher.log"
MANUAL_JOBS_PATH = ROOT_DIR / "inputs" / "manual_jobs.csv"
JOB_MAX_AGE_DAYS = 15


def _log(message: str) -> None:
    timestamp = datetime.now().isoformat(timespec="seconds")
    line = f"[{timestamp}] {message}"
    print(line)
    LAUNCHER_LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LAUNCHER_LOG_PATH.open("a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def _log_file_only(message: str) -> None:
    timestamp = datetime.now().isoformat(timespec="seconds")
    line = f"[{timestamp}] {message}"
    LAUNCHER_LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LAUNCHER_LOG_PATH.open("a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def _slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", str(value).lower()).strip("_")
    return slug or "unknown"


def _short_title_slug(title: str, max_words: int = 4) -> str:
    return "_".join(_slugify(title).split("_")[:max_words]) or "job"


def _application_dir(job: Job) -> Path:
    company = str(job.get("company", "")).strip() or "company"
    title = str(job.get("title", "")).strip() or "job"
    return OUTPUTS_DIR / "applications" / f"{_slugify(company)}_{_short_title_slug(title)}"


def _parse_posted_date(raw: str) -> Any:
    if not raw:
        return None
    text = raw.strip().lower()
    if text in {"unknown", "n/a", "not listed"}:
        return None
    if "today" in text or "just now" in text:
        return date.today()
    if "yesterday" in text:
        return date.fromordinal(date.today().toordinal() - 1)
    age_match = re.search(r"(\d+)\s+(day|days|d)\b", text)
    if age_match:
        return date.fromordinal(date.today().toordinal() - int(age_match.group(1)))
    month_day_year = re.search(r"([a-z]{3,9})\s+(\d{1,2}),\s*(\d{4})", text)
    if month_day_year:
        month = {
            "jan": 1,
            "feb": 2,
            "mar": 3,
            "apr": 4,
            "may": 5,
            "jun": 6,
            "jul": 7,
            "aug": 8,
            "sep": 9,
            "oct": 10,
            "nov": 11,
            "dec": 12,
        }.get(month_day_year.group(1)[:3].lower(), 1)
        return date(int(month_day_year.group(3)), month, int(month_day_year.group(2)))
    iso_match = re.search(r"(\d{4})-(\d{2})-(\d{2})", text)
    if iso_match:
        return date(int(iso_match.group(1)), int(iso_match.group(2)), int(iso_match.group(3)))
    return None


def _normalize_job_age(job: Job) -> Job:
    normalized = job.copy()
    parsed = _parse_posted_date(str(normalized.get("posted_date", "") or "").strip())
    if parsed is None:
        normalized["posted_date"] = "Unknown"
        normalized["job_age_days"] = "Unknown"
        return normalized
    normalized["posted_date"] = parsed.isoformat()
    normalized["job_age_days"] = str((date.today() - parsed).days)
    return normalized


def _apply_age_rejection(job: Job) -> None:
    age_value = str(job.get("job_age_days", "Unknown")).strip()
    if not age_value.isdigit():
        return
    if int(age_value) <= JOB_MAX_AGE_DAYS:
        return
    signals = job.get("matched_signals", [])
    if not isinstance(signals, list):
        signals = [str(signals)]
    if "Rejected: older than 15 days" not in signals:
        signals.append("Rejected: older than 15 days")
    job["matched_signals"] = signals
    job["priority"] = "Reject"


def _is_rejected_old_job(job: Job) -> bool:
    signals = job.get("matched_signals", [])
    return "Rejected: older than 15 days" in (signals if isinstance(signals, list) else [str(signals)])


def action_extract(url: str) -> dict[str, Any]:
    _log("Fetching job")
    return extract_job_from_url(url)


def action_extract_jd(jd_text: str) -> dict[str, Any]:
    _log("Extracting from pasted JD")
    return extract_job_from_description(jd_text)


def action_check_duplicate(job: Job) -> dict[str, Any]:
    folder = _application_dir(job)
    return {"exists": folder.exists(), "application_folder": str(folder)}


def _save_manual_job(job: Job) -> None:
    description = str(job.get("description", "")).strip()
    link = str(job.get("link", "")).strip()
    if not description:
        return

    MANUAL_JOBS_PATH.parent.mkdir(parents=True, exist_ok=True)
    if not MANUAL_JOBS_PATH.exists():
        with MANUAL_JOBS_PATH.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(
                handle,
                fieldnames=["company", "title", "link", "source", "location", "salary", "description"],
            )
            writer.writeheader()

    existing_keys: set[str] = set()
    with MANUAL_JOBS_PATH.open("r", newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            row_key = (
                str(row.get("company", "")).strip().lower(),
                str(row.get("title", "")).strip().lower(),
                str(row.get("link", "")).strip().lower(),
            )
            existing_keys.add(row_key)

    key = (
        str(job.get("company", "")).strip().lower(),
        str(job.get("title", "")).strip().lower(),
        link.lower(),
    )
    if key in existing_keys:
        return

    with MANUAL_JOBS_PATH.open("a", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["company", "title", "link", "source", "location", "salary", "description"],
        )
        writer.writerow(
            {
                "company": job.get("company", ""),
                "title": job.get("title", ""),
                "link": link,
                "source": job.get("source", "Manual"),
                "location": job.get("location", ""),
                "salary": job.get("salary", ""),
                "description": description,
            }
        )


def _should_use_ai(job: Job) -> bool:
    if str(job.get("force_ai", "")).strip().lower() in {"true", "1", "yes", "y"}:
        return True
    priority = str(job.get("priority", "")).strip().lower()
    fit_score = float(str(job.get("fit_score", "0") or "0").replace("%", "") or 0)
    return priority == "high" or fit_score >= 70


def action_generate(job: Job) -> dict[str, Any]:
    options = {
        "generate_cv": bool(job.get("generate_cv", True)),
        "generate_cover": bool(job.get("generate_cover", True)),
        "generate_apply_package": bool(job.get("generate_apply_package", True)),
        "update_google_sheet": bool(job.get("update_google_sheet", True)),
        "force_ai": bool(job.get("force_ai", False)),
        "force_regenerate": bool(job.get("force_regenerate", False)),
        "skip_existing": bool(job.get("skip_existing", True)),
        "duplicate_action": str(job.get("duplicate_action", "")).strip().lower(),
    }

    folder = _application_dir(job)
    duplicate = folder.exists()
    if duplicate and options["duplicate_action"] == "cancel":
        return {"ok": True, "duplicate": True, "application_folder": str(folder), "action": "cancelled"}
    if duplicate and options["duplicate_action"] == "open_existing":
        return {"ok": True, "duplicate": True, "application_folder": str(folder), "action": "open_existing"}

    _save_manual_job(job)
    folder.mkdir(parents=True, exist_ok=True)

    _log("Scoring job")
    configs = load_markdown_files(DATA_DIR)
    current_cv = load_current_cv()
    profile_config = {"skills": configs.get("skills", ""), "cv_profile": configs.get("cv_profile", "")}

    prepared = score_job(_normalize_job_age(job), configs)
    _apply_age_rejection(prepared)
    _log("Calculating fit score")
    prepared.update(calculate_fit_score(prepared, current_cv))
    prepared.update(detect_special_instructions(prepared.get("description", "")))
    prepared["application_folder"] = str(folder)
    prepared["force_ai"] = options["force_ai"]
    prepared["force_regenerate"] = options["force_regenerate"]
    prepared["ai_usage_reason"] = (
        "force_ai" if options["force_ai"] else "high priority/fit gate" if _should_use_ai(prepared) else "rule-based fallback"
    )

    base = generate_application(prepared, profile_config)
    use_ai = _should_use_ai(prepared)
    prepared["ai_used"] = "No"
    prepared["generation_mode"] = "rule_based"
    prepared["ai_generated_at"] = ""
    prepared.update(base)

    blocked_old_job = _is_rejected_old_job(prepared) and not options["force_regenerate"]

    if use_ai and not blocked_old_job:
        ai = generate_application_with_ai(prepared, current_cv, profile_config)
        if ai.get("cover_message") and ai.get("hook"):
            prepared["cover_message"] = ai["cover_message"]
            prepared["bullets"] = ai.get("bullets", prepared.get("bullets", []))
            prepared["hook"] = ai["hook"]
            prepared["ai_used"] = "Yes"
            prepared["generation_mode"] = "ai"
            prepared["ai_generated_at"] = datetime.now().isoformat(timespec="seconds")

    prepared["cover_message"] = polish_application(prepared.get("cover_message", ""))
    prepared["hook"] = polish_application(prepared.get("hook", ""))

    cv_status = "Skipped"
    cover_status = "Skipped"
    package_status = "Skipped"
    sheet_status = "Skipped"
    cv_path = folder / CV_DOCX_FILENAME
    cover_path = folder / "cover_letter.txt"
    pdf_path = folder / CV_PDF_FILENAME
    apply_path = folder / "apply.txt"

    if blocked_old_job:
        cv_status = "Skipped (older than 15 days)"
        cover_status = "Skipped (older than 15 days)"
        package_status = "Skipped (older than 15 days)"
    try:
        if options["generate_cv"]:
            _log("Generating CV")
            if cv_path.exists() and options["skip_existing"] and not options["force_regenerate"]:
                cv_status = "Skipped (exists)"
            else:
                tailored = tailor_cv(current_cv, prepared, use_ai=use_ai)
                valid, warnings = validate_cv(tailored)
                if not valid:
                    prepared["cv_review_status"] = "Needs Review"
                    prepared["cv_notes"] = "; ".join(warnings)
                export_cv_to_docx(tailored, cv_path)
                cv_status = "Done"
            if cv_path.exists() and not pdf_path.exists():
                export_pdf_from_docx(cv_path)
            prepared["cv_generated"] = "Done" if cv_path.exists() else "Failed"
            prepared["cv_file_path"] = str(cv_path) if cv_path.exists() else ""
            prepared["cv_pdf_path"] = str(pdf_path) if pdf_path.exists() else ""
            prepared["cv_generated_at"] = datetime.now().isoformat(timespec="seconds") if cv_path.exists() else ""
    except Exception as error:
        cv_status = f"Failed: {error}"

    try:
        if options["generate_cover"] and not blocked_old_job:
            _log("Generating cover letter")
            if cover_path.exists() and options["skip_existing"] and not options["force_regenerate"]:
                cover_status = "Skipped (exists)"
            else:
                export_cover_letter(prepared, cover_path)
                cover_status = "Done"
            prepared["cover_generated"] = "Done" if cover_path.exists() else "Failed"
            prepared["cover_file_path"] = str(cover_path) if cover_path.exists() else ""
            prepared["cover_generated_at"] = datetime.now().isoformat(timespec="seconds") if cover_path.exists() else ""
    except Exception as error:
        cover_status = f"Failed: {error}"

    try:
        if options["generate_apply_package"] and not blocked_old_job:
            _log("Generating apply package")
            if apply_path.exists() and options["skip_existing"] and not options["force_regenerate"]:
                package_status = "Skipped (exists)"
            else:
                path = create_apply_package(prepared)
                prepared["apply_package_path"] = str(path)
                package_status = "Done"
            generate_review_report(prepared)
    except Exception as error:
        package_status = f"Failed: {error}"

    try:
        if options["update_google_sheet"]:
            _log("Updating Google Sheets")
            export_jobs_to_google_sheets([prepared])
            sheet_status = "Done"
    except Exception as error:
        sheet_status = f"Failed: {error}"

    _log("Done")
    return {
        "ok": True,
        "duplicate": duplicate,
        "is_older_than_15_days": blocked_old_job,
        "posted_date": str(prepared.get("posted_date", "Unknown")),
        "job_age_days": str(prepared.get("job_age_days", "Unknown")),
        "application_folder": str(folder),
        "cv_file_path": str(cv_path) if cv_path.exists() else "",
        "cover_file_path": str(cover_path) if cover_path.exists() else "",
        "apply_package_path": str(apply_path) if apply_path.exists() else "",
        "sheet_url": action_sheet_url().get("url", ""),
        "ai_usage_reason": prepared.get("ai_usage_reason", ""),
        "cv_status": cv_status,
        "cover_status": cover_status,
        "apply_package_status": package_status,
        "sheet_status": sheet_status,
    }


def action_mark_status(job: Job, status_type: str) -> dict[str, Any]:
    company = str(job.get("company", ""))
    title = str(job.get("title", ""))
    link = str(job.get("link", ""))
    updates: dict[str, Any] = {}
    if status_type == "cv_approved":
        updates["cv_review_status"] = "Approved"
    elif status_type == "cover_approved":
        updates["cover_review_status"] = "Approved"
    elif status_type == "applied":
        updates["status"] = "Applied"
        updates["applied_date"] = datetime.now().date().isoformat()
    else:
        raise ValueError(f"Unknown status action: {status_type}")
    ok = update_job_fields_in_google_sheet(company, title, link, updates)
    return {"ok": ok}


def action_full_search() -> dict[str, Any]:
    _log("Fetching job")
    _log("Scoring job")
    _log("Calculating fit score")
    _log("Generating CV")
    _log("Generating cover letter")
    _log("Updating Google Sheets")
    run_full_pipeline()
    _log("Done")
    return {"ok": True}


def action_sheet_url() -> dict[str, Any]:
    if load_dotenv is not None:
        load_dotenv()
    sheet_id = os.getenv("GOOGLE_SHEET_ID", "").strip()
    return {"url": f"https://docs.google.com/spreadsheets/d/{sheet_id}" if sheet_id else ""}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "action",
        choices=[
            "extract",
            "extract_jd",
            "check_duplicate",
            "generate",
            "full_search",
            "scrape_all",
            "sheet_url",
            "mark_cv_approved",
            "mark_cover_approved",
            "mark_applied",
        ],
    )
    parser.add_argument("--url", default="")
    parser.add_argument("--jd-text", default="")
    parser.add_argument("--job-json", default="")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    try:
        payload = json.loads(args.job_json) if args.job_json else {}
        if args.action == "extract":
            result = action_extract(args.url)
        elif args.action == "extract_jd":
            result = action_extract_jd(args.jd_text)
        elif args.action == "check_duplicate":
            result = action_check_duplicate(payload)
        elif args.action == "generate":
            result = action_generate(payload)
        elif args.action in {"full_search", "scrape_all"}:
            result = action_full_search()
        elif args.action == "mark_cv_approved":
            result = action_mark_status(payload, "cv_approved")
        elif args.action == "mark_cover_approved":
            result = action_mark_status(payload, "cover_approved")
        elif args.action == "mark_applied":
            result = action_mark_status(payload, "applied")
        else:
            result = action_sheet_url()
        print(json.dumps({"ok": True, "result": result}, ensure_ascii=False))
    except Exception as error:
        _log(f"ERROR: {type(error).__name__}: {error}")
        _log_file_only(traceback.format_exc().strip())
        print(
            json.dumps(
                {
                    "ok": False,
                    "error_type": type(error).__name__,
                    "error_message": str(error),
                },
                ensure_ascii=False,
            )
        )


if __name__ == "__main__":
    main()
