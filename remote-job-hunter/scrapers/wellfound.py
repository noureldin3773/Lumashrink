from __future__ import annotations

from typing import Any

try:
    import requests
except ImportError:
    requests = None


SOURCE = "Wellfound"
URL = "https://wellfound.com/jobs?keywords=product%20designer&remote=true"
HEADERS = {"User-Agent": "Mozilla/5.0", "Accept": "text/html"}
Job = dict[str, Any]


def fetch_wellfound_jobs(timeout: int = 12) -> list[Job]:
    if requests is None:
        raise RuntimeError("The requests package is not installed. Run: pip install -r requirements.txt")

    response = requests.get(URL, headers=HEADERS, timeout=timeout)
    if response.status_code in {401, 403} or "Please enable JS" in response.text:
        print("Wellfound is protected by anti-bot/JS checks. Skipping Wellfound for this run.")
        return []
    response.raise_for_status()
    print("Wellfound page loaded, but no stable public parser is available yet. Skipping Wellfound for this run.")
    return []
