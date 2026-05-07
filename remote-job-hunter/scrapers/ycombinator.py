from __future__ import annotations

import html
import json
import re
from typing import Any
from urllib.parse import urljoin

from scrapers.remoteok import _is_design_title

try:
    import requests
except ImportError:
    requests = None


SOURCE = "Y Combinator"
URL = "https://www.ycombinator.com/jobs?query=designer"
BASE_URL = "https://www.ycombinator.com"
HEADERS = {"User-Agent": "Mozilla/5.0", "Accept": "text/html"}

Job = dict[str, Any]


def fetch_ycombinator_jobs(timeout: int = 20) -> list[Job]:
    if requests is None:
        raise RuntimeError("The requests package is not installed. Run: pip install -r requirements.txt")

    response = requests.get(URL, headers=HEADERS, timeout=timeout)
    response.raise_for_status()

    postings = _extract_job_postings(response.text)
    raw_jobs = [_parse_job(posting) for posting in postings]
    jobs = [job for job in raw_jobs if _is_design_title(job["title"])]

    print(f"Y Combinator total jobs fetched: {len(raw_jobs)}")
    print(f"Y Combinator total design jobs kept: {len(jobs)}")
    print(f"Y Combinator total rejected by title: {len(raw_jobs) - len(jobs)}")
    return jobs


def _extract_job_postings(page_text: str) -> list[dict[str, Any]]:
    text = html.unescape(page_text)
    marker = '"jobPostings"'
    marker_index = text.find(marker)
    if marker_index == -1:
        return []

    start = text.find("[", marker_index)
    if start == -1:
        return []

    depth = 0
    in_string = False
    escaped = False
    for index in range(start, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        else:
            if char == '"':
                in_string = True
            elif char == "[":
                depth += 1
            elif char == "]":
                depth -= 1
                if depth == 0:
                    return json.loads(text[start : index + 1])

    return []


def _parse_job(item: dict[str, Any]) -> Job:
    skills = ", ".join(str(skill) for skill in item.get("skills", []) or [])
    description = " ".join(part for part in (item.get("companyOneLiner", ""), skills) if part)
    return {
        "company": str(item.get("companyName") or "").strip(),
        "title": str(item.get("title") or "").strip(),
        "link": urljoin(BASE_URL, str(item.get("url") or "")),
        "source": SOURCE,
        "location": str(item.get("location") or "Remote").strip(),
        "salary": str(item.get("salaryRange") or "").strip(),
        "description": description,
    }
