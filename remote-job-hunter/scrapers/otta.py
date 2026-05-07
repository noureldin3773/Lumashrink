from __future__ import annotations

from typing import Any

try:
    import requests
except ImportError:
    requests = None


SOURCE = "Otta / Welcome to the Jungle"
URL = "https://app.welcometothejungle.com/jobs?query=product%20designer&remote=true"
HEADERS = {"User-Agent": "Mozilla/5.0", "Accept": "text/html"}
Job = dict[str, Any]


def fetch_otta_jobs(timeout: int = 12) -> list[Job]:
    if requests is None:
        raise RuntimeError("The requests package is not installed. Run: pip install -r requirements.txt")

    response = requests.get(URL, headers=HEADERS, timeout=timeout)
    if response.status_code in {401, 403} or "Login" in response.text:
        print("Otta/Welcome to the Jungle requires app login/session for job results. Skipping Otta for this run.")
        return []
    response.raise_for_status()
    print("Otta/Welcome to the Jungle loaded, but no stable public parser is available yet. Skipping Otta for this run.")
    return []
