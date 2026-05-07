from pathlib import Path
from pprint import pprint
import re
import json
from datetime import datetime, date
from typing import Any

from scrapers.himalayas import fetch_himalayas_jobs
from scrapers.jobicy import fetch_jobicy_jobs
from scrapers.otta import fetch_otta_jobs
from scrapers.remoteco import fetch_remoteco_jobs
from scrapers.remotive import fetch_remotive_jobs
from scrapers.remoteok import fetch_remoteok_jobs
from scrapers.weworkremotely import fetch_weworkremotely_jobs
from scrapers.wellfound import fetch_wellfound_jobs
from scrapers.workingnomads import fetch_workingnomads_jobs
from scrapers.ycombinator import fetch_ycombinator_jobs
from src.config_loader import load_markdown_files
from src.cover_exporter import export_cover_letter
from src.cv_exporter import CV_DOCX_FILENAME, CV_PDF_FILENAME, export_cv_to_docx, export_pdf_from_docx
from src.cv_tailor import tailor_cv
from src.cv_validator import validate_cv
from src.exporter import export_jobs_to_csv
from src.fit_score import calculate_fit_score
from src.generator import generate_application, generate_application_with_ai
from src.google_sheets import export_jobs_to_google_sheets, load_sheet_overrides
from src.manual_import import load_manual_jobs
from src.polish import polish_application
from src.review_report import generate_review_report
from src.scoring import score_job
from src.special_instructions import detect_special_instructions


Job = dict[str, Any]
ROOT_DIR = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT_DIR / "data"
CURRENT_CV_PATH = DATA_DIR / "current_cv.md"
MANUAL_JOBS_PATH = ROOT_DIR / "inputs" / "manual_jobs.csv"
OUTPUTS_DIR = ROOT_DIR / "outputs"
OUTPUT_PATH = ROOT_DIR / "outputs" / "jobs.csv"
USE_SAMPLE_JOBS = False
JOB_MAX_AGE_DAYS = 15


def get_sample_jobs() -> list[Job]:
    return [
        {
            "company": "Northstar AI",
            "title": "Senior Product Designer",
            "link": "https://example.com/jobs/northstar-ai-senior-product-designer",
            "source": "sample",
            "location": "Remote Worldwide",
            "salary": "$4,000/month",
            "description": "Remote-first AI SaaS startup hiring for product strategy, Figma, UX research, and design systems.",
        },
        {
            "company": "CraftBoard",
            "title": "Product Designer",
            "link": "https://example.com/jobs/craftboard-product-designer",
            "source": "sample",
            "location": "Global remote",
            "salary": "",
            "description": "SaaS product team looking for a designer to improve UX research, user flows, and product quality.",
        },
        {
            "company": "BrightPixel Studio",
            "title": "Junior Graphic Designer",
            "link": "https://example.com/jobs/brightpixel-junior-graphic-designer",
            "source": "sample",
            "location": "Onsite only",
            "salary": "",
            "description": "Junior graphic designer role focused on social media designer tasks, Canva assets, and unpaid trial work.",
        },
    ]


def main() -> None:
    configs = load_markdown_files(DATA_DIR)
    current_cv = load_current_cv()
    jobs, source_counts = get_jobs()
    sheet_overrides = load_sheet_overrides()
    if sheet_overrides:
        jobs = _apply_sheet_overrides(jobs, sheet_overrides)
    profile_config = {
        "skills": configs.get("skills", ""),
        "cv_profile": configs.get("cv_profile", ""),
    }
    scored_jobs = [prepare_job(job, configs, profile_config, current_cv) for job in jobs]
    output_path = export_jobs_to_csv(scored_jobs, OUTPUT_PATH)
    try:
        export_jobs_to_google_sheets(scored_jobs)
    except Exception as error:
        print("Google Sheets export failed")
        print(f"Exception type: {type(error).__name__}")
        print(f"Exception message: {error}")

    print(f"Loaded {len(configs)} markdown files from {DATA_DIR}")
    for source, count in source_counts.items():
        print(f"{source} jobs: {count}")
    print(f"Found {len(jobs)} jobs")
    print(f"Exported {len(scored_jobs)} scored jobs to {output_path}")
    pprint(scored_jobs)


def load_current_cv() -> str:
    if not CURRENT_CV_PATH.exists():
        print(f"Current CV not found at {CURRENT_CV_PATH}. CV tailoring will be skipped.")
        return ""

    return CURRENT_CV_PATH.read_text(encoding="utf-8")


