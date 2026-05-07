import json
import os
import re
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

SENIOR_CV_CONTEXT = """You are an elite-level Senior Product Designer resume optimizer.

Your job is NOT to rewrite a CV.

Your job is to produce a CV that:
gets shortlisted, passes ATS, signals senior-level immediately, and competes at $4k+ remote level.

CORE OBJECTIVE:
Every line must prove: “I improve products and deliver measurable business impact”, not “I design screens”.

RECRUITER PSYCHOLOGY:
Recruiters scan CVs in 6–10 seconds and look for impact, ownership, and product thinking.
If these are not obvious instantly, reject.

BULLET FORMULA (MANDATORY):
[Strong Action Verb] + [Product/Feature/Problem] + [Impact]
If a bullet has no impact, rewrite it.

SENIOR SIGNALS (MANDATORY):
Ownership, Product Thinking, Impact, Systems Thinking, Collaboration, End-to-End delivery.

CNTXT AI RULE (MOST IMPORTANT):
Current role must have EXACTLY 5 bullets and be the strongest section.
Each bullet must show leadership, product complexity (AI/systems), real impact (or logical impact), and decision-making.

STRICTLY FORBIDDEN:
Generic wording, weak/task-based verbs, tool-only bullets, vague statements, duplicate ideas.

IMPACT ENFORCER:
Prefer numbers. If no metric exists, still express impact (improved usability, reduced friction, accelerated development, increased clarity, enhanced UX).

JOB MATCHING:
Adapt to JD keywords naturally: design systems, complex flows, product thinking, mobile/web, RTL/LTR, stakeholders, business impact.

POWER LANGUAGE:
worked→led, helped→improved, made→delivered, designed→drove/built/optimized

QUALITY FILTER:
Every bullet must be impactful, senior-level, specific, and strong.
Only output 9/10+ bullets.

OUTPUT FORMAT:
[Job Title — Company]
• Bullet 1
• Bullet 2
• Bullet 3
• Bullet 4
• Bullet 5 (if needed)
No commentary; only CV-ready content.
"""

TOKEN_RULE = (
    "Token rule: Keep output compact. Reuse provided CV context as source-of-truth and avoid repeating long inputs. "
    "Focus only on job-specific tailoring."
)


def generate_application(job: Job, profile_config: dict[str, str]) -> dict[str, Any]:
    description = str(job.get("description", ""))
    company = str(job.get("company", "")).strip() or "your team"
    title = str(job.get("title", "")).strip() or "this role"
    cv_version = _select_cv_version(description)

    return {
        "cv_version": cv_version,
        "cover_message": _build_cover_message(company, title, description, profile_config),
        "bullets": _build_bullets(description),
        "hook": _build_hook(company, description),
    }


def generate_application_with_ai(
    job: Job,
    current_cv: str,
    profile_config: dict[str, str],
) -> dict[str, Any]:
    fallback = _fallback_application_fields(job, profile_config)

    if load_dotenv is None or OpenAI is None:
        print("OpenAI application generation skipped: dependencies are not installed. Run: pip install -r requirements.txt")
        return fallback

    load_dotenv()
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        print("OpenAI application generation skipped: OPENAI_API_KEY is missing in .env")
        return fallback

    payload = _build_ai_payload(job, current_cv, profile_config)
    parsed = call_json(
        feature="cover_generation",
        task_level="quality",
        payload=payload,
        schema_name="application_generation",
        schema={
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "cover_message": {"type": "string"},
                "bullets": {"type": "array", "items": {"type": "string"}, "minItems": 3, "maxItems": 5},
                "hook": {"type": "string"},
            },
            "required": ["cover_message", "bullets", "hook"],
        },
        job_key=str(job.get("link", "")) or f"{job.get('company','')}|{job.get('title','')}",
        max_output_tokens=260,
    )
    if not parsed:
        print("OpenAI application generation failed")
        return fallback
    return _parse_ai_dict(parsed, fallback)


def _fallback_application_fields(job: Job, profile_config: dict[str, str]) -> dict[str, Any]:
    fallback = generate_application(job, profile_config)
    return {
        "cover_message": fallback["cover_message"],
        "bullets": fallback["bullets"],
        "hook": fallback["hook"],
    }


