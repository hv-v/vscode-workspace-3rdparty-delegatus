import { launchModelIds, listedModels } from "@/lib/agent/models";
import { projectDisplayName } from "@/lib/displayNames";
import { TASK_PRIORITIES, type TaskPriority } from "@/lib/tasks/types";
import type { FileEntry, ProjectCatalogEntry } from "@/lib/types";

import { draftWorkingDirectory, projectKey } from "@/components/projectModel";

/**
 * The ticket-shaped create form (Type, Title, Description, Project, Priority,
 * Assignee). Storage is unchanged: a task's `text` is still one field whose
 * first line is the title, so the form joins the parts and every reader,
 * MCP tool and linked board sees the task it always saw.
 */

export type TicketEngine = "claude" | "codex";
const TICKET_ENGINES: readonly TicketEngine[] = ["claude", "codex"];

/** Who takes the task once it exists. `none` leaves it in Inbox; `auto`
    launches a fresh agent on the project's usual engine and default model;
    `model` launches a fresh agent on that engine and model. Nothing is stored
    on the task: the choice becomes an ordinary spawn of the task as the
    agent's brief. */
export type TaskAssignee =
  | { kind: "none" }
  | { kind: "auto" }
  | { kind: "model"; engine: TicketEngine; model: string };

export const NO_ASSIGNEE: TaskAssignee = { kind: "none" };

/** The `<select>` value of an assignee, and its inverse. A model the
    catalogue no longer accepts reads as unassigned. */
export function assigneeValue(assignee: TaskAssignee): string {
  return assignee.kind === "model" ? `model:${assignee.engine}:${assignee.model}` : assignee.kind;
}

export function readAssigneeValue(value: string): TaskAssignee {
  if (value === "auto") return { kind: "auto" };
  const match = /^model:(claude|codex):(.+)$/.exec(value);
  if (!match) return NO_ASSIGNEE;
  const engine = match[1] as TicketEngine;
  const model = match[2]!;
  return launchModelIds(engine).includes(model) ? { kind: "model", engine, model } : NO_ASSIGNEE;
}

export interface TicketOption {
  value: string;
  label: string;
}

/** The models a task can be given to, one group per engine, in catalogue
    order. A saved retired choice stays listed while it is the current one. */
export function ticketModelOptions(current?: TaskAssignee): { engine: TicketEngine; options: TicketOption[] }[] {
  return TICKET_ENGINES.map((engine) => ({
    engine,
    options: listedModels(engine, current?.kind === "model" && current.engine === engine ? current.model : null).map((model) => ({
      value: assigneeValue({ kind: "model", engine, model: model.id }),
      label: model.label,
    })),
  }));
}

/** The ticket types offered when no workspace manifest names any. */
export const DEFAULT_TICKET_TYPES: readonly string[] = ["Bug", "Implementation", "Research", "Improvement"];

/** A project's ticket types: its own manifest's `ticketTypes`, else its
    workspace parent's, else the defaults. */
export function ticketTypesFor(project: string, catalog: readonly ProjectCatalogEntry[]): readonly string[] {
  const entry = catalog.find((row) => row.project === project);
  if (entry?.ticketTypes?.length) return entry.ticketTypes;
  const parent = entry?.workspaceParent ? catalog.find((row) => row.project === entry.workspaceParent) : undefined;
  return parent?.ticketTypes?.length ? parent.ticketTypes : DEFAULT_TICKET_TYPES;
}

/** The title as stored: the type in brackets ahead of it, so the card, every
    reader and the agent's brief carry the type without a new task field. */
export function typedTitle(type: string, title: string): string {
  const kind = type.trim();
  const head = title.trim();
  return kind && head ? `[${kind}] ${head}` : title;
}

/** Title on the first line, then a blank line, then the description. The
    title's own line breaks fold to spaces so it stays one line. */
export function composeTaskText(title: string, description: string): string {
  const head = title.replace(/\s*\r?\n\s*/g, " ").trim();
  const body = description.trim();
  if (!head) return body;
  return body ? `${head}\n\n${body}` : head;
}

export function readTaskPriority(value: string): TaskPriority {
  return (TASK_PRIORITIES as readonly string[]).includes(value) ? value as TaskPriority : "normal";
}

/** Every project the operator can file a task in: the catalog, the projects
    the loaded conversations belong to, and the current one, by name. */
export function ticketProjectOptions(
  current: string,
  currentName: string | undefined,
  files: readonly FileEntry[],
  catalog: readonly ProjectCatalogEntry[],
): TicketOption[] {
  const names = new Map<string, string | undefined>();
  names.set(current, currentName);
  for (const entry of catalog) if (!names.has(entry.project) || !names.get(entry.project)) names.set(entry.project, entry.displayName);
  for (const file of files) {
    const key = projectKey(file);
    if (!names.has(key) || !names.get(key)) names.set(key, file.projectName);
  }
  const options = [...names].map(([value, name]) => ({ value, label: projectDisplayName(value, name) }));
  const [head, ...rest] = options;
  return [head!, ...rest.sort((a, b) => a.label.localeCompare(b.label))];
}

/** Where and with what a fresh assignee launches: the project's own checkout
    (the root most of its conversations ran in, else the catalog's root) and,
    for `auto`, the engine its newest conversation used, Claude by default. */
export function autoSpawnShape(
  files: readonly FileEntry[],
  project: string,
  catalog: readonly ProjectCatalogEntry[],
  fallbacks: readonly string[] = [],
): { engine: TicketEngine; cwd: string } | null {
  const root = catalog.find((entry) => entry.project === project)?.projectRoot;
  const cwd = draftWorkingDirectory(files, project, undefined, [...(root ? [root] : []), ...fallbacks]);
  if (!cwd) return null;
  const newest = files
    .filter((file) => projectKey(file) === project && (file.engine === "claude" || file.engine === "codex"))
    .sort((a, b) => b.mtime - a.mtime)[0];
  return { engine: newest?.engine === "codex" ? "codex" : "claude", cwd };
}
