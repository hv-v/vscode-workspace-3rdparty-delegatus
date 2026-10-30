# SHIRE-1695 — review analysis of the speed_event interface

State on 2026-10-29. Written for review before anything is pushed; nothing here has been committed or published.

> **Update, later on 2026-10-29:** the MR threads are now read through the `.gitlab` mirror. The reviewers want
> request/response, so the interface was reworked into `srv/CheckSpeed.srv` — see
> `../.task_todos/SHIRE-1695-mr-comments.md` for the threads, the prepared change and the draft replies. Problems A
> and B below are resolved (status noted in each).

## Sources

| source | where | read |
|---|---|---|
| SHIRE-1695 (ticket + 3 comments) | `.atlassian/.jira/implementation/SHIRE-1695.json`, updated 2026-10-29 | yes |
| SHIRE-1719 (dependency, 1 comment) | `.atlassian/.jira/selected-for-development/SHIRE-1719.json`, pinned with `sync.sh add` | yes |
| SHIRE-1517 (evidence metadata) | `.atlassian/.jira/selected-for-development/SHIRE-1517.json` | yes |
| Confluence 284984803 (SHIRE-1509 rule engine, [WIP] v2, 2026-10-27) | `.atlassian/.confluence/284984803.html` | yes |
| `jen_evidence_rules_manager` MR !3, note 110710 | `.gitlab/.mr/shire/jen_evidence_rules_manager/3.json` | yes (update) |
| `jen_speed_enforcement_msgs` MR !1 | `.gitlab/.mr/shire/interfaces/jen_speed_enforcement_msgs/1.json` | yes (update) |

**(Superseded — the `.gitlab` mirror now has them.) The MR comments were not read.** `sync.sh` mirrors Jira and Confluence only, and `rules/atlassian.md` forbids
contacting `*.jenoptik.corp` any other way, which covers `as-git-01`. Paste the MR discussions into
`.task_todos/SHIRE-1695-mr-comments.md` and they can be answered point by point. Everything below is based on the
Jira comments and the Confluence page.

## Review comments known so far

### 1. Jose Roquette, SHIRE-1695: "The second AC depends on SHIRE-1719"

The interface can be defined now, but implementing it in the Speed Enforcement component needs the
`jen_speed_enforcement` node, which SHIRE-1719 creates.

What we did: AC1 is in `jen_speed_enforcement_msgs`. AC2 is implemented in the temporary `SpeedEnforcement` class
inside `jen_evidence_rules_manager` (local branch `SHIRE-1695-speed-event`, commit `54bf912`).

- **Defence of the current version:** SHIRE-1719's AC says the node is created "with initial MVP implementation
  (moved from evidence rules manager)". `SpeedEnforcement` is that MVP, so the publisher moves with it, and the
  interface is exercised and unit-tested (26 tests, Docker build green) before the node exists.
- **Against it:** Zach's comment on SHIRE-1719 says the MVP "has been created with a very different design" and
  will not simply be moved. The Confluence design (below) has no `speed_event` topic coming out of the manager at all.
  The ERM change also adds two dependencies to the manager (`jen_speed_enforcement_msgs`, `jen_scene_msgs`) that
  the final design may not need.

**Recommendation:** deliver AC1 now (MR !1 only). Keep the manager branch unmerged and pick AC2 up in SHIRE-1719,
on the real node. If the reviewers want the interface exercised now, the manager change is small (14 lines of
production code) and can be offered as interim, explicitly marked for removal in SHIRE-1719.

### 2. Zach Gerstman, SHIRE-1719: the MVP has a very different design

This concerns SHIRE-1719's estimate, not the message content. It does confirm point 1: the manager's
`SpeedEnforcement` is not the target architecture, so code placed there is likely to be rewritten.

## Messages versus the Confluence design (SHIRE-1509 page)

The page says speed enforcement receives **action requests** from the manager, based on `TriggerEvent.msg`, and
returns **STATE_PROGRESS / STATE_CONFIRMED / STATE_DISCARDED / STATE_ERROR** so the manager can send
`EvidenceStatus.msg`.

| | Confluence | current MR !1 |
|---|---|---|
| transport | action, goal = TriggerEvent | topic `speed_event` |
| decision state | 4 states | `is_violation` only |
| speed limit, trigger limit, travel speed | required (also SHIRE-1517) | yes |
| below minimum / above maximum | required (SHIRE-1695 design text) | `SpeedRange` |
| object_id, source_uuid, direction, vehicle_class | in the goal's TriggerEvent | repeated in `SpeedEvent` |

- **Defence:** the ticket asks for "ROS2 topics (or equivalent messaging interface) for speed_event", and the page is
  [WIP], about the rule engine, and its own comment (2026-10-27) says it is being updated after a discussion. The
  speed metadata (`speed`, both limits, `speed_range`) is needed in either design and carries over unchanged.
