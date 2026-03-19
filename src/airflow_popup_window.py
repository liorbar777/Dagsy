#!/usr/bin/env python3
"""Custom popup window for local Airflow watcher events."""

from __future__ import annotations

import argparse
import subprocess
import sys
import tkinter as tk
from tkinter import font as tkfont


THEMES = {
    "failure": {
        "title": "Airflow Failure",
        "accent": "#b42318",
        "surface": "#fff4f2",
        "border": "#f4c7c3",
        "button": "#b42318",
    },
    "success": {
        "title": "Airflow Success",
        "accent": "#166534",
        "surface": "#f0fdf4",
        "border": "#bbf7d0",
        "button": "#166534",
    },
    "generic": {
        "title": "Airflow Update",
        "accent": "#1d4ed8",
        "surface": "#eff6ff",
        "border": "#bfdbfe",
        "button": "#1d4ed8",
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", default="generic")
    parser.add_argument("--title", required=True)
    parser.add_argument("--message", required=True)
    parser.add_argument("--url", required=True)
    return parser.parse_args()


class PopupWindow:
    def __init__(self, kind: str, title: str, message: str, url: str) -> None:
        self.kind = kind if kind in THEMES else "generic"
        self.theme = THEMES[self.kind]
        self.title = title
        self.message = message
        self.url = url
        self.result = "Dismiss"

        self.root = tk.Tk()
        self.root.title(self.theme["title"])
        self.root.configure(bg="#e5e7eb")
        self.root.attributes("-topmost", True)
        self.root.resizable(False, False)
        self.root.protocol("WM_DELETE_WINDOW", self.dismiss)

        self.title_font = tkfont.Font(size=15, weight="bold")
        self.body_font = tkfont.Font(size=12)
        self.meta_font = tkfont.Font(size=11)
        self._build()
        self._position()

    def _build(self) -> None:
        frame = tk.Frame(
            self.root,
            bg=self.theme["surface"],
            highlightbackground=self.theme["border"],
            highlightthickness=1,
            padx=18,
            pady=16,
        )
        frame.pack(fill="both", expand=True, padx=10, pady=10)

        accent = tk.Frame(frame, bg=self.theme["accent"], height=6)
        accent.pack(fill="x", pady=(0, 14))

        title = tk.Label(
            frame,
            text=self.title,
            font=self.title_font,
            bg=self.theme["surface"],
            fg="#0f172a",
            anchor="w",
            justify="left",
        )
        title.pack(fill="x")

        subtitle = tk.Label(
            frame,
            text=self.theme["title"],
            font=self.meta_font,
            bg=self.theme["surface"],
            fg="#475569",
            anchor="w",
        )
        subtitle.pack(fill="x", pady=(4, 12))

        body = tk.Label(
            frame,
            text=self.message,
            font=self.body_font,
            bg=self.theme["surface"],
            fg="#1f2937",
            justify="left",
            anchor="w",
            wraplength=540,
        )
        body.pack(fill="x")

        actions = tk.Frame(frame, bg=self.theme["surface"])
        actions.pack(fill="x", pady=(18, 0))

        dismiss = tk.Button(
            actions,
            text="Dismiss",
            command=self.dismiss,
            bg="#ffffff",
            fg="#334155",
            activebackground="#e2e8f0",
            relief="flat",
            padx=14,
            pady=8,
            cursor="hand2",
        )
        dismiss.pack(side="right")

        open_button = tk.Button(
            actions,
            text="Open in Airflow",
            command=self.open_url,
            bg=self.theme["button"],
            fg="#ffffff",
            activebackground=self.theme["accent"],
            relief="flat",
            padx=14,
            pady=8,
            cursor="hand2",
        )
        open_button.pack(side="right", padx=(0, 10))

    def _position(self) -> None:
        self.root.update_idletasks()
        width = 600
        height = 300
        screen_width = self.root.winfo_screenwidth()
        x = max(24, screen_width - width - 32)
        y = 76
        self.root.geometry(f"{width}x{height}+{x}+{y}")
        self.root.lift()
        self.root.focus_force()

    def open_url(self) -> None:
        subprocess.Popen(["/usr/bin/open", self.url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def dismiss(self) -> None:
        self.result = "Dismiss"
        self.root.destroy()

    def run(self) -> str:
        self.root.mainloop()
        return self.result


def main() -> int:
    args = parse_args()
    popup = PopupWindow(args.kind, args.title, args.message, args.url)
    print(popup.run())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