def prepare_job(job: Job, configs: dict[str, str], profile_config: dict[str, str], current_cv: str) -> Job:
    normalized_job = _normalize_job_age(job)
    scored_job = score_job(normalized_job, configs)
    _apply_age_rejection(scored_job)
    scored_job.update(calculate_fit_score(scored_job, current_cv))
    scored_job.update(detect_special_instructions(scored_job.get("description", "")))
    application_dir = _application_dir_for_job(scored_job)
    application_dir.mkdir(parents=True, exist_ok=True)
    scored_job["application_folder"] = str(application_dir)
    application = _generate_application_fields(scored_job, profile_config, current_cv)
    scored_job.update(application)
    if _is_rejected_old_job(scored_job):
        _mark_generation_skipped_for_old_job(scored_job)
    else:
        _generate_application_assets(scored_job, current_cv, application_dir)
    _write_job_info(scored_job, application_dir)
    review_report_path = generate_review_report(scored_job)
    scored_job["review_report_path"] = str(review_report_path)
    return scored_job


def _generate_application_assets(job: Job, current_cv: str, application_dir: Path) -> None:
    force_regenerate = _to_bool(job.get("force_regenerate", False))
    company = str(job.get("company", "")).strip() or "company"
    cv_path = application_dir / CV_DOCX_FILENAME
    cv_pdf_path = application_dir / CV_PDF_FILENAME
    cover_path = application_dir / "cover_letter.txt"

    cv_exists = cv_path.exists()
    cover_exists = cover_path.exists()
    pdf_exists = cv_pdf_path.exists()

    if cv_exists and cover_exists and not force_regenerate:
        job["application_folder"] = str(application_dir)
        job["cv_generated"] = "Done"
        job["cover_generated"] = "Done"
        job["cv_file_path"] = str(cv_path)
        job["cover_file_path"] = str(cover_path)
        job["cv_pdf_path"] = str(cv_pdf_path) if pdf_exists else ""
        job["cv_generated_at"] = _file_timestamp(cv_path)
        job["cover_generated_at"] = _file_timestamp(cover_path)
        if not pdf_exists:
            generated_pdf = export_pdf_from_docx(cv_path)
            job["cv_pdf_path"] = str(generated_pdf) if generated_pdf else ""
        print(f"Application already exists, skipping generation for {company}")
        return

    if force_regenerate:
        _generate_tailored_cv(job, current_cv, application_dir, force_regenerate=True)
        _generate_cover_letter(job, application_dir, force_regenerate=True)
        return

    if cv_exists:
        job["cv_generated"] = "Done"
        job["cv_file_path"] = str(cv_path)
        job["cv_generated_at"] = _file_timestamp(cv_path)
        if pdf_exists:
            job["cv_pdf_path"] = str(cv_pdf_path)
        else:
            generated_pdf = export_pdf_from_docx(cv_path)
            job["cv_pdf_path"] = str(generated_pdf) if generated_pdf else ""
    else:
        _generate_tailored_cv(job, current_cv, application_dir)

    if cover_exists:
        job["cover_generated"] = "Done"
        job["cover_file_path"] = str(cover_path)
        job["cover_generated_at"] = _file_timestamp(cover_path)
    else:
        _generate_cover_letter(job, application_dir)


