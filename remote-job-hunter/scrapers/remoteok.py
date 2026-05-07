from __future__ import annotations

import re
from typing import Any

try:
    import requests
except ImportError:
    requests = None


REMOTEOK_API_URL = "https://remoteok.com/api"
REMOTEOK_JOB_URL = "https://remoteok.com/remote-jobs/{job_id}"
SOURCE = "RemoteOK"
HEADERS = {
    "User-Agent": "remote-job-hunter/0.1 (+https://example.com)",
    "Accept": "application/json",
}
BROAD_INCLUDE_TITLE_KEYWORDS = (
    "product designer",
    "product design",
    "ux designer",
    "ui designer",
    "ux/ui",
    "ui/ux",
    "user experience",
    "experience designer",
    "interaction designer",
    "digital product designer",
    "web designer",
    "app designer",
    "mobile designer",
    "visual designer",
    "product design lead",
    "design lead",
    "head of design",
    "founding designer",
    "design manager",
    "ux researcher",
    "product researcher",
)
BAD_FIT_TITLE_KEYWORDS = (
    "graphic designer",
    "brand designer",
    "marketing designer",
    "social media",
    "video editor",
    "motion designer",
    "illustrator",
    "3d artist",
    "intern",
    "internship",
    "junior",
    "engineer",
    "developer",
    "frontend",
    "backend",
    "fullstack",
    "software",
    "recruiter",
    "sales",
    "customer support",
)

Job = dict[str, Any]


def fetch_remoteok_jobs(timeout: int = 20) -> list[Job]:
    if requests is None:
        raise RuntimeError("The requests package is not installed. Run: pip install -r requirements.txt")

    response = requests.get(REMOTEOK_API_URL, headers=HEADERS, timeout=timeout)
    response.raise_for_status()

    payload = response.json()
    if not isinstance(payload, list):
        return []

    total_jobs_fetched = 0
    total_rejected_by_title = 0
    design_jobs: list[Job] = []

    for item in payload:
        if not _is_job_item(item):
            continue

        total_jobs_fetched += 1
        job = _parse_job(item)
        if _is_design_title(str(job.get("title", ""))):
            design_jobs.append(job)
        else:
            print(f"REJECTED TITLE: {job.get('title', '')}")
            total_rejected_by_title += 1

    print(f"RemoteOK total jobs fetched: {total_jobs_fetched}")
    print(f"RemoteOK total design jobs kept: {len(design_jobs)}")
    print(f"RemoteOK total rejected by title: {total_rejected_by_title}")

    return design_jobs


def _is_job_item(item: Any) -> bool:
    return isinstance(item, dict) and bool(item.get("id")) and bool(item.get("position"))


def _parse_job(item: dict[str, Any]) -> Job:
    job_id = str(item.get("id", "")).strip()
    description = _clean_text(str(item.get("description") or ""))

    return {
        "company": str(item.get("company") or "").strip(),
        "title": str(item.get("position") or "").strip(),
        "link": _get_job_link(item, job_id),
        "source": SOURCE,
        "location": _get_location(item),
        "salary": _get_salary(item),
        "description": description,
    }


def _is_design_title(title: str) -> bool:
    normalized_title = title.lower()
    has_good_keyword = any(keyword in normalized_title for keyword in BROAD_INCLUDE_TITLE_KEYWORDS)
    has_bad_keyword = any(keyword in normalized_title for keyword in BAD_FIT_TITLE_KEYWORDS)
    return has_good_keyword and not has_bad_keyword


def _get_job_link(item: dict[str, Any], job_id: str) -> str:
    for key in ("url", "slug"):
        value = str(item.get(key) or "").strip()
        if value.startswith("http"):
            return value
        if value.startswith("/"):
            return f"https://remoteok.com{value}"

    return REMOTEOK_JOB_URL.format(job_id=job_id)


def _get_location(item: dict[str, Any]) -> str:
    location = str(item.get("location") or "").strip()
    return location or "Remote"


def _get_salary(item: dict[str, Any]) -> str:
    salary_min = item.get("salary_min")
    salary_max = item.get("salary_max")

    if salary_min and salary_max:
        return f"${int(salary_min):,}-${int(salary_max):,}"
    if salary_min:
        return f"${int(salary_min):,}+"
    if salary_max:
        return f"Up to ${int(salary_max):,}"

    return ""


def _clean_text(text: str) -> str:
    without_html = re.sub(r"<[^>]+>", " ", text)
    return re.sub(r"\s+", " ", without_html).strip()