def _build_ai_payload(job: Job, current_cv: str, profile_config: dict[str, str]) -> dict[str, Any]:
    profile = "\n\n".join(
        [
            str(profile_config.get("skills", "")).strip(),
            str(profile_config.get("cv_profile", "")).strip(),
        ]
    ).strip()
    current_cv_text = str(current_cv or "").strip()
    description = str(job.get("description", "")).strip()
    company = str(job.get("company", "")).strip()
    title = str(job.get("title", "")).strip()
    special_instruction_text = str(job.get("special_instruction_text", "")).strip()
    has_special_instruction = str(job.get("has_special_instruction", "")).strip().lower() in {"true", "1", "yes", "y"}
    special_instruction_block = (
        f"\nSpecial application instructions from JD:\n{special_instruction_text}\n"
        if has_special_instruction and special_instruction_text
        else ""
    )

    return {
        "system": f"{SENIOR_CV_CONTEXT}\n\n{TOKEN_RULE}\nOptimize specifically for my CV data.",
        "user": {
            "job_description": f"Company: {company}\nTitle: {title}\nDescription: {description}\n{special_instruction_block}".strip(),
            "cv_data": _compact_cv_context(current_cv_text),
            "target_role": "Senior Product Designer",
            "profile_context": _compact_text(profile, max_chars=1200),
            "output_requirements": {
                "cover_message": "4-5 lines, confident, specific, no buzzwords",
                "bullets": "3 to 5 bullets, senior-level, action + what + impact/result",
                "hook": "1-2 lines, company/job specific",
                "bullet_restrictions": [
                    "Every bullet must start with a strong action verb",
                    "No duplicate lines are allowed",
                    "No near-duplicate bullets are allowed, even if idea/context is similar",
                    "If duplicate is detected, replace it with a new unique bullet",
                ],
            },
        },
    }


def _compact_text(text: str, max_chars: int = 2500) -> str:
    clean = " ".join((text or "").split())
    return clean[:max_chars]


def _compact_cv_context(cv_text: str) -> str:
    # Keep high-signal CV data only (summary + recent roles + skills cues)
    cleaned = (cv_text or "").strip()
    if not cleaned:
        return ""
    sections = cleaned.split("# ")
    kept: list[str] = []
    for section in sections:
        s = section.strip()
        if not s:
            continue
        lower = s.lower()
        if lower.startswith("summary") or lower.startswith("work experience") or lower.startswith("skills"):
            kept.append(s)
    return _compact_text("\n\n".join(kept) if kept else cleaned, max_chars=3500)


def _parse_ai_dict(parsed: dict[str, Any], fallback: dict[str, Any]) -> dict[str, Any]:
    cover_message = str(parsed.get("cover_message", "")).strip()
    hook = str(parsed.get("hook", "")).strip()
    bullets = parsed.get("bullets", [])
    if not isinstance(bullets, list):
        bullets = []
    bullets = [str(bullet).strip() for bullet in bullets if str(bullet).strip()][:5]
    bullets = _enforce_bullet_quality(bullets)

    if not cover_message or not hook or not (3 <= len(bullets) <= 5):
        print("OpenAI application generation returned incomplete fields")
        return fallback

    return {
        "cover_message": cover_message,
        "bullets": bullets,
        "hook": hook,
    }


def _enforce_bullet_quality(bullets: list[str]) -> list[str]:
    action_starts = ("led", "improved", "redesigned", "delivered", "built", "optimized", "simplified")
    upgraded: list[str] = []
    seen_keys: set[str] = set()
    for bullet in bullets:
        text = " ".join(str(bullet).split()).strip(" -")
        if not text:
            continue
        lower = text.lower()
        if not lower.startswith(action_starts):
            text = f"Improved {text[0].lower() + text[1:]}" if len(text) > 1 else f"Improved {text}"
            lower = text.lower()
        has_impact = any(token in lower for token in ["%", "increased", "reduced", "improved", "result", "impact", "faster", "higher", "lower"])
        if not has_impact:
            text = f"{text}, improving product outcomes."
            lower = text.lower()
        has_ownership = any(token in lower for token in ["led", "owned", "delivered", "built", "redesigned", "optimized", "improved", "simplified"])
        if not has_ownership:
            text = f"Led {text[0].lower() + text[1:]}" if len(text) > 1 else f"Led {text}"
        dedupe_key = _bullet_dedupe_key(text)
        if dedupe_key in seen_keys:
            continue
        seen_keys.add(dedupe_key)
        upgraded.append(text)
    upgraded = _fill_unique_bullets(upgraded, min_count=3, max_count=5)
    return upgraded[:5]


