import os
from pathlib import Path
from typing import Any, Optional

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None

try:
    from google.oauth2.service_account import Credentials
except ImportError:
    Credentials = None

try:
    import gspread
except ImportError:
    gspread = None


Job = dict[str, Any]
MANUAL_PRESERVE_COLUMNS = (
    "force_ai",
    "force_regenerate",
    "status",
    "applied_date",
    "follow_up_date",
    "notes",
    "cv_review_status",
    "cover_review_status",
    "special_instruction_handled",
    "ready_to_apply",
    "cv_notes",
)
PRIORITY_ORDER = {
    "high": 0,
    "medium": 1,
    "low": 2,
    "reject": 3,
}
APPLY_PRIORITY_ORDER = {
    "a+": 0,
    "a": 1,
    "b": 2,
    "c": 3,
    "skip": 4,
}

EXPORT_COLUMNS = (
    "company",
    "title",
    "link",
    "source",
    "location",
    "salary",
    "description",
    "posted_date",
    "job_age_days",
    "has_special_instruction",
    "special_instruction_text",
    "special_instruction_handled",
    "match_score",
    "priority",
    "matched_signals",
    "fit_score",
    "matched_skills",
    "missing_skills",
    "fit_summary",
    "recommendation",
    "cv_version",
    "cover_message",
    "bullets",
    "hook",
    "ai_used",
    "ai_generated_at",
    "generation_mode",
    "cv_generated",
    "application_folder",
    "cv_file_path",
    "cv_pdf_path",
    "cv_generated_at",
    "cv_review_status",
    "cover_review_status",
    "application_ready",
    "ready_to_apply",
    "apply_priority",
    "cv_notes",
    "cover_generated",
    "cover_file_path",
    "cover_generated_at",
    "force_ai",
    "force_regenerate",
    "status",
    "applied_date",
    "follow_up_date",
    "notes",
)

SCOPES = (
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive",
)


def update_job_fields_in_google_sheet(
    company: str,
    title: str,
    link: str,
    updates: dict[str, Any],
) -> bool:
    if load_dotenv is None or Credentials is None or gspread is None:
        raise RuntimeError("Google Sheets dependencies are not installed. Run: pip install -r requirements.txt")

    load_dotenv()
    sheet_id = os.getenv("GOOGLE_SHEET_ID", "").strip()
    worksheet_name = os.getenv("GOOGLE_WORKSHEET_NAME", "").strip()
    credentials_file = os.getenv("GOOGLE_CREDENTIALS_FILE", "").strip()
    _validate_settings(sheet_id, worksheet_name, credentials_file)

    credentials = Credentials.from_service_account_file(credentials_file, scopes=list(SCOPES))
    client = gspread.authorize(credentials)
    worksheet = client.open_by_key(sheet_id).worksheet(worksheet_name)

    existing_rows = _read_existing_rows(worksheet)
    target_key = f"{company.strip().lower()}|{title.strip().lower()}|{link.strip().lower()}"
    found = False
    for row in existing_rows:
        if _job_key(row) == target_key:
            for key, value in updates.items():
                if key in EXPORT_COLUMNS:
                    row[key] = value
            found = True
            break

    if not found:
        return False

    prepared = [_prepare_job(row) for row in existing_rows]
    prepared = sorted(prepared, key=_sort_key)
    rows = [list(EXPORT_COLUMNS)]
    rows.extend(_job_to_row(row) for row in prepared)
    worksheet.clear()
    worksheet.update(rows)
    _format_sheet(worksheet, prepared)
    return True


