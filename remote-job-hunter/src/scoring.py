from __future__ import annotations

import re
from typing import Any


Job = dict[str, Any]


REMOTE_WORLDWIDE_TERMS = ("remote worldwide", "worldwide", "global remote")
POSITIVE_KEYWORDS = ("ai", "saas", "fintech", "b2b", "startup", "design system")
SKILL_KEYWORDS = ("figma", "design systems", "ux research", "product strategy")
TARGET_TITLES = ("senior product designer", "product designer")
NO_SALARY_VALUES = ("", "n/a", "not listed", "unknown", "none")


def score_job(job: Job, config: dict[str, str]) -> Job:
    """Score a job and return a copy with score metadata."""
    title = str(job.get("title", "")).lower()
    location = str(job.get("location", "")).lower()
    salary = str(job.get("salary", "")).lower()
    description = str(job.get("description", "")).lower()
    location_and_description = f"{location} {description}"

    score = 0
    matched_signals: list[str] = []

    score = _add(score, matched_signals, 30, "Remote worldwide/global remote", _contains_any(location_and_description, REMOTE_WORLDWIDE_TERMS))
    score = _add(score, matched_signals, 25, "Visible salary at or above $3,000/month", _salary_above_minimum(salary))
    score = _add(score, matched_signals, 20, "Target product design title", _contains_any(title, TARGET_TITLES))
    score = _add(score, matched_signals, 15, "Relevant product/company keyword", _contains_keyword(description, POSITIVE_KEYWORDS))
    score = _add(score, matched_signals, 10, "Remote-first", "remote-first" in description)
    score = _add(score, matched_signals, 10, "Core product design skill keyword", _contains_keyword(description, SKILL_KEYWORDS))

    score = _add(score, matched_signals, -50, "Onsite only", _contains_any(location_and_description, ("onsite only", "on-site only")))
    score = _add(score, matched_signals, -50, "Hybrid only", "hybrid only" in location_and_description)
    score = _add(score, matched_signals, -40, "Internship or junior role", _contains_any(f"{title} {description}", ("intern", "internship", "junior")))
    score = _add(score, matched_signals, -40, "Volunteer or unpaid", _contains_any(description, ("volunteer", "unpaid")))
    score = _add(score, matched_signals, -30, "No salary listed", salary.strip() in NO_SALARY_VALUES)
    score = _add(score, matched_signals, -30, "Graphic/social media designer role", _contains_any(f"{title} {description}", ("graphic designer", "social media designer")))

    scored_job = job.copy()
    scored_job["match_score"] = score
    scored_job["priority"] = get_priority(score)
    scored_job["matched_signals"] = matched_signals
    return scored_job


def score_jobs(jobs: list[Job], config: dict[str, str]) -> list[Job]:
    return [score_job(job, config) for job in jobs]


def get_priority(score: int) -> str:
    if score < 10:
        return "Reject"
    if score >= 60:
        return "High"
    if score >= 35:
        return "Medium"
    return "Low"


def _add(score: int, reasons: list[str], points: int, reason: str, condition: bool) -> int:
    if condition:
        reasons.append(f"{points:+} {reason}")
        return score + points
    return score


def _contains_any(text: str, terms: tuple[str, ...]) -> bool:
    return any(term in text for term in terms)


def _contains_keyword(text: str, terms: tuple[str, ...]) -> bool:
    return any(re.search(rf"(?<![a-z0-9]){re.escape(term)}(?![a-z0-9])", text) for term in terms)


def _salary_above_minimum(salary: str) -> bool:
    if salary.strip() in NO_SALARY_VALUES:
        return False

    numbers = [int(value.replace(",", "")) for value in re.findall(r"\d[\d,]*", salary)]
    if not numbers:
        return False

    if "year" in salary or "annual" in salary:
        numbers = [number // 12 for number in numbers]

    return any(number >= 3000 for number in numbers)
