import { expect, test } from "bun:test";
import { CLAUDE_ACCOUNT_SETTING_SOURCES_ENV, claudeAccountSettingSources } from "./claudeSettingSources";

const env = (value: string | undefined) => ({ [CLAUDE_ACCOUNT_SETTING_SOURCES_ENV]: value });

test("unset or blank keeps the upstream empty list", () => {
  expect(claudeAccountSettingSources({})).toBe("");
  expect(claudeAccountSettingSources(env(undefined))).toBe("");
  expect(claudeAccountSettingSources(env("  "))).toBe("");
  expect(claudeAccountSettingSources(env(" , "))).toBe("");
});

test("project and local are admitted, trimmed and de-duplicated", () => {
  expect(claudeAccountSettingSources(env("project"))).toBe("project");
  expect(claudeAccountSettingSources(env(" project , local "))).toBe("project,local");
  expect(claudeAccountSettingSources(env("project,project"))).toBe("project");
});

test("user or an unknown source never widens what loads", () => {
  expect(claudeAccountSettingSources(env("user"))).toBe("");
  expect(claudeAccountSettingSources(env("project,user"))).toBe("");
  expect(claudeAccountSettingSources(env("projects"))).toBe("");
});
