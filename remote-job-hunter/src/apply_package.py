import re
from pathlib import Path
from typing import Any


Job = dict[str, Any]


def create_apply_package(job: Job) -> Path:
    company = str(job.get("company", "")).strip() or "company"
    title = str(job.get("title", "")).strip() or "job"
    application_folder = Path(
        job.get("application_folder")
        or (Path("outputs") / "applications" / f"{_slugify(company)}_{_short_title_slug(title)}")
    )
    application_folder.mkdir(parents=True, exist_ok=True)

    output_path = application_folder / "apply.txt"
    output_path.write_text(_build_apply_text(job), encoding="utf-8")
    return output_path


def _build_apply_text(job: Job) -> str:
    company = str(job.get("company", "")).strip()
    title = str(job.get("title", "")).strip()
    link = str(job.get("link", "")).strip()
    cover_message = str(job.get("cover_message", "")).strip()
    cv_file_path = str(job.get("cv_file_path", "")).strip()
    has_special = _to_bool(job.get("has_special_instruction", False))
    special_text = str(job.get("special_instruction_text", "")).strip()

    instructions_block = special_text if has_special and special_text else "None"

    lines = [
        "JOB INFO",
        f"Company: {company}",
        f"Title: {title}",
        f"Link: {link}",
        "",
        "COVER MESSAGE (READY TO PASTE)",
        cover_message or "N/A",
        "",
        f"CV FILE PATH: {cv_file_path or 'N/A'}",
        "",
        "SPECIAL INSTRUCTIONS",
        instructions_block,
        "",
        "CHECKLIST",
        "- [ ] CV reviewed",
        "- [ ] Cover reviewed",
        "- [ ] Instructions added",
        "",
        "FINAL VERSION (READY TO SUBMIT)",
        cover_message or "N/A",
    ]
    return "\n".join(lines).strip() + "\n"


def _to_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"true", "1", "yes", "y"}


def _slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")
    return slug or "unknown"


def _short_title_slug(title: str, max_words: int = 4) -> str:
    words = _slugify(title).split("_")[:max_words]
    return "_".join(words) or "job"
