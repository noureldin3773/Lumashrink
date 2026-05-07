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


SOURCE = "Remote.co"
URL = "https://remote.co/remote-jobs/design/"
BASE_URL = "https://remote.co"
HEADERS = {"User-Agent": "Mozilla/5.0", "Accept": "text/html"}

Job = dict[str, Any]


def fetch_remoteco_jobs(timeout: int = 12) -> list[Job]:
    if requests is None:
        raise RuntimeError("The requests package is not installed. Run: pip install -r requirements.txt")
    if BeautifulSoup is None:
        raise RuntimeError("The beautifulsoup4 package is not installed. Run: pip install -r requirements.txt")

    try:
        response = requests.get(URL, headers=HEADERS, timeout=timeout)
    except requests.RequestException as error:
        print(f"Remote.co request failed. Skipping Remote.co: {error}")
        return []
    response.raise_for_status()

    soup = BeautifulSoup(response.text, "html.parser")
    raw_jobs = _parse_jobs(soup)
    jobs = [job for job in raw_jobs if _is_design_title(job["title"])]
    print(f"Remote.co total jobs fetched: {len(raw_jobs)}")
    print(f"Remote.co total design jobs kept: {len(jobs)}")
    print(f"Remote.co total rejected by title: {len(raw_jobs) - len(jobs)}")
    return jobs


def _parse_jobs(soup: Any) -> list[Job]:
    jobs = []
    seen_links: set[str] = set()
    for link in soup.select('a[href*="/remote-jobs/"]'):
        title = _clean_text(link.get_text(" ", strip=True))
        href = str(link.get("href") or "")
        if not title or href in seen_links or "remote-jobs/design" in href:
            continue
        seen_links.add(href)
        container = link.find_parent(["li", "article", "div"])
        text = _clean_text(container.get_text(" ", strip=True)) if container else title
        jobs.append(
            {
                "company": "",
                "title": title,
                "link": urljoin(BASE_URL, href),
                "source": SOURCE,
                "location": "Remote",
                "salary": "",
                "description": text,
            }
        )
    return jobs


def _clean_text(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()
