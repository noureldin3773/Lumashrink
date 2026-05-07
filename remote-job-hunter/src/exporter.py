import csv
from pathlib import Path
from typing import Any, Union


Job = dict[str, Any]


CSV_FIELDS = (
    "company",
    "title",
    "link",
    "source",
    "location",
    "salary",
    "description",
    "posted_date",
    "job_age_days",
    "has_special_instruction",
    "special_instruction_text",
    "special_instruction_handled",
    "match_score",
    "priority",
    "matched_signals",
    "fit_score",
    "matched_skills",
    "missing_skills",
    "fit_summary",
    "recommendation",
    "cv_version",
    "cover_message",
    "bullets",
    "hook",
    "ai_used",
    "ai_generated_at",
    "generation_mode",
    "cv_generated",
    "application_folder",
    "cv_file_path",
    "cv_pdf_path",
    "cv_generated_at",
    "cv_review_status",
    "cv_notes",
    "cover_generated",
    "cover_file_path",
    "cover_generated_at",
    "ready_to_apply",
    "force_regenerate",
    "status",
    "applied_date",
    "follow_up_date",
    "notes",
)


def export_jobs_to_csv(jobs: list[Job], output_path: Union[str, Path] = "outputs/jobs.csv") -> Path:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    export_rows = [_prepare_row(job) for job in jobs]

    with path.open("w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=CSV_FIELDS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(export_rows)

    return path


save_jobs_to_csv = export_jobs_to_csv


def _prepare_row(job: Job) -> Job:
    row = job.copy()
    matched_signals = row.get("matched_signals", [])
    if isinstance(matched_signals, list):
        row["matched_signals"] = "; ".join(matched_signals)
    bullets = row.get("bullets", [])
    if isinstance(bullets, list):
        row["bullets"] = "; ".join(bullets)
    matched_skills = row.get("matched_skills", [])
    if isinstance(matched_skills, list):
        row["matched_skills"] = "; ".join(matched_skills)
    missing_skills = row.get("missing_skills", [])
    if isinstance(missing_skills, list):
        row["missing_skills"] = "; ".join(missing_skills)
    row["cv_generated"] = row.get("cv_generated") or ""
    row["ai_used"] = row.get("ai_used") or "No"
    row["ai_generated_at"] = row.get("ai_generated_at") or ""
    row["generation_mode"] = row.get("generation_mode") or "rule_based"
    row["application_folder"] = row.get("application_folder") or ""
    row["cv_file_path"] = row.get("cv_file_path") or ""
    row["cv_pdf_path"] = row.get("cv_pdf_path") or ""
    row["cv_generated_at"] = row.get("cv_generated_at") or ""
    row["cv_review_status"] = row.get("cv_review_status") or "Needs Review"
    row["cv_notes"] = row.get("cv_notes") or ""
    row["cover_generated"] = row.get("cover_generated") or ""
    row["cover_file_path"] = row.get("cover_file_path") or ""
    row["cover_generated_at"] = row.get("cover_generated_at") or ""
    row["has_special_instruction"] = row.get("has_special_instruction") or ""
    row["special_instruction_text"] = row.get("special_instruction_text") or ""
    row["special_instruction_handled"] = row.get("special_instruction_handled") or ""
    row["ready_to_apply"] = row.get("ready_to_apply") or ""
    row["force_regenerate"] = row.get("force_regenerate") or ""
    row["status"] = row.get("status") or "New"
    row["posted_date"] = row.get("posted_date") or "Unknown"
    row["job_age_days"] = row.get("job_age_days") or "Unknown"
    row["applied_date"] = row.get("applied_date") or ""
    row["follow_up_date"] = row.get("follow_up_date") or ""
    row["notes"] = row.get("notes") or ""
    return row
