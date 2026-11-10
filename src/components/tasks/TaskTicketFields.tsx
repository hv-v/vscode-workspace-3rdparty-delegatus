"use client";

import { useMemo, useRef, useState, type ReactNode } from "react";

import { useIsMobile } from "@/hooks/useIsMobile";
import { useLocale, type MessageKey, type TFunction } from "@/lib/i18n";
import { TASK_PRIORITIES, type TaskPriority } from "@/lib/tasks/types";
import type { FileEntry, ProjectCatalogEntry } from "@/lib/types";

import {
  DEFAULT_TICKET_TYPES,
  NO_ASSIGNEE,
  assigneeValue,
  readAssigneeValue,
  readTaskPriority,
  ticketModelOptions,
  ticketProjectOptions,
  ticketTypesFor,
  type TaskAssignee,
} from "./taskTicket";

/** The ticket's fields beside the composer's text, persisted per originating
    project next to the shared draft so a reload keeps the whole form. */
export interface TaskTicketState {
  title: string;
  project: string;
  priority: TaskPriority;
  /** One of the project's ticket types; empty is untyped. */
  type: string;
  assignee: TaskAssignee;
}

const ticketKey = (project: string) => "llvTaskTicket:" + project;

function readTicket(project: string): TaskTicketState {
  const blank: TaskTicketState = { title: "", project, priority: "normal", type: "", assignee: NO_ASSIGNEE };
  if (typeof window === "undefined") return blank;
  try {
    const raw = window.localStorage.getItem(ticketKey(project));
    if (!raw) return blank;
    const stored = JSON.parse(raw) as Partial<Record<keyof TaskTicketState, unknown>>;
    return {
      title: typeof stored.title === "string" ? stored.title : "",
      project: typeof stored.project === "string" && stored.project ? stored.project : project,
      priority: readTaskPriority(typeof stored.priority === "string" ? stored.priority : ""),
      type: typeof stored.type === "string" ? stored.type : "",
      assignee: readAssigneeValue(typeof stored.assignee === "string" ? stored.assignee : ""),
    };
  } catch {
    return blank;
  }
}

function writeTicket(origin: string, state: TaskTicketState): void {
  if (typeof window === "undefined") return;
  try {
    const empty = !state.title && state.project === origin && state.priority === "normal" && !state.type && state.assignee.kind === "none";
    if (empty) window.localStorage.removeItem(ticketKey(origin));
    else window.localStorage.setItem(ticketKey(origin), JSON.stringify({ ...state, assignee: assigneeValue(state.assignee) }));
  } catch {
    /* storage full / disabled: the fields just won't survive reload */
  }
}

export interface UseTaskTicketReturn {
  state: TaskTicketState;
  /** The latest state, for a submit that runs outside a render. */
  ref: { readonly current: TaskTicketState };
  set: (patch: Partial<TaskTicketState>) => void;
  reset: () => void;
  restore: (taken: TaskTicketState) => void;
}

/** Type, title, project, priority and assignee of the task being written in
    `origin`'s create form. */
export function useTaskTicket(origin: string): UseTaskTicketReturn {
  const [state, setState] = useState<TaskTicketState>(() => readTicket(origin));
  const ref = useRef(state);
  const commit = (next: TaskTicketState) => {
    ref.current = next;
    setState(next);
    writeTicket(origin, next);
  };
  return {
    state,
    ref,
    set: (patch) => commit({ ...ref.current, ...patch }),
    reset: () => commit({ title: "", project: origin, priority: "normal", type: "", assignee: NO_ASSIGNEE }),
    restore: (taken) => commit({ ...taken, title: ref.current.title.trim() ? ref.current.title : taken.title }),
  };
}

/** A default type reads in the interface language; a configured one as written. */
function typeLabel(t: TFunction, type: string): string {
  return (DEFAULT_TICKET_TYPES as readonly string[]).includes(type) ? t(`tasks.ticket.type.${type.toLowerCase()}` as MessageKey) : type;
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="flex min-w-0 flex-1 flex-col gap-0.5">
      <span className="px-0.5 text-[9.5px] font-bold uppercase tracking-wide text-muted">{label}</span>
      {children}
    </label>
  );
}


