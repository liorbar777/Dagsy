#!/usr/bin/env python3
"""Watch local Airflow and notify for new failures and successful manual DAG runs."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import Any


ACCESS_TOKEN: str | None = None
MAX_SUCCESS_ITEMS = 10
SYSTEM_PYTHON = "/usr/bin/python3"
NATIVE_DIALOG_HELPER = os.path.expanduser("~/Applications/airflow-dialog-helper")
DIALOG_QUEUE_DIR = os.path.expanduser("~/Library/Application Support/local-airflow-watcher/dialog_queue")
DIALOG_RUNTIME_PATH = os.path.expanduser(
    "~/Library/Application Support/local-airflow-watcher/dialog_queue_runtime.json"
)
WATCHER_STATE_PATH = os.path.expanduser(
    "~/Library/Application Support/local-airflow-watcher/watcher_state.json"
)
SUCCESS_PANEL_STATE_PATH = os.path.expanduser(
    "~/Library/Application Support/local-airflow-watcher/success_panel_state.json"
)
FAILURE_PANEL_STATE_PATH = os.path.expanduser(
    "~/Library/Application Support/local-airflow-watcher/failure_panel_state.json"
)
SUCCESS_PANEL_RUNTIME_PATH = os.path.expanduser(
    "~/Library/Application Support/local-airflow-watcher/success_panel_runtime.json"
)
FAILURE_PANEL_RUNTIME_PATH = os.path.expanduser(
    "~/Library/Application Support/local-airflow-watcher/failure_panel_runtime.json"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Poll a local Airflow instance and show popups for new retries, task failures, "
            "DAG failures, and successful manual DAG runs that happen after the listener starts."
        )
    )
    parser.add_argument("--base-url", default="http://localhost:8080")
    parser.add_argument("--username", default="admin")
    parser.add_argument("--password", default="admin")
    parser.add_argument("--poll-interval", type=int, default=5)
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--dag-id", action="append", default=[])
    parser.add_argument("--popup-mode", choices=["dialog", "notification"], default="dialog")
    parser.add_argument("--environment-label", default="local")
    parser.add_argument("--drain-dialog-queue", action="store_true", help=argparse.SUPPRESS)
    return parser.parse_args()


def fetch_access_token(base_url: str, username: str, password: str) -> str:
    auth_url = f"{base_url.rstrip('/')}/auth/token"
    request = urllib.request.Request(
        auth_url,
        headers={"Accept": "application/json", "Content-Type": "application/json"},
        data=json.dumps({"username": username, "password": password}).encode(),
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        payload = json.load(response)
    return payload["access_token"]


def make_request(url: str, base_url: str, username: str, password: str) -> dict[str, Any]:
    global ACCESS_TOKEN
    if ACCESS_TOKEN is None:
        ACCESS_TOKEN = fetch_access_token(base_url, username, password)

    def do_request(token: str) -> dict[str, Any]:
        request = urllib.request.Request(
            url,
            headers={
                "Accept": "application/json",
                "Authorization": f"Bearer {token}",
            },
        )
        with urllib.request.urlopen(request, timeout=15) as response:
            return json.load(response)

    try:
        return do_request(ACCESS_TOKEN)
    except urllib.error.HTTPError as error:
        if error.code != 401:
            raise
        ACCESS_TOKEN = fetch_access_token(base_url, username, password)
        return do_request(ACCESS_TOKEN)


def list_dags(base_url: str, username: str, password: str) -> list[dict[str, Any]]:
    query = urllib.parse.urlencode({"limit": 1000})
    url = f"{base_url.rstrip('/')}/api/v2/dags?{query}"
    payload = make_request(url, base_url, username, password)
    return payload.get("dags", [])


def format_local_timestamp(timestamp: str | None) -> str:
    if not timestamp:
        return "unknown end time"
    try:
        normalized = timestamp.replace("Z", "+00:00")
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        local_dt = parsed.astimezone()
        return local_dt.strftime("%Y-%m-%d %H:%M:%S %Z")
    except ValueError:
        return str(timestamp)


def load_inferred_dag_ids() -> set[str]:
    inferred: set[str] = set()
    state_paths = [
        WATCHER_STATE_PATH,
        SUCCESS_PANEL_STATE_PATH,
        FAILURE_PANEL_STATE_PATH,
    ]
    for state_path in state_paths:
        if not os.path.exists(state_path):
            continue
        try:
            with open(state_path, "r", encoding="utf-8") as state_file:
                payload = json.load(state_file)
        except Exception:
            continue

        if not isinstance(payload, dict):
            continue

        for item in payload.get("dag_failures", []):
            if isinstance(item, dict) and item.get("dag_id"):
                inferred.add(str(item["dag_id"]))
        for item in payload.get("task_states", []):
            if isinstance(item, dict) and item.get("dag_id"):
                inferred.add(str(item["dag_id"]))
        for item in payload.get("runs_with_task_alerts", []):
            if isinstance(item, dict) and item.get("dag_id"):
                inferred.add(str(item["dag_id"]))
        for item in payload.get("manual_successes", []):
            if isinstance(item, dict) and item.get("dag_id"):
                inferred.add(str(item["dag_id"]))
        for item in payload.get("items", []):
            if isinstance(item, dict) and item.get("dagId"):
                inferred.add(str(item["dagId"]))
            elif isinstance(item, dict) and item.get("title", "").startswith("Airflow "):
                title = str(item.get("title", ""))
                if ":" in title and "." in title:
                    dag_task = title.split(": ", 1)[1]
                    dag_id = dag_task.rsplit(".", 1)[0]
                    if dag_id:
                        inferred.add(dag_id)
    return inferred


def build_airflow_url(base_url: str, dag_id: str, run_id: str, task_id: str | None = None) -> str:
    encoded_dag_id = urllib.parse.quote(dag_id, safe="")
    encoded_run_id = urllib.parse.quote(run_id, safe="")
    if task_id:
        encoded_task_id = urllib.parse.quote(task_id, safe="")
        return (
            f"{base_url.rstrip('/')}/dags/{encoded_dag_id}/runs/{encoded_run_id}/"
            f"tasks/{encoded_task_id}"
        )
    return f"{base_url.rstrip('/')}/dags/{encoded_dag_id}/runs/{encoded_run_id}"


def build_airflow_error_url(base_url: str, dag_id: str, run_id: str, task_id: str | None = None) -> str:
    base = build_airflow_url(base_url, dag_id, run_id, task_id)
    separator = "&" if "?" in base else "?"
    return f"{base}{separator}tab=logs&search=error&log_level=error"


def show_notification(title: str, message: str) -> None:
    script = """
