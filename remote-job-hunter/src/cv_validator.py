import re


KNOWN_COMPANIES = (
    "CNTXT AI",
    "Qannas",
    "Mint-Ops",
    "Rowad",
    "Khamsat",
)
REQUIRED_SECTIONS = ("SUMMARY", "WORK EXPERIENCE", "SKILLS", "EDUCATION")


def validate_cv(cv_text: str) -> tuple[bool, list[str]]:
    warnings: list[str] = []

    warnings.extend(_check_required_sections(cv_text))
    warnings.extend(_check_empty_sections(cv_text))
    warnings.extend(_check_duplicate_lines(cv_text))
    warnings.extend(_check_excessive_repetition(cv_text))
    warnings.extend(_check_invented_companies(cv_text))
    warnings.extend(_check_invented_metrics(cv_text))

    valid = not warnings
    if not valid:
        print("CV validation warnings:")
        for warning in warnings:
            print(f"- {warning}")

    return valid, warnings


def _check_required_sections(cv_text: str) -> list[str]:
    warnings = []
    for section in REQUIRED_SECTIONS:
        if not re.search(rf"^#\s+{re.escape(section)}\s*$", cv_text, flags=re.MULTILINE | re.IGNORECASE):
            warnings.append(f"Missing required section: {section}")
    return warnings


def _check_empty_sections(cv_text: str) -> list[str]:
    warnings = []
    sections = _parse_sections(cv_text)
    for section in REQUIRED_SECTIONS:
        content = sections.get(section, "").strip()
        if not content:
            warnings.append(f"Empty section: {section}")
    return warnings


def _check_duplicate_lines(cv_text: str) -> list[str]:
    warnings = []
    seen: set[str] = set()
    duplicates: set[str] = set()

    for line in cv_text.splitlines():
        normalized = _normalize_line(line)
        if not normalized or normalized in {"---"}:
            continue
        if normalized in seen:
            duplicates.add(line.strip())
        seen.add(normalized)

    if duplicates:
        warnings.append(f"Duplicate lines found: {', '.join(sorted(duplicates)[:5])}")

    return warnings


def _check_excessive_repetition(cv_text: str) -> list[str]:
    warnings = []
    words = re.findall(r"\b[a-zA-Z][a-zA-Z+-]{3,}\b", cv_text.lower())
    ignored = {"with", "and", "through", "across", "designer", "design", "product"}
    meaningful_words = [word for word in words if word not in ignored]
    total = len(meaningful_words)
    if total < 30:
        return warnings

    counts = {word: meaningful_words.count(word) for word in set(meaningful_words)}
    repeated = [word for word, count in counts.items() if count >= 8 and count / total > 0.06]
    if repeated:
        warnings.append(f"Excessive repetition detected: {', '.join(sorted(repeated)[:5])}")

    return warnings


def _check_invented_companies(cv_text: str) -> list[str]:
    warnings = []
    experience_headings = re.findall(r"^##\s+(.+?)$", cv_text, flags=re.MULTILINE)

    for heading in experience_headings:
        if "—" not in heading:
            continue
        company = heading.split("—", 1)[1].split("(", 1)[0].strip()
        if company and company not in KNOWN_COMPANIES:
            warnings.append(f"Possible invented company in experience: {company}")

    return warnings


def _check_invented_metrics(cv_text: str) -> list[str]:
    warnings = []
    known_metrics = {"70%", "40%", "35%", "25%", "15%", "30%", "30+", "4+"}
    found_metrics = set(re.findall(r"\b\d+\+?%|\b\d+\+", cv_text))
    invented_metrics = sorted(metric for metric in found_metrics if metric not in known_metrics)
    if invented_metrics:
        warnings.append(f"Possible invented metrics found: {', '.join(invented_metrics[:5])}")

    return warnings


def _parse_sections(cv_text: str) -> dict[str, str]:
    matches = list(re.finditer(r"^#\s+(.+?)\s*$", cv_text, flags=re.MULTILINE))
    sections: dict[str, str] = {}
    for index, match in enumerate(matches):
        heading = match.group(1).strip().upper()
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(cv_text)
        sections[heading] = cv_text[start:end].strip()
    return sections


def _normalize_line(line: str) -> str:
    return re.sub(r"\s+", " ", line.strip().lower())
