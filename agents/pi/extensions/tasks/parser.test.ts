#!/usr/bin/env tsx
/**
 * Parser/serializer tests for the tasks extension.
 *
 * These cover the round-trip invariants that the rest of the extension
 * relies on:
 *
 * - `CLOSED:` is captured regardless of whether it appears above or
 *   below the `:PROPERTIES:` drawer, and serializes back above the
 *   drawer (matching `org-todo`'s native behaviour).
 * - `:CREATED:` rides through as an ordinary property line.
 *
 * Run: `tsx parser.test.ts` (or via `./test.sh`).
 */

import {
  extractOrgLink,
  getDrawerProperty,
  getFileKeyword,
  getLinkedIssues,
  parseTasks,
  resolveIssueUrl,
  serializeTasks,
  serializeTasksPreservingFile,
  setDrawerProperty,
  setLinkedIssues,
  type Task,
} from "./parser.ts";
import { scaffoldPlan } from "./scaffold.ts";

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

function assertContains(haystack: string, needle: string, message: string): void {
  if (haystack.includes(needle)) {
    passed++;
    console.log(`ok - ${message}`);
  } else {
    failed++;
    console.log(`not ok - ${message}`);
    console.log(`  expected to contain: ${JSON.stringify(needle)}`);
    console.log(`  actual: ${JSON.stringify(haystack)}`);
  }
}

// ── CLOSED: above the drawer (org-todo native) ────────────────────────

{
  const input = [
    "* DONE [#B] Task one",
    "CLOSED: [2026-04-25 Sat 12:00]",
    ":PROPERTIES:",
    ":ID: 11111111-2222-4333-8444-555555555555",
    ":CREATED: [2026-04-24 Fri 09:15]",
    ":END:",
    "Some description.",
    "",
  ].join("\n");

  const { tasks } = parseTasks(input);
  assertEqual(tasks.length, 1, "parses one task (CLOSED above drawer)");
  assertEqual(tasks[0]!.closed, "2026-04-25 Sat 12:00",
    "captures CLOSED above drawer");
  assertEqual(
    tasks[0]!.propertyLines,
    [
      ":ID: 11111111-2222-4333-8444-555555555555",
      ":CREATED: [2026-04-24 Fri 09:15]",
    ],
    "preserves :ID: and :CREATED: property lines",
  );
}

// ── CLOSED: below the drawer (legacy / pre-amendment) ─────────────────

{
  const input = [
    "* DONE [#B] Task two",
    ":PROPERTIES:",
    ":ID: 22222222-3333-4444-8555-666666666666",
    ":END:",
    "CLOSED: [2026-04-25 Sat 12:00]",
    "Some description.",
    "",
  ].join("\n");

  const { tasks } = parseTasks(input);
  assertEqual(tasks.length, 1, "parses one task (CLOSED below drawer)");
  assertEqual(tasks[0]!.closed, "2026-04-25 Sat 12:00",
    "captures CLOSED below drawer");
}

// ── Serializer always emits CLOSED above drawer ───────────────────────

{
  const inputBelow = [
    "* DONE [#B] Round-trip",
    ":PROPERTIES:",
    ":ID: 33333333-4444-4555-8666-777777777777",
    ":END:",
    "CLOSED: [2026-04-25 Sat 12:00]",
    "",
  ].join("\n");

  const { tasks } = parseTasks(inputBelow);
  const out = serializeTasks(tasks);

  assertContains(out, "* DONE [#B] Round-trip\nCLOSED: [2026-04-25 Sat 12:00]\n:PROPERTIES:",
    "serializer emits CLOSED above drawer");
  // No leftover CLOSED below drawer.
  const closedCount = (out.match(/^CLOSED:/gm) ?? []).length;
  assertEqual(closedCount, 1, "exactly one CLOSED line after round-trip");
}

// ── :CREATED: round-trip ──────────────────────────────────────────────

{
  const input = [
    "* TODO New task",
    ":PROPERTIES:",
    ":ID: 44444444-5555-4666-8777-888888888888",
    ":CREATED: [2026-04-28 Tue 10:49]",
    ":END:",
    "",
  ].join("\n");

  const { tasks } = parseTasks(input);
  const out = serializeTasks(tasks);
  assertContains(out, ":CREATED: [2026-04-28 Tue 10:49]",
    ":CREATED: survives round-trip in property lines");
}

