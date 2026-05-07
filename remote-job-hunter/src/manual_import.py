import csv
from pathlib import Path
from typing import Any, Union


Job = dict[str, Any]

MANUAL_JOB_FIELDS = (
    "company",
    "title",
    "link",
    "source",
    "location",
    "salary",
    "description",
)


def load_manual_jobs(input_path: Union[str, Path] = "inputs/manual_jobs.csv") -> list[Job]:
    path = Path(input_path)
    _ensure_manual_jobs_file(path)

    jobs: list[Job] = []
    with path.open("r", newline="", encoding="utf-8") as csv_file:
        reader = csv.DictReader(csv_file)
        for row in reader:
            job = _normalize_row(row)
            if _is_empty_job(job):
                continue

            jobs.append(job)

    return jobs


def _ensure_manual_jobs_file(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    if path.exists() and path.stat().st_size > 0:
        return

    with path.open("w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=MANUAL_JOB_FIELDS)
        writer.writeheader()


def _normalize_row(row: dict[str, Any]) -> Job:
    job = {
        field: str(row.get(field) or "").strip()
        for field in MANUAL_JOB_FIELDS
    }
    job["source"] = job["source"] or "Manual Import"
    return job


def _is_empty_job(job: Job) -> bool:
    return not any(str(job.get(field, "")).strip() for field in MANUAL_JOB_FIELDS if field != "source")