on run argv
    display notification (item 2 of argv) with title (item 1 of argv) sound name "Submarine"
end run
"""
    subprocess.Popen(["/usr/bin/osascript", "-e", script, title, message])


def classify_dialog_kind(title: str) -> str:
    normalized = title.lower()
    if "failed" in normalized or "retrying" in normalized:
        return "failure"
    if "succeeded" in normalized or "success" in normalized:
        return "success"
    return "generic"


def show_dialog(title: str, message: str, open_url: str) -> None:
    kind = classify_dialog_kind(title)
    run_dialog(title, message, open_url, kind)


def run_dialog(title: str, message: str, open_url: str, kind: str) -> str:
    if os.path.exists(NATIVE_DIALOG_HELPER):
        result = subprocess.run(
            [
                NATIVE_DIALOG_HELPER,
                "--kind",
                kind,
                "--title",
                title,
                "--message",
                message,
                "--url",
                open_url,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            button = result.stdout.strip()
            return button or "Dismiss"
        print(
            f"Native dialog helper failed for '{title}': {result.stderr.strip()}",
            file=sys.stderr,
            flush=True,
        )

    script = """
on run argv
    set dialogTitle to item 1 of argv
    set dialogMessage to item 2 of argv
    set openUrl to item 3 of argv
    set dialogResult to display dialog dialogMessage with title dialogTitle buttons {"Dismiss", "Open in Airflow"} default button "Dismiss"
    if button returned of dialogResult is "Open in Airflow" then
        do shell script "/usr/bin/open " & quoted form of openUrl
        return "Open in Airflow"
    end if
    return "Dismiss"
