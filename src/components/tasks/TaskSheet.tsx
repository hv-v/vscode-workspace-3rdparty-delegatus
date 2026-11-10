"use client";

import { ChevronLeft } from "lucide-react";
import { useMemo, useState } from "react";

import { X } from "@/components/icons";
import { fmtAge } from "@/components/utils";
import { projectDisplayName } from "@/lib/displayNames";
import { useLocale } from "@/lib/i18n";
import type { BoardTask } from "@/lib/tasks/types";
import type { FileEntry, ProjectCatalogEntry } from "@/lib/types";

import { TaskComposer } from "./TaskComposer";
import { TASK_TONES, taskTitle } from "./taskModel";
import { TaskTicketFields, useTaskTicket } from "./TaskTicketFields";
import { useTaskCreateDraft } from "./useTaskCreateDraft";
import { Z } from "@/components/layers";

export type TaskSheetView = "list" | "new";

/** Create view: the ticket (Title, the shared composer as Description, then
    Project, Priority and Assignee). Commits an `unplaced` task — placement is
    a board gesture the phone defers to `place on map`. */
function NewTaskView({
  project,
  projectName,
  projectCatalog,
  projectCwd,
  files,
  onCreated,
}: {
  project: string;
  projectName?: string;
  projectCatalog?: readonly ProjectCatalogEntry[];
  projectCwd?: string;
  files: FileEntry[];
  onCreated: (task: BoardTask) => void;
}) {
  const { t } = useLocale();
  const ticket = useTaskTicket(project);
  const draft = useTaskCreateDraft(project, { placement: "unplaced" }, onCreated, { ticket, files, projectCatalog, originCwd: projectCwd });

  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        void draft.composer.submit();
      }}
      className="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto p-3"
    >
      <TaskTicketFields
        ticket={ticket}
        files={files}
        projectName={projectName}
        projectCatalog={projectCatalog}
        origin={project}
        onTitleEnter={() => draft.composer.inputRef.current?.focus()}
      >
        <TaskComposer
          draft={draft}
          placeholder={t("tasks.ticket.descriptionPlaceholder")}
          createLabel={t("tasks.sheetCreate")}
          sendPayloadAvailable={Boolean(ticket.state.title.trim())}
        />
      </TaskTicketFields>
    </form>
  );
}

/**
 * The phone's task list and its create view, full-screen over the screen it
 * was opened on. A task in the list, and a task just created, open on the
 * phone's task screen (#2072 slice 5), which is where a task's status, text,
 * pipelines and agents live; this sheet has no editor of its own.
 */
export function TaskSheet({
  project,
  projectName,
  projectCatalog,
  projectCwd,
  tasks,
  files,
  initialView,
  onClose,
  onOpenTask,
}: {
  project: string;
  projectName?: string;
  projectCatalog?: readonly ProjectCatalogEntry[];
  projectCwd?: string;
  tasks: BoardTask[];
  files: FileEntry[];
  initialView: TaskSheetView;
  onClose: () => void;
  /** The task screen's opener: a row of the list, or the task just created. */
  onOpenTask: (task: BoardTask, from: "list" | "new") => void;
}) {
  const { t } = useLocale();
  const [view, setView] = useState<TaskSheetView>(initialView);
  const rows = useMemo(
    () =>
      [...tasks].sort((a, b) => {
        const doneRank = (task: BoardTask) => (task.status === "done" ? 1 : 0);
        return doneRank(a) - doneRank(b) || b.updatedAt.localeCompare(a.updatedAt);
      }),
    [tasks],
  );

  return (
    <div data-mobile2-sheet="tasks" className={`fixed inset-0 ${Z.sheet} flex flex-col bg-canvas pb-[env(safe-area-inset-bottom)]`}>
      <div className="flex min-h-[52px] shrink-0 items-center gap-2 border-b border-border bg-card px-2 py-1.5">
        {view !== "list" ? (
          <button
            type="button"
            className="flex h-11 w-11 shrink-0 items-center justify-center rounded-[8px] border border-border bg-canvas text-muted hover:text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
            aria-label={t("tasks.sheetBack")}
            onClick={() => setView("list")}
          >
            <ChevronLeft className="h-5 w-5" aria-hidden />
          </button>
        ) : null}
        <span className="shrink-0 pl-1 text-[13px] font-bold">
          {view === "new" ? t("tasks.sheetNew") : t("tasks.panelTitle")}
        </span>
        <span className="min-w-0 flex-1 truncate text-[11.5px] text-muted" title={projectName ?? project}>{projectDisplayName(project, projectName)}</span>
        <button
          type="button"
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-[8px] border border-border bg-canvas text-muted hover:text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
          aria-label={t("common.close")}
          onClick={onClose}
        >
          <X className="h-5 w-5" aria-hidden />
        </button>
      </div>

      {view === "list" ? (
        <div className="flex min-h-0 flex-1 flex-col gap-1 overflow-y-auto p-2">
          <button
            type="button"
            className="flex min-h-11 shrink-0 items-center justify-center gap-1 rounded-[10px] border border-dashed border-accent/50 text-[13px] font-bold text-accent hover:bg-accent/5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
            onClick={() => setView("new")}
          >
            + {t("tasks.sheetNew")}
          </button>
          {rows.map((task) => {
            const tone = TASK_TONES[task.status];
            return (
              <button
                key={task.id}
                type="button"
                className={`flex w-full min-w-0 flex-col gap-0.5 rounded-[10px] border border-border bg-card px-2.5 py-2 text-left shadow-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40 ${
                  task.status === "done" ? "opacity-60" : ""
                }`}
                data-task-sheet-row={task.id}
                onClick={() => onOpenTask(task, "list")}
              >
                <span className="flex min-w-0 items-center gap-1.5">
                  <span
                    className="shrink-0 rounded-full px-1.5 py-0.5 text-[9px] font-bold"
                    style={{ backgroundColor: tone.soft, color: tone.color }}
                  >
                    {t(`tasks.status.${task.status}`)}
                  </span>
                  <span className="min-w-0 flex-1 truncate text-[12.5px] font-semibold">
                    {taskTitle(task.text) || t("tasks.untitled")}
                  </span>
                </span>
                <span className="flex items-center gap-2 pl-0.5 text-[10.5px] text-muted">
                  {task.assignments.length ? <span>⤷ {task.assignments.length}</span> : null}
                  <span>{fmtAge(new Date(task.updatedAt).getTime() / 1000)}</span>
                </span>
              </button>
            );
          })}
          {!rows.length ? <div className="px-2 py-4 text-center text-[11.5px] text-muted">{t("tasks.sheetEmpty")}</div> : null}
        </div>
      ) : (
        <NewTaskView project={project} projectName={projectName} projectCatalog={projectCatalog} projectCwd={projectCwd} files={files} onCreated={(task) => onOpenTask(task, "new")} />
      )}
    </div>
  );
}