def export_jobs_to_google_sheets(jobs: list[Job]) -> None:
    print(f"Number of jobs being exported: {len(jobs)}")

    if load_dotenv is None or Credentials is None or gspread is None:
        raise RuntimeError("Google Sheets dependencies are not installed. Run: pip install -r requirements.txt")

    load_dotenv()

    sheet_id = os.getenv("GOOGLE_SHEET_ID", "").strip()
    worksheet_name = os.getenv("GOOGLE_WORKSHEET_NAME", "").strip()
    credentials_file = os.getenv("GOOGLE_CREDENTIALS_FILE", "").strip()

    print(f"Loaded GOOGLE_SHEET_ID: {sheet_id}")
    print(f"Loaded GOOGLE_WORKSHEET_NAME: {worksheet_name}")
    print(f"Loaded GOOGLE_CREDENTIALS_FILE: {credentials_file}")
    print(f"Credentials file exists: {Path(credentials_file).exists() if credentials_file else False}")

    _validate_settings(sheet_id, worksheet_name, credentials_file)

    credentials = Credentials.from_service_account_file(credentials_file, scopes=list(SCOPES))
    client = gspread.authorize(credentials)
    spreadsheet = client.open_by_key(sheet_id)
    worksheet = spreadsheet.worksheet(worksheet_name)

    existing_rows = _read_existing_rows(worksheet)
    existing_rows_by_key = {_job_key(row): _prepare_job(row) for row in existing_rows if _job_key(row)}
    existing_rows_without_key = [_prepare_job(row) for row in existing_rows if not _job_key(row)]

    merged_by_key: dict[str, Job] = dict(existing_rows_by_key)
    new_rows_without_key: list[Job] = []
    for job in jobs:
        prepared = _prepare_job(job)
        key = _job_key(prepared)
        if key and key in existing_rows_by_key:
            preserved = existing_rows_by_key[key]
            for column in MANUAL_PRESERVE_COLUMNS:
                prepared[column] = preserved.get(column, prepared.get(column, ""))
        if _to_bool(job.get("force_regenerate", False)):
            prepared["force_regenerate"] = "FALSE"

        if key:
            merged_by_key[key] = prepared
        else:
            new_rows_without_key.append(prepared)

    merged_jobs: list[Job] = list(merged_by_key.values()) + existing_rows_without_key + new_rows_without_key

    merged_jobs = sorted(merged_jobs, key=_sort_key)

    rows = [list(EXPORT_COLUMNS)]
    rows.extend(_job_to_row(job) for job in merged_jobs)

    worksheet.clear()
    worksheet.update(rows)
    _format_sheet(worksheet, merged_jobs)

    print(f"Exported {len(merged_jobs)} rows to Google Sheets")
    print("Google Sheet sorted and formatted successfully.")


def load_force_ai_overrides() -> dict[str, bool]:
    overrides = load_sheet_overrides()
    return {key: values.get("force_ai", False) for key, values in overrides.items()}


def load_sheet_overrides() -> dict[str, dict[str, bool]]:
    if load_dotenv is None or Credentials is None or gspread is None:
        return {}

    load_dotenv()
    sheet_id = os.getenv("GOOGLE_SHEET_ID", "").strip()
    worksheet_name = os.getenv("GOOGLE_WORKSHEET_NAME", "").strip()
    credentials_file = os.getenv("GOOGLE_CREDENTIALS_FILE", "").strip()

    if not (sheet_id and worksheet_name and credentials_file):
        return {}

    if not Path(credentials_file).exists():
        return {}

    try:
        credentials = Credentials.from_service_account_file(credentials_file, scopes=list(SCOPES))
        client = gspread.authorize(credentials)
        worksheet = client.open_by_key(sheet_id).worksheet(worksheet_name)
        rows = worksheet.get_all_records(default_blank="")
    except Exception as error:
        print(f"Could not load sheet overrides from Google Sheets: {error}")
        return {}

    overrides: dict[str, dict[str, bool]] = {}
    for row in rows:
        key = _job_key(row)
        if not key:
            continue
        overrides[key] = {
            "force_ai": _to_bool(row.get("force_ai", "")),
            "force_regenerate": _to_bool(row.get("force_regenerate", "")),
        }
    return overrides


def _validate_settings(sheet_id: str, worksheet_name: str, credentials_file: str) -> None:
    missing = []
    if not sheet_id:
        missing.append("GOOGLE_SHEET_ID")
    if not worksheet_name:
        missing.append("GOOGLE_WORKSHEET_NAME")
    if not credentials_file:
        missing.append("GOOGLE_CREDENTIALS_FILE")

    if missing:
        raise ValueError(f"Missing Google Sheets settings in .env: {', '.join(missing)}")


