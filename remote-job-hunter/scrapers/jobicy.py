from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from typing import Any

from scrapers.remoteok import _is_design_title

try:
    import requests
except ImportError:
    requests = None


SOURCE = "Jobicy"
RSS_URL = "https://jobicy.com/jobs-rss-feed"
HEADERS = {"User-Agent": "Mozilla/5.0", "Accept": "application/rss+xml,application/xml,text/xml,*/*"}

Job = dict[str, Any]


def fetch_jobicy_jobs(timeout: int = 20) -> list[Job]:
    if requests is None:
        raise RuntimeError("The requests package is not installed. Run: pip install -r requirements.txt")

    response = requests.get(RSS_URL, headers=HEADERS, timeout=timeout)
    if response.status_code == 403:
        print("Jobicy returned 403/Cloudflare challenge. Skipping Jobicy for this run.")
        return []
    response.raise_for_status()

    raw_jobs = _parse_rss(response.text)
    jobs = [job for job in raw_jobs if _is_design_title(job["title"])]
    print(f"Jobicy total jobs fetched: {len(raw_jobs)}")
    print(f"Jobicy total design jobs kept: {len(jobs)}")
    print(f"Jobicy total rejected by title: {len(raw_jobs) - len(jobs)}")
    return jobs


def _parse_rss(text: str) -> list[Job]:
    try:
        root = ET.fromstring(text)
    except ET.ParseError:
        return []

    jobs = []
    for item in root.findall(".//item"):
        title = _node_text(item, "title")
        jobs.append(
            {
                "company": "",
                "title": title,
                "link": _node_text(item, "link"),
                "source": SOURCE,
                "location": "Remote",
                "salary": "",
                "description": _clean_html(_node_text(item, "description")),
            }
        )
    return jobs


def _node_text(item: Any, tag: str) -> str:
    node = item.find(tag)
    return (node.text or "").strip() if node is not None else ""


def _clean_html(text: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", text)).strip()
