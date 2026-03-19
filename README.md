# Dagsy — Local Airflow DAG Watcher

> **macOS only** — Windows and Linux support is not available yet.

Dagsy is a lightweight macOS application that monitors a locally running Apache Airflow instance and instantly notifies you about DAG and task failures, retries, and successful manual runs — without keeping the Airflow UI open.

---

## Install (one command)

```bash
curl -fsSL https://raw.githubusercontent.com/liorbar777/Dagsy/main/install.sh | bash
```

Or clone and install:

```bash
git clone https://github.com/liorbar777/Dagsy.git
cd Dagsy
./install.sh
```

Then launch:

```bash
open ~/Applications/Dagsy.app
```

> **First launch blocked by macOS?**
> Go to **System Settings → Privacy & Security** → scroll down → click **Open Anyway**.

---

## Why Dagsy?

When developing data pipelines locally with Astronomer or a plain Airflow stack, you're constantly context-switching between your editor, the terminal, and the Airflow UI. Dagsy removes the manual checking:

- **Catch failures the moment they happen** — no more refreshing the Airflow UI
- **Distinguish task retries from final failures** — so you don't panic prematurely
- **Know when a manual run finishes** — especially useful for long-running backfills
- **Stay in flow** — alerts surface as native macOS dialogs, not browser tabs

---

## Features

| Feature | Details |
|---|---|
| Task failure alerts | Native dialog with task name, DAG, run ID, attempt number, and a direct "Open in Airflow" button pointing at the error log |
| Task retry alerts | Notifies on each retry attempt so you can monitor progress |
| DAG-level failure alerts | Triggered when the whole DAG run fails (deduplicated against task-level alerts) |
| Manual run success alerts | Notifies when a manually triggered DAG run completes successfully |
| Failure panel | Persistent panel listing all recent failures with one-click links |
| Success panel | Persistent panel listing recent successful manual runs |
| Dialog queue | Alerts are queued and shown one-by-one — none are ever lost |
| State persistence | Watcher state survives restarts — no duplicate alerts after a reboot |
| Configurable | Poll interval, Airflow URL, credentials, and DAG filter are all CLI flags |

---

## Requirements

- macOS 10.15 or later
- Python 3 (ships with macOS — no install needed)
- A locally running Airflow instance (e.g. via [Astronomer CLI](https://www.astronomer.io/docs/astro/cli/overview))

---

## Project Structure

```
Dagsy/
├── watch_local_airflow_failures.py   # Core watcher script (pure Python, no deps)
├── install.sh                        # One-command installer
├── bin/
│   ├── airflow-dag-listener-controller  # App controller binary (macOS arm64/x86_64)
│   ├── airflow-failure-alert            # Failure panel UI binary
│   └── airflow-success-panel            # Success panel UI binary
├── app/
│   └── Info.plist                    # macOS bundle metadata
├── assets/
│   └── applet.icns                   # App icon
├── scripts/
│   └── build_app.sh                  # Packages everything into Dagsy.app
└── README.md
```

---

## Building the .app manually

If you want to build the `.app` yourself instead of using `install.sh`:

```bash
git clone https://github.com/liorbar777/Dagsy.git
cd Dagsy
chmod +x scripts/build_app.sh
./scripts/build_app.sh
```

By default the `.app` is written to `~/Applications/Dagsy.app`. Override with `--dest`:

```bash
./scripts/build_app.sh --dest ~/Desktop/Dagsy.app
```

---

## Running without the .app

You can run the watcher directly from the terminal without building the app:

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

Example — watch two specific DAGs with macOS notifications:

```bash
python3 watch_local_airflow_failures.py \
  --dag-id my_etl_dag \
  --dag-id another_dag \
  --popup-mode notification
```

---

## State & Logs

Dagsy stores runtime state in:

```
~/Library/Application Support/local-airflow-watcher/
├── watcher_state.json         # Seen failures/successes (survives restarts)
├── failure_panel_state.json
├── success_panel_state.json
├── failure_panel_runtime.json
├── success_panel_runtime.json
└── dialog_queue/              # Queued alerts waiting to be shown
```

To fully reset state (re-seeds from current Airflow state on next launch):

```bash
rm -rf ~/Library/Application\ Support/local-airflow-watcher/
```

---

## How It Works

1. On first run Dagsy **seeds** its state by scanning recent DAG runs — preventing a flood of alerts for pre-existing failures.
2. Every `--poll-interval` seconds it fetches recent runs via the Airflow REST API v2.
3. New task failures/retries trigger a **failure panel** entry and a native dialog.
4. Successful manual runs trigger a **success panel** entry.
5. Dialogs are serialised through a queue so they appear one-by-one and are never dropped.

---

## License

MIT
