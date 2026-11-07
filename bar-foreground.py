#!/usr/bin/env python3
"""Temporarily override Omarchy's shared bar foreground through user config."""

import fcntl
import json
import os
import re
import sys
import tempfile
from pathlib import Path


HOME = Path.home()
CONFIG = HOME / ".config/omarchy/shell.toml"
STATE = HOME / ".local/state/omarchy/plugins/dim-it/bar-foreground.json"
KEYS = ("text", "active")


def read_lines(path: Path) -> list[str]:
    try:
        return path.read_text().splitlines(keepends=True)
    except FileNotFoundError:
        return []


def section_bounds(lines: list[str], name: str) -> tuple[int | None, int | None]:
    start = None
    for index, line in enumerate(lines):
        match = re.match(r"^\s*\[([^]]+)\]\s*(?:#.*)?(?:\r?\n)?$", line)
        if not match:
            continue
        if start is not None:
            return start, index
        if match.group(1) == name:
            start = index
    if start is not None:
        return start, len(lines)
    return None, None


def key_index(lines: list[str], start: int | None, end: int | None, key: str) -> int | None:
    if start is None or end is None:
        return None
    for index in range(start + 1, end):
        if re.match(rf"^\s*{re.escape(key)}\s*=", lines[index]):
            return index
    return None


def replace_keys(values: dict[str, str | None]) -> None:
    lines = read_lines(CONFIG)
    start, end = section_bounds(lines, "bar")
    if start is None and any(value is not None for value in values.values()):
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        if lines and lines[-1].strip():
            lines.append("\n")
        lines.append("[bar]\n")
        start, end = len(lines) - 1, len(lines)

    if start is not None:
        # Work backwards so removing a line never shifts a later match.
        for key in reversed(KEYS):
            index = key_index(lines, start, end, key)
            value = values.get(key)
            if value is None:
                if index is not None:
                    lines.pop(index)
            else:
                replacement = f'{key} = "{value}"\n'
                if index is None:
                    lines.insert(end, replacement)
                    end += 1
                else:
                    lines[index] = replacement

        if start < len(lines) and lines[start].strip() == "[bar]":
            section_end = next(
                (i for i in range(start + 1, len(lines)) if re.match(r"^\s*\[[^]]+\]", lines[i])),
                len(lines),
            )
            content = [line for line in lines[start + 1:section_end] if line.strip() and not line.lstrip().startswith("#")]
            if not content:
                del lines[start:section_end]

    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    if not lines:
        try:
            CONFIG.unlink()
        except FileNotFoundError:
            pass
        return
    CONFIG.write_text("".join(lines))


def darken(color: str, factor: float) -> str:
    value = color.strip().lower()
    if not re.fullmatch(r"#[0-9a-f]{6}(?:[0-9a-f]{2})?", value):
        raise ValueError(f"unsupported color from active theme: {color!r}")
    alpha = value[1:3] if len(value) == 9 else "ff"
    rgb = value[3:9] if len(value) == 9 else value[1:7]
    channels = [max(0, min(255, round(int(rgb[i:i + 2], 16) / factor))) for i in (0, 2, 4)]
    return "#" + alpha + "".join(f"{channel:02x}" for channel in channels)


def load_state() -> dict | None:
    try:
        return json.loads(STATE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def save_state(state: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=STATE.parent, prefix=".bar-foreground.")
    with os.fdopen(fd, "w") as stream:
        json.dump(state, stream)
        stream.write("\n")
    os.replace(temporary, STATE)


def apply(mode: str, text_color: str, active_color: str) -> None:
    if mode not in ("dark", "very-dark", "black"):
        raise ValueError(f"unknown foreground mode: {mode}")
    state = load_state()
    if state is None:
        lines = read_lines(CONFIG)
        start, end = section_bounds(lines, "bar")
        original = {}
        for key in KEYS:
            index = key_index(lines, start, end, key)
            original[key] = lines[index] if index is not None else None
        state = {
            "hadFile": CONFIG.exists(),
            "hadBarSection": start is not None,
            "original": original,
            "base": {"text": text_color, "active": active_color},
        }
        save_state(state)

    if mode == "black":
        changed = {key: "#ff000000" for key in KEYS}
    else:
        factor = 1.5 if mode == "dark" else 2.1
        changed = {key: darken(state["base"][key], factor) for key in KEYS}
    replace_keys(changed)


def restore() -> None:
    state = load_state()
    if state is None:
        return
    lines = read_lines(CONFIG)
    start, end = section_bounds(lines, "bar")
    if start is not None and end is not None:
        for key in reversed(KEYS):
            index = key_index(lines, start, end, key)
            original_line = state["original"].get(key)
            if original_line is None:
                if index is not None:
                    lines.pop(index)
                    end -= 1
            elif index is not None:
                lines[index] = original_line
            else:
                lines.insert(end, original_line)
                end += 1

        if not state.get("hadBarSection"):
            content = [line for line in lines[start + 1:end] if line.strip() and not line.lstrip().startswith("#")]
            if not content:
                del lines[start:end]
    if not state.get("hadFile") and not any(line.strip() for line in lines):
        try:
            CONFIG.unlink()
        except FileNotFoundError:
            pass
    else:
        CONFIG.parent.mkdir(parents=True, exist_ok=True)
        CONFIG.write_text("".join(lines))
    try:
        STATE.unlink()
    except FileNotFoundError:
        pass


def main() -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    lock_path = STATE.with_suffix(".lock")
    with lock_path.open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if len(sys.argv) >= 2 and sys.argv[1] == "apply":
            if len(sys.argv) != 5 or sys.argv[2] not in ("dark", "very-dark", "black"):
                raise SystemExit("usage: bar-foreground.py apply dark|very-dark|black TEXT_COLOR ACTIVE_COLOR")
            apply(sys.argv[2], sys.argv[3], sys.argv[4])
        elif len(sys.argv) == 2 and sys.argv[1] == "restore":
            restore()
        else:
            raise SystemExit("usage: bar-foreground.py apply|restore ...")


if __name__ == "__main__":
    main()