def _generate_tailored_cv(job: Job, current_cv: str, application_dir: Path, force_regenerate: bool = False) -> None:
    if not current_cv.strip():
        job["cv_generated"] = "Failed"
        job["cv_file_path"] = ""
        job["cv_pdf_path"] = ""
        job["cv_generated_at"] = ""
        job["cv_notes"] = _append_note(job.get("cv_notes", ""), "Current CV is missing")
        return

    company = str(job.get("company", "")).strip() or "company"
    output_path = application_dir / CV_DOCX_FILENAME

    if output_path.exists() and not force_regenerate:
        job["cv_generated"] = "Done"
        job["cv_file_path"] = str(output_path)
        existing_pdf = output_path.with_suffix(".pdf")
        if existing_pdf.exists():
            job["cv_pdf_path"] = str(existing_pdf)
        else:
            generated_pdf = export_pdf_from_docx(output_path)
            job["cv_pdf_path"] = str(generated_pdf) if generated_pdf else ""
        job["cv_generated_at"] = _file_timestamp(output_path)
        print(f"CV already exists, skipping generation for {company}")
        return

    try:
        tailored_cv = tailor_cv(current_cv, job, use_ai=_to_bool(job.get("ai_used", False)))
        valid_cv, warnings = validate_cv(tailored_cv)
        if not valid_cv:
            job["cv_review_status"] = "Needs Review"
            job["cv_notes"] = _append_note(job.get("cv_notes", ""), f"CV validation: {'; '.join(warnings)}")
        exported_path = export_cv_to_docx(tailored_cv, output_path)
        job["cv_generated"] = "Done"
        job["cv_file_path"] = str(exported_path)
        pdf_path = exported_path.with_suffix(".pdf")
        job["cv_pdf_path"] = str(pdf_path) if pdf_path.exists() else ""
        job["cv_generated_at"] = _now_timestamp()
        print(f"Generated CV for {company}")
    except Exception as error:
        job["cv_generated"] = "Failed"
        job["cv_file_path"] = ""
        job["cv_pdf_path"] = ""
        job["cv_generated_at"] = ""
        job["cv_notes"] = _append_note(job.get("cv_notes", ""), str(error))
        print(f"CV generation failed for {company}: {error}")


def _generate_cover_letter(job: Job, application_dir: Path, force_regenerate: bool = False) -> None:
    company = str(job.get("company", "")).strip() or "company"
    output_path = application_dir / "cover_letter.txt"

    if output_path.exists() and not force_regenerate:
        job["cover_generated"] = "Done"
        job["cover_file_path"] = str(output_path)
        job["cover_generated_at"] = _file_timestamp(output_path)
        print(f"Cover letter already exists, skipping generation for {company}")
        return

    try:
        exported_path = export_cover_letter(job, output_path)
        job["cover_generated"] = "Done"
        job["cover_file_path"] = str(exported_path)
        job["cover_generated_at"] = _now_timestamp()
    except Exception as error:
        job["cover_generated"] = "Failed"
        job["cover_file_path"] = ""
        job["cover_generated_at"] = ""
        job["notes"] = _append_note(job.get("notes", ""), f"Cover generation failed: {error}")
        print(f"Cover letter generation failed for {company}: {error}")


def _write_job_info(job: Job, application_dir: Path) -> None:
    payload = {
        "company": str(job.get("company", "")),
        "title": str(job.get("title", "")),
        "link": str(job.get("link", "")),
        "source": str(job.get("source", "")),
        "fit_score": job.get("fit_score", ""),
        "match_score": job.get("match_score", ""),
        "ai_used": job.get("ai_used", "No"),
        "generation_mode": job.get("generation_mode", "rule_based"),
        "generated_at": _now_timestamp(),
    }
    job_info_path = application_dir / "job_info.json"
    job_info_path.write_text(json.dumps(payload, ensure_ascii=True, indent=2), encoding="utf-8")
    job["job_info_path"] = str(job_info_path)


def _append_note(existing_notes: Any, note: str) -> str:
    existing = str(existing_notes or "").strip()
    if not existing:
        return note
    return f"{existing}; {note}"


def _generate_application_fields(job: Job, profile_config: dict[str, str], current_cv: str) -> Job:
    if _is_rejected_old_job(job):
        basic_application = generate_application(job, profile_config)
        basic_application["ai_used"] = "No"
        basic_application["ai_generated_at"] = ""
        basic_application["generation_mode"] = "rule_based"
        basic_application["cover_message"] = ""
        basic_application["hook"] = ""
        basic_application["bullets"] = []
        return basic_application

    basic_application = generate_application(job, profile_config)
    company = str(job.get("company", "")).strip() or "Unknown Company"
    use_ai = _should_use_ai(job)
    basic_application["use_ai"] = use_ai
    basic_application["ai_used"] = "No"
    basic_application["ai_generated_at"] = ""
    basic_application["generation_mode"] = "rule_based"

    if not use_ai:
        print(f"Skipping AI for {company}")
        basic_application["cover_message"] = polish_application(basic_application.get("cover_message", ""))
        basic_application["hook"] = polish_application(basic_application.get("hook", ""))
        return basic_application

    print(f"Using AI for {company}")

    try:
        ai_application = generate_application_with_ai(job, current_cv, profile_config)
    except Exception as error:
        print("AI application generation failed; using basic generator")
        print(f"Exception type: {type(error).__name__}")
        print(f"Exception message: {error}")
        return basic_application

    if not _has_complete_ai_application(ai_application):
        print("AI application generation incomplete; using basic generator")
        basic_application["cover_message"] = polish_application(basic_application.get("cover_message", ""))
        basic_application["hook"] = polish_application(basic_application.get("hook", ""))
        return basic_application

    result = {
        **basic_application,
        "cover_message": ai_application["cover_message"],
        "bullets": ai_application["bullets"],
        "hook": ai_application["hook"],
        "ai_used": "Yes",
        "ai_generated_at": _now_timestamp(),
        "generation_mode": "ai",
    }
    result["cover_message"] = polish_application(result.get("cover_message", ""))
    result["hook"] = polish_application(result.get("hook", ""))
    return result


