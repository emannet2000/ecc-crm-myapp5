#!/usr/bin/env python3
"""Report every function listed by `go tool cover -func`, including zero coverage."""
import argparse
import json
import re
from collections import defaultdict
from pathlib import Path


def report(source):
    functions = []
    total = None
    for line in source.splitlines():
        match = re.match(r"^(\S+):(\d+):\s+(\S+)\s+([\d.]+)%$", line.strip())
        if match:
            file, number, name, percentage = match.groups()
            functions.append({"file": file, "line": int(number), "name": name, "statement_coverage": float(percentage)})
        elif line.startswith("total:"):
            total = float(line.split()[-1].rstrip("%"))
    if not functions or total is None:
        raise ValueError("Expected a complete go tool cover -func report")
    groups = defaultdict(list)
    for function in functions:
        groups[function["file"]].append(function)
    untouched = [function for function in functions if function["statement_coverage"] == 0]
    complete = [function for function in functions if function["statement_coverage"] == 100]
    summary = {"statement_coverage": total, "functions": len(functions), "untouched_functions": len(untouched), "fully_statement_covered_functions": len(complete), "partially_statement_covered_functions": len(functions) - len(untouched) - len(complete)}
    lines = ["# Backend function coverage", "", f"Statement coverage: **{total:g}%**. Functions: **{len(functions)}**; untouched: **{len(untouched)}**; fully statement-covered: **{len(complete)}**.", "", "Coverage shows executed statements, not assertion quality, all input combinations, or browser/provider acceptance. Untouched functions remain explicit testing gaps.", "", "| File | Functions | Untouched | Fully statement-covered |", "| --- | ---: | ---: | ---: |"]
    for file, entries in sorted(groups.items()):
        lines.append(f"| {file} | {len(entries)} | {sum(entry['statement_coverage'] == 0 for entry in entries)} | {sum(entry['statement_coverage'] == 100 for entry in entries)} |")
    lines.extend(["", "## Every measured function", "", "| Location | Function | Statement coverage |", "| --- | --- | ---: |"])
    for function in sorted(functions, key=lambda entry: (entry["statement_coverage"], entry["file"], entry["line"])):
        lines.append(f"| {function['file']}:{function['line']} | `{function['name']}` | {function['statement_coverage']:g}% |")
    return summary, functions, "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    summary, functions, markdown = report(args.input.read_text())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(markdown)
    args.output.with_suffix(".json").write_text(json.dumps({"summary": summary, "functions": functions}, indent=2) + "\n")
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
