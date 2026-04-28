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

import { parseTasks, serializeTasks, type Task } from "./parser.ts";
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

// ── Summary ───────────────────────────────────────────────────────────

console.log(`\n# ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