def _should_use_ai(job: Job) -> bool:
    if _to_bool(job.get("force_ai", False)):
        return True
    priority = str(job.get("priority", "")).strip().lower()
    fit_score = _safe_int(job.get("fit_score", 0))
    return priority == "high" or fit_score >= 70


def _safe_int(value: Any, default: int = 0) -> int:
    try:
        return int(float(str(value).strip()))
    except (ValueError, TypeError):
        return default


def _to_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"true", "1", "yes", "y"}


def _job_key(job: Job) -> str:
    company = str(job.get("company", "")).strip().lower()
    title = str(job.get("title", "")).strip().lower()
    link = str(job.get("link", "")).strip().lower()
    if not (company and title and link):
        return ""
    return f"{company}|{title}|{link}"


def _apply_sheet_overrides(jobs: list[Job], overrides: dict[str, dict[str, bool]]) -> list[Job]:
    updated_jobs: list[Job] = []
    forced_ai_count = 0
    forced_regen_count = 0
    for job in jobs:
        enriched = job.copy()
        key = _job_key(enriched)
        if key and key in overrides:
            flags = overrides[key]
            enriched["force_ai"] = flags.get("force_ai", False)
            enriched["force_regenerate"] = flags.get("force_regenerate", False)
            if flags.get("force_ai", False):
                forced_ai_count += 1
            if flags.get("force_regenerate", False):
                forced_regen_count += 1
        updated_jobs.append(enriched)

    if forced_ai_count:
        print(f"Loaded force_ai=TRUE for {forced_ai_count} jobs from Google Sheets")
    if forced_regen_count:
        print(f"Loaded force_regenerate=TRUE for {forced_regen_count} jobs from Google Sheets")
    return updated_jobs


def _has_complete_ai_application(application: dict[str, Any]) -> bool:
    bullets = application.get("bullets", [])
    return (
        bool(str(application.get("cover_message", "")).strip())
        and bool(str(application.get("hook", "")).strip())
        and isinstance(bullets, list)
        and len([bullet for bullet in bullets if str(bullet).strip()]) == 3
    )


def _slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")
    return slug or "unknown"


def _short_title_slug(title: str, max_words: int = 4) -> str:
    words = _slugify(title).split("_")[:max_words]
    return "_".join(words) or "job"


def _application_dir_for_job(job: Job) -> Path:
    company = str(job.get("company", "")).strip() or "company"
    title = str(job.get("title", "")).strip() or "job"
    return OUTPUTS_DIR / "applications" / f"{_slugify(company)}_{_short_title_slug(title)}"


def _normalize_job_age(job: Job) -> Job:
    normalized = job.copy()
    raw_posted = str(normalized.get("posted_date", "") or "").strip()
    parsed = _parse_posted_date(raw_posted)
    if parsed is None:
        normalized["posted_date"] = "Unknown"
        normalized["job_age_days"] = "Unknown"
        return normalized

    normalized["posted_date"] = parsed.isoformat()
    normalized["job_age_days"] = str((date.today() - parsed).days)
    return normalized


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
        month = _month_number(month_day_year.group(1))
        return date(int(month_day_year.group(3)), month, int(month_day_year.group(2)))
    iso_match = re.search(r"(\d{4})-(\d{2})-(\d{2})", text)
    if iso_match:
        return date(int(iso_match.group(1)), int(iso_match.group(2)), int(iso_match.group(3)))
    return None


def _apply_age_rejection(job: Job) -> None:
    age_value = str(job.get("job_age_days", "Unknown")).strip()
    if not age_value.isdigit():
        return
    age_days = int(age_value)
    if age_days <= JOB_MAX_AGE_DAYS:
        return
    signals = job.get("matched_signals", [])
    if not isinstance(signals, list):
        signals = [str(signals)]
    rejection_signal = "Rejected: older than 15 days"
    if rejection_signal not in signals:
        signals.append(rejection_signal)
    job["matched_signals"] = signals
    job["priority"] = "Reject"


