import { afterAll, expect, test } from "bun:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { projectIdentityFromRepositoryRoot } from "./identity";
import { readWorkspaceManifest, workspaceProjects } from "./workspaceManifest";

const root = fs.mkdtempSync(path.join(os.tmpdir(), "workspace-manifest-"));
afterAll(() => fs.rmSync(root, { recursive: true, force: true }));

function repository(directory: string): void {
  fs.mkdirSync(path.join(directory, ".git"), { recursive: true });
  fs.writeFileSync(path.join(directory, ".git", "HEAD"), "ref: refs/heads/main\n");
  fs.writeFileSync(path.join(directory, ".git", "config"), "[core]\n repositoryformatversion = 0\n");
}

test("only configured, initialized repositories inside the workspace are returned", () => {
  const workspace = path.join(root, "workspace");
  const child = path.join(workspace, "repos", "project");
  const excluded = path.join(workspace, "third-party");
  const outside = path.join(root, "outside");
  for (const directory of [workspace, child, excluded, outside]) repository(directory);
  fs.symlinkSync(outside, path.join(workspace, "escape"));
  fs.writeFileSync(path.join(workspace, ".delegatus-workspace.json"), JSON.stringify({ projects: ["repos/project", "repos/project", "escape", "../outside", "missing"] }));
  const parent = { project: projectIdentityFromRepositoryRoot(workspace)!.project, projectRoot: workspace, smt: 0, conversations: 1 };
  expect(workspaceProjects(parent)).toEqual([{ project: projectIdentityFromRepositoryRoot(child)!.project, displayName: "project", projectRoot: child, workspaceParent: parent.project, smt: 0, conversations: 0 }]);
});

test("the manifest's ticket types are read clean, and absent when it names none", () => {
  const workspace = path.join(root, "typed");
  repository(workspace);
  const entry = { project: "typed", projectRoot: workspace, smt: 0, conversations: 1 };
  fs.writeFileSync(path.join(workspace, ".delegatus-workspace.json"), JSON.stringify({ ticketTypes: [" Spike ", "Spike", "[Chore]", 7, "", "x".repeat(41)] }));
  expect(readWorkspaceManifest(entry)?.ticketTypes).toEqual(["Spike", "Chore"]);
  fs.writeFileSync(path.join(workspace, ".delegatus-workspace.json"), JSON.stringify({ projects: [] }));
  expect(readWorkspaceManifest(entry)?.ticketTypes).toBeUndefined();
});
