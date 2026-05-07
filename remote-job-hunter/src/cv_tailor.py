import re
import json
import os
from typing import Any

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None

try:
    from openai import OpenAI
except ImportError:
    OpenAI = None

from src.ai_runtime import call_json

Job = dict[str, Any]

SENIOR_CV_CONTEXT = """You are an expert Senior Product Designer resume writer.

Your task is to rewrite and enhance CV content to match a STRONG senior-level product designer (4–6+ years experience).

Goal: high-impact senior CV with ownership, product thinking, measurable results, business impact.

Core rule: Every bullet = [Action Verb] + [What was done] + [Impact / Result].

Mandatory: ownership, product thinking, measurable impact, systems thinking, collaboration, end-to-end process.
Avoid: generic phrases, weak verbs, tool-only bullets, repetition, vague statements.

Special role rule: Senior Product Designer — CNTXT AI is the strongest section and MUST have exactly 5 bullets.
"""
TOKEN_RULE = (
    "Token rule: Keep input compact. Reuse provided CV context and avoid repeating unchanged text. "
    "Tailor only what is needed for this job."
)

SECTION_ORDER = ("Name", "SUMMARY", "WORK EXPERIENCE", "SKILLS", "EDUCATION")
TRUTHFUL_KEYWORDS = (
    "AI",
    "SaaS",
    "Fintech",
    "Finance",
    "Education",
    "B2B",
    "UX research",
    "Design systems",
    "Product strategy",
    "UX flows",
    "Figma",
    "Dashboard",
    "Mobile",
    "Web",
)
ROLE_BULLET_CATEGORIES = {
    "impact": ("increase", "improved", "improve", "reduced", "growth", "engagement", "conversion", "retention", "kpi", "%"),
    "system": ("design system", "component", "ui kit", "pattern", "scalable", "consistency", "accessibility", "prototype", "figma"),
    "collaboration": ("collaborated", "partnered", "cross-functional", "pm", "engineer", "leadership", "strategy", "stakeholder", "workshop"),
}
ACTION_VERBS = ("Improved", "Built", "Partnered", "Optimized", "Delivered", "Shaped")


def tailor_cv(current_cv: str, job: Job, use_ai: bool = True) -> str:
    sections = _parse_sections(current_cv)
    title = str(job.get("title", "")).strip()
    description = str(job.get("description", "")).strip()
    job_text = f"{title} {description}"
    ai_sections = _tailor_with_ai(current_cv, sections, job) if use_ai else {}

    work_experience_text = ai_sections.get(
        "work_experience",
        _tailor_work_experience(sections.get("Work Experience", ""), job_text),
    )
    tailored_sections = {
        "Name": _format_header(sections.get("Name", "")),
        "SUMMARY": ai_sections.get("summary", _build_summary(job_text)),
        "WORK EXPERIENCE": _enforce_experience_quality(work_experience_text, job_text),
        "SKILLS": _tailor_skills(sections.get("Skills", ""), job_text),
        "EDUCATION": _normalize_bullet_section(sections.get("Education", "")),
    }

    return _render_cv(tailored_sections)


def _parse_sections(cv_text: str) -> dict[str, str]:
    matches = list(re.finditer(r"^#\s+(.+?)\s*$", cv_text, flags=re.MULTILINE))
    sections: dict[str, str] = {}

    if matches:
        first_heading_start = matches[0].start()
        if cv_text[:first_heading_start].strip():
            sections["Name"] = cv_text[:first_heading_start].strip()

    for index, match in enumerate(matches):
        heading = _normalize_heading(match.group(1))
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(cv_text)
        content = _strip_separators(cv_text[start:end])
        sections[heading] = content

    if "Name" not in sections and cv_text.strip():
        first_section = cv_text.split("# Summary", 1)[0].strip()
        sections["Name"] = first_section

    return sections


def _normalize_heading(heading: str) -> str:
    normalized = heading.strip().lower()
    if "summary" in normalized:
        return "Summary"
    if "work" in normalized and "experience" in normalized:
        return "Work Experience"
    if "skill" in normalized:
        return "Skills"
    if "education" in normalized:
        return "Education"
    return "Name"


def _build_summary(job_text: str) -> str:
    focus = _detect_focus(job_text)
    keywords = _matched_truthful_keywords(job_text)
    strengths = _summary_strengths(keywords)

    return (
        f"Senior Product Designer with 4+ years of experience designing {focus} products for web and mobile. "
        f"Strong in {strengths}, UX flows, prototyping, and developer-ready UI. "
        "Experienced with cross-functional teams, usability testing, and scalable design systems."
    )