def _is_rejected_old_job(job: Job) -> bool:
    signals = job.get("matched_signals", [])
    if isinstance(signals, list):
        return "Rejected: older than 15 days" in signals
    return "Rejected: older than 15 days" in str(signals)


def _mark_generation_skipped_for_old_job(job: Job) -> None:
    job["cv_generated"] = "Skipped"
    job["cover_generated"] = "Skipped"
    job["cv_file_path"] = ""
    job["cv_pdf_path"] = ""
    job["cover_file_path"] = ""
    job["cv_generated_at"] = ""
    job["cover_generated_at"] = ""


def _now_timestamp() -> str:
    return datetime.now().isoformat(timespec="seconds")


def _file_timestamp(path: Path) -> str:
    try:
        return datetime.fromtimestamp(path.stat().st_mtime).isoformat(timespec="seconds")
    except OSError:
        return ""


def get_jobs() -> tuple[list[Job], dict[str, int]]:
    remoteok_jobs = _fetch_source("RemoteOK", fetch_remoteok_jobs)
    remotive_jobs = _fetch_source("Remotive", fetch_remotive_jobs)
    weworkremotely_jobs = _fetch_source("We Work Remotely", fetch_weworkremotely_jobs)
    himalayas_jobs = _fetch_source("Himalayas", fetch_himalayas_jobs)
    workingnomads_jobs = _fetch_source("Working Nomads", fetch_workingnomads_jobs)
    jobicy_jobs = _fetch_source("Jobicy", fetch_jobicy_jobs)
    remoteco_jobs = _fetch_source("Remote.co", fetch_remoteco_jobs)
    ycombinator_jobs = _fetch_source("Y Combinator", fetch_ycombinator_jobs)
    wellfound_jobs = _fetch_source("Wellfound", fetch_wellfound_jobs)
    otta_jobs = _fetch_source("Otta / Welcome to the Jungle", fetch_otta_jobs)
    manual_jobs = load_manual_jobs(MANUAL_JOBS_PATH)

    source_counts = {
        "RemoteOK": len(remoteok_jobs),
        "Remotive": len(remotive_jobs),
        "We Work Remotely": len(weworkremotely_jobs),
        "Himalayas": len(himalayas_jobs),
        "Working Nomads": len(workingnomads_jobs),
        "Jobicy": len(jobicy_jobs),
        "Remote.co": len(remoteco_jobs),
        "Y Combinator": len(ycombinator_jobs),
        "Wellfound": len(wellfound_jobs),
        "Otta / Welcome to the Jungle": len(otta_jobs),
        "Manual Import": len(manual_jobs),
    }
    jobs = dedupe_jobs(
        remoteok_jobs
        + remotive_jobs
        + weworkremotely_jobs
        + himalayas_jobs
        + workingnomads_jobs
        + jobicy_jobs
        + remoteco_jobs
        + ycombinator_jobs
        + wellfound_jobs
        + otta_jobs
        + manual_jobs
    )

    if USE_SAMPLE_JOBS:
        sample_jobs = get_sample_jobs()
        source_counts["sample"] = len(sample_jobs)
        jobs = dedupe_jobs(jobs + sample_jobs)

    if not jobs:
        print("No remote jobs found. Using sample jobs for a test export.")
        jobs = get_sample_jobs()
        source_counts["sample"] = len(jobs)

    return jobs, source_counts


def _fetch_source(source_name: str, fetcher: Any) -> list[Job]:
    try:
        return fetcher()
    except ValueError as error:
        print(f"{source_name} API returned invalid JSON: {error}")
    except Exception as error:
        print(f"{source_name} scraper failed: {error}")

    return []


def dedupe_jobs(jobs: list[Job]) -> list[Job]:
    seen: set[tuple[str, str, str]] = set()
    unique_jobs: list[Job] = []

    for job in jobs:
        key = (
            str(job.get("company", "")).strip().lower(),
            str(job.get("title", "")).strip().lower(),
            str(job.get("link", "")).strip().lower(),
        )
        if key in seen:
            continue

        seen.add(key)
        unique_jobs.append(job)

    return unique_jobs


if __name__ == "__main__":
    main()