def _bullet_dedupe_key(text: str) -> str:
    normalized = re.sub(r"[^a-z0-9\s]", " ", text.lower())
    stopwords = {
        "the", "a", "an", "and", "to", "of", "for", "with", "by", "on", "in", "across",
        "improved", "led", "built", "optimized", "delivered", "redesigned", "simplified",
        "product", "experience", "user", "users"
    }
    tokens = [token for token in normalized.split() if token and token not in stopwords]
    return " ".join(sorted(set(tokens))[:12])


def _fill_unique_bullets(bullets: list[str], min_count: int = 3, max_count: int = 5) -> list[str]:
    templates = [
        "Led end-to-end product discovery and delivery for a core workflow, improving clarity and reducing user friction.",
        "Redesigned a high-impact journey by simplifying key decision points, improving completion quality and user confidence.",
        "Built scalable design patterns for repeated product surfaces, improving consistency and accelerating implementation.",
        "Optimized cross-functional handoff quality with structured UX specs, reducing revision cycles and delivery delays.",
        "Delivered measurable UX improvements through iterative testing and refinement, improving usability and task success.",
    ]
    action_starts = ("led", "improved", "redesigned", "delivered", "built", "optimized", "simplified")
    seen = {_bullet_dedupe_key(b) for b in bullets}
    result = [b for b in bullets if b and b.lower().startswith(action_starts)]

    for template in templates:
        if len(result) >= max_count:
            break
        key = _bullet_dedupe_key(template)
        if key in seen:
            continue
        seen.add(key)
        result.append(template)

    return result[:max(max_count, min_count)]


def _select_cv_version(description: str) -> str:
    normalized = description.lower()
    if "ai" in normalized or "saas" in normalized:
        return "AI_SAAS"
    if "fintech" in normalized or "finance" in normalized:
        return "FINTECH"
    return "GENERAL"


def _build_cover_message(company: str, title: str, description: str, profile_config: dict[str, str]) -> str:
    focus = _job_focus(description)
    profile_text = " ".join(
        [
            str(profile_config.get("skills", "")),
            str(profile_config.get("cv_profile", "")),
        ]
    )
    positioning = "I design SaaS, AI, and fintech products end-to-end"
    if "fintech" in profile_text.lower():
        positioning = "I design SaaS, AI, and fintech products end-to-end"

    lines = [
        f"Hi {company} team,",
        f"I am Nour, a Senior Product Designer. {positioning}.",
        f"The {title} role stood out because it connects closely with {focus}.",
        "I would be excited to help shape clear UX flows, scalable design systems, and developer-ready product experiences.",
    ]
    return "\n".join(lines)


def _build_bullets(description: str) -> list[str]:
    normalized = description.lower()
    first_bullet = "Designed end-to-end product experiences for SaaS and AI platforms"
    if "fintech" in normalized or "finance" in normalized:
        first_bullet = "Designed fintech product experiences, dashboards, and complex financial UX flows"

    return [
        first_bullet,
        "Built scalable design systems used by development teams",
        "Delivered developer-ready UI and improved product workflows",
    ]


def _build_hook(company: str, description: str) -> str:
    focus = _job_focus(description)
    return f"{company} feels like a strong fit because the role connects with {focus}. I am especially interested in helping turn complex product needs into simple, polished user experiences."


def _job_focus(description: str) -> str:
    normalized = description.lower()
    if "fintech" in normalized or "finance" in normalized:
        return "fintech product design"
    if "ai" in normalized and "saas" in normalized:
        return "AI-powered SaaS product design"
    if "ai" in normalized:
        return "AI product design"
    if "saas" in normalized:
        return "SaaS product design"
    if "design system" in normalized or "design systems" in normalized:
        return "design systems and product workflows"
    return "product design, UX flows, and strong execution"
