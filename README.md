# Dagsy — Local Airflow DAG Watcher

Dagsy is a lightweight macOS menu-bar application that monitors a locally running Apache Airflow instance and instantly notifies you about DAG and task failures, retries, and successful manual runs — without you having to keep the Airflow UI open.

---

## Why Dagsy?

When developing data pipelines locally with Astronomer or a plain Airflow stack, you're often context-switching between your editor, the terminal, and the Airflow UI. Dagsy removes the manual checking:

- **Catch failures the moment they happen** — no more refreshing the Airflow UI
- **Distinguish task retries from final failures** — so you don't panic prematurely
- **Know when a manual run finishes** — especially useful for long-running backfills
- **Stay in flow** — alerts surface as native macOS dialogs or notifications, not browser tabs

---

## Features

| Feature | Details |
|---|---|
| Task failure alerts | Pop-up dialog with task name, DAG, run ID, attempt number, and a direct "Open in Airflow" button pointing at the error log |
| Task retry alerts | Notifies on each retry attempt so you can monitor progress |
| DAG-level failure alerts | Triggered when the whole DAG run fails (deduplicated against task-level alerts) |
| Manual run success alerts | Notifies when a manually triggered DAG run completes successfully |
| Failure panel | Persistent panel listing all recent failures with one-click links |
| Success panel | Persistent panel listing recent successful manual runs |
| Dialog queue | Alerts are queued so they're shown one-by-one and never lost |
| Configurable polling | Poll interval, base URL, credentials, and DAG filter are all CLI flags |
| State persistence | Watcher state survives restarts — no duplicate alerts after a reboot |

---

## Requirements

- macOS 10.15 or later
- Python 3 (`/usr/bin/python3` — ships with macOS, no install needed)
- A locally running Airflow instance (e.g. via [Astronomer CLI](https://www.astronomer.io/docs/astro/cli/overview))
- Three pre-compiled helper binaries (see [Building the .app](#building-the-app))

---

## Project Structure

```
Dagsy/
├── watch_local_airflow_failures.py   # Core watcher script (pure Python, no deps)
├── app/
│   └── Info.plist                    # macOS bundle metadata
├── assets/
│   └── applet.icns                   # App icon
├── scripts/
│   └── build_app.sh                  # Packages everything into Dagsy.app
└── README.md
```

---

## Building the .app

### Prerequisites

The `.app` bundle requires three pre-compiled native binaries that are **not** included in this repo (they are compiled separately as Swift/Objective-C apps):

| Binary | Role | Default expected path |
|---|---|---|
| `airflow-dag-listener-controller` | App controller — launches the watcher script | `~/Applications/airflow-dag-listener-controller` |
| `airflow-failure-alert` | Native failure panel UI | `~/Applications/airflow-failure-alert` |
| `airflow-success-panel` | Native success panel UI | `~/Applications/airflow-success-panel` |

Place these binaries in `~/Applications/` before running the build script, or override via environment variables:

```bash
export CONTROLLER_BIN=/path/to/airflow-dag-listener-controller
export FAILURE_PANEL=/path/to/airflow-failure-alert
export SUCCESS_PANEL=/path/to/airflow-success-panel
```

### Run the build

```bash
chmod +x scripts/build_app.sh
./scripts/build_app.sh
```

By default the `.app` is written to `~/Applications/Dagsy.app`. Override with `--dest`:

```bash
./scripts/build_app.sh --dest ~/Desktop/Dagsy.app
```

The script will:
1. Validate all required binaries exist
2. Create the `.app` bundle layout under the destination path
3. Copy the `Info.plist`, icon, controller binary, and watcher script into the bundle
4. Install the two panel helpers next to the `.app`

---

## Running Dagsy

### Via the .app (recommended)

Double-click `Dagsy.app` in Finder or `~/Applications`, or drag it to `/Applications` first.

### Directly from the terminal

```bash
python3 watch_local_airflow_failures.py \
  --base-url http://localhost:8080 \
  --username admin \
  --password admin \
  --poll-interval 5
```

### CLI options

| Flag | Default | Description |
|---|---|---|
| `--base-url` | `http://localhost:8080` | Airflow base URL |
| `--username` | `admin` | Airflow username |
| `--password` | `admin` | Airflow password |
| `--poll-interval` | `5` | Seconds between polls |
| `--limit` | `20` | Max recent DAG runs to inspect per DAG |
| `--dag-id` | _(all DAGs)_ | Filter to specific DAG IDs (repeat for multiple) |
| `--popup-mode` | `dialog` | `dialog` for native panels, `notification` for macOS notifications |
| `--environment-label` | `local` | Label shown in alert panels |

Example — watch only two DAGs with macOS notifications:

```bash
python3 watch_local_airflow_failures.py \
  --dag-id my_etl_dag \
  --dag-id another_dag \
  --popup-mode notification
```

---

## State & Logs

Dagsy stores its runtime state in:

```
~/Library/Application Support/local-airflow-watcher/
├── watcher_state.json         # Seen failures/successes (survives restarts)
├── failure_panel_state.json   # Current failure panel contents
├── success_panel_state.json   # Current success panel contents
├── failure_panel_runtime.json # Panel visibility flag
├── success_panel_runtime.json # Panel visibility flag
└── dialog_queue/              # Queued alerts waiting to be shown
```

To reset all state (e.g. to re-seed from current Airflow state):

```bash
rm -rf ~/Library/Application\ Support/local-airflow-watcher/
```

---

## How It Works

1. On first run Dagsy **seeds** its state by scanning recent DAG runs — this prevents a flood of alerts for pre-existing failures.
2. Every `--poll-interval` seconds it fetches recent runs for all watched DAGs via the Airflow REST API v2.
3. New task failures/retries trigger a **failure panel** entry and a native dialog.
4. Successful manual runs (or runs that had task alerts and recovered) trigger a **success panel** entry.
5. Dialogs are serialised through a queue so they appear one at a time and are never dropped.

---

## License

MIT
