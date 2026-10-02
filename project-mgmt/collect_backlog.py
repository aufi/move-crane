#!/usr/bin/env python3
"""Collect Crane backlog and GitHub Project metadata through the gh CLI."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


ISSUE_FIELDS = (
    "number,title,url,createdAt,updatedAt,labels,assignees,milestone"
)
PR_FIELDS = (
    "number,title,url,createdAt,updatedAt,isDraft,mergeStateStatus,"
    "reviewDecision,statusCheckRollup,labels,assignees,milestone,author,"
    "reviewRequests"
)


class CollectionError(RuntimeError):
    """Raised when configuration or GitHub data cannot be collected."""


def read_repository_list(path: Path) -> list[str]:
    """Read the simple repositories list without requiring a YAML package."""
    repositories: list[str] = []
    in_repositories = False
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        if not line.startswith((" ", "\t")):
            in_repositories = line.strip() == "repositories:"
            continue
        if in_repositories and line.strip().startswith("- "):
            repository = line.strip()[2:].strip().strip("'\"")
            if repository.count("/") != 1:
                raise CollectionError(
                    f"Invalid repository {repository!r} in {path}"
                )
            repositories.append(repository)

    if not repositories:
        raise CollectionError(f"No repositories found in {path}")
    if len(repositories) != len(set(repositories)):
        raise CollectionError(f"Duplicate repository in {path}")
    return repositories


def read_project_config(path: Path) -> dict[str, Any]:
    """Read scalar values from the project section of project.yaml."""
    project: dict[str, Any] = {}
    in_project = False
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        if not line.startswith((" ", "\t")):
            in_project = line.strip() == "project:"
            continue
        if not in_project or ":" not in line:
            continue
        key, value = line.strip().split(":", 1)
        value = value.strip().strip("'\"")
        project[key] = int(value) if key == "number" else value

    required = {"owner", "number", "url"}
    missing = required - project.keys()
    if missing:
        raise CollectionError(
            f"Missing project keys in {path}: {', '.join(sorted(missing))}"
        )
    return project


def run_gh(arguments: list[str], retries: int = 2) -> Any:
    """Run gh and decode its JSON output, retrying transient API failures."""
    command = ["gh", *arguments]
    for attempt in range(retries + 1):
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            try:
                return json.loads(result.stdout)
            except json.JSONDecodeError as exc:
                raise CollectionError(
                    f"gh returned invalid JSON for {' '.join(command)}: {exc}"
                ) from exc

        error = result.stderr.strip() or result.stdout.strip()
        transient = any(
            marker in error.lower()
            for marker in ("rate limit", "timeout", "temporarily unavailable")
        )
        if not transient or attempt == retries:
            raise CollectionError(
                f"Command failed ({result.returncode}): {' '.join(command)}\n{error}"
            )
        time.sleep(2 ** (attempt + 1))
    raise AssertionError("unreachable")


def collect_repository(repository: str) -> dict[str, Any]:
    """Collect all open work and planning metadata for one repository."""
    issues = run_gh(
        [
            "issue",
            "list",
            "--repo",
            repository,
            "--state",
            "open",
            "--limit",
            "1000",
            "--json",
            ISSUE_FIELDS,
        ]
    )
    pull_requests = run_gh(
        [
            "pr",
            "list",
            "--repo",
            repository,
            "--state",
            "open",
            "--limit",
            "1000",
            "--json",
            PR_FIELDS,
        ]
    )
    labels = run_gh(
        [
            "label",
            "list",
            "--repo",
            repository,
            "--limit",
            "1000",
            "--json",
            "name,color,description",
        ]
    )
    milestones = run_gh(
        [
            "api",
            f"repos/{repository}/milestones?state=open&per_page=100",
        ]
    )
    return {
        "issues": issues,
        "pullRequests": pull_requests,
        "labels": labels,
        "milestones": milestones,
    }


def collect_project(project: dict[str, Any]) -> dict[str, Any]:
    """Collect project metadata, fields, items, and enabled workflows."""
    owner = str(project["owner"])
    number = str(project["number"])
    metadata = run_gh(
        ["project", "view", number, "--owner", owner, "--format", "json"]
    )
    fields = run_gh(
        ["project", "field-list", number, "--owner", owner, "--format", "json"]
    )
    items = run_gh(
        [
            "project",
            "item-list",
            number,
            "--owner",
            owner,
            "--format",
            "json",
            "--limit",
            "1000",
        ]
    )
    query = """
query($owner: String!, $number: Int!) {
  organization(login: $owner) {
    projectV2(number: $number) {
      workflows(first: 100) {
        nodes { number name enabled updatedAt }
      }
    }
  }
}
""".strip()
    workflow_response = run_gh(
        [
            "api",
            "graphql",
            "-f",
            f"query={query}",
            "-F",
            f"owner={owner}",
            "-F",
            f"number={number}",
        ]
    )
    workflows = (
        workflow_response.get("data", {})
        .get("organization", {})
        .get("projectV2", {})
        .get("workflows", {})
        .get("nodes", [])
    )
    return {
        "metadata": metadata,
        "fields": fields.get("fields", []),
        "items": items.get("items", []),
        "workflows": workflows,
    }


def collect(repositories_path: Path, project_path: Path) -> dict[str, Any]:
    """Collect a complete snapshot for configured repositories and project."""
    repositories = read_repository_list(repositories_path)
    project_config = read_project_config(project_path)
    repository_data: dict[str, Any] = {}
    for repository in repositories:
        print(f"Collecting {repository}", file=sys.stderr)
        repository_data[repository] = collect_repository(repository)
    print(
        f"Collecting project {project_config['owner']}/{project_config['number']}",
        file=sys.stderr,
    )
    project_data = collect_project(project_config)
    return {
        "schemaVersion": 1,
        "generatedAt": datetime.now(UTC).isoformat(timespec="seconds"),
        "configuration": {
            "repositories": repositories,
            "project": project_config,
        },
        "repositories": repository_data,
        "project": project_data,
    }


def write_json_atomic(path: Path, data: Any) -> None:
    """Write formatted JSON without exposing a partially written snapshot."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=path.parent, delete=False
    ) as temporary:
        json.dump(data, temporary, indent=2, sort_keys=True)
        temporary.write("\n")
        temporary_path = Path(temporary.name)
    os.replace(temporary_path, path)


def parse_args() -> argparse.Namespace:
    directory = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repositories",
        type=Path,
        default=directory / "repositories.yaml",
        help="repository list (default: repositories.yaml next to this script)",
    )
    parser.add_argument(
        "--project",
        type=Path,
        default=directory / "project.yaml",
        help="project configuration (default: project.yaml next to this script)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="write JSON to this path instead of stdout",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        data = collect(args.repositories, args.project)
        if args.output:
            write_json_atomic(args.output, data)
        else:
            json.dump(data, sys.stdout, indent=2, sort_keys=True)
            sys.stdout.write("\n")
    except (CollectionError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