def _job_to_row(job: Job) -> list[str]:
    return [str(job.get(column, "")) for column in EXPORT_COLUMNS]


def _prepare_job(job: Job) -> Job:
    prepared = job.copy()
    for key in ("matched_signals", "bullets", "matched_skills", "missing_skills"):
        value = prepared.get(key, [])
        if isinstance(value, list):
            prepared[key] = "; ".join(str(item) for item in value)

    prepared["status"] = prepared.get("status") or "New"
    prepared["posted_date"] = prepared.get("posted_date") or "Unknown"
    prepared["job_age_days"] = prepared.get("job_age_days") or "Unknown"
    prepared["ai_used"] = prepared.get("ai_used") or "No"
    prepared["ai_generated_at"] = prepared.get("ai_generated_at") or ""
    prepared["generation_mode"] = prepared.get("generation_mode") or "rule_based"
    has_special_instruction = _to_bool(prepared.get("has_special_instruction", False))
    prepared["has_special_instruction"] = "TRUE" if has_special_instruction else "FALSE"
    prepared["special_instruction_text"] = prepared.get("special_instruction_text") or ""
    if has_special_instruction:
        prepared["special_instruction_handled"] = prepared.get("special_instruction_handled") or "No"
    else:
        prepared["special_instruction_handled"] = prepared.get("special_instruction_handled") or "Yes"
    prepared["cv_generated"] = prepared.get("cv_generated") or ""
    prepared["application_folder"] = prepared.get("application_folder") or ""
    prepared["cv_file_path"] = prepared.get("cv_file_path") or ""
    prepared["cv_pdf_path"] = prepared.get("cv_pdf_path") or ""
    prepared["cv_generated_at"] = prepared.get("cv_generated_at") or ""
    prepared["cv_review_status"] = prepared.get("cv_review_status") or "Needs Review"
    prepared["cover_review_status"] = prepared.get("cover_review_status") or "Needs Review"
    if has_special_instruction:
        prepared["application_ready"] = "Needs Manual Check"
    elif prepared["cv_generated"] == "Done" and prepared.get("cover_generated") == "Done":
        prepared["application_ready"] = "Yes"
    else:
        prepared["application_ready"] = prepared.get("application_ready") or "No"
    prepared["apply_priority"] = _apply_priority(prepared)
    prepared["ready_to_apply"] = _ready_to_apply(prepared)
    prepared["cv_notes"] = prepared.get("cv_notes") or ""
    prepared["cover_generated"] = prepared.get("cover_generated") or ""
    prepared["cover_file_path"] = prepared.get("cover_file_path") or ""
    prepared["cover_generated_at"] = prepared.get("cover_generated_at") or ""
    prepared["force_ai"] = prepared.get("force_ai") or ""
    prepared["force_regenerate"] = prepared.get("force_regenerate") or ""
    prepared["applied_date"] = prepared.get("applied_date") or ""
    prepared["follow_up_date"] = prepared.get("follow_up_date") or ""
    prepared["notes"] = prepared.get("notes") or ""
    return prepared


def _read_existing_rows(worksheet: Any) -> list[Job]:
    try:
        rows = worksheet.get_all_records(default_blank="")
    except Exception:
        return []

    cleaned_rows: list[Job] = []
    for row in rows:
        cleaned = {column: row.get(column, "") for column in EXPORT_COLUMNS}
        cleaned_rows.append(cleaned)
    return cleaned_rows


def _job_key(job: Job) -> str:
    company = str(job.get("company", "")).strip().lower()
    title = str(job.get("title", "")).strip().lower()
    link = str(job.get("link", "")).strip().lower()
    if not (company and title and link):
        return ""
    return f"{company}|{title}|{link}"


