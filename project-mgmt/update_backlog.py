#!/usr/bin/env python3
"""Collect GitHub data and regenerate the Crane backlog status report."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from collect_backlog import CollectionError, collect, write_json_atomic
from render_backlog import render, write_text_atomic


def parse_args() -> argparse.Namespace:
    directory = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repositories",
        type=Path,
        default=directory / "repositories.yaml",
        help="repository list",
    )
    parser.add_argument(
        "--project",
        type=Path,
        default=directory / "project.yaml",
        help="project configuration",
    )
    parser.add_argument(
        "--data-output",
        type=Path,
        default=directory / "backlog-data.json",
        help="JSON snapshot output",
    )
    parser.add_argument(
        "--report-output",
        type=Path,
        default=directory / "backlog-status.md",
        help="Markdown report output",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        snapshot = collect(args.repositories, args.project)
        report = render(snapshot)
        write_json_atomic(args.data_output, snapshot)
        write_text_atomic(args.report_output, report)
    except (CollectionError, OSError, KeyError, TypeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(f"Wrote {args.data_output}")
    print(f"Wrote {args.report_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
