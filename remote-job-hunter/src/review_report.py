import re
from pathlib import Path
from typing import Any


Job = dict[str, Any]


def generate_review_report(job: Job) -> Path:
    company = str(job.get("company", "")).strip() or "company"
    title = str(job.get("title", "")).strip() or "job"
    application_folder = Path(
        job.get("application_folder")
        or (Path("outputs") / "applications" / f"{_slugify(company)}_{_short_title_slug(title)}")
    )
    application_folder.mkdir(parents=True, exist_ok=True)

    output_path = application_folder / "review_report.txt"
    report = _build_report(job)
    output_path.write_text(report, encoding="utf-8")
    return output_path


def _build_report(job: Job) -> str:
    company = str(job.get("company", "")).strip()
    title = str(job.get("title", "")).strip()
    fit_score = str(job.get("fit_score", "")).strip()
    match_score = str(job.get("match_score", "")).strip()
    recommendation = str(job.get("recommendation", "")).strip()
    missing_skills = _normalize_list(job.get("missing_skills", []))
    cv_file_path = str(job.get("cv_file_path", "")).strip()
    cover_file_path = str(job.get("cover_file_path", "")).strip()

    lines = [
        f"Job: {title} at {company}",
        f"Fit score: {fit_score}",
        f"Match score: {match_score}",
        f"Recommendation: {recommendation}",
        f"Missing skills: {missing_skills}",
        f"CV file path: {cv_file_path}",
        f"Cover letter path: {cover_file_path}",
        "",
        "Checklist:",
        "[ ] CV reviewed",
        "[ ] Cover letter reviewed",
        "[ ] JD special instructions checked",
        "[ ] Applied",
        "[ ] Follow-up scheduled",
        "",
    ]
    return "\n".join(lines)


def _normalize_list(value: Any) -> str:
    if isinstance(value, list):
        cleaned = [str(item).strip() for item in value if str(item).strip()]
        return ", ".join(cleaned) if cleaned else "None"
    text = str(value).strip()
    return text or "None"


def _slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")
    return slug or "unknown"


def _short_title_slug(title: str, max_words: int = 4) -> str:
    words = _slugify(title).split("_")[:max_words]
    return "_".join(words) or "job"
