from __future__ import annotations

import html
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


HIMALAYAS_URL = "https://himalayas.app/jobs"
HIMALAYAS_API_SEARCH_URL = "https://himalayas.app/jobs/api/search"
BASE_URL = "https://himalayas.app"
SOURCE = "Himalayas"
SEARCH_QUERIES = (
    "product designer",
    "ux designer",
    "ui designer",
    "design lead",
    "design manager",
    "ux researcher",
)
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Cache-Control": "no-cache",
    "Pragma": "no-cache",
    "Referer": "https://himalayas.app/",
    "Upgrade-Insecure-Requests": "1",
}

Job = dict[str, Any]


def fetch_himalayas_jobs(timeout: int = 20) -> list[Job]:
    if requests is None:
        raise RuntimeError("The requests package is not installed. Run: pip install -r requirements.txt")

    api_jobs = _fetch_himalayas_api_jobs(timeout)
    if api_jobs:
        return _filter_design_jobs(api_jobs)

    if BeautifulSoup is None:
        raise RuntimeError("The beautifulsoup4 package is not installed. Run: pip install -r requirements.txt")

    response = _fetch_himalayas_page(timeout)

    soup = BeautifulSoup(response.text, "html.parser")
    raw_jobs = _extract_job_items(soup, response.text)
    return _filter_design_jobs(raw_jobs)


def _filter_design_jobs(raw_jobs: list[Job]) -> list[Job]:
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

    print(f"Himalayas total jobs fetched: {len(raw_jobs)}")
    print(f"Himalayas total design jobs kept: {len(design_jobs)}")
    print(f"Himalayas total rejected by title: {rejected_by_title}")

    return design_jobs


def _fetch_himalayas_api_jobs(timeout: int) -> list[Job]:
    session = requests.Session()
    session.headers.update(
        {
            "User-Agent": HEADERS["User-Agent"],
            "Accept": "application/json",
            "Accept-Language": HEADERS["Accept-Language"],
            "Referer": HIMALAYAS_URL,
        }
    )

    jobs: list[Job] = []
    seen_links: set[str] = set()

    for query in SEARCH_QUERIES:
        response = session.get(
            HIMALAYAS_API_SEARCH_URL,
            params={"q": query, "sort": "recent", "page": 1},
            timeout=timeout,
        )
        if response.status_code == 403:
            print(f"Himalayas API returned 403 for query: {query}")
            continue
        response.raise_for_status()

        payload = response.json()
        raw_jobs = payload.get("jobs", []) if isinstance(payload, dict) else []
        for item in raw_jobs:
            if not isinstance(item, dict):
                continue

            job = _parse_api_job(item)
            link = str(job.get("link", "")).strip()
            if not link or link in seen_links:
                continue

            seen_links.add(link)
            jobs.append(job)

    return jobs


def _parse_api_job(item: dict[str, Any]) -> Job:
    description = _clean_html(str(item.get("description") or item.get("excerpt") or ""))
    categories = " ".join(str(category) for category in item.get("categories", []) or [])
    description = _clean_text(" ".join(part for part in (description, categories) if part))

    return {
        "company": str(item.get("companyName") or "").strip(),
        "title": str(item.get("title") or "").strip(),
        "link": str(item.get("applicationLink") or item.get("guid") or "").strip(),
        "source": SOURCE,
        "location": _format_api_location(item),
        "salary": _format_api_salary(item),
        "description": description,
    }


def _format_api_location(item: dict[str, Any]) -> str:
    restrictions = item.get("locationRestrictions") or []
    if restrictions:
        return ", ".join(str(location) for location in restrictions)
    return "Remote Worldwide"


def _format_api_salary(item: dict[str, Any]) -> str:
    minimum = item.get("minSalary")
    maximum = item.get("maxSalary")
    currency = str(item.get("currency") or "USD").strip()

    if minimum and maximum:
        return f"{currency} {int(minimum):,}-{int(maximum):,}/year"
    if minimum:
        return f"{currency} {int(minimum):,}+/year"
    if maximum:
        return f"Up to {currency} {int(maximum):,}/year"
    return ""


def _fetch_himalayas_page(timeout: int) -> Any:
    session = requests.Session()
    session.headers.update(HEADERS)

    response = session.get(HIMALAYAS_URL, timeout=timeout, allow_redirects=True)
    if response.status_code == 403:
        fallback_url = f"{HIMALAYAS_URL}?q=product%20designer"
        response = session.get(fallback_url, timeout=timeout, allow_redirects=True)

    if response.status_code == 403:
        print("Himalayas returned 403 Forbidden. Skipping Himalayas for this run.")
        return _empty_response()

    response.raise_for_status()
    return response


def _empty_response() -> Any:
    class EmptyResponse:
        text = ""

    return EmptyResponse()


def _extract_job_items(soup: Any, html_text: str) -> list[Job]:
    jobs = _extract_jobs_from_html_links(soup)
    if jobs:
        return jobs

    return _extract_jobs_from_next_payload(html_text)


