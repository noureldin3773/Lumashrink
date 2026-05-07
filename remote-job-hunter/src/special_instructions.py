import re
from typing import Any


def detect_special_instructions(job_description: Any) -> dict[str, Any]:
    text = str(job_description or "").strip()
    if not text:
        return {"has_special_instruction": False, "special_instruction_text": ""}

    patterns = [
        r"mention the word[^.\n]*",
        r"include the word[^.\n]*",
        r"\btag\b[^.\n]*",
        r"to show you read[^.\n]*",
        r"when applying[^.\n]*",
    ]

    matches: list[str] = []
    for pattern in patterns:
        for match in re.finditer(pattern, text, flags=re.IGNORECASE):
            snippet = match.group(0).strip(" :.-")
            if snippet and snippet not in matches:
                matches.append(snippet)

    return {
        "has_special_instruction": len(matches) > 0,
        "special_instruction_text": " | ".join(matches),
    }