def _sort_key(job: Job) -> tuple[int, float, float]:
    apply_priority_rank = APPLY_PRIORITY_ORDER.get(str(job.get("apply_priority", "")).strip().lower(), 99)
    fit_score = _to_number(job.get("fit_score"), default=-1.0)
    match_score = _to_number(job.get("match_score"), default=-1.0)
    return (apply_priority_rank, -fit_score, -match_score)


def _to_number(value: Any, default: float = 0.0) -> float:
    if value is None:
        return default
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value).strip().replace("%", "")
    if not text:
        return default
    try:
        return float(text)
    except ValueError:
        return default


def _to_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    text = str(value).strip().lower()
    return text in {"true", "1", "yes", "y"}


def _format_sheet(worksheet: Any, jobs: list[Job]) -> None:
    sheet_id = worksheet.id
    total_rows = len(jobs) + 1
    total_columns = len(EXPORT_COLUMNS)

    worksheet.freeze(rows=1)

    requests: list[dict[str, Any]] = [
        {
            "repeatCell": {
                "range": {
                    "sheetId": sheet_id,
                    "startRowIndex": 0,
                    "endRowIndex": 1,
                    "startColumnIndex": 0,
                    "endColumnIndex": total_columns,
                },
                "cell": {"userEnteredFormat": {"textFormat": {"bold": True}}},
                "fields": "userEnteredFormat.textFormat.bold",
            }
        },
        {
            "setBasicFilter": {
                "filter": {
                    "range": {
                        "sheetId": sheet_id,
                        "startRowIndex": 0,
                        "endRowIndex": total_rows,
                        "startColumnIndex": 0,
                        "endColumnIndex": total_columns,
                    }
                }
            }
        },
        {
            "autoResizeDimensions": {
                "dimensions": {
                    "sheetId": sheet_id,
                    "dimension": "COLUMNS",
                    "startIndex": 0,
                    "endIndex": total_columns,
                }
            }
        },
    ]

    for index, job in enumerate(jobs, start=1):
        color = _match_score_color(_to_number(job.get("match_score"), default=-1.0))
        if color is None:
            continue
        requests.append(
            {
                "repeatCell": {
                    "range": {
                        "sheetId": sheet_id,
                        "startRowIndex": index,
                        "endRowIndex": index + 1,
                        "startColumnIndex": 0,
                        "endColumnIndex": total_columns,
                    },
                    "cell": {"userEnteredFormat": {"backgroundColor": color}},
                    "fields": "userEnteredFormat.backgroundColor",
                }
            }
        )

    worksheet.spreadsheet.batch_update({"requests": requests})


def _match_score_color(match_score: float) -> Optional[dict[str, float]]:
    if match_score < 0:
        return None
    if match_score >= 50:
        return {"red": 0.76, "green": 0.93, "blue": 0.76}
    if match_score >= 35:
        return {"red": 1.00, "green": 0.95, "blue": 0.60}
    if match_score >= 20:
        return {"red": 1.00, "green": 0.84, "blue": 0.65}
    return {"red": 0.97, "green": 0.70, "blue": 0.70}


def _apply_priority(job: Job) -> str:
    fit_score = _to_number(job.get("fit_score"), default=-1.0)
    priority = str(job.get("priority", "")).strip().lower()
    if fit_score >= 85 and priority == "high":
        return "A+"
    if fit_score >= 75:
        return "A"
    if fit_score >= 60:
        return "B"
    if fit_score >= 45:
        return "C"
    return "Skip"


def _ready_to_apply(job: Job) -> str:
    cv_done = str(job.get("cv_generated", "")).strip().lower() == "done"
    cover_done = str(job.get("cover_generated", "")).strip().lower() == "done"
    cv_approved = str(job.get("cv_review_status", "")).strip().lower() == "approved"
    cover_approved = str(job.get("cover_review_status", "")).strip().lower() == "approved"
    has_special = _to_bool(job.get("has_special_instruction", False))
    special_handled = _to_bool(job.get("special_instruction_handled", False))
    special_ok = (not has_special) or special_handled

    return "Yes" if (cv_done and cover_done and cv_approved and cover_approved and special_ok) else "No"
