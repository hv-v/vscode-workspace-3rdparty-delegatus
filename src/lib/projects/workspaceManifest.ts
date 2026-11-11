import fs from "node:fs";
import path from "node:path";

import { projectIdentityFromRepositoryRoot } from "./identity";
import type { ProjectCatalogEntry } from "@/lib/types";

/** `.delegatus-workspace.json` at a project's root: the workspace's child
    projects, and the ticket types its task form offers. */
export interface WorkspaceManifest {
  root: string;
  projects: unknown;
  /** Absent when the manifest names none; the form then offers its defaults. */
  ticketTypes?: string[];
}

const TICKET_TYPE_LIMIT = 20;
const TICKET_TYPE_LENGTH = 40;

/** Trimmed, de-duplicated, one-line names; anything else is dropped. */
function readTicketTypes(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  const types: string[] = [];
  for (const item of value) {
    if (typeof item !== "string") continue;
    const name = item.replace(/[\s\[\]]+/g, " ").trim();
    if (!name || name.length > TICKET_TYPE_LENGTH || types.includes(name)) continue;
    types.push(name);
    if (types.length === TICKET_TYPE_LIMIT) break;
  }
  return types.length ? types : undefined;
}

export function readWorkspaceManifest(entry: ProjectCatalogEntry): WorkspaceManifest | null {
  if (!entry.projectRoot) return null;
  try {
    const root = fs.realpathSync(entry.projectRoot);
    const manifest = JSON.parse(fs.readFileSync(path.join(root, ".delegatus-workspace.json"), "utf8"));
    if (!manifest || typeof manifest !== "object") return null;
    const ticketTypes = readTicketTypes(manifest.ticketTypes);
    return { root, projects: manifest.projects, ...(ticketTypes ? { ticketTypes } : {}) };
  } catch { return null; }
}

/** An explicit list keeps discovery bounded and makes third-party inclusion a choice.
    One argument only, so it stays safe to pass to `map`/`flatMap`. */
export function workspaceProjects(parent: ProjectCatalogEntry): ProjectCatalogEntry[] {
  return workspaceProjectsFromManifest(parent, readWorkspaceManifest(parent));
}

/** The child projects of an already-read manifest. */
export function workspaceProjectsFromManifest(parent: ProjectCatalogEntry, manifest: WorkspaceManifest | null): ProjectCatalogEntry[] {
  if (!manifest) return [];
  const { root, projects: paths } = manifest;
  if (!Array.isArray(paths)) return [];
  const seen = new Set([parent.project]);
  const projects: ProjectCatalogEntry[] = [];
  for (const item of paths.slice(0, 500)) {
    if (typeof item !== "string" || !item || path.isAbsolute(item)) continue;
    try {
      const child = fs.realpathSync(path.resolve(root, item));
      const relative = path.relative(root, child);
      if (!relative || relative.startsWith(`..${path.sep}`) || relative === ".." || path.isAbsolute(relative)) continue;
      const identity = projectIdentityFromRepositoryRoot(child);
      if (!identity || seen.has(identity.project)) continue;
      seen.add(identity.project);
      projects.push({ project: identity.project, displayName: path.basename(child), projectRoot: child, workspaceParent: parent.project, smt: 0, conversations: 0 });
    } catch { /* A missing or inaccessible checkout is not a project yet. */ }
  }
  return projects;
}
