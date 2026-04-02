#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timezone, timedelta
from pathlib import Path
import subprocess
import sys

WORLD_FILE = "scripts/world/world.gd"
OUTPUT_FILE = Path("artifacts/world-gd-weekly-review.md")


def _run(cmd: list[str]) -> str:
    completed = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return completed.stdout.strip()


def main() -> int:
    now = datetime.now(timezone.utc)
    since = (now - timedelta(days=7)).strftime("%Y-%m-%d")
    until = now.strftime("%Y-%m-%d")

    commit_log = _run([
        "git",
        "log",
        "--since",
        since,
        "--pretty=format:%h|%ad|%an|%s",
        "--date=short",
        "--",
        WORLD_FILE,
    ])
    diff_stat = _run([
        "git",
        "log",
        "--since",
        since,
        "--numstat",
        "--pretty=tformat:",
        "--",
        WORLD_FILE,
    ])

    changed = bool(commit_log.strip())
    lines_added = 0
    lines_removed = 0
    for row in diff_stat.splitlines():
        if not row.strip():
            continue
        parts = row.split("\t")
        if len(parts) != 3:
            continue
        add_raw, del_raw, _path = parts
        if add_raw.isdigit():
            lines_added += int(add_raw)
        if del_raw.isdigit():
            lines_removed += int(del_raw)

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Weekly review — scripts/world/world.gd",
        "",
        f"- Window (UTC): {since} → {until}",
        f"- Commits touching `world.gd`: {'yes' if changed else 'no'}",
        f"- Diffstat (7d): +{lines_added} / -{lines_removed}",
        "",
        "## Commit list",
    ]
    if changed:
        lines.append("")
        for entry in commit_log.splitlines():
            sha, date_raw, author, subject = entry.split("|", maxsplit=3)
            lines.append(f"- `{sha}` ({date_raw}) {author}: {subject}")
    else:
        lines.extend(["", "- No commits in this window."])

    lines.extend([
        "",
        "## Review outcome",
        "",
        "- [ ] Verified no semantic decisions were added to `world.gd`.",
        "- [ ] Verified composition/lifecycle/dispatch-only boundary remains intact.",
        "- [ ] Verified size/complexity budget trend does not show relapse by accumulation.",
    ])
    OUTPUT_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"Wrote {OUTPUT_FILE}")
    if changed:
        print("::warning::world.gd changed in the last 7 days. Complete the weekly checklist.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as err:
        print(err.stderr or str(err), file=sys.stderr)
        raise SystemExit(1)
