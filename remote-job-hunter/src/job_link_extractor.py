from urllib.parse import urlparse
from typing import Any
import re

import requests
from bs4 import BeautifulSoup


JobExtract = dict[str, Any]
BLOCKED_DOMAINS = ("linkedin.com", "indeed.com", "glassdoor.com")


def extract_job_from_url(url: str) -> JobExtract:
    clean_url = str(url or "").strip()
    result: JobExtract = {
        "title": "",
        "company": "",
        "description": "",
        "location": "",
        "salary": "",
        "posted_date": "Unknown",
        "job_age_days": "Unknown",
        "needs_manual_description": False,
    }
    if not clean_url:
        result["needs_manual_description"] = True
        return result

    if _is_restricted_domain(clean_url):
        result["needs_manual_description"] = True
        return result

    try:
        response = requests.get(clean_url, headers=_headers(), timeout=20)
        response.raise_for_status()
    except Exception:
        result["needs_manual_description"] = True
        return result

    soup = BeautifulSoup(response.text, "html.parser")
    result["title"] = _extract_title(soup)
    result["company"] = _extract_company(soup, result["title"])
    result["description"] = _extract_description(soup)
    result["location"] = _extract_location(soup, response.text)
    result["salary"] = _extract_salary(soup, response.text)
    age_days = _extract_job_age_days(response.text)
    if age_days is not None:
        result["job_age_days"] = str(age_days)

    confidence = _confidence_score(result)
    result["needs_manual_description"] = confidence < 2 or not result["description"]
    return result


def extract_job_from_description(text: str) -> JobExtract:
    description = str(text or "").strip()
    result: JobExtract = {
        "title": _extract_title_from_text(description),
        "company": _extract_company_from_text(description),
        "description": description,
        "location": _extract_location_from_text(description),
        "salary": _extract_salary_from_text(description),
        "posted_date": _extract_posted_date_from_text(description) or "Unknown",
        "job_age_days": "Unknown",
        "needs_manual_description": not bool(description),
    }
    if result["posted_date"] != "Unknown":
        age_days = _extract_job_age_days(description)
        if age_days is not None:
            result["job_age_days"] = str(age_days)
    return result


def _headers() -> dict[str, str]:
    return {
        "User-Agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        )
    }


def _is_restricted_domain(url: str) -> bool:
    netloc = urlparse(url).netloc.lower()
    return any(domain in netloc for domain in BLOCKED_DOMAINS)


def _extract_title(soup: BeautifulSoup) -> str:
    h1 = soup.find("h1")
    if h1:
        title = h1.get_text(" ", strip=True)
        if title:
            return title
    if soup.title and soup.title.string:
        return soup.title.string.strip()
    return ""


def _extract_company(soup: BeautifulSoup, title: str) -> str:
    for selector in ("[data-company]", ".company", ".job-company", ".company-name"):
        tag = soup.select_one(selector)
        if tag:
            text = tag.get_text(" ", strip=True)
            if text:
                return text

    title_lower = title.lower()
    if " at " in title_lower:
        return title.split(" at ", 1)[-1].strip()
    if " - " in title:
        return title.split(" - ", 1)[0].strip()
    return ""


def _extract_description(soup: BeautifulSoup) -> str:
    meta = soup.find("meta", attrs={"name": "description"}) or soup.find("meta", attrs={"property": "og:description"})
    meta_text = str(meta.get("content", "")).strip() if meta else ""

    paragraphs = [p.get_text(" ", strip=True) for p in soup.find_all("p")]
    paragraph_text = "\n".join([text for text in paragraphs if len(text.split()) >= 8][:8]).strip()

    if paragraph_text and meta_text:
        return f"{meta_text}\n\n{paragraph_text}"
    return paragraph_text or meta_text


def _extract_location(soup: BeautifulSoup, html_text: str) -> str:
    for selector in (".location", "[data-location]", ".job-location"):
        tag = soup.select_one(selector)
        if tag:
            text = tag.get_text(" ", strip=True)
            if text:
                return text

    return _find_visible_hint(html_text, ("remote", "worldwide", "global", "location"))


def _extract_salary(soup: BeautifulSoup, html_text: str) -> str:
    for selector in (".salary", "[data-salary]", ".job-salary"):
        tag = soup.select_one(selector)
        if tag:
            text = tag.get_text(" ", strip=True)
            if text:
                return text

    return _find_visible_hint(html_text, ("$", "salary", "/month", "/year", "k"))


def _find_visible_hint(text: str, hints: tuple[str, ...]) -> str:
    lower = text.lower()
    for hint in hints:
        index = lower.find(hint.lower())
        if index == -1:
            continue
        start = max(0, index - 70)
        end = min(len(text), index + 140)
        snippet = " ".join(text[start:end].split())
        if snippet:
            return snippet[:180]
    return ""


def _confidence_score(data: JobExtract) -> int:
    score = 0
    if data.get("title"):
        score += 1
    if data.get("company"):
        score += 1
    if data.get("description"):
        score += 1
    if data.get("location"):
        score += 1
    if data.get("salary"):
        score += 1
    return score


def _extract_job_age_days(html_text: str) -> Any:
    text = str(html_text or "").lower()
    match = re.search(r"(\d+)\s+(day|days)\s+ago", text)
    if match:
        return int(match.group(1))
    if "today" in text or "just posted" in text:
        return 0
    if "yesterday" in text:
        return 1
    return None


def _extract_title_from_text(text: str) -> str:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    for line in lines[:8]:
        lower = line.lower()
        if any(term in lower for term in ("product designer", "ux designer", "ui designer", "design lead", "head of design")):
            return line
    return lines[0] if lines else ""


def _extract_company_from_text(text: str) -> str:
    patterns = [
        r"company[:\s]+([^\n,]+)",
        r"at\s+([A-Z][A-Za-z0-9&\-\s]{2,40})",
    ]
    for pattern in patterns:
        match = re.search(pattern, text, flags=re.IGNORECASE)
        if match:
            return match.group(1).strip(" -:")
    return ""


def _extract_location_from_text(text: str) -> str:
    match = re.search(r"(remote|worldwide|global|united states|europe|uk|canada|egypt|cairo)", text, flags=re.IGNORECASE)
    return match.group(1).strip() if match else ""


def _extract_salary_from_text(text: str) -> str:
    match = re.search(r"(\$[\d,]+(?:\s*-\s*\$[\d,]+)?(?:\s*/\s*(month|year))?)", text, flags=re.IGNORECASE)
    return match.group(1).strip() if match else ""


def _extract_posted_date_from_text(text: str) -> str:
    match = re.search(r"(\d+\s+days?\s+ago|today|yesterday|\d{4}-\d{2}-\d{2}|[A-Za-z]{3,9}\s+\d{1,2},\s*\d{4})", text, flags=re.IGNORECASE)
    return match.group(1).strip() if match else ""
