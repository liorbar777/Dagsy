#!/usr/bin/env python3
"""Shared Tk panel UI for local Airflow watcher state files."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tkinter as tk
from pathlib import Path
from tkinter import font as tkfont
from typing import Any

POLL_INTERVAL_MS = 1000
WINDOW_WIDTH = 500
WINDOW_HEIGHT = 620
PANEL_THEMES = {
    "success": {
        "title": "Airflow Successes",
        "accent": "#177245",
        "surface": "#f2fbf5",
        "border": "#cfe8d6",
        "button": "#177245",
        "button_fg": "#ffffff",
    },
    "failure": {
        "title": "Airflow Failures",
        "accent": "#9f1239",
        "surface": "#fff1f2",
        "border": "#fecdd3",
        "button": "#9f1239",
        "button_fg": "#ffffff",
    },
}


class AirflowPanelApp:
    def __init__(self, panel_kind: str, state_path: str) -> None:
        if panel_kind not in PANEL_THEMES:
            raise ValueError(f"Unsupported panel kind: {panel_kind}")
        self.panel_kind = panel_kind
        self.theme = PANEL_THEMES[panel_kind]
        self.state_path = Path(state_path).expanduser()
        self.root = tk.Tk()
        self.root.withdraw()
        self.root.configure(bg="#f8fafc")
        self.root.title(self.theme["title"])
        self.root.resizable(False, True)
        self.root.protocol("WM_DELETE_WINDOW", self.root.destroy)
        self.root.attributes("-topmost", True)
        self._last_signature: str | None = None

        self.title_font = tkfont.Font(size=16, weight="bold")
        self.subtitle_font = tkfont.Font(size=11)
        self.card_title_font = tkfont.Font(size=12, weight="bold")
        self.card_body_font = tkfont.Font(size=11)

        self._build_window()
        self.root.after(0, self._refresh)

    def _build_window(self) -> None:
        shell = tk.Frame(self.root, bg="#f8fafc", padx=16, pady=16)
        shell.pack(fill="both", expand=True)

        header = tk.Frame(shell, bg="#f8fafc")
        header.pack(fill="x")
        self.title_label = tk.Label(
            header,
            text=self.theme["title"],
            font=self.title_font,
            fg="#0f172a",
            bg="#f8fafc",
            anchor="w",
        )
        self.title_label.pack(side="left", fill="x", expand=True)
        self.count_label = tk.Label(
            header,
            text="",
            font=self.subtitle_font,
            fg="#475569",
            bg="#f8fafc",
            anchor="e",
        )
        self.count_label.pack(side="right")

        self.subtitle_label = tk.Label(
            shell,
            text="",
            font=self.subtitle_font,
            fg="#64748b",
            bg="#f8fafc",
            anchor="w",
            justify="left",
        )
        self.subtitle_label.pack(fill="x", pady=(6, 12))

        canvas_host = tk.Frame(shell, bg="#f8fafc")
        canvas_host.pack(fill="both", expand=True)

        self.canvas = tk.Canvas(
            canvas_host,
            bg="#f8fafc",
            bd=0,
            highlightthickness=0,
            width=WINDOW_WIDTH,
        )
        scrollbar = tk.Scrollbar(canvas_host, orient="vertical", command=self.canvas.yview)
        self.canvas.configure(yscrollcommand=scrollbar.set)
        scrollbar.pack(side="right", fill="y")
        self.canvas.pack(side="left", fill="both", expand=True)

        self.content_frame = tk.Frame(self.canvas, bg="#f8fafc")
        self.content_window = self.canvas.create_window((0, 0), window=self.content_frame, anchor="nw")
        self.content_frame.bind("<Configure>", self._on_frame_configure)
        self.canvas.bind("<Configure>", self._on_canvas_configure)

    def _on_frame_configure(self, _event: tk.Event[tk.Misc]) -> None:
        self.canvas.configure(scrollregion=self.canvas.bbox("all"))

    def _on_canvas_configure(self, event: tk.Event[tk.Misc]) -> None:
        self.canvas.itemconfigure(self.content_window, width=event.width)

    def _refresh(self) -> None:
        payload = self._load_payload()
        if payload is None:
            self.root.after(POLL_INTERVAL_MS, self._refresh)
            return

        items = payload.get("items", [])
        if not items:
            self.root.destroy()
            return

        signature = json.dumps(payload, sort_keys=True)
        if signature != self._last_signature:
            self._last_signature = signature
            self._rebuild(payload)
            self._show_and_position()

        self.root.after(POLL_INTERVAL_MS, self._refresh)

    def _show_and_position(self) -> None:
        self.root.update_idletasks()
        screen_width = self.root.winfo_screenwidth()
        screen_height = self.root.winfo_screenheight()
        width = WINDOW_WIDTH
        height = min(WINDOW_HEIGHT, max(360, screen_height - 160))
        x = max(24, screen_width - width - 32)
        y = 72
        self.root.geometry(f"{width}x{height}+{x}+{y}")
        self.root.deiconify()
        self.root.lift()

    def _load_payload(self) -> dict[str, Any] | None:
        try:
            raw = self.state_path.read_text(encoding="utf-8")
            payload = json.loads(raw)
        except FileNotFoundError:
            self.root.destroy()
            return None
        except json.JSONDecodeError:
            return {"environmentLabel": "", "items": []} if False else None
        except Exception:
            return None

        if not isinstance(payload, dict):
            return {"environmentLabel": "", "items": []}
        items = payload.get("items")
        if not isinstance(items, list):
            payload["items"] = []
        return payload

    def _write_payload(self, payload: dict[str, Any]) -> None:
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        temp_path = self.state_path.with_suffix(self.state_path.suffix + ".tmp")
        temp_path.write_text(json.dumps(payload), encoding="utf-8")
        os.replace(temp_path, self.state_path)

    def _item_key(self, item: dict[str, Any]) -> tuple[str, ...]:
        if self.panel_kind == "success":
            return (
                str(item.get("dagId", "")),
                str(item.get("runId", "")),
                str(item.get("endDate", "")),
                str(item.get("url", "")),
            )
        return (
            str(item.get("token", "")),
            str(item.get("title", "")),
            str(item.get("message", "")),
            str(item.get("url", "")),
        )

    def _dismiss_item(self, target_item: dict[str, Any]) -> None:
        payload = self._load_payload()
        if payload is None:
            return
        items = payload.get("items", [])
        remaining: list[dict[str, Any]] = []
        removed = False
        target_key = self._item_key(target_item)
        for item in items:
            if not removed and isinstance(item, dict) and self._item_key(item) == target_key:
                removed = True
                continue
            remaining.append(item)
        payload["items"] = remaining
        self._write_payload(payload)
        if not remaining:
            self.root.destroy()

    def _open_url(self, url: str) -> None:
        if not url:
            return
        subprocess.Popen(["open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def _item_title(self, item: dict[str, Any]) -> str:
        if self.panel_kind == "success":
            return str(item.get("dagId", "<unknown dag>"))
        return str(item.get("title", "Airflow failure"))

    def _item_body(self, item: dict[str, Any]) -> str:
        if self.panel_kind == "success":
            run_id = str(item.get("runId", "<unknown run>"))
            end_date = str(item.get("endDate", "unknown end time"))
            return f"Run: {run_id}\nFinished: {end_date}"
        return str(item.get("message", ""))

    def _rebuild(self, payload: dict[str, Any]) -> None:
        environment_label = str(payload.get("environmentLabel", "")).strip()
        items = [item for item in payload.get("items", []) if isinstance(item, dict)]
        items = list(reversed(items))

        title = self.theme["title"]
        if environment_label:
            title = f"{environment_label.capitalize()} {title}"
        self.title_label.configure(text=title)
        count = len(items)
        self.count_label.configure(text=f"{count} item" + ("" if count == 1 else "s"))
        self.subtitle_label.configure(
            text="Open an item in Airflow or dismiss it from the panel."
        )

        for child in self.content_frame.winfo_children():
            child.destroy()

        for item in items:
            card = tk.Frame(
                self.content_frame,
                bg=self.theme["surface"],
                highlightbackground=self.theme["border"],
                highlightthickness=1,
                bd=0,
                padx=12,
                pady=12,
            )
            card.pack(fill="x", pady=(0, 10))

            title_label = tk.Label(
                card,
                text=self._item_title(item),
                font=self.card_title_font,
                fg="#0f172a",
                bg=self.theme["surface"],
                anchor="w",
                justify="left",
            )
            title_label.pack(fill="x")

            body_label = tk.Label(
                card,
                text=self._item_body(item),
                font=self.card_body_font,
                fg="#334155",
                bg=self.theme["surface"],
                anchor="w",
                justify="left",
                wraplength=420,
            )
            body_label.pack(fill="x", pady=(6, 10))

            buttons = tk.Frame(card, bg=self.theme["surface"])
            buttons.pack(fill="x")

            open_button = tk.Button(
                buttons,
                text="Open",
                command=lambda url=str(item.get("url", "")): self._open_url(url),
                bg=self.theme["button"],
                fg=self.theme["button_fg"],
                activebackground=self.theme["accent"],
                activeforeground="#ffffff",
                relief="flat",
                padx=12,
                pady=6,
                cursor="hand2",
            )
            open_button.pack(side="left")

            dismiss_button = tk.Button(
                buttons,
                text="Dismiss",
                command=lambda current=item: self._dismiss_item(current),
                bg="#ffffff",
                fg="#334155",
                activebackground="#e2e8f0",
                activeforeground="#0f172a",
                relief="flat",
                padx=12,
                pady=6,
                cursor="hand2",
            )
            dismiss_button.pack(side="right")

    def run(self) -> int:
        self.root.mainloop()
        return 0


def main(argv: list[str] | None = None, *, panel_kind: str | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if panel_kind is None:
        if len(args) != 2:
            print("Usage: airflow_panel_helper.py <success|failure> <state-path>", file=sys.stderr)
            return 2
        panel_kind, state_path = args
    else:
        if len(args) != 1:
            print("Usage: helper_wrapper.py <state-path>", file=sys.stderr)
            return 2
        state_path = args[0]

    app = AirflowPanelApp(panel_kind, state_path)
    return app.run()


if __name__ == "__main__":
    raise SystemExit(main())
