from __future__ import annotations

import re
from typing import Any

from scrapers.remoteok import _is_design_title

try:
    import requests
except ImportError:
    requests = None


REMOTIVE_API_URL = "https://remotive.com/api/remote-jobs?category=design"
SOURCE = "Remotive"
HEADERS = {
    "User-Agent": "remote-job-hunter/0.1 (+https://example.com)",
    "Accept": "application/json",
}

Job = dict[str, Any]


def fetch_remotive_jobs(timeout: int = 20) -> list[Job]:
    if requests is None:
        raise RuntimeError("The requests package is not installed. Run: pip install -r requirements.txt")

    response = requests.get(REMOTIVE_API_URL, headers=HEADERS, timeout=timeout)
    response.raise_for_status()

    payload = response.json()
    raw_jobs = payload.get("jobs", []) if isinstance(payload, dict) else []
    if not isinstance(raw_jobs, list):
        return []

    design_jobs: list[Job] = []
    rejected_by_title = 0

    for item in raw_jobs:
        if not isinstance(item, dict):
            continue

        job = _parse_job(item)
        if _is_design_title(str(job.get("title", ""))):
            design_jobs.append(job)
        else:
            print(f"REJECTED TITLE: {job.get('title', '')}")
            rejected_by_title += 1

    print(f"Remotive total jobs fetched: {len(raw_jobs)}")
    print(f"Remotive total design jobs kept: {len(design_jobs)}")
    print(f"Remotive total rejected by title: {rejected_by_title}")

    return design_jobs


def _parse_job(item: dict[str, Any]) -> Job:
    return {
        "company": str(item.get("company_name") or "").strip(),
        "title": str(item.get("title") or "").strip(),
        "link": str(item.get("url") or "").strip(),
        "source": SOURCE,
        "location": _get_location(item),
        "salary": str(item.get("salary") or "").strip(),
        "description": _clean_text(str(item.get("description") or "")),
    }


def _get_location(item: dict[str, Any]) -> str:
    candidate = item.get("candidate_required_location") or item.get("job_type") or "Remote"
    return str(candidate).strip() or "Remote"


def _clean_text(text: str) -> str:
    without_html = re.sub(r"<[^>]+>", " ", text)
    return re.sub(r"\s+", " ", without_html).strip()