/**
 * The ticket's own fields, in ticket order: a one-line Title, the Description
 * (`children`, the shared composer), then Type, Project, Priority and
 * Assignee. Type lists the project's ticket types (`ticketTypes` in its
 * `.delegatus-workspace.json`, else the defaults). Assignee lists
 * `Unassigned`, `Auto` (a fresh agent on the project's usual engine) and
 * every Claude and Codex model a fresh agent can launch on.
 */
export function TaskTicketFields({
  ticket,
  files,
  projectName,
  projectCatalog = [],
  origin,
  onTitleEnter,
  children,
}: {
  ticket: UseTaskTicketReturn;
  files: FileEntry[];
  projectName?: string;
  projectCatalog?: readonly ProjectCatalogEntry[];
  /** The board the form opened on, listed first in the project choice. */
  origin: string;
  /** Enter in the title moves on to the description. */
  onTitleEnter?: () => void;
  /** The description editor. */
  children?: ReactNode;
}) {
  const { t } = useLocale();
  const isMobile = useIsMobile();
  const { state } = ticket;
  const projects = useMemo(() => ticketProjectOptions(origin, projectName, files, projectCatalog), [origin, projectName, files, projectCatalog]);
  const types = useMemo(() => ticketTypesFor(state.project, projectCatalog), [state.project, projectCatalog]);
  const models = useMemo(() => ticketModelOptions(state.assignee), [state.assignee]);
  const type = types.includes(state.type) ? state.type : "";
  const control = `w-full min-w-0 rounded-[8px] border border-border bg-canvas text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40 ${
    isMobile ? "min-h-11 px-2 text-[14px]" : "h-7 px-1.5 text-[11.5px]"
  }`;

  return (
    <div className="flex flex-col gap-1.5" data-task-ticket="">
      <Field label={t("tasks.ticket.title")}>
        <input
          type="text"
          data-task-ticket-title=""
          value={state.title}
          placeholder={t("tasks.ticket.titlePlaceholder")}
          maxLength={200}
          onChange={(event) => ticket.set({ title: event.target.value })}
          onKeyDown={(event) => {
            if (event.key !== "Enter" || event.nativeEvent.isComposing) return;
            event.preventDefault();
            onTitleEnter?.();
          }}
          className={`${control} font-semibold`}
        />
      </Field>
      {children ? (
        <div className="flex min-w-0 flex-col gap-0.5" data-task-ticket-description="">
          <span className="px-0.5 text-[9.5px] font-bold uppercase tracking-wide text-muted">{t("tasks.ticket.description")}</span>
          {children}
        </div>
      ) : null}
      <div className={`flex gap-1.5 ${isMobile ? "flex-col" : "flex-row"}`}>
        <Field label={t("tasks.ticket.type")}>
          <select
            data-task-ticket-type=""
            value={type}
            onChange={(event) => ticket.set({ type: event.target.value })}
            className={control}
          >
            <option value="">{t("tasks.ticket.noType")}</option>
            {types.map((option) => <option key={option} value={option}>{typeLabel(t, option)}</option>)}
          </select>
        </Field>
        <Field label={t("tasks.ticket.project")}>
          <select
            data-task-ticket-project=""
            value={state.project}
            onChange={(event) => {
              const project = event.target.value;
              ticket.set({ project, type: ticketTypesFor(project, projectCatalog).includes(state.type) ? state.type : "" });
            }}
            className={control}
          >
            {projects.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
          </select>
        </Field>
        <Field label={t("kanban.priority")}>
          <select
            data-task-ticket-priority=""
            value={state.priority}
            onChange={(event) => ticket.set({ priority: readTaskPriority(event.target.value) })}
            className={control}
          >
            {TASK_PRIORITIES.map((priority) => <option key={priority} value={priority}>{t(`kanban.priority.${priority}`)}</option>)}
          </select>
        </Field>
        <Field label={t("tasks.ticket.assignee")}>
          <select
            data-task-ticket-assignee=""
            value={assigneeValue(state.assignee)}
            onChange={(event) => ticket.set({ assignee: readAssigneeValue(event.target.value) })}
            className={control}
          >
            <option value="none">{t("tasks.ticket.unassigned")}</option>
            <option value="auto">{t("tasks.ticket.auto")}</option>
            {models.map((group) => group.options.length ? (
              <optgroup key={group.engine} label={group.engine === "codex" ? "Codex" : "Claude"}>
                {group.options.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
              </optgroup>
            ) : null)}
          </select>
        </Field>
      </div>
    </div>
  );
}