// ── scaffoldPlan canonical-skeleton snapshot ──────────────────────────
//
// Regression guard against unintentional changes to the canonical
// change-record skeleton documented in `agents/skills/org-plan/SKILL.md`.
// (Plan creation only happens via the agent harness; the elisp side
// has no scaffolder so there is no cross-implementation pairing.)

{
  // Freeze the date so the snapshot is deterministic.
  const realDate = Date;
  // @ts-expect-error — monkey-patch global Date for the duration of the test.
  globalThis.Date = class extends realDate {
    constructor() {
      super("2026-04-28T00:00:00");
    }
  };
  try {
    const fixture: Task = {
      level: 2,
      status: "TODO",
      priority: null,
      summary: "Refine org-memory protocol",
      tags: [],
      description: "",
      children: [],
      propertyLines: [":ID: 80ea589b-501c-42d9-86e7-4d414c0c314e"],
      importPath: null,
      importRaw: null,
      isLocal: false,
      closed: null,
      lineNumber: 0,
      endLine: 0,
    };
    const expected = [
      "#+TITLE: Refine org-memory protocol",
      "#+DATE: 2026-04-28 Tue",
      "#+PARENT_ID: 80ea589b-501c-42d9-86e7-4d414c0c314e",
      "#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)",
      "",
      "* Context",
      "",
      "* Plan",
      "",
      "* Implementation",
      "",
      "",
    ].join("\n");
    const actual = scaffoldPlan(fixture);
    assertEqual(actual, expected,
      "scaffoldPlan canonical-skeleton snapshot (org-plan SKILL)");
  } finally {
    globalThis.Date = realDate;
  }
}

// ── Generic round-trip: unknown #+ keywords + drawer properties ──────
//
// Third-party extensions (e.g. `jira`) build on the contract that the
// parser/serializer pass unknown keywords and drawer properties through
// untouched. Lock that in with fictional namespaces so the test does not
// also exercise any first-party conventions.

{
  const input = [
    "#+TITLE: Fixture",
    "#+FOO_BAR: hello world",
    "#+QUUX: 42",
    "",
    "* TODO Top-level",
    ":PROPERTIES:",
    ":ID: aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
    ":FOO_BAZ: alpha beta",
    ":NS_ZIM: gamma",
    ":END:",
    "Description line.",
    "",
  ].join("\n");

  const out = serializeTasksPreservingFile(input, parseTasks(input).tasks);

  assertContains(out, "#+FOO_BAR: hello world",
    "unknown file keyword #+FOO_BAR round-trips");
  assertContains(out, "#+QUUX: 42",
    "unknown file keyword #+QUUX round-trips");
  assertContains(out, ":FOO_BAZ: alpha beta",
    "unknown drawer property :FOO_BAZ: round-trips");
  assertContains(out, ":NS_ZIM: gamma",
    "unknown drawer property :NS_ZIM: round-trips");
}

// ── getFileKeyword helper ────────────────────────────────────────────

{
  const content = [
    "#+TITLE: Example",
    "#+FOO_BAR: alpha",
    "#+QUUX:42",
    "",
    "* TODO Task",
  ].join("\n");

  assertEqual(getFileKeyword(content, "FOO_BAR"), "alpha",
    "getFileKeyword returns value for present keyword");
  assertEqual(getFileKeyword(content, "foo_bar"), "alpha",
    "getFileKeyword is case-insensitive on name");
  assertEqual(getFileKeyword(content, "QUUX"), "42",
    "getFileKeyword tolerates no-space-after-colon");
  assertEqual(getFileKeyword(content, "MISSING"), null,
    "getFileKeyword returns null for absent keyword");

  // Regression: an empty #+KEYWORD: line must not leak into the next line.
  const withBlank = [
    "#+JIRA_CLOUDID: abc-123",
    "#+JIRA_PROJECT:",
    "#+JIRA_BASE_URL: https://example.com",
    "",
  ].join("\n");
  assertEqual(getFileKeyword(withBlank, "JIRA_PROJECT"), "",
    "getFileKeyword: empty value yields empty string, not next-line content");
  assertEqual(getFileKeyword(withBlank, "JIRA_BASE_URL"), "https://example.com",
    "getFileKeyword: line after empty keyword still resolvable");
}

// ── getDrawerProperty / setDrawerProperty helpers ────────────────────

