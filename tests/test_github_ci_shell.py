from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).parent.parent
SCRIPT = ROOT / "scripts" / "summarize-github-ci.sh"


def summarize(payload: object, **env: str) -> tuple[dict, str]:
    result = subprocess.run(
        ["bash", str(SCRIPT)],
        input=json.dumps(payload),
        env={**os.environ, **env},
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout), result.stderr


def test_slurped_pages_and_non_blocking_conclusions():
    summary, _ = summarize([
        {"check_runs": [{"id": 1, "status": "completed", "conclusion": "success"}]},
        {"check_runs": [{"id": 2, "status": "completed", "conclusion": "skipped"}]},
    ])
    assert summary["status"] == "success"
    assert summary["filtered_count"] == 2


def test_malformed_payloads_fail_closed():
    assert summarize({"message": "Not Found"})[0]["status"] == "unknown"
    assert summarize({"check_runs": "oops"})[0]["status"] == "unknown"
    assert summarize([{"check_runs": []}, {"message": "partial"}])[0]["status"] == "unknown"
    result = subprocess.run(
        ["bash", str(SCRIPT)], input="not-json", capture_output=True, text=True, check=True
    )
    assert json.loads(result.stdout)["status"] == "fetch-error"


def test_empty_and_trusted_publisher_only_are_blocking_states():
    assert summarize({"check_runs": []})[0]["status"] == "none"
    publisher = {
        "id": 303,
        "name": "base-controlled samorev publisher",
        "app": {"id": 15368},
        "status": "in_progress",
        "conclusion": None,
    }
    summary, _ = summarize(
        {"check_runs": [publisher]},
        SAMOREV_IGNORED_GITHUB_CHECK_RUN_IDS="303",
        SAMOREV_IGNORED_GITHUB_CHECK_NAME=publisher["name"],
        SAMOREV_IGNORED_GITHUB_CHECK_APP_ID="15368",
    )
    assert summary["status"] == "self-only"
    assert summary["excluded_self"] == 1


def test_untrusted_same_name_check_remains_pending():
    publisher = {
        "id": 999,
        "name": "base-controlled samorev publisher",
        "app": {"id": 15368},
        "status": "in_progress",
        "conclusion": None,
    }
    summary, _ = summarize(
        {"check_runs": [publisher]},
        SAMOREV_IGNORED_GITHUB_CHECK_RUN_IDS="303",
        SAMOREV_IGNORED_GITHUB_CHECK_NAME=publisher["name"],
        SAMOREV_IGNORED_GITHUB_CHECK_APP_ID="15368",
    )
    assert summary["status"] == "pending"
    assert summary["excluded_self"] == 0


def test_partial_configuration_warns_and_excludes_nothing():
    summary, stderr = summarize(
        {"check_runs": [{"id": 303, "status": "in_progress", "conclusion": None}]},
        SAMOREV_IGNORED_GITHUB_CHECK_RUN_IDS="303",
    )
    assert summary["status"] == "pending"
    assert "incomplete GitHub self-check" in stderr
