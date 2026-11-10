import { expect, test } from "bun:test";

import type { FileEntry } from "@/lib/types";

import {
  assigneeValue,
  autoSpawnShape,
  composeTaskText,
  readAssigneeValue,
  ticketModelOptions,
  ticketProjectOptions,
  ticketTypesFor,
  typedTitle,
} from "./taskTicket";

function conv(path: string, project: string, extra: Partial<FileEntry> = {}): FileEntry {
  return {
    path, root: "claude-projects", name: path, project, title: path.slice(1), cwd: `/work/${project}`,
    engine: "claude", kind: "session", fmt: "claude", parent: null, mtime: 2, size: 1, activity: "idle",
    proc: "done", pid: null, pendingQuestion: null, waitingInput: null, ...extra,
  } as FileEntry;
}

test("the title becomes the first line and the description follows a blank line", () => {
  expect(composeTaskText("Fix the limiter", "It drops requests.\nSee logs.")).toBe("Fix the limiter\n\nIt drops requests.\nSee logs.");
  expect(composeTaskText("  Fix\n the limiter ", "  ")).toBe("Fix the limiter");
  expect(composeTaskText("", "Only a body")).toBe("Only a body");
  expect(composeTaskText(" ", " ")).toBe("");
});

test("an assignee survives its select value, and junk or an unknown model reads as unassigned", () => {
  for (const assignee of [{ kind: "none" }, { kind: "auto" }, { kind: "model", engine: "claude", model: "opus" }, { kind: "model", engine: "codex", model: "gpt-6.1-sol" }] as const) {
    expect(readAssigneeValue(assigneeValue(assignee))).toEqual(assignee);
  }
  expect(readAssigneeValue("model:claude:")).toEqual({ kind: "none" });
  expect(readAssigneeValue("model:claude:not-a-model")).toEqual({ kind: "none" });
  expect(readAssigneeValue("agent:/a.jsonl")).toEqual({ kind: "none" });
  expect(readAssigneeValue("bogus")).toEqual({ kind: "none" });
});

test("the assignee offers the Claude and Codex models a fresh agent can launch on", () => {
  const groups = ticketModelOptions();
  expect(groups.map((group) => group.engine)).toEqual(["claude", "codex"]);
  expect(groups[0]!.options.map((option) => option.value)).toContain("model:claude:opus");
  expect(groups[1]!.options.map((option) => option.value)).toContain("model:codex:gpt-6.1-sol");
  expect(groups[0]!.options.map((option) => option.value)).not.toContain("model:claude:claude-haiku-4-5");
  expect(ticketModelOptions({ kind: "model", engine: "claude", model: "claude-haiku-4-5" })[0]!.options.map((option) => option.value)).toContain("model:claude:claude-haiku-4-5");
});

test("ticket types come from the project, else its workspace parent, else the defaults", () => {
  const catalog = [
    { project: "ws", ticketTypes: ["Spike", "Chore"], smt: 0, conversations: 0 },
    { project: "child", workspaceParent: "ws", smt: 0, conversations: 0 },
    { project: "own", workspaceParent: "ws", ticketTypes: ["Paper"], smt: 0, conversations: 0 },
  ];
  expect(ticketTypesFor("child", catalog)).toEqual(["Spike", "Chore"]);
  expect(ticketTypesFor("own", catalog)).toEqual(["Paper"]);
  expect(ticketTypesFor("lone", catalog)).toEqual(["Bug", "Implementation", "Research", "Improvement"]);
});

test("the type leads the stored title in brackets, and never stands alone", () => {
  expect(typedTitle("Bug", " Fix the limiter ")).toBe("[Bug] Fix the limiter");
  expect(typedTitle("", "Fix the limiter")).toBe("Fix the limiter");
  expect(typedTitle("Bug", "  ")).toBe("  ");
});

test("the current project is listed first, the rest by name", () => {
  const files = [conv("/a.jsonl", "zeta", { projectName: "Zeta" }), conv("/b.jsonl", "alpha", { projectName: "Alpha" })];
  const options = ticketProjectOptions("zeta", "Zeta", files, [{ project: "mid", displayName: "Mid", smt: 0, conversations: 0 }]);
  expect(options.map((option) => option.value)).toEqual(["zeta", "alpha", "mid"]);
});

test("auto launches in the project's checkout with its newest engine, or nowhere", () => {
  const files = [conv("/a.jsonl", "orbit", { mtime: 1 }), conv("/b.jsonl", "orbit", { mtime: 5, engine: "codex" })];
  expect(autoSpawnShape(files, "orbit", [])).toEqual({ engine: "codex", cwd: "/work/orbit" });
  expect(autoSpawnShape([], "orbit", [{ project: "orbit", projectRoot: "/repo/orbit", smt: 0, conversations: 0 }])).toEqual({ engine: "claude", cwd: "/repo/orbit" });
  expect(autoSpawnShape([], "orbit", [], ["/fallback"])).toEqual({ engine: "claude", cwd: "/fallback" });
  expect(autoSpawnShape([], "orbit", [])).toBeNull();
});
