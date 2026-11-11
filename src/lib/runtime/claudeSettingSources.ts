/**
 * The `--setting-sources` value a Claude engine on a provider account is
 * started with.
 *
 * Upstream passes an empty list, so a provider-account session loads none of
 * the filesystem settings: no CLAUDE.md, no `.claude/rules`, no project
 * skills, subagents or hooks. An install whose agents must follow the
 * repository's own instructions opts into project sources with
 * `LLV_CLAUDE_ACCOUNT_SETTING_SOURCES` (`project`, `local`, or both, comma
 * separated). `user` is never admitted: the account home stays out, which is
 * what the empty default protects. Anything unrecognised falls back to the
 * empty default rather than widening what loads.
 */
export const CLAUDE_ACCOUNT_SETTING_SOURCES_ENV = "LLV_CLAUDE_ACCOUNT_SETTING_SOURCES";

const ADMITTED_SOURCES = new Set(["project", "local"]);

export function claudeAccountSettingSources(env: Record<string, string | undefined> = process.env): string {
  const raw = env[CLAUDE_ACCOUNT_SETTING_SOURCES_ENV]?.trim();
  if (!raw) return "";
  const sources = raw.split(",").map((source) => source.trim()).filter(Boolean);
  if (sources.length === 0 || !sources.every((source) => ADMITTED_SOURCES.has(source))) return "";
  return [...new Set(sources)].join(",");
}
