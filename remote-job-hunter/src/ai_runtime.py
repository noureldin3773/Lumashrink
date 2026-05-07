import hashlib
import json
import os
from pathlib import Path
from typing import Any, Optional

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None

try:
    from openai import OpenAI
except ImportError:
    OpenAI = None


ROOT = Path(__file__).resolve().parents[1]
CACHE_PATH = ROOT / "outputs" / "cache" / "ai_cache.json"
LOG_PATH = ROOT / "outputs" / "logs" / "ai_usage.log"

MODELS = {
    "cheap": "gpt-5-nano",
    "normal": "gpt-5-mini",
    "quality": "gpt-5",
}

MODEL_COST_PER_1M = {
    "gpt-5-nano": {"input": 0.05, "output": 0.4},
    "gpt-5-mini": {"input": 0.25, "output": 2.0},
    "gpt-5": {"input": 1.25, "output": 10.0},
}


def _mode() -> str:
    return os.getenv("OPENAI_PIPELINE_MODE", "FAST_MODE").strip().upper()


def select_model(task_level: str = "normal") -> str:
    task = (task_level or "normal").strip().lower()
    if _mode() == "QUALITY_MODE":
        return MODELS.get(task, MODELS["normal"])
    if task == "quality":
        return MODELS["normal"]
    return MODELS.get(task, MODELS["normal"])


def _cache_load() -> dict[str, Any]:
    if not CACHE_PATH.exists():
        return {}
    try:
        return json.loads(CACHE_PATH.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _cache_save(data: dict[str, Any]) -> None:
    CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    CACHE_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def _cache_key(feature: str, payload: dict[str, Any], job_key: str) -> str:
    raw = json.dumps({"feature": feature, "job_key": job_key, "payload": payload}, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _estimate_cost(model: str, input_tokens: int, output_tokens: int) -> float:
    pricing = MODEL_COST_PER_1M.get(model, {"input": 0.0, "output": 0.0})
    return (input_tokens / 1_000_000) * pricing["input"] + (output_tokens / 1_000_000) * pricing["output"]


def _log_usage(feature: str, model: str, usage: Any, cache_hit: bool = False) -> None:
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    input_tokens = int(getattr(usage, "input_tokens", 0) or 0) if usage else 0
    output_tokens = int(getattr(usage, "output_tokens", 0) or 0) if usage else 0
    cost = _estimate_cost(model, input_tokens, output_tokens)
    line = json.dumps(
        {
            "feature": feature,
            "model": model,
            "mode": _mode(),
            "cache_hit": cache_hit,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "estimated_cost_usd": round(cost, 6),
        },
        ensure_ascii=False,
    )
    with LOG_PATH.open("a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def _client() -> Optional["OpenAI"]:
    if load_dotenv is not None:
        load_dotenv()
    if OpenAI is None:
        return None
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        return None
    return OpenAI(api_key=api_key)


def call_json(
    *,
    feature: str,
    task_level: str,
    payload: dict[str, Any],
    schema_name: str,
    schema: dict[str, Any],
    job_key: str,
    max_output_tokens: int = 300,
) -> Optional[dict[str, Any]]:
    cache = _cache_load()
    key = _cache_key(feature, payload, job_key)
    if key in cache:
        _log_usage(feature, "cache", None, cache_hit=True)
        return cache[key]

    client = _client()
    if client is None:
        return None

    model = select_model(task_level)
    try:
        response = client.responses.create(
            model=model,
            input=json.dumps(payload, ensure_ascii=False),
            max_output_tokens=max_output_tokens,
            reasoning={"effort": "low"},
            text={
                "format": {
                    "type": "json_schema",
                    "name": schema_name,
                    "strict": True,
                    "schema": schema,
                }
            },
        )
        output = json.loads(str(getattr(response, "output_text", "") or "{}"))
        cache[key] = output
        _cache_save(cache)
        _log_usage(feature, model, getattr(response, "usage", None), cache_hit=False)
        return output
    except Exception:
        return None


def call_json_batch(
    *,
    feature: str,
    task_level: str,
    shared_system: str,
    batch_items: list[dict[str, Any]],
    schema_name: str,
    schema: dict[str, Any],
    max_output_tokens: int = 300,
) -> Optional[dict[str, Any]]:
    payload = {"system": shared_system, "jobs": batch_items}
    return call_json(
        feature=feature,
        task_level=task_level,
        payload=payload,
        schema_name=schema_name,
        schema=schema,
        job_key=f"batch:{len(batch_items)}",
        max_output_tokens=max_output_tokens,
    )