def _tailor_work_experience(work_experience: str, job_text: str) -> str:
    experiences = _split_experience_blocks(work_experience)
    if not experiences:
        return work_experience.strip()

    chronological = sorted(experiences, key=_experience_start_date, reverse=True)
    return "\n\n".join(_highlight_relevant_bullets(block, job_text) for block in chronological).strip()


def _tailor_with_ai(current_cv: str, sections: dict[str, str], job: Job) -> dict[str, str]:
    if load_dotenv is None or OpenAI is None:
        return {}

    load_dotenv()
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        return {}

    work_experience = sections.get("Work Experience", "")
    experience_blocks = _split_experience_structured(work_experience)

    payload = _build_tailor_payload(current_cv, job, sections.get("Summary", ""), experience_blocks)
    parsed = call_json(
        feature="cv_tailoring",
        task_level="normal",
        payload=payload,
        schema_name="tailored_cv_sections",
        schema={
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "summary_text": {"type": "string"},
                "experience": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "additionalProperties": False,
                        "properties": {
                            "heading": {"type": "string"},
                            "bullets": {"type": "array", "items": {"type": "string"}},
                        },
                        "required": ["heading", "bullets"],
                    },
                },
            },
            "required": ["summary_text", "experience"],
        },
        job_key=str(job.get("link", "")) or f"{job.get('company','')}|{job.get('title','')}",
        max_output_tokens=300,
    )
    if not parsed:
        return {}
    return _parse_ai_tailor_dict(parsed, experience_blocks)


def _build_tailor_payload(
    current_cv: str,
    job: Job,
    current_summary: str,
    experience_blocks: list[dict[str, Any]],
) -> str:
    company = str(job.get("company", "")).strip()
    title = str(job.get("title", "")).strip()
    description = str(job.get("description", "")).strip()
    serialized_experience = json.dumps(experience_blocks, ensure_ascii=True, indent=2)

    return {
        "system": f"{SENIOR_CV_CONTEXT}\n\n{TOKEN_RULE}\nOptimize specifically for my CV data.",
        "user": {
            "job_description": f"Company: {company}\nTitle: {title}\nDescription: {description}",
            "cv_data": _compact_text(current_cv, max_chars=4500),
            "target_role": "Senior Product Designer",
            "current_summary": _compact_text(current_summary, max_chars=600),
            "current_work_experience_blocks": json.loads(serialized_experience),
            "rewrite_scope": ["summary", "work_experience_bullets"],
            "rules": {
                "keep_structure_identical": True,
                "keep_same_headings": True,
                "bullets_per_role": "3-5 (CNTXT AI must be exactly 5)",
                "no_invention": True,
                "senior_tone": True,
            },
        },
    }


def _compact_text(text: str, max_chars: int = 3000) -> str:
    return " ".join((text or "").split())[:max_chars]


def _parse_ai_tailor_dict(parsed: dict[str, Any], experience_blocks: list[dict[str, Any]]) -> dict[str, str]:
    summary_text = str(parsed.get("summary_text", "")).strip()

    ai_experience = parsed.get("experience", [])
    experience_text = _merge_ai_experience(experience_blocks, ai_experience)

    result: dict[str, str] = {}
    if summary_text:
        result["summary"] = summary_text
    if experience_text:
        result["work_experience"] = experience_text
    return result


def _split_experience_structured(work_experience: str) -> list[dict[str, Any]]:
    blocks = _split_experience_blocks(work_experience)
    structured = []
    for block in blocks:
        lines = [line for line in block.splitlines() if line.strip()]
        if not lines:
            continue
        heading = lines[0].strip()
        bullets = [line.strip() for line in lines[1:] if line.strip().startswith("-")]
        notes = [line.strip() for line in lines[1:] if line.strip() and not line.strip().startswith("-")]
        structured.append({"heading": heading, "bullets": bullets, "notes": notes})
    return structured


