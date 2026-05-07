from typing import Any


Job = dict[str, Any]

SKILL_KEYWORDS = {
    "Figma": ("figma",),
    "UX Research": ("ux research", "user research"),
    "UI Design": ("ui design", "user interface"),
    "Prototyping": ("prototyping", "prototype"),
    "Design Systems": ("design systems", "design system"),
    "SaaS": ("saas",),
    "AI": ("ai", "artificial intelligence"),
    "Fintech": ("fintech", "finance", "financial"),
    "B2B": ("b2b",),
    "Mobile App Design": ("mobile app", "mobile apps", "ios", "android"),
    "Web App Design": ("web app", "web apps", "web application", "web applications"),
    "Usability Testing": ("usability testing", "user testing"),
    "Product Strategy": ("product strategy", "product thinking"),
    "Handoff": ("handoff", "developer handoff", "development handoff"),
}


def calculate_fit_score(job: Job, current_cv: str) -> dict[str, Any]:
    job_text = _normalize_text(f"{job.get('title', '')} {job.get('description', '')}")
    cv_text = _normalize_text(current_cv)

    required_skills = _extract_skills(job_text)
    matched_skills = [skill for skill in required_skills if _has_skill(cv_text, skill)]
    missing_skills = [skill for skill in required_skills if skill not in matched_skills]

    if not required_skills:
        fit_score = 50
    else:
        fit_score = round((len(matched_skills) / len(required_skills)) * 100)

    fit_score = max(0, min(100, fit_score))

    return {
        "fit_score": fit_score,
        "matched_skills": matched_skills,
        "missing_skills": missing_skills,
        "fit_summary": _build_fit_summary(fit_score, matched_skills, missing_skills),
        "recommendation": _recommendation(fit_score),
    }


def _extract_skills(text: str) -> list[str]:
    return [skill for skill in SKILL_KEYWORDS if _has_skill(text, skill)]


def _has_skill(text: str, skill: str) -> bool:
    return any(keyword in text for keyword in SKILL_KEYWORDS[skill])


def _build_fit_summary(fit_score: int, matched_skills: list[str], missing_skills: list[str]) -> str:
    matched = ", ".join(matched_skills) if matched_skills else "no direct keyword matches"
    missing = ", ".join(missing_skills) if missing_skills else "no major missing skills found"
    return f"{fit_score}% fit based on matched skills: {matched}. Missing or less visible in CV: {missing}."


def _recommendation(fit_score: int) -> str:
    if fit_score >= 75:
        return "Strong Apply"
    if fit_score >= 60:
        return "Apply"
    if fit_score >= 45:
        return "Maybe"
    return "Skip"


def _normalize_text(text: str) -> str:
    return " ".join(str(text).lower().split())