- **Risk:** if the action/state design stands, `SpeedEvent` becomes the action's result payload, the topic goes, and
  `object_id`, `source_uuid`, `direction`, `vehicle_class` and `is_violation` become redundant. A drop-in proposal
  is in `../.examples/SHIRE-1695-enforce-speed-action.md`.

**Question to settle in review:** is SHIRE-1509's action + state design agreed for speed enforcement? If yes, MR !1
should take the action proposal before it merges, so the interface is not changed twice.

## Field-by-field defence of `SpeedEvent`

| field | why it is there |
|---|---|
| `speed`, `base_speed_limit`, `trigger_speed_limit` | SHIRE-1695 design text and SHIRE-1517 AC: "speed limit, trigger limit and travel speed" |
| `is_violation` | design text: returns whether the vehicle is above or under the speed limit defined for it |
| `speed_range` | design text: report a speed below a minimal or above a maximal limit, shown in the databar |
| `direction`, `vehicle_class` | the rule selectors in the example configuration (`direction`, `vehicle_class`); requested in review |
| `object_id`, `source_uuid` | a topic has no request/response link, so the event must name its TriggerEvent |

Likely questions and answers:

- **Why `jen_units_msgs/KmH` when `TriggerEvent.speed` and `ValidateObject.speed` are `float64`?** Messages between
  nodes carry their unit (SHIRE-1590, the units system). The existing messages predate it.
- **Why `jen_scene_msgs/DirectionOfTravel` and not `jen_vision_msgs/ObjectDirection`?** It is the vocabulary of the
  rule configuration (BOTH / TOWARDS / AWAY). Known cost: an UNKNOWN object direction is reported as BOTH. If that
  is rejected, `ObjectDirection` is the alternative, at the price of a `jen_vision_msgs` submodule. In the action
  design the field disappears either way.
- **`speed_range` is always IN_RANGE.** The min/max configuration does not exist yet (rule engine, SHIRE-1509/1516).
  The field is in the message so the interface does not change when it does.
- **No `header`.** Nothing in the ticket needs a stamp; the TriggerEvent carries the timing.

## Problems found in the branches (fix before review)

Commands are for you to run; nothing was executed.

### A. MR !1 cannot merge: the branch has no common history with `master`

**Resolved:** you merged `master` into the branch on GitLab (`307bb69`); the MR is now mergeable.

`origin/master` of `jen_speed_enforcement_msgs` is GitLab's `Initial commit` (`6c9ee0a`, a template README).
The local branch starts from its own root commit `4fb0d80`, so `git merge-base` finds nothing and both sides add
`README.md`.

```bash
cd jen_evidence_rules_manager/jen_speed_enforcement_msgs
git fetch origin
git rebase origin/master            # conflict: README.md added on both sides
git checkout --theirs README.md     # during a rebase, "theirs" is our commit's version
git add README.md && git rebase --continue
git push --force-with-lease origin SHIRE-1695-speed-event
```

### B. The manager branch `SHIRE-1695-speed-event` (`54bf912`) is not ready either

**Done locally:** rebased onto `bf39df3`, `jen_speed_enforcement_msgs` added as a submodule (pinned to `307bb69`),
message reworded — now `94082fd`. The old commit is kept as branch `backup/SHIRE-1695-speed-event-54bf912`. Per the
MR !3 review this branch should not be opened as an MR; see the threads file.

1. **It sits on an old base.** Its parent is `59edc5b`, the pre-amend version of the SHIRE-1660 commit. The current
   `SHIRE-1660-evidence-rules-mngr-mvp` is `bf39df3`, which adds the same `jen_units_msgs` Dockerfile line.
   Rebase: `git rebase --onto SHIRE-1660-evidence-rules-mngr-mvp 59edc5b SHIRE-1695-speed-event`.
2. **CI would fail.** `jen_speed_enforcement_msgs/` is untracked in the manager repo, but the Dockerfile copies it.
   It needs to be a submodule, now that the remote exists:
   `git submodule add -b SHIRE-1695-speed-event git@as-git-01.jenoptik.corp:shire/interfaces/jen_speed_enforcement_msgs.git jen_speed_enforcement_msgs`
   (switch the branch to `master` once MR !1 merges).
3. **Commit message.** `speed event` should follow the repo's `SHIRE-1695: …` convention.

This only matters if the manager change is kept (see point 1 of the review comments).

### C. Minor, in MR !1

- `package.xml` licence is `propietary`, copied from `jen_calibration_manager_msgs`; `jen_units_msgs` has the same
  spelling, the manager uses `proprietary`. Fix or keep consistent with the interface repos.
- `package.xml` maintainer is `vhaponov@n-ix.com`; the GitLab commits use `valentyn.haponov@jenoptik.com`.

## Open decisions for you

1. Deliver AC1 only and move AC2 to SHIRE-1719 (recommended), or keep the manager change as interim?
2. Switch MR !1 to the action + state design now, or defend the topic until SHIRE-1509's page is final?
3. Paste the MR !3 / MR !1 discussions so they can be answered directly.