def _merge_ai_experience(experience_blocks: list[dict[str, Any]], ai_experience: Any) -> str:
    if not isinstance(ai_experience, list):
        return ""

    ai_by_heading: dict[str, list[str]] = {}
    for item in ai_experience:
        if not isinstance(item, dict):
            continue
        heading = str(item.get("heading", "")).strip()
        bullets = item.get("bullets", [])
        if not heading or not isinstance(bullets, list):
            continue
        cleaned = [f"- {str(bullet).strip().lstrip('-').strip()}" for bullet in bullets if str(bullet).strip()]
        ai_by_heading[heading] = cleaned

    merged_blocks = []
    for block in experience_blocks:
        heading = str(block.get("heading", "")).strip()
        original_bullets = block.get("bullets", [])
        notes = block.get("notes", [])
        if not heading:
            continue

        ai_bullets = ai_by_heading.get(heading, [])
        final_bullets = _normalize_bullet_count_for_role(heading, ai_bullets, original_bullets)

        merged_blocks.append("\n".join([heading, *final_bullets, *notes]).strip())

    return "\n\n".join(block for block in merged_blocks if block.strip()).strip()


def _split_experience_blocks(work_experience: str) -> list[str]:
    matches = list(re.finditer(r"^##\s+.+$", work_experience, flags=re.MULTILINE))
    if not matches:
        return [work_experience.strip()] if work_experience.strip() else []

    blocks = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(work_experience)
        blocks.append(work_experience[match.start() : end].strip())

    return blocks


def _experience_score(block: str, job_text: str) -> int:
    normalized_block = block.lower()
    normalized_job = job_text.lower()
    score = 0

    weighted_terms = {
        "ai": 5,
        "saas": 5,
        "fintech": 5,
        "finance": 5,
        "design system": 4,
        "ux flow": 4,
        "research": 3,
        "figma": 3,
        "mobile": 2,
        "web": 2,
        "dashboard": 3,
        "b2b": 3,
        "education": 3,
    }

    for term, weight in weighted_terms.items():
        if term in normalized_job and term in normalized_block:
            score += weight

    return score


def _highlight_relevant_bullets(block: str, job_text: str) -> str:
    lines = block.splitlines()
    heading = lines[0] if lines else ""
    bullets = [line for line in lines[1:] if line.strip().startswith("-")]
    other_lines = [line for line in lines[1:] if not line.strip().startswith("-")]

    improved_bullets = [_improve_bullet(bullet, job_text) for bullet in bullets]
    improved_bullets = _select_role_bullets(improved_bullets, job_text)

    return "\n".join([heading, *improved_bullets, *other_lines]).strip()


def _bullet_score(bullet: str, job_text: str) -> int:
    bullet_lower = bullet.lower()
    job_lower = job_text.lower()
    return sum(1 for keyword in _matched_truthful_keywords(job_lower) if keyword.lower() in bullet_lower)


def _improve_bullet(bullet: str, job_text: str) -> str:
    text = bullet.strip()
    lower_text = text.lower()
    lower_job = job_text.lower()

    if "design systems" in lower_job and "design system" in lower_text:
        return text.replace("Built", "Built and maintained").replace("reusable UI kits", "reusable UI kits for faster handoff")
    if ("ux flows" in lower_job or "workflow" in lower_job) and "ux flows" in lower_text:
        return text.replace("Built", "Structured").replace("Designed", "Designed and refined")
    if "product strategy" in lower_job and "product strategy" in lower_text:
        return text.replace("Contributed to", "Supported")

    return text


def _tailor_skills(skills: str, job_text: str) -> str:
    if not skills.strip():
        return skills.strip()

    sections = _split_skill_groups(skills)
    cleaned_groups = []
    for heading, content in sections:
        cleaned_items = _clean_skill_items(content)
        cleaned_items = _rank_skills_for_job(cleaned_items, job_text)[:8]
        if cleaned_items:
            cleaned_groups.append(f"## {heading}\n{', '.join(cleaned_items)}")

    return "\n\n".join(cleaned_groups).strip()


def _rank_skills_for_job(items: list[str], job_text: str) -> list[str]:
    normalized_job = job_text.lower()
    return sorted(
        items,
        key=lambda item: (0 if item.lower() in normalized_job else 1, len(item)),
    )


def _enforce_experience_quality(work_experience_text: str, job_text: str) -> str:
    blocks = _split_experience_blocks(work_experience_text)
    if not blocks:
        return work_experience_text.strip()

    rewritten_blocks = []
    used_openers: set[str] = set()
    for block in blocks:
        lines = [line for line in block.splitlines() if line.strip()]
        if not lines:
            continue
        heading = lines[0].strip()
        bullets = [line for line in lines[1:] if line.strip().startswith("-")]
        notes = [line for line in lines[1:] if line.strip() and not line.strip().startswith("-")]
        selected = _select_role_bullets(bullets, job_text, heading=heading)
        normalized = _diversify_openers(selected, used_openers)
        rewritten_blocks.append("\n".join([heading, *normalized, *notes]).strip())
    return "\n\n".join(rewritten_blocks).strip()


