#!/usr/bin/env bash
# Run one of the Claude hook scripts in .claude/hooks/ for an Antigravity hook.
#
# The two harnesses disagree on both ends of the contract:
#   Antigravity stdin   {"toolCall":{"name":"run_command","args":{"CommandLine":…}}, …}
#   Claude stdin        {"tool_name":"Bash","tool_input":{"command":…}}
#   Claude deny         {"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":…}}
#   Antigravity deny    {"decision":"deny","reason":…}
# so this translates the payload in, runs the script, and translates its answer
# out. The enforcement logic stays in one place, .claude/hooks/.
#
# Usage: claude-hook.sh <script name without .sh>
#   e.g. claude-hook.sh corp-guard
# stdin:  Antigravity hook JSON
# stdout: Antigravity hook JSON; {} when the script has nothing to say
#
# Fails open like the scripts it wraps (.claude/rules/hooks.md): a missing jq,
# an unknown tool or a script error answers {} and the tool runs as normal.
# {} carries no decision, so the ordinary permission flow still applies;
# "allow" is never sent, because that would skip the user's approval.
set -euo pipefail

workspace=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
readonly workspace

pass() {
    printf '{}\n'
    exit 0
}

[[ $# -eq 1 && "$1" =~ ^[a-z][a-z-]*$ ]] || pass
script="$workspace/.claude/hooks/$1.sh"
[[ -x "$script" ]] || pass
command -v jq >/dev/null 2>&1 || pass

payload=$(cat) || pass

# Antigravity tool name -> the Claude tool the script expects. File tools are
# matched under both their tool names and their step type (code_action), since
# the hook matcher documentation derives names from either.
claude_payload=$(jq -c '
    def path_arg: .TargetFile // .AbsolutePath // .FilePath // .Path // "";
    (.toolCall.name // "") as $name
    | (.toolCall.args // {}) as $args
    | if ($name | length) == 0 then {}
      elif $name == "run_command" then
          {tool_name: "Bash", tool_input: {command: ($args.CommandLine // "")}}
      elif $name == "read_url_content" then
          {tool_name: "WebFetch", tool_input: {url: ($args.Url // $args.url // "")}}
      elif $name == "view_file" then
          {tool_name: "Read", tool_input: {file_path: ($args | path_arg)}}
      elif ($name | test("^(write_to_file|replace_file_content|multi_replace_file_content|code_action|file_change|propose_code)$")) then
          {tool_name: "Write", tool_input: {file_path: ($args | path_arg)}}
      else {tool_name: $name, tool_input: {}}
      end' <<<"$payload" 2>/dev/null) || pass

answer=$(printf '%s' "$claude_payload" | (cd "$workspace" && CLAUDE_PROJECT_DIR="$workspace" "$script") 2>/dev/null) || pass
[[ -n "$answer" ]] || pass

# Claude-only tool names in a reason would send the agent looking for tools it lacks.
jq -c '
    def plain: gsub("mcp__codebase-memory__"; "codebase-memory ");
    (.hookSpecificOutput // {}) as $h
    | if $h.permissionDecision == "deny" then
          {decision: "deny", reason: ($h.permissionDecisionReason // "" | plain)}
      elif ($h.additionalContext // "") != "" then
          {injectSteps: [{systemMessage: {systemMessage: ($h.additionalContext | plain)}}]}
      else {}
      end' <<<"$answer" 2>/dev/null || pass