{
  const input = [
    "* TODO Generic-helper subject",
    ":PROPERTIES:",
    ":ID: cccccccc-dddd-4eee-8fff-000011112222",
    ":FOO_BAZ: original value",
    ":END:",
    "",
  ].join("\n");

  const { tasks } = parseTasks(input);
  const task = tasks[0]!;

  assertEqual(getDrawerProperty(task, "FOO_BAZ"), "original value",
    "getDrawerProperty returns value for present property");
  assertEqual(getDrawerProperty(task, "foo_baz"), "original value",
    "getDrawerProperty is case-insensitive on name");
  assertEqual(getDrawerProperty(task, "MISSING"), null,
    "getDrawerProperty returns null for absent property");

  // Update existing.
  setDrawerProperty(task, "FOO_BAZ", "updated value");
  assertEqual(getDrawerProperty(task, "FOO_BAZ"), "updated value",
    "setDrawerProperty replaces existing value in place");

  // Add new.
  setDrawerProperty(task, "NS_NEW", "hello");
  assertEqual(getDrawerProperty(task, "NS_NEW"), "hello",
    "setDrawerProperty appends new property line");

  // Verify ordering and round-trip.
  const out = serializeTasks(tasks);
  assertContains(out, ":FOO_BAZ: updated value",
    "setDrawerProperty replacement appears in serialized output");
  assertContains(out, ":NS_NEW: hello",
    "setDrawerProperty appended property appears in serialized output");

  // Remove.
  setDrawerProperty(task, "FOO_BAZ", null);
  assertEqual(getDrawerProperty(task, "FOO_BAZ"), null,
    "setDrawerProperty(name, null) removes property");
  const out2 = serializeTasks(tasks);
  assertEqual((out2.match(/:FOO_BAZ:/g) ?? []).length, 0,
    "removed property no longer appears in serialized output");
}

// ── extractOrgLink helper ────────────────────────────────────────────

{
  assertEqual(
    extractOrgLink("[[https://example/x][label]]"),
    { target: "https://example/x", description: "label" },
    "extractOrgLink: target + description",
  );
  assertEqual(
    extractOrgLink("[[https://example/x]]"),
    { target: "https://example/x", description: null },
    "extractOrgLink: target only",
  );
  assertEqual(
    extractOrgLink("[[file:design/log/foo.org][Plan]]"),
    { target: "design/log/foo.org", description: "Plan" },
    "extractOrgLink: file: prefix stripped from target",
  );
  assertEqual(
    extractOrgLink("MBFW-123"),
    null,
    "extractOrgLink: bare token returns null",
  );
  assertEqual(
    extractOrgLink("[[unterminated"),
    null,
    "extractOrgLink: malformed link returns null",
  );
}

// ── resolveIssueUrl helper ──────────────────────────────────────────

{
  assertEqual(
    resolveIssueUrl("https://example/browse/{ID}", "MBFW-123"),
    "https://example/browse/MBFW-123",
    "resolveIssueUrl: {ID} placeholder substitution",
  );
  assertEqual(
    resolveIssueUrl("https://example/browse/", "MBFW-123"),
    "https://example/browse/MBFW-123",
    "resolveIssueUrl: suffix-append fallback when no placeholder",
  );
  assertEqual(
    resolveIssueUrl("https://example/issues?id={ID}&v=full", "42"),
    "https://example/issues?id=42&v=full",
    "resolveIssueUrl: placeholder mid-template",
  );
  assertEqual(
    resolveIssueUrl("https://example/{ID}/comments?id={ID}", "X-1"),
    "https://example/X-1/comments?id=X-1",
    "resolveIssueUrl: replaces every occurrence of {ID}",
  );
  assertEqual(
    resolveIssueUrl(null, "MBFW-123"),
    null,
    "resolveIssueUrl: null template returns null",
  );
  assertEqual(
    resolveIssueUrl("", "MBFW-123"),
    null,
    "resolveIssueUrl: empty template returns null",
  );
  assertEqual(
    resolveIssueUrl("https://example/browse/{ID}", "a/b"),
    "https://example/browse/a%2Fb",
    "resolveIssueUrl: URL-encodes the key",
  );
}

// ── getLinkedIssues + setLinkedIssues round-trip ──────────────────────