def _select_role_bullets(bullets: list[str], job_text: str, heading: str = "") -> list[str]:
    if not bullets:
        return bullets

    cleaned = [bullet if bullet.startswith("- ") else f"- {bullet.lstrip('-').strip()}" for bullet in bullets]
    buckets: dict[str, list[str]] = {key: [] for key in ROLE_BULLET_CATEGORIES}
    leftovers: list[str] = []
    for bullet in cleaned:
        lower = bullet.lower()
        matched = False
        for category, terms in ROLE_BULLET_CATEGORIES.items():
            if any(term in lower for term in terms):
                buckets[category].append(_improve_bullet(bullet, job_text))
                matched = True
                break
        if not matched:
            leftovers.append(_improve_bullet(bullet, job_text))

    ordered = []
    for category in ("impact", "system", "collaboration"):
        if buckets[category]:
            ordered.append(buckets[category][0])
        elif leftovers:
            ordered.append(leftovers.pop(0))
    min_count = 5 if _is_cntxt_role(heading) else 3
    max_count = 5
    while len(ordered) < min_count and leftovers:
        ordered.append(leftovers.pop(0))
    while len(ordered) < min_count and cleaned:
        ordered.append(cleaned[min(len(ordered), len(cleaned) - 1)])
    for bullet in leftovers:
        if len(ordered) >= max_count:
            break
        ordered.append(bullet)
    return ordered[:max_count]


def _is_cntxt_role(heading: str) -> bool:
    text = (heading or "").lower()
    return "cntxt" in text and "senior product designer" in text


def _normalize_bullet_count_for_role(heading: str, ai_bullets: list[str], original_bullets: list[str]) -> list[str]:
    min_count = 5 if _is_cntxt_role(heading) else 3
    max_count = 5
    source = ai_bullets if ai_bullets else original_bullets
    cleaned = [b if b.startswith("- ") else f"- {b.lstrip('-').strip()}" for b in source if str(b).strip()]
    if not cleaned:
        return cleaned
    while len(cleaned) < min_count:
        cleaned.append(cleaned[-1])
    return cleaned[:max_count]


def _diversify_openers(bullets: list[str], used_openers: set[str]) -> list[str]:
    diversified: list[str] = []
    verb_index = 0
    for bullet in bullets:
        text = bullet.lstrip("- ").strip()
        words = text.split()
        opener = words[0].lower() if words else ""
        if opener in used_openers or opener in {"led"}:
            replacement = ACTION_VERBS[verb_index % len(ACTION_VERBS)]
            verb_index += 1
            text = f"{replacement} {' '.join(words[1:])}".strip()
            words = text.split()
            opener = words[0].lower() if words else opener
        used_openers.add(opener)
        diversified.append(f"- {text}")
    return diversified


def _detect_focus(job_text: str) -> str:
    normalized = job_text.lower()
    focus_terms = []
    if "ai" in normalized:
        focus_terms.append("AI")
    if "saas" in normalized:
        focus_terms.append("SaaS")
    if "fintech" in normalized or "finance" in normalized:
        focus_terms.append("fintech")
    if "education" in normalized or "edtech" in normalized:
        focus_terms.append("education")

    if not focus_terms:
        return "product"
    if len(focus_terms) == 1:
        return focus_terms[0]
    if len(focus_terms) == 2:
        return f"{focus_terms[0]} and {focus_terms[1]}"
    return ", ".join(focus_terms[:-1]) + f", and {focus_terms[-1]}"


def _matched_truthful_keywords(job_text: str) -> list[str]:
    normalized = job_text.lower()
    return [keyword for keyword in TRUTHFUL_KEYWORDS if keyword.lower() in normalized]


def _render_cv(sections: dict[str, str]) -> str:
    rendered_sections = []
    for section in SECTION_ORDER:
        content = sections.get(section, "").strip()
        if not content:
            continue
        heading = "# Nour Eldin Abbas" if section == "Name" else f"# {section}"
        rendered_sections.append(f"{heading}\n{content}")

    return "\n\n---\n\n".join(rendered_sections).strip() + "\n"


def _strip_separators(text: str) -> str:
    lines = [line for line in text.strip().splitlines() if line.strip() != "---"]
    return "\n".join(lines).strip()


