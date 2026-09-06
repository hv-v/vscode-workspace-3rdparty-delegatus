#!/usr/bin/env python3
"""Report what a Claude Code session spent, and how much of it was tool output.

Model token counts are exact (the per-request `usage` block each assistant
message carries). Tool-result sizes are payload bytes with a ~4 bytes/token
estimate — the API never attributes tokens to an individual tool call, so the
split between "graph queries" and "reading files by hand" is an estimate of
where the context went, not a billed figure.
"""

import argparse
import json
import pathlib
import sys
from collections import defaultdict

MCP_PREFIX = "mcp__codebase-memory__"
FILE_TOOLS = {"Read", "Grep", "Glob", "Bash", "NotebookEdit", "Edit", "Write"}
BYTES_PER_TOKEN = 4


def transcript_dir(workspace: pathlib.Path) -> pathlib.Path:
    slug = str(workspace).replace("/", "-")
    return pathlib.Path.home() / ".claude" / "projects" / slug


def blocks(message):
    content = message.get("content") if isinstance(message, dict) else None
    return content if isinstance(content, list) else []


def payload_size(block) -> int:
    content = block.get("content")
    if isinstance(content, str):
        return len(content)
    return len(json.dumps(content)) if content is not None else 0


def scan(path: pathlib.Path) -> dict:
    usage = defaultdict(int)
    calls = defaultdict(int)
    payload = defaultdict(int)
    names = {}

    with path.open(errors="replace") as handle:
        for line in handle:
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            message = record.get("message")
            if not isinstance(message, dict):
                continue

            counters = message.get("usage")
            if isinstance(counters, dict):
                for field in ("input_tokens", "output_tokens",
                              "cache_read_input_tokens", "cache_creation_input_tokens"):
                    usage[field] += counters.get(field) or 0

            for block in blocks(message):
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "tool_use":
                    names[block.get("id")] = block.get("name") or "?"
                    calls[block.get("name") or "?"] += 1
                elif block.get("type") == "tool_result":
                    name = names.get(block.get("tool_use_id"), "?")
                    payload[name] += payload_size(block)

    return {"path": path, "usage": usage, "calls": calls, "payload": payload}


def bucket(name: str) -> str:
    if name.startswith(MCP_PREFIX):
        return "code graph (MCP)"
    if name.startswith("mcp__"):
        return "other MCP servers"
    return "file exploration" if name in FILE_TOOLS else "other tools"


def humanise(tokens: float) -> str:
    return f"{tokens / 1000:.1f}k" if tokens >= 1000 else f"{tokens:.0f}"


def report(scans: list, top: int) -> None:
    usage = defaultdict(int)
    calls = defaultdict(int)
    payload = defaultdict(int)
    for item in scans:
        for key, value in item["usage"].items():
            usage[key] += value
        for key, value in item["calls"].items():
            calls[key] += value
        for key, value in item["payload"].items():
            payload[key] += value

    print(f"sessions: {len(scans)}")
    print()
    print("model tokens (exact, billed)")
    print(f"  input          {usage['input_tokens']:>12,}")
    print(f"  output         {usage['output_tokens']:>12,}")
    print(f"  cache write    {usage['cache_creation_input_tokens']:>12,}")
    print(f"  cache read     {usage['cache_read_input_tokens']:>12,}")
    billed = (usage["input_tokens"] + usage["output_tokens"]
              + usage["cache_creation_input_tokens"] + usage["cache_read_input_tokens"])
    print(f"  total          {billed:>12,}")

    by_bucket = defaultdict(int)
    bucket_calls = defaultdict(int)
    for name, size in payload.items():
        by_bucket[bucket(name)] += size
    for name, count in calls.items():
        bucket_calls[bucket(name)] += count

    total_payload = sum(by_bucket.values()) or 1
    print()
    print("tool output entering context (estimated, ~4 bytes/token)")
    for label in ("code graph (MCP)", "file exploration", "other MCP servers", "other tools"):
        size = by_bucket.get(label, 0)
        print(f"  {label:<20} {humanise(size / BYTES_PER_TOKEN):>8} tok"
              f"  {size * 100 / total_payload:>5.1f}%"
              f"  {bucket_calls.get(label, 0):>4} calls")

    print()
    print(f"heaviest tools (top {top})")
    for name, size in sorted(payload.items(), key=lambda kv: -kv[1])[:top]:
        print(f"  {name:<44} {humanise(size / BYTES_PER_TOKEN):>8} tok  {calls.get(name, 0):>4} calls")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--workspace", required=True, type=pathlib.Path)
    parser.add_argument("--sessions", type=int, default=1,
                        help="how many of the most recent sessions to include (0 = all)")
    parser.add_argument("--top", type=int, default=10)
    args = parser.parse_args()

    directory = transcript_dir(args.workspace)
    if not directory.is_dir():
        print(f"no Claude Code transcripts for {args.workspace} (looked in {directory})",
              file=sys.stderr)
        return 69

    files = sorted(directory.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not files:
        print(f"no .jsonl transcripts in {directory}", file=sys.stderr)
        return 69
    if args.sessions:
        files = files[:args.sessions]

    report([scan(path) for path in files], args.top)
    return 0


if __name__ == "__main__":
    sys.exit(main())