{
  const input = [
    "* TODO Mixed bare-key and org-link tokens",
    ":PROPERTIES:",
    ":ID: dddddddd-eeee-4fff-8000-111122223333",
    ":LINKED_ISSUES: MBFW-123 MBE-45 [[https://github.com/foo/bar/issues/42][gh#42]]",
    ":END:",
    "",
  ].join("\n");

  const { tasks } = parseTasks(input);
  const task = tasks[0]!;
  const base = "https://your-org.atlassian.net/browse/{ID}";
  const issues = getLinkedIssues(task, base);

  assertEqual(issues.length, 3, "getLinkedIssues: returns three tokens");
  assertEqual(
    issues[0],
    {
      url: "https://your-org.atlassian.net/browse/MBFW-123",
      label: "MBFW-123",
      rawToken: "MBFW-123",
    },
    "getLinkedIssues: bare key resolves via template",
  );
  assertEqual(
    issues[1],
    {
      url: "https://your-org.atlassian.net/browse/MBE-45",
      label: "MBE-45",
      rawToken: "MBE-45",
    },
    "getLinkedIssues: second bare key resolves",
  );
  assertEqual(
    issues[2],
    {
      url: "https://github.com/foo/bar/issues/42",
      label: "gh#42",
      rawToken: "[[https://github.com/foo/bar/issues/42][gh#42]]",
    },
    "getLinkedIssues: org-link token uses target+description",
  );
}

{
  // Missing #+ISSUE_URL_BASE: bare keys still parse, url is null.
  const input = [
    "* TODO Bare keys without template",
    ":PROPERTIES:",
    ":ID: eeeeeeee-ffff-4000-8111-222233334444",
    ":LINKED_ISSUES: MBFW-123",
    ":END:",
    "",
  ].join("\n");

  const { tasks } = parseTasks(input);
  const issues = getLinkedIssues(tasks[0]!, null);
  assertEqual(issues.length, 1, "getLinkedIssues: bare key without template still listed");
  assertEqual(issues[0]!.url, null,
    "getLinkedIssues: bare key without template has null url");
  assertEqual(issues[0]!.label, "MBFW-123",
    "getLinkedIssues: bare key label preserved");
}

{
  // Empty/absent property
  const input = [
    "* TODO No linked issues",
    ":PROPERTIES:",
    ":ID: ffffffff-0000-4111-8222-333344445555",
    ":END:",
    "",
  ].join("\n");
  const { tasks } = parseTasks(input);
  assertEqual(getLinkedIssues(tasks[0]!, "https://x/{ID}").length, 0,
    "getLinkedIssues: returns [] when property absent");
}

{
  // setLinkedIssues round-trip
  const input = [
    "* TODO Set property",
    ":PROPERTIES:",
    ":ID: 00112233-4455-4666-8777-8899aabbccdd",
    ":END:",
    "",
  ].join("\n");
  const { tasks } = parseTasks(input);
  const task = tasks[0]!;

  setLinkedIssues(task, ["MBFW-123", "MBE-45"]);
  assertEqual(getDrawerProperty(task, "LINKED_ISSUES"), "MBFW-123 MBE-45",
    "setLinkedIssues: writes whitespace-joined tokens");

  const out = serializeTasks(tasks);
  assertContains(out, ":LINKED_ISSUES: MBFW-123 MBE-45",
    "setLinkedIssues: round-trips through serializer");

  setLinkedIssues(task, []);
  assertEqual(getDrawerProperty(task, "LINKED_ISSUES"), null,
    "setLinkedIssues([]): clears the property");
}

// ── Round-trip preserves :LINKED_ISSUES: line verbatim ─────────────────

{
  const input = [
    "#+ISSUE_URL_BASE: https://your-org.atlassian.net/browse/{ID}",
    "",
    "* TODO Round-trip",
    ":PROPERTIES:",
    ":ID: 11223344-5566-4777-8888-99aabbccddee",
    ":LINKED_ISSUES: MBFW-123 [[https://x/y][y]]",
    ":END:",
    "Body.",
    "",
  ].join("\n");

  const out = serializeTasksPreservingFile(input, parseTasks(input).tasks);
  assertContains(out,
    "#+ISSUE_URL_BASE: https://your-org.atlassian.net/browse/{ID}",
    "#+ISSUE_URL_BASE preamble round-trips",
  );
  assertContains(out,
    ":LINKED_ISSUES: MBFW-123 [[https://x/y][y]]",
    ":LINKED_ISSUES: drawer line round-trips verbatim",
  );
}

// ── Summary ───────────────────────────────────────────────────────────

console.log(`\n# ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
