import re


GENERIC_PHRASES = (
    "i am excited to apply",
    "i believe i am a great fit",
)


def polish_application(text: str) -> str:
    value = str(text or "").strip()
    if not value:
        return ""

    polished = value
    for phrase in GENERIC_PHRASES:
        polished = re.sub(re.escape(phrase), "", polished, flags=re.IGNORECASE)

    polished = _remove_repetition(polished)
    polished = _tighten_language(polished)
    polished = re.sub(r"\s+\n", "\n", polished)
    polished = re.sub(r"\n{3,}", "\n\n", polished)
    polished = re.sub(r"[ \t]{2,}", " ", polished)
    return polished.strip(" ,.-\n")


def _remove_repetition(text: str) -> str:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    seen: set[str] = set()
    unique_lines = []
    for line in lines:
        key = line.lower()
        if key in seen:
            continue
        seen.add(key)
        unique_lines.append(line)
    return "\n".join(unique_lines) if unique_lines else text


def _tighten_language(text: str) -> str:
    replacements = {
        r"\bI would be excited to\b": "I can",
        r"\bI would love to\b": "I can",
        r"\bI am very interested in\b": "I am interested in",
        r"\bI think I can\b": "I can",
        r"\bI believe I can\b": "I can",
    }
    result = text
    for pattern, replacement in replacements.items():
        result = re.sub(pattern, replacement, result, flags=re.IGNORECASE)
    return result
