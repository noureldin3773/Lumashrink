from __future__ import annotations

import re
from typing import Any

from scrapers.remoteok import _is_design_title

try:
    import requests
except ImportError:
    requests = None


SOURCE = "Working Nomads"
API_URL = "https://www.workingnomads.com/jobsapi/_search"

Job = dict[str, Any]


def fetch_workingnomads_jobs(timeout: int = 20) -> list[Job]:
    if requests is None:
        raise RuntimeError("The requests package is not installed. Run: pip install -r requirements.txt")

    payload = {
        "track_total_hits": True,
        "from": 0,
        "size": 50,
        "_source": [
            "company",
            "category_name",
            "locations",
            "location_base",
            "salary_range",
            "salary_range_short",
            "id",
            "slug",
            "title",
            "tags",
            "description",
            "annual_salary_usd",
        ],
        "sort": [{"pub_date": {"order": "desc"}}],
        "query": {"bool": {"filter": [{"terms": {"category_name.raw": ["Design"]}}]}},
    }
    response = requests.post(API_URL, json=payload, timeout=timeout)
    response.raise_for_status()

    hits = response.json().get("hits", {}).get("hits", [])
    raw_jobs = [_parse_job(hit.get("_source", {})) for hit in hits if isinstance(hit, dict)]
    jobs = [job for job in raw_jobs if _is_design_title(job["title"])]

    print(f"Working Nomads total jobs fetched: {len(raw_jobs)}")
    print(f"Working Nomads total design jobs kept: {len(jobs)}")
    print(f"Working Nomads total rejected by title: {len(raw_jobs) - len(jobs)}")
    return jobs


def _parse_job(item: dict[str, Any]) -> Job:
    slug = str(item.get("slug") or "").strip()
    salary = str(item.get("salary_range_short") or item.get("salary_range") or "").strip()
    if not salary and item.get("annual_salary_usd"):
        salary = f"${int(item['annual_salary_usd']):,}/year"

    locations = item.get("locations") or []
    location = ", ".join(str(location) for location in locations) or str(item.get("location_base") or "Remote")

    return {
        "company": str(item.get("company") or "").strip(),
        "title": str(item.get("title") or "").strip(),
        "link": f"https://www.workingnomads.com/jobs/{slug}" if slug else "https://www.workingnomads.com/remote-design-jobs",
        "source": SOURCE,
        "location": location,
        "salary": salary,
        "description": _clean_html(str(item.get("description") or "")),
    }


def _clean_html(text: str) -> str:
    without_html = re.sub(r"<[^>]+>", " ", text)
    return re.sub(r"\s+", " ", without_html).strip()
