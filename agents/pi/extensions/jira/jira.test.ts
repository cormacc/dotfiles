#!/usr/bin/env tsx
/**
 * Unit tests for the jira extension's pure helpers.
 *
 * The MCP-driven workflows themselves are tested manually against the
 * SAND sandbox project (per the parent change-record's design
 * decisions); these tests cover only the deterministic, I/O-free
 * argument-resolution and keyword-reading logic.
 *
 * Run: `tsx jira.test.ts` (or via `./test.sh`).
 */

import { buildClonePrompt, getFileKeyword, resolveKey } from "./utils.ts";

let passed = 0;
let failed = 0;

function assertEqual<T>(actual: T, expected: T, message: string): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) {
    passed++;
    console.log(`ok - ${message}`);
  } else {
    failed++;
    console.log(`not ok - ${message}`);
    console.log(`  expected: ${e}`);
    console.log(`  actual:   ${a}`);
  }
}

// ── resolveKey: well-formed PROJ-NNN passes through ──────────────────

assertEqual(
  resolveKey("MBFW-123", "SAND"),
  { key: "MBFW-123" },
  "resolveKey: PROJ-NNN passes through unchanged",
);

assertEqual(
  resolveKey("SAND-42", null),
  { key: "SAND-42" },
  "resolveKey: PROJ-NNN works without project keyword",
);

// ── resolveKey: bare number with project ──────────────────────────────

assertEqual(
  resolveKey("42", "SAND"),
  { key: "SAND-42" },
  "resolveKey: bare number prepends #+JIRA_PROJECT",
);

// ── resolveKey: bare number without project ───────────────────────────

{
  const r = resolveKey("42", null);
  if ("error" in r) {
    passed++;
    console.log("ok - resolveKey: bare number without project returns error");
  } else {
    failed++;
    console.log("not ok - resolveKey: bare number without project should error");
  }
}

// ── resolveKey: malformed input ───────────────────────────────────────

{
  const r = resolveKey("not-a-key", "SAND");
  if ("error" in r) {
    passed++;
    console.log("ok - resolveKey: malformed input returns error");
  } else {
    failed++;
    console.log("not ok - resolveKey: malformed input should error");
  }
}

// ── getFileKeyword: matches helper behaviour from tasks/parser.ts ─────

{
  const content = [
    "#+JIRA_CLOUDID: abc-123",
    "#+JIRA_PROJECT:",
    "#+JIRA_BASE_URL: https://example.com",
    "",
  ].join("\n");

  assertEqual(
    getFileKeyword(content, "JIRA_CLOUDID"),
    "abc-123",
    "getFileKeyword: returns value",
  );
  assertEqual(
    getFileKeyword(content, "JIRA_PROJECT"),
    "",
    "getFileKeyword: empty value yields empty string (not next-line)",
  );
  assertEqual(
    getFileKeyword(content, "JIRA_BASE_URL"),
    "https://example.com",
    "getFileKeyword: line after empty keyword still resolvable",
  );
  assertEqual(
    getFileKeyword(content, "ABSENT"),
    null,
    "getFileKeyword: returns null for absent keyword",
  );
  assertEqual(
    getFileKeyword(content, "jira_cloudid"),
    "abc-123",
    "getFileKeyword: case-insensitive on name",
  );
}

// ── buildClonePrompt: structural sanity ───────────────────────────

{
  const prompt = buildClonePrompt(
    ["SAND-1", "SAND-2"],
    {
      cloudId: "abc-cloud",
      project: "SAND",
      baseUrl: "https://example.atlassian.net",
    },
    "/tmp/proj",
    "TASKS.org",
    "TASKS.local.org",
  );
  if (prompt.includes("SAND-1") && prompt.includes("SAND-2")) {
    passed++;
    console.log("ok - buildClonePrompt: lists every key");
  } else {
    failed++;
    console.log("not ok - buildClonePrompt: should list every key");
  }
  if (prompt.includes("abc-cloud")) {
    passed++;
    console.log("ok - buildClonePrompt: inlines cloudId when present");
  } else {
    failed++;
    console.log("not ok - buildClonePrompt: should inline cloudId");
  }
  if (prompt.includes("atlassian_getJiraIssue")) {
    passed++;
    console.log("ok - buildClonePrompt: references the MCP tool name");
  } else {
    failed++;
    console.log("not ok - buildClonePrompt: should reference atlassian_getJiraIssue");
  }
  if (prompt.includes(":LINKED_ISSUES: <KEY>")) {
    passed++;
    console.log("ok - buildClonePrompt: instructs setting :LINKED_ISSUES:");
  } else {
    failed++;
    console.log("not ok - buildClonePrompt: should instruct :LINKED_ISSUES: write");
  }
}

// Without #+JIRA_CLOUDID, the prompt must instruct cloudId resolution.
{
  const prompt = buildClonePrompt(
    ["SAND-1"],
    { cloudId: null, project: "SAND", baseUrl: "https://example.atlassian.net" },
    "/tmp/proj",
    "TASKS.org",
    "TASKS.local.org",
  );
  if (prompt.includes("atlassian_getAccessibleAtlassianResources")) {
    passed++;
    console.log(
      "ok - buildClonePrompt: instructs cloudId resolution when keyword absent",
    );
  } else {
    failed++;
    console.log(
      "not ok - buildClonePrompt: should instruct cloudId resolution when keyword absent",
    );
  }
}

console.log(`\n# ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
