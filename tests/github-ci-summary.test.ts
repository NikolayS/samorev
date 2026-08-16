import { describe, expect, test } from "bun:test";
import { reviewGateFindings, summarizeGitHubCi } from "../src/fetchReport";

const publisher = { id: 303, name: "base-controlled samorev publisher" };

describe("GitHub CI self-check exclusion", () => {
  test("excludes only the exact configured publisher and discloses it", () => {
    expect(summarizeGitHubCi({ check_runs: [
      { name: "typecheck", conclusion: "success" },
      { ...publisher, status: "in_progress", conclusion: null },
    ] }, "303")).toEqual({
      status: "success",
      summary: "total=1 success=1 failure=0 pending=0 other=0 excluded_self=1",
    });
  });

  test("fails closed when no independent CI remains", () => {
    expect(summarizeGitHubCi({ check_runs: [
      { ...publisher, status: "in_progress", conclusion: null },
    ] }, "303").status).toBe("self-only");
    expect(reviewGateFindings("self-only", false)).toEqual([
      expect.objectContaining({ severity: "CRITICAL", title: "Pipeline status is self-only" }),
    ]);
  });

  test("does not hide a similarly named check with a different id", () => {
    expect(summarizeGitHubCi({ check_runs: [
      { name: "samorev-lint", conclusion: "failure", status: "completed" },
      { ...publisher, status: "in_progress", conclusion: null },
    ] }, "303")).toEqual({
      status: "failure",
      summary: "total=1 success=0 failure=1 pending=0 other=0 excluded_self=1",
    });
  });

  test("does not exclude a completed publisher failure or exclude implicitly", () => {
    expect(summarizeGitHubCi({ check_runs: [
      { ...publisher, status: "completed", conclusion: "failure" },
    ] }, "303").status).toBe("failure");
    expect(summarizeGitHubCi({ check_runs: [
      { ...publisher, status: "in_progress", conclusion: null },
    ] }).status).toBe("pending");
  });
});
