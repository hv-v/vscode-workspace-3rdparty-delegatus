"use client";

import { useEffect, useRef } from "react";

import { applyTaskSnapshot, revertTaskSnapshot } from "@/hooks/useFiles";
import { useTaskDraft, type TaskDraftCapture } from "@/hooks/useTaskDraft";
import { useLocale } from "@/lib/i18n";
import type { BoardTask } from "@/lib/tasks/types";
import type { FileEntry, ProjectCatalogEntry } from "@/lib/types";

import { assignCreatedTask } from "./assignCreatedTask";
import { createTask, type CreateTaskInput } from "./taskApi";
import { composeTaskText, ticketTypesFor, typedTitle } from "./taskTicket";
import type { UseTaskTicketReturn } from "./TaskTicketFields";

const PROVISIONAL_PREFIX = "provisional:";

/** Whether a task id is a card drawn ahead of its create. */
export function isProvisionalTaskId(id: string): boolean {
  return id.startsWith(PROVISIONAL_PREFIX);
}

function provisionalTask(project: string, text: string, taken: TaskDraftCapture, placement: Pick<CreateTaskInput, "placement" | "pos">, priority?: CreateTaskInput["priority"]): BoardTask {
  const at = new Date().toISOString();
  return {
    id: `${PROVISIONAL_PREFIX}${taken.requestId}`, project, status: "inbox", text, placement: placement.placement,
    ...(placement.pos ? { pos: placement.pos } : {}), ...(taken.dueAt ? { dueAt: taken.dueAt, dueTz: taken.dueTz } : {}),
    ...(priority && priority !== "normal" ? { priority } : {}),
    ...(taken.attachments.length ? { attachments: taken.attachments } : {}), assignments: [], createdAt: at, updatedAt: at,
  };
}

/** The ticket form a create reads its title, project, priority and assignee
    from, with what the assignee step needs to resolve a conversation or a
    checkout. */
export interface TaskCreateTicket {
  ticket: UseTaskTicketReturn;
  files: FileEntry[];
  projectCatalog?: readonly ProjectCatalogEntry[];
  /** The checkout of the board the form opened on: where `auto` launches when
      the task stays in that project and no conversation names one. */
  originCwd?: string;
}

/**
 * The project's task draft, wired to one create: what every surface that makes a task from the shared composer
 * does (the kanban board's new-task card).
 *
 * With a ticket, the composer's text is the description: the title goes on the first line, the ticket's project
 * and priority go with the create, and once the task exists its assignee gets it (`assignCreatedTask`). Without
 * one, the composer's text is the whole task as before.
 *
 * The text (or a dictated override), the deadline, the staged images and the draft's request id go to the task
 * route, so a double press or a retry after a lost answer resolves to one task. Empty text, a busy composer or a
 * voice send in flight create nothing. The composer resets on the press and a provisional Inbox card, keyed by the
 * request id and drawn as saving, stands in for the task until the route answers; the created task (or the one a
 * retry matched) replaces it and is handed to `onCreated`. A refusal takes the card off, puts the text, deadline,
 * images and ticket back into the form and shows the route's words.
 */
export function useTaskCreateDraft(
  project: string,
  placement: Pick<CreateTaskInput, "placement" | "pos">,
  onCreated: (task: BoardTask) => void,
  ticketed?: TaskCreateTicket,
) {
  const { t } = useLocale();
  /* A ref (updated in an effect) bridges the composer's `submit`, needed at construction, to the later `save`
     without a forward reference. */
  const saveRef = useRef<(text?: string) => void | Promise<void>>(() => {});
  const draft = useTaskDraft(project, (overrideText) => saveRef.current(overrideText));
  const { composer } = draft;

  const save = async (overrideText?: string) => {
    const body = (overrideText ?? composer.textRef.current).trim();
    if (composer.busy || composer.voiceSending) return;
    const fields = ticketed?.ticket.ref.current;
    const type = fields && ticketTypesFor(fields.project || project, ticketed?.projectCatalog ?? []).includes(fields.type) ? fields.type : "";
    const text = fields ? composeTaskText(typedTitle(type, fields.title), body) : body;
    if (!text) {
      composer.setStatus({ kind: "err", text: t(fields ? "tasks.ticket.needsTitle" : "tasks.composerNeedsText") });
      return;
    }
    const target = fields?.project || project;
    const priority = fields && fields.priority !== "normal" ? fields.priority : undefined;
    const taken = draft.capture(body);
    const card = provisionalTask(target, text, taken, placement, priority);
    applyTaskSnapshot(card, false);
    composer.setStatus(null);
    draft.reset();
    ticketed?.ticket.reset();
    const created = await createTask({
      project: target,
      text,
      ...placement,
      dueAt: taken.dueAt,
      dueTz: taken.dueTz,
      attachments: taken.attachments,
      clientRequestId: taken.requestId,
      ...(priority ? { priority } : {}),
    });
    revertTaskSnapshot(card.id);
    if ("error" in created) {
      draft.restore(taken);
      if (fields) ticketed?.ticket.restore(fields);
      composer.setStatus({ kind: "err", text: created.error });
      return;
    }
    applyTaskSnapshot(created.task, true);
    onCreated(created.task);
    if (fields && ticketed) await assignCreatedTask(created.task, fields.assignee, ticketed.files, ticketed.projectCatalog ?? [], target === project && ticketed.originCwd ? [ticketed.originCwd] : []);
  };
  useEffect(() => {
    saveRef.current = save;
  });
  return draft;
}