end run
"""
    result = subprocess.run(
        ["/usr/bin/osascript", "-e", script, title, message, open_url],
        capture_output=True,
        text=True,
        check=False,
    )
    button = result.stdout.strip() or "Dismiss"
    if result.returncode != 0:
        print(
            f"Could not show dialog for '{title}': {result.stderr.strip()}",
            file=sys.stderr,
            flush=True,
        )
        return "Dismiss"
    return button


def write_panel_runtime(runtime_path: str, *, visible: bool, minimized: bool = False) -> None:
    os.makedirs(os.path.dirname(runtime_path), exist_ok=True)
    with open(runtime_path, "w", encoding="utf-8") as runtime_file:
        json.dump({"visible": visible, "minimized": minimized}, runtime_file)


def enqueue_dialog(title: str, message: str, open_url: str, kind: str) -> None:
    os.makedirs(DIALOG_QUEUE_DIR, exist_ok=True)
    payload = {
        "title": title,
        "message": message,
        "url": open_url,
        "kind": kind,
        "createdAtNs": time.time_ns(),
    }
    item_path = os.path.join(DIALOG_QUEUE_DIR, f"{payload['createdAtNs']}.json")
    with open(item_path, "w", encoding="utf-8") as item_file:
        json.dump(payload, item_file)


def load_runtime_pid() -> int | None:
    if not os.path.exists(DIALOG_RUNTIME_PATH):
        return None
    try:
        with open(DIALOG_RUNTIME_PATH, "r", encoding="utf-8") as runtime_file:
            payload = json.load(runtime_file)
        pid = int(payload.get("pid"))
    except Exception:
        return None
    try:
        os.kill(pid, 0)
    except OSError:
        return None
    return pid


def write_runtime_pid(pid: int) -> None:
    os.makedirs(os.path.dirname(DIALOG_RUNTIME_PATH), exist_ok=True)
    with open(DIALOG_RUNTIME_PATH, "w", encoding="utf-8") as runtime_file:
        json.dump({"pid": pid}, runtime_file)


def clear_runtime_pid() -> None:
    try:
        os.remove(DIALOG_RUNTIME_PATH)
    except FileNotFoundError:
        return


def ensure_dialog_queue_worker() -> None:
    if load_runtime_pid() is not None:
        return
    proc = subprocess.Popen(
        [sys.executable, os.path.abspath(__file__), "--drain-dialog-queue"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        text=True,
    )
    # Give the worker a moment to write its PID file, then verify only one
    # worker is running (guards against a rare double-spawn race).
    time.sleep(0.05)
    if load_runtime_pid() is None:
        write_runtime_pid(proc.pid)


def next_dialog_item_path() -> str | None:
    if not os.path.isdir(DIALOG_QUEUE_DIR):
        return None
    item_names = sorted(name for name in os.listdir(DIALOG_QUEUE_DIR) if name.endswith(".json"))
    if not item_names:
        return None
    return os.path.join(DIALOG_QUEUE_DIR, item_names[0])


def drain_dialog_queue() -> int:
    write_runtime_pid(os.getpid())
    try:
        while True:
            item_path = next_dialog_item_path()
            if item_path is None:
                return 0
            try:
                with open(item_path, "r", encoding="utf-8") as item_file:
                    payload = json.load(item_file)
            except Exception:
                try:
                    os.remove(item_path)
                except FileNotFoundError:
                    pass
                continue

            run_dialog(
                str(payload.get("title", "Dagsy: Your DAG Watcher")),
                str(payload.get("message", "")),
                str(payload.get("url", "http://localhost:8080")),
                str(payload.get("kind", "generic")),
            )
            try:
                os.remove(item_path)
            except FileNotFoundError:
                pass
    except Exception as error:
        print(f"Dialog queue worker error: {error}", file=sys.stderr, flush=True)
        return 1
    finally:
        clear_runtime_pid()


def emit_popup(popup_mode: str, title: str, message: str, open_url: str) -> None:
    if popup_mode == "notification":
        show_notification(title, message)
    else:
        show_dialog(title, message, open_url)


def list_recent_runs(
    base_url: str,
    username: str,
    password: str,
    limit: int,
    watched_dag_ids: set[str],
) -> list[dict[str, Any]]:
    dag_ids = sorted(watched_dag_ids) if watched_dag_ids else [
        dag.get("dag_id", "") for dag in list_dags(base_url, username, password)
    ]

    dag_runs: list[dict[str, Any]] = []
    for dag_id in dag_ids:
        if not dag_id:
            continue
        dag_id_encoded = urllib.parse.quote(dag_id, safe="")
        query = urllib.parse.urlencode({"order_by": "-start_date", "limit": limit})
        url = f"{base_url.rstrip('/')}/api/v2/dags/{dag_id_encoded}/dagRuns?{query}"
        payload = make_request(url, base_url, username, password)
        dag_runs.extend(payload.get("dag_runs", []))

    def sort_key(item: dict[str, Any]) -> str:
        return item.get("start_date") or item.get("logical_date") or ""

    return sorted(dag_runs, key=sort_key, reverse=True)


def list_task_instances(
    base_url: str,
    username: str,
    password: str,
    dag_id: str,
    dag_run_id: str,
) -> list[dict[str, Any]]:
    dag_id_encoded = urllib.parse.quote(dag_id, safe="")
    dag_run_id_encoded = urllib.parse.quote(dag_run_id, safe="")
    url = (
        f"{base_url.rstrip('/')}/api/v2/dags/{dag_id_encoded}/dagRuns/"
        f"{dag_run_id_encoded}/taskInstances"
    )
    payload = make_request(url, base_url, username, password)
    return payload.get("task_instances", [])


def get_run_type(dag_run: dict[str, Any]) -> str:
    return str(dag_run.get("run_type") or dag_run.get("dag_run_type") or "").lower()


def is_manual_run(dag_run: dict[str, Any]) -> bool:
    run_type = get_run_type(dag_run)
    run_id = str(dag_run.get("dag_run_id") or "")
    return run_type == "manual" or run_id.startswith("manual__")


def is_successful_manual_run(dag_run: dict[str, Any]) -> bool:
    return dag_run.get("state") == "success" and is_manual_run(dag_run)


def should_notify_success(dag_run: dict[str, Any], had_task_alerts: bool) -> bool:
    return dag_run.get("state") == "success" and (is_manual_run(dag_run) or had_task_alerts)


@dataclass(frozen=True)
class DagRunKey:
    dag_id: str
    run_id: str


@dataclass(frozen=True)
class SuccessfulRunKey:
    dag_id: str
    run_id: str
    end_date: str | None


@dataclass(frozen=True)
class TaskStateKey:
    dag_id: str
    run_id: str
    task_id: str
    state: str
    try_number: int | None
    end_date: str | None


def load_watcher_state() -> tuple[
    set[DagRunKey],
    set[TaskStateKey],
    set[DagRunKey],
    set[SuccessfulRunKey],
    bool,
]:
    try:
        with open(WATCHER_STATE_PATH, "r", encoding="utf-8") as state_file:
            payload = json.load(state_file)
    except FileNotFoundError:
        return set(), set(), set(), set(), False
    except Exception:
        return set(), set(), set(), set(), False

    dag_failures = {
        DagRunKey(str(item.get("dag_id", "")), str(item.get("run_id", "")))
        for item in payload.get("dag_failures", [])
        if isinstance(item, dict)
    }
    task_states = {
        TaskStateKey(
            dag_id=str(item.get("dag_id", "")),
            run_id=str(item.get("run_id", "")),
            task_id=str(item.get("task_id", "")),
            state=str(item.get("state", "")),
            try_number=item.get("try_number"),
            end_date=item.get("end_date"),
        )
        for item in payload.get("task_states", [])
        if isinstance(item, dict)
    }
    runs_with_task_alerts = {
        DagRunKey(str(item.get("dag_id", "")), str(item.get("run_id", "")))
        for item in payload.get("runs_with_task_alerts", [])
        if isinstance(item, dict)
    }
    manual_successes = {
        SuccessfulRunKey(
            dag_id=str(item.get("dag_id", "")),
            run_id=str(item.get("run_id", "")),
            end_date=item.get("end_date"),
        )
        for item in payload.get("manual_successes", [])
        if isinstance(item, dict)
    }
    initialized = bool(payload.get("initialized"))
    return dag_failures, task_states, runs_with_task_alerts, manual_successes, initialized


def save_watcher_state(
    dag_failures: set[DagRunKey],
    task_states: set[TaskStateKey],
    runs_with_task_alerts: set[DagRunKey],
    manual_successes: set[SuccessfulRunKey],
) -> None:
    os.makedirs(os.path.dirname(WATCHER_STATE_PATH), exist_ok=True)
    payload = {
        "initialized": True,
        "dag_failures": sorted((asdict(item) for item in dag_failures), key=lambda item: (item["dag_id"], item["run_id"])),
        "task_states": sorted(
            (asdict(item) for item in task_states),
            key=lambda item: (
                item["dag_id"],
                item["run_id"],
                item["task_id"],
                item["state"],
                item["try_number"] if item["try_number"] is not None else -1,
                item["end_date"] or "",
            ),
        ),
        "runs_with_task_alerts": sorted(
            (asdict(item) for item in runs_with_task_alerts),
            key=lambda item: (item["dag_id"], item["run_id"]),
        ),
        "manual_successes": sorted(
            (asdict(item) for item in manual_successes),
            key=lambda item: (item["dag_id"], item["run_id"], item["end_date"] or ""),
        ),
    }
    temp_path = WATCHER_STATE_PATH + ".tmp"
    with open(temp_path, "w", encoding="utf-8") as state_file:
        json.dump(payload, state_file)
    os.replace(temp_path, WATCHER_STATE_PATH)


class SuccessPanelManager:
    def __init__(self, environment_label: str, popup_mode: str) -> None:
        self.environment_label = environment_label
        self.popup_mode = popup_mode
        self.helper_path = os.path.expanduser("~/Applications/airflow-success-panel")
        self.state_dir = os.path.expanduser("~/Library/Application Support/local-airflow-watcher")
        self.state_path = os.path.join(self.state_dir, "success_panel_state.json")
        self.runtime_path = SUCCESS_PANEL_RUNTIME_PATH
        self.helper_process: subprocess.Popen[str] | None = None
        self.ui_enabled = popup_mode == "dialog"
        self._known_runs: set[SuccessfulRunKey] = set()
        os.makedirs(self.state_dir, exist_ok=True)
        self._items: list[dict[str, str]] = self._load_existing_items()

    def process_events(self) -> None:
        return

    def add_success(self, dag_run: dict[str, Any], base_url: str) -> None:
        self._items = self._load_existing_items()
        dag_key = SuccessfulRunKey(
            dag_id=dag_run.get("dag_id", ""),
            run_id=dag_run.get("dag_run_id", ""),
            end_date=dag_run.get("end_date"),
        )
        if dag_key in self._known_runs:
            return

        self._known_runs.add(dag_key)
        dag_id = dag_run.get("dag_id", "<unknown dag>")
        run_id = dag_run.get("dag_run_id", "<unknown run>")
        end_date = dag_run.get("end_date") or "unknown end time"
        title, message = build_success_message(dag_id, run_id, end_date)
        open_url = build_airflow_url(base_url, dag_id, run_id)
        if not self.ui_enabled:
            emit_popup(self.popup_mode, title, message, open_url)
            return

        self._items.append(
            {
                "title": title,
                "message": message,
                "dagId": dag_id,
                "runId": run_id,
                "endDate": end_date,
                "url": open_url,
                "token": str(time.time_ns()),
            }
        )
        self._items = self._items[-MAX_SUCCESS_ITEMS:]
        self._write_state_file()
        self._ensure_helper_started()
        if not self.ui_enabled:
            # Helper failed to start — fall back to a direct popup
            emit_popup(self.popup_mode, title, message, open_url)

    def _write_state_file(self) -> None:
        payload = {
            "environmentLabel": self.environment_label,
            "items": self._items,
        }
        with open(self.state_path, "w", encoding="utf-8") as state_file:
            json.dump(payload, state_file)
        write_panel_runtime(self.runtime_path, visible=bool(self._items))

    def _load_existing_items(self) -> list[dict[str, str]]:
        if not os.path.exists(self.state_path):
            return []
        try:
            with open(self.state_path, "r", encoding="utf-8") as state_file:
                payload = json.load(state_file)
            items = payload.get("items", [])
            if not isinstance(items, list):
                return []

            normalized_items: list[dict[str, str]] = []
            for item in items[-MAX_SUCCESS_ITEMS:]:
                if not isinstance(item, dict):
                    continue
                dag_id = str(item.get("dagId", ""))
                run_id = str(item.get("runId", ""))
                end_date = str(item.get("endDate", ""))
                url = str(item.get("url", ""))
                if not dag_id or not run_id:
                    continue
                normalized_items.append(
                    {
                        "title": str(item.get("title", "")),
                        "message": str(item.get("message", "")),
                        "dagId": dag_id,
                        "runId": run_id,
                        "endDate": end_date,
                        "url": url,
                        "token": str(item.get("token", "")),
                    }
                )
                self._known_runs.add(
                    SuccessfulRunKey(
                        dag_id=dag_id,
                        run_id=run_id,
                        end_date=end_date or None,
                    )
                )
            return normalized_items
        except Exception:
            return []

    def _ensure_helper_started(self) -> None:
        if not os.path.exists(self.helper_path):
            self.ui_enabled = False
            return
        if self.helper_process is not None and self.helper_process.poll() is None:
            return
        try:
            self.helper_process = subprocess.Popen(
                [self.helper_path, self.state_path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
                text=True,
            )
            time.sleep(0.15)
            if self.helper_process.poll() is not None:
                raise RuntimeError(
                    f"success panel helper exited immediately with status {self.helper_process.returncode}"
                )
        except Exception as error:
            print(f"Could not start success panel helper: {error}", file=sys.stderr, flush=True)
            self.ui_enabled = False

    def _cleanup_existing_helpers(self) -> None:
        if not os.path.exists(self.helper_path):
            return
        try:
            subprocess.run(
                ["pkill", "-f", self.helper_path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        except Exception:
            return


class FailurePanelManager:
    def __init__(self, environment_label: str, popup_mode: str) -> None:
        self.environment_label = environment_label
        self.popup_mode = popup_mode
        self.helper_path = os.path.expanduser("~/Applications/airflow-failure-alert")
        self.state_dir = os.path.expanduser("~/Library/Application Support/local-airflow-watcher")
        self.state_path = os.path.join(self.state_dir, "failure_panel_state.json")
        self.runtime_path = FAILURE_PANEL_RUNTIME_PATH
        self.helper_process: subprocess.Popen[str] | None = None
        self.ui_enabled = popup_mode == "dialog"
        os.makedirs(self.state_dir, exist_ok=True)
        self._items: list[dict[str, str]] = self._load_existing_items()

    def show_failure(self, title: str, message: str, open_url: str) -> None:
        self._items = self._load_existing_items()
        if not self.ui_enabled:
            emit_popup(self.popup_mode, title, message, open_url)
            return
        self._items.append(
            {
                "title": title,
                "message": message,
                "url": open_url,
                "token": str(time.time_ns()),
            }
        )
        self._items = self._items[-MAX_SUCCESS_ITEMS:]
        self._write_state_file()
        self._ensure_helper_started()
        if not self.ui_enabled:
            # Helper failed to start — fall back to a direct popup
            emit_popup(self.popup_mode, title, message, open_url)

    def _write_state_file(self) -> None:
        payload = {
            "environmentLabel": self.environment_label,
            "items": self._items,
        }
        with open(self.state_path, "w", encoding="utf-8") as state_file:
            json.dump(payload, state_file)
        write_panel_runtime(self.runtime_path, visible=bool(self._items))

    def _load_existing_items(self) -> list[dict[str, str]]:
        if not os.path.exists(self.state_path):
            return []
        try:
            with open(self.state_path, "r", encoding="utf-8") as state_file:
                payload = json.load(state_file)
            items = payload.get("items", [])
            if not isinstance(items, list):
                return []
            normalized_items: list[dict[str, str]] = []
            for item in items[-MAX_SUCCESS_ITEMS:]:
                if not isinstance(item, dict):
                    continue
                normalized_items.append(
                    {
                        "title": str(item.get("title", "")),
                        "message": str(item.get("message", "")),
                        "url": str(item.get("url", "")),
                        "token": str(item.get("token", "")),
                    }
                )
            return normalized_items
        except Exception:
            return []

    def _ensure_helper_started(self) -> None:
        if not os.path.exists(self.helper_path):
            self.ui_enabled = False
            return
        if self.helper_process is not None and self.helper_process.poll() is None:
            return
        try:
            self.helper_process = subprocess.Popen(
                [self.helper_path, self.state_path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
                text=True,
            )
            time.sleep(0.15)
            if self.helper_process.poll() is not None:
                raise RuntimeError(
                    f"failure panel helper exited immediately with status {self.helper_process.returncode}"
                )
        except Exception as error:
            print(f"Could not start failure panel helper: {error}", file=sys.stderr, flush=True)
            self.ui_enabled = False

    def _cleanup_existing_helpers(self) -> None:
        if not os.path.exists(self.helper_path):
            return
        try:
            subprocess.run(
                ["pkill", "-f", self.helper_path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        except Exception:
            return


def seed_seen_keys(
    base_url: str,
    username: str,
    password: str,
    limit: int,
    watched_dag_ids: set[str],
    watcher_start_time: datetime,
) -> tuple[set[DagRunKey], set[TaskStateKey], set[DagRunKey], set[DagRunKey]]:
    dag_failures: set[DagRunKey] = set()
    task_states: set[TaskStateKey] = set()
    runs_with_task_alerts: set[DagRunKey] = set()
    successful_manual_runs: set[SuccessfulRunKey] = set()
    recent_runs = list_recent_runs(base_url, username, password, limit, watched_dag_ids)

    for dag_run in recent_runs:
        dag_id = dag_run.get("dag_id", "")
        run_id = dag_run.get("dag_run_id", "")
        dag_key = DagRunKey(dag_id, run_id)
        if dag_run.get("state") == "failed":
            dag_failures.add(dag_key)
        if not dag_id or not run_id:
            continue
        for task_instance in list_task_instances(base_url, username, password, dag_id, run_id):
            state = task_instance.get("state")
            if state not in {"up_for_retry", "failed"}:
                continue
            runs_with_task_alerts.add(dag_key)
            task_states.add(
                TaskStateKey(
                    dag_id=dag_id,
                    run_id=run_id,
                    task_id=task_instance.get("task_id", ""),
                    state=state,
                    try_number=task_instance.get("try_number"),
                    end_date=task_instance.get("end_date"),
                )
            )
        # Seed successful runs that completed BEFORE the watcher started so
        # they don't trigger popups. Runs that completed after watcher_start_time
        # are left unseeded so they do trigger a popup.
        if should_notify_success(dag_run, dag_key in runs_with_task_alerts):
            end_date_str = dag_run.get("end_date")
            if end_date_str:
                try:
                    end_dt = datetime.fromisoformat(end_date_str.replace("Z", "+00:00"))
                    if end_dt.tzinfo is None:
                        end_dt = end_dt.replace(tzinfo=timezone.utc)
                    if end_dt < watcher_start_time:
                        successful_manual_runs.add(
                            SuccessfulRunKey(
                                dag_id=dag_id,
                                run_id=run_id,
                                end_date=end_date_str,
                            )
                        )
                except ValueError:
                    pass
    return dag_failures, task_states, runs_with_task_alerts, successful_manual_runs


def build_dag_failure_message(dag_run: dict[str, Any]) -> tuple[str, str]:
    dag_id = dag_run.get("dag_id", "<unknown dag>")
    run_id = dag_run.get("dag_run_id", "<unknown run>")
    end_date = format_local_timestamp(dag_run.get("end_date"))
    manual_prefix = "Manual run\n" if is_manual_run(dag_run) else ""
    title = f"Airflow DAG failed: {dag_id}"
    message = f"{manual_prefix}DAG: {dag_id}\nRun: {run_id}\nFailed: {end_date}\n\nOpen the Airflow run for details."
    return title, message


def build_task_message(task_instance: dict[str, Any], dag_run_id: str) -> tuple[str, str]:
    dag_id = task_instance.get("dag_id", "<unknown dag>")
    task_id = task_instance.get("task_id", "<unknown task>")
    state = task_instance.get("state", "")
    try_number = task_instance.get("try_number")
    max_tries = task_instance.get("max_tries")
    end_date = format_local_timestamp(task_instance.get("end_date"))
    attempt_text = f"{try_number}/{max_tries}" if max_tries not in (None, 0) else str(try_number)
    manual_prefix = "Manual run\n" if str(dag_run_id).startswith("manual__") else ""
    if state == "up_for_retry":
        title = f"Airflow task retrying: {dag_id}.{task_id}"
        message = (
            f"{manual_prefix}Task: {task_id}\nDAG: {dag_id}\nRun: {dag_run_id}\n"
            f"Retry scheduled after attempt {attempt_text}\n\nOpen the Airflow task for details."
        )
    else:
        title = f"Airflow task failed: {dag_id}.{task_id}"
        message = (
            f"{manual_prefix}Task: {task_id}\nDAG: {dag_id}\nRun: {dag_run_id}\n"
            f"Failed: {end_date}\nAttempt: {attempt_text}\n\nOpen the Airflow task for details."
        )
    return title, message


def build_success_message(dag_id: str, run_id: str, end_date: str) -> tuple[str, str]:
    title = f"Manual DAG succeeded: {dag_id}"
    message = (
        f"Manual run\nDAG: {dag_id}\nRun: {run_id}\nFinished: {format_local_timestamp(end_date)}\n\n"
        "Open the Airflow run for details."
    )
    return title, message


def clear_stale_ui_state() -> None:
    """Delete leftover panel messages and queued dialogs from previous runs."""
    for path in (SUCCESS_PANEL_STATE_PATH, FAILURE_PANEL_STATE_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    if os.path.isdir(DIALOG_QUEUE_DIR):
        for name in os.listdir(DIALOG_QUEUE_DIR):
            try:
                os.remove(os.path.join(DIALOG_QUEUE_DIR, name))
            except FileNotFoundError:
                pass
    for helper in ("airflow-success-panel", "airflow-failure-alert", "airflow-dialog-helper"):
        subprocess.run(
            ["pkill", "-f", os.path.expanduser(f"~/Applications/{helper}")],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )


def main() -> int:
    args = parse_args()
    if args.drain_dialog_queue:
        return drain_dialog_queue()

    clear_stale_ui_state()
    watcher_start_time = datetime.now(tz=timezone.utc)
    watched_dag_ids = set(args.dag_id)
    if not watched_dag_ids:
        watched_dag_ids = load_inferred_dag_ids()
    success_panel = SuccessPanelManager(args.environment_label, args.popup_mode)
    failure_panel = FailurePanelManager(args.environment_label, args.popup_mode)

    print(
        f"Watching local Airflow at {args.base_url} every {args.poll_interval}s",
        flush=True,
    )
    if watched_dag_ids:
        print("Filtering to DAGs: " + ", ".join(sorted(watched_dag_ids)), flush=True)

    (
        seen_dag_failures,
        seen_task_states,
        runs_with_task_alerts,
        seen_manual_successes,
        _,
    ) = load_watcher_state()
    seeded = False

    while True:
        try:
            if not seeded:
                (
                    seen_dag_failures,
                    seen_task_states,
                    runs_with_task_alerts,
                    seen_manual_successes,
                ) = seed_seen_keys(
                    base_url=args.base_url,
                    username=args.username,
                    password=args.password,
                    limit=args.limit,
                    watched_dag_ids=watched_dag_ids,
                    watcher_start_time=watcher_start_time,
                )
                print(
                    "Seeded "
                    f"{len(seen_dag_failures)} existing DAG failures, "
                    f"{len(seen_task_states)} existing task states, and "
                    f"{len(seen_manual_successes)} existing successful manual DAG runs.",
                    flush=True,
                )
                seeded = True
                save_watcher_state(
                    seen_dag_failures,
                    seen_task_states,
                    runs_with_task_alerts,
                    seen_manual_successes,
                )

            recent_runs = list_recent_runs(
                base_url=args.base_url,
                username=args.username,
                password=args.password,
                limit=args.limit,
                watched_dag_ids=watched_dag_ids,
            )
            for dag_run in recent_runs:
                dag_id = dag_run.get("dag_id", "")
                run_id = dag_run.get("dag_run_id", "")
                dag_key = DagRunKey(dag_id, run_id)
                manual_run = is_manual_run(dag_run)

                if not dag_id or not run_id:
                    continue
                if not manual_run and dag_key not in runs_with_task_alerts and not is_successful_manual_run(dag_run):
                    continue

                emitted_task_popup_for_run = False
                task_instances = list_task_instances(
                    base_url=args.base_url,
                    username=args.username,
                    password=args.password,
                    dag_id=dag_id,
                    dag_run_id=run_id,
                )
                for task_instance in task_instances:
                    state = task_instance.get("state")
                    if state not in {"up_for_retry", "failed"}:
                        continue

                    task_key = TaskStateKey(
                        dag_id=dag_id,
                        run_id=run_id,
                        task_id=task_instance.get("task_id", ""),
                        state=state,
                        try_number=task_instance.get("try_number"),
                        end_date=task_instance.get("end_date"),
                    )
                    if task_key in seen_task_states:
                        continue

                    seen_task_states.add(task_key)
                    emitted_task_popup_for_run = True
                    runs_with_task_alerts.add(dag_key)
                    save_watcher_state(
                        seen_dag_failures,
                        seen_task_states,
                        runs_with_task_alerts,
                        seen_manual_successes,
                    )
                    title, message = build_task_message(task_instance, run_id)
                    print(f"{title} | {message}", flush=True)
                    failure_url = build_airflow_error_url(
                        args.base_url,
                        dag_id,
                        run_id,
                        task_instance.get("task_id"),
                    )
                    if args.popup_mode == "notification":
                        emit_popup(args.popup_mode, title, message, failure_url)
                    else:
                        failure_panel.show_failure(title, message, failure_url)

                if dag_run.get("state") == "failed":
                    if dag_key in seen_dag_failures:
                        continue
                    seen_dag_failures.add(dag_key)
                    if dag_key in runs_with_task_alerts or emitted_task_popup_for_run:
                        print(
                            f"Skipping DAG popup for {dag_id} {run_id} because a task-level popup already exists.",
                            flush=True,
                        )
                        save_watcher_state(
                            seen_dag_failures,
                            seen_task_states,
                            runs_with_task_alerts,
                            seen_manual_successes,
                        )
                        continue
                    title, message = build_dag_failure_message(dag_run)
                    print(f"{title} | {message}", flush=True)
                    failure_url = build_airflow_error_url(args.base_url, dag_id, run_id)
                    if args.popup_mode == "notification":
                        emit_popup(args.popup_mode, title, message, failure_url)
                    else:
                        failure_panel.show_failure(title, message, failure_url)
                    save_watcher_state(
                        seen_dag_failures,
                        seen_task_states,
                        runs_with_task_alerts,
                        seen_manual_successes,
                    )
                    continue

                success_key = SuccessfulRunKey(
                    dag_id=dag_id,
                    run_id=run_id,
                    end_date=dag_run.get("end_date"),
                )
                if should_notify_success(dag_run, dag_key in runs_with_task_alerts) and success_key not in seen_manual_successes:
                    seen_manual_successes.add(success_key)
                    print(
                        f"DAG succeeded: {dag_id} | Run: {run_id} | Finished: {dag_run.get('end_date')}",
                        flush=True,
                    )
                    success_panel.add_success(dag_run, args.base_url)
                    save_watcher_state(
                        seen_dag_failures,
                        seen_task_states,
                        runs_with_task_alerts,
                        seen_manual_successes,
                    )
        except urllib.error.HTTPError as error:
            print(
                f"Watcher HTTP error for {error.url}: HTTP {error.code} {error.reason}",
                file=sys.stderr,
                flush=True,
            )
        except urllib.error.URLError as error:
            print(
                f"Could not reach local Airflow at {args.base_url}: {error}",
                file=sys.stderr,
                flush=True,
            )
        except Exception as error:
            print(f"Watcher error: {error}", file=sys.stderr, flush=True)

        success_panel.process_events()
        time.sleep(args.poll_interval)


if __name__ == "__main__":
    raise SystemExit(main())