def _format_header(name_section: str) -> str:
    lines = [line.strip() for line in name_section.splitlines() if line.strip()]
    role = _extract_header_value(lines, ("role:",), default="Senior Product Designer")
    email = _extract_header_value(lines, ("email:",), default=_find_first(lines, "@"))
    phone = _extract_header_value(lines, ("phone:",), default=_find_phone(lines))
    location = _extract_header_value(lines, ("location:",), default=_find_location(lines))
    portfolio = _extract_header_value(lines, ("portfolio:",), default=_find_url(lines))

    contact_parts = [part for part in (email, phone, location, portfolio) if part]
    return "\n".join([role, " | ".join(contact_parts)]).strip()


def _extract_header_value(lines: list[str], prefixes: tuple[str, ...], default: str = "") -> str:
    for line in lines:
        lower = line.lower()
        for prefix in prefixes:
            if lower.startswith(prefix):
                return line.split(":", 1)[1].strip()
    return default


def _find_first(lines: list[str], needle: str) -> str:
    return next((line for line in lines if needle in line), "")


def _find_phone(lines: list[str]) -> str:
    return next((line for line in lines if re.search(r"\d{7,}", line)), "")


def _find_location(lines: list[str]) -> str:
    return next((line for line in lines if "cairo" in line.lower() or "egypt" in line.lower()), "")


def _find_url(lines: list[str]) -> str:
    return next((line for line in lines if "." in line and "@" not in line and not line.lower().startswith("role:")), "")


def _summary_strengths(keywords: list[str]) -> str:
    preferred = [keyword for keyword in keywords if keyword in {"AI", "SaaS", "Fintech", "Finance", "Education", "B2B"}]
    if preferred:
        return ", ".join(preferred[:4])
    return "product design, UX research, and design systems"


def _experience_start_date(block: str) -> tuple[int, int]:
    heading = block.splitlines()[0] if block.splitlines() else ""
    date_match = re.search(r"\(([^)]*)\)", heading)
    if not date_match:
        return (0, 0)

    date_text = date_match.group(1)
    first_date = date_text.split("-", 1)[0].strip()
    month_match = re.search(r"([A-Za-z]{3,9})\s+(\d{4})", first_date)
    year_match = re.search(r"(\d{4})", first_date)
    if not year_match:
        return (0, 0)

    year = int(year_match.group(1))
    month = _month_number(month_match.group(1)) if month_match else 1
    return (year, month)


def _month_number(month: str) -> int:
    months = {
        "jan": 1,
        "feb": 2,
        "mar": 3,
        "apr": 4,
        "may": 5,
        "jun": 6,
        "jul": 7,
        "aug": 8,
        "sep": 9,
        "oct": 10,
        "nov": 11,
        "dec": 12,
    }
    return months.get(month[:3].lower(), 1)


def _split_skill_groups(skills: str) -> list[tuple[str, str]]:
    matches = list(re.finditer(r"^##\s+(.+?)\s*$", skills, flags=re.MULTILINE))
    if not matches:
        return [("Skills", skills)]

    groups = []
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(skills)
        groups.append((match.group(1).strip(), skills[start:end].strip()))
    return groups


def _clean_skill_items(content: str) -> list[str]:
    raw_items = re.split(r",|\n|;", content)
    seen: set[str] = set()
    items = []
    for item in raw_items:
        cleaned = item.strip(" .-")
        cleaned = re.sub(r"\s+", " ", cleaned)
        if not cleaned:
            continue
        key = cleaned.lower()
        if key in seen:
            continue
        seen.add(key)
        items.append(_title_skill(cleaned))
    return items


def _title_skill(skill: str) -> str:
    special = {
        "figma": "Figma",
        "html": "HTML",
        "css": "CSS",
        "xd": "XD",
        "ux": "UX",
        "ui": "UI",
        "uxcam": "UXCam",
        "miro": "Miro",
        "jira": "Jira",
        "trello": "Trello",
        "mixpanel": "Mixpanel",
        "wordpress": "WordPress",
    }
    words = [special.get(word.lower(), word.capitalize()) for word in skill.split()]
    return " ".join(words)


def _normalize_bullet_section(content: str) -> str:
    lines = []
    for line in content.splitlines():
        cleaned = line.strip()
        if not cleaned:
            continue
        if cleaned.startswith("- "):
            lines.append(cleaned)
        else:
            lines.append(f"- {cleaned}")
    return "\n".join(lines)