def _extract_jobs_from_html_links(soup: Any) -> list[Job]:
    jobs: list[Job] = []
    seen_links: set[str] = set()

    for link in soup.select('a[href*="/companies/"][href*="/jobs/"]'):
        href = str(link.get("href") or "").strip()
        absolute_link = urljoin(BASE_URL, href)
        if absolute_link in seen_links:
            continue

        title = _clean_text(link.get_text(" ", strip=True))
        if not title:
            continue

        card = link.find_parent("article") or link.find_parent("li") or link.parent
        company = _find_company(card, href)
        location = _find_location(card)
        salary = _find_salary(card)
        description = _clean_text(" ".join(part for part in (title, company, location, salary) if part))

        jobs.append(
            {
                "company": company,
                "title": title,
                "link": absolute_link,
                "source": SOURCE,
                "location": location or "Remote",
                "salary": salary,
                "description": description,
            }
        )
        seen_links.add(absolute_link)

    return jobs


def _extract_jobs_from_next_payload(html_text: str) -> list[Job]:
    jobs: list[Job] = []
    article_starts = [
        match.start()
        for match in re.finditer(
            r'\\"\$\\",\\"article\\",\\"https://himalayas\.app/companies/[^\\"]+/jobs/[^\\"]+\\"',
            html_text,
        )
    ]

    for index, start in enumerate(article_starts):
        end = article_starts[index + 1] if index + 1 < len(article_starts) else len(html_text)
        segment = html_text[start:end]
        job = _parse_next_payload_segment(segment)
        if job["title"] and job["link"]:
            jobs.append(job)

    return jobs


def _parse_next_payload_segment(segment: str) -> Job:
    article_link = _match_first(r'\\"article\\",\\"(?P<link>https://himalayas\.app/companies/[^\\"]+/jobs/[^\\"]+)\\"', segment, "link")
    title_match = re.search(
        r'\\"href\\":\\"/companies/.+?/jobs/.+?\\",\\"prefetch\\":false,\\"children\\":\\"(?P<title>.+?)\\"',
        segment,
    )
    title = title_match.group("title").strip() if title_match else ""
    segment_after_title = segment[title_match.end() :] if title_match else segment
    company_slug = _match_first(r"himalayas\.app/companies/(?P<slug>[^/]+)/jobs/", article_link, "slug")
    company = _match_first(
        r'\\"href\\":\\"/companies/[^\\"]+\\",\\"prefetch\\":false,\\"children\\":\[\\"(?P<company>[^\\"]+)',
        segment_after_title,
        "company",
    ) or _company_from_slug(company_slug)
    location = _match_first(r'\\"(?P<location>[A-Za-z, +]+ only)\\"', segment, "location")
    salary = _match_first(r"Salary:\s*(?P<salary>[^\\\"]+)", segment, "salary")
    tags = _extract_tags(segment)
    description = _clean_text(" ".join(part for part in (title, " ".join(tags), location, salary) if part))

    return {
        "company": _decode(company),
        "title": _decode(title),
        "link": _decode(article_link),
        "source": SOURCE,
        "location": _decode(location) or "Remote",
        "salary": _decode(salary),
        "description": _decode(description),
    }


def _parse_job(item: Job) -> Job:
    return item


def _find_company(card: Any, job_href: str) -> str:
    if card is not None:
        company_link = card.select_one('a[href^="/companies/"]:not([href*="/jobs/"])')
        if company_link is not None:
            company = _clean_text(company_link.get_text(" ", strip=True))
            if company:
                return company

    slug_match = re.search(r"/companies/([^/]+)/jobs/", job_href)
    return _company_from_slug(slug_match.group(1) if slug_match else "")


def _find_location(card: Any) -> str:
    if card is None:
        return ""

    text = _clean_text(card.get_text(" ", strip=True))
    match = re.search(r"([A-Z][A-Za-z,\s+]+ only|Remote|Worldwide)", text)
    return match.group(1).strip() if match else ""


def _find_salary(card: Any) -> str:
    if card is None:
        return ""

    text = _clean_text(card.get_text(" ", strip=True))
    match = re.search(r"Salary:\s*([^\n]+?)(?:\s{2,}|$)", text)
    return match.group(1).strip() if match else ""


def _extract_tags(segment: str) -> list[str]:
    tags = []
    for value in re.findall(r'\\"children\\":\\"([^\\"]{2,50})\\"', segment):
        decoded = _decode(value)
        if decoded and decoded not in tags and not decoded.endswith("ago"):
            tags.append(decoded)

    return tags[:8]


def _match_first(pattern: str, text: str, group_name: str) -> str:
    match = re.search(pattern, text)
    return match.group(group_name).strip() if match else ""


def _company_from_slug(slug: str) -> str:
    return " ".join(part.capitalize() for part in slug.split("-") if part)


def _decode(value: str) -> str:
    return html.unescape(value.replace(r"\u0026", "&").replace(r"\/", "/")).strip()


def _clean_html(text: str) -> str:
    without_html = re.sub(r"<[^>]+>", " ", text)
    return _decode(without_html)


def _clean_text(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()
