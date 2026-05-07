import re
from pathlib import Path
from typing import Any, Union


Job = dict[str, Any]


def export_cover_letter(job: Job, filename: Union[str, Path, None] = None) -> Path:
    output_path = Path(filename) if filename else _default_output_path(job)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(_build_cover_letter_text(job), encoding="utf-8")
    return output_path


def _default_output_path(job: Job) -> Path:
    company = str(job.get("company", "")).strip() or "company"
    title = str(job.get("title", "")).strip() or "job"
    folder = Path("outputs") / "applications" / f"{_slugify(company)}_{_short_title_slug(title)}"
    return folder / "cover_letter.txt"


def _build_cover_letter_text(job: Job) -> str:
    cover_message = str(job.get("cover_message", "")).strip()
    hook = str(job.get("hook", "")).strip()
    bullets = job.get("bullets", [])
    if isinstance(bullets, str):
        bullet_items = [item.strip() for item in bullets.split(";") if item.strip()]
    else:
        bullet_items = [str(item).strip() for item in bullets if str(item).strip()]

    sections = []
    if cover_message:
        sections.append(cover_message)
    if bullet_items:
        sections.append("\n".join(f"- {bullet}" for bullet in bullet_items))
    if hook:
        sections.append(hook)

    return "\n\n".join(sections).strip() + "\n"


def _slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")
    return slug or "unknown"


def _short_title_slug(title: str, max_words: int = 4) -> str:
    words = _slugify(title).split("_")[:max_words]
    return "_".join(words) or "job"
