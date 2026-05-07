from __future__ import annotations

import re
from typing import Any
from urllib.parse import urljoin

from scrapers.remoteok import _is_design_title

try:
    import requests
except ImportError:
    requests = None

try:
    from bs4 import BeautifulSoup
except ImportError:
    BeautifulSoup = None


WEWORKREMOTELY_URL = "https://weworkremotely.com/categories/remote-design-jobs"
BASE_URL = "https://weworkremotely.com"
SOURCE = "We Work Remotely"
HEADERS = {
    "User-Agent": "remote-job-hunter/0.1 (+https://example.com)",
    "Accept": "text/html,application/xhtml+xml",
}

Job = dict[str, Any]


def fetch_weworkremotely_jobs(timeout: int = 20) -> list[Job]:
    if requests is None:
        raise RuntimeError("The requests package is not installed. Run: pip install -r requirements.txt")
    if BeautifulSoup is None:
        raise RuntimeError("The beautifulsoup4 package is not installed. Run: pip install -r requirements.txt")

    response = requests.get(WEWORKREMOTELY_URL, headers=HEADERS, timeout=timeout)
    response.raise_for_status()

    soup = BeautifulSoup(response.text, "html.parser")
    raw_jobs = _extract_job_items(soup)
    design_jobs: list[Job] = []
    rejected_by_title = 0

    for item in raw_jobs:
        job = _parse_job(item)
        if not job["title"]:
            continue

        if _is_design_title(job["title"]):
            design_jobs.append(job)
        else:
            print(f"REJECTED TITLE: {job['title']}")
            rejected_by_title += 1

    print(f"We Work Remotely total jobs fetched: {len(raw_jobs)}")
    print(f"We Work Remotely total design jobs kept: {len(design_jobs)}")
    print(f"We Work Remotely total rejected by title: {rejected_by_title}")

    return design_jobs


def _extract_job_items(soup: Any) -> list[Any]:
    items = []
    seen_links: set[str] = set()

    for link in soup.select('a[href^="/remote-jobs/"]'):
        href = str(link.get("href") or "")
        if not href or href in seen_links:
            continue

        seen_links.add(href)
        items.append(link)

    return items


def _parse_job(item: Any) -> Job:
    company = _get_text(item, ".company")
    title = _get_text(item, ".title")
    location = _get_text(item, ".region")
    link = urljoin(BASE_URL, str(item.get("href") or "").strip())

    description = " ".join(part for part in (title, company, location) if part)

    return {
        "company": company,
        "title": title,
        "link": link,
        "source": SOURCE,
        "location": location or "Remote",
        "salary": "",
        "description": _clean_text(description),
    }


def _get_text(item: Any, selector: str) -> str:
    element = item.select_one(selector)
    if element is None:
        return ""

    return _clean_text(element.get_text(" ", strip=True))


def _clean_text(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()
