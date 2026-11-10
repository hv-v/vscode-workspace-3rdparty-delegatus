import { getLocale, translate } from "@/lib/i18n";
import type { BoardTask } from "@/lib/tasks/types";
import type { FileEntry, ProjectCatalogEntry } from "@/lib/types";

import { createTaskSpawnGesture, spawnTaskAgent } from "./taskApi";
import { autoSpawnShape, type TaskAssignee } from "./taskTicket";
import { pushTaskToast } from "./taskToast";

/**
 * Hands a just-created task to its chosen assignee through the ordinary spawn
 * route: a fresh agent in the project's checkout, on the chosen model or, for
 * `auto`, on the project's usual engine. The outcome is a toast; a failure
 * leaves the task in Inbox, created, where the card's own controls can still
 * assign it.
 */
export async function assignCreatedTask(
  task: BoardTask,
  assignee: TaskAssignee,
  files: FileEntry[],
  catalog: readonly ProjectCatalogEntry[],
  /** Checkouts to launch in when the project names none of its own. */
  fallbackCwds: readonly string[] = [],
): Promise<void> {
  if (assignee.kind === "none") return;
  const locale = getLocale();
  const shape = autoSpawnShape(files, task.project, catalog, fallbackCwds);
  if (!shape) {
    pushTaskToast("err", translate(locale, "tasks.ticket.autoNoCwd"));
    return;
  }
  const launch = assignee.kind === "model" ? { engine: assignee.engine, model: assignee.model, cwd: shape.cwd } : shape;
  const spawned = await spawnTaskAgent(task.id, createTaskSpawnGesture(launch));
  /* A spawn result carries its own optional `error`, so only `state` tells the route's refusal apart. */
  if (!("state" in spawned)) pushTaskToast("err", translate(locale, "tasks.ticket.autoFailed", { error: spawned.error }));
  else if (spawned.state === "failed" || spawned.state === "conflict") pushTaskToast("err", translate(locale, "tasks.ticket.autoFailed", { error: spawned.error ?? spawned.state }));
  else pushTaskToast("ok", translate(locale, "tasks.ticket.autoStarted", { engine: launch.engine === "codex" ? "Codex" : "Claude" }));
}
