import { describe, expect, test } from "bun:test";
import { summarizeGitHubCi } from "../src/fetchReport";

const publisher = "base-controlled samorev publisher";

describe("GitHub CI self-check exclusion", () => {
  test("excludes only the exact configured publisher and discloses it", () => {
    expect(summarizeGitHubCi({ check_runs: [
      { name: "typecheck", conclusion: "success" },
      { name: publisher, status: "in_progress", conclusion: null },
    ] }, publisher)).toEqual({
      status: "success",
      summary: "total=1 success=1 failure=0 pending=0 other=0 excluded_self=1",
    });
  });

  test("fails closed when no independent CI remains", () => {
    expect(summarizeGitHubCi({ check_runs: [
      { name: publisher, conclusion: "failure", status: "completed" },
    ] }, publisher).status).toBe("self-only");
  });

  test("does not hide a similarly named untrusted check", () => {
    expect(summarizeGitHubCi({ check_runs: [
      { name: "samorev-lint", conclusion: "failure", status: "completed" },
      { name: publisher, status: "in_progress", conclusion: null },
    ] }, publisher)).toEqual({
      status: "failure",
      summary: "total=1 success=0 failure=1 pending=0 other=0 excluded_self=1",
    });
  });
});
