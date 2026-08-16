import { describe, expect, test } from "bun:test";
import { formatCiBadge, reviewGateFindings, summarizeGitHubCi } from "../src/fetchReport";

const publisher = { id: 303, name: "base-controlled samorev publisher" };
const trusted = { runIds: ["303"], name: publisher.name, appId: "15368" };

describe("GitHub CI self-check exclusion", () => {
  test("excludes only the exact configured publisher and discloses it", () => {
    expect(summarizeGitHubCi({ check_runs: [
      { name: "typecheck", conclusion: "success" },
      { ...publisher, app: { id: 15368 }, status: "in_progress", conclusion: null },
    ] }, trusted)).toEqual({
      status: "success",
      summary: "total=1 success=1 failure=0 pending=0 other=0 excluded_self=1",
    });
  });

  test("fails closed when no independent CI remains", () => {
    expect(summarizeGitHubCi({ check_runs: [
      { ...publisher, app: { id: 15368 }, status: "in_progress", conclusion: null },
    ] }, trusted).status).toBe("self-only");
    expect(reviewGateFindings("self-only", false)).toEqual([
      expect.objectContaining({ severity: "HIGH", title: "Pipeline status is self-only" }),
    ]);
    expect(formatCiBadge("self-only")).toBe("FAIL");
  });

  test("does not hide a similarly named check with a different id", () => {
    expect(summarizeGitHubCi({ check_runs: [
      { name: "samorev-lint", conclusion: "failure", status: "completed" },
      { ...publisher, app: { id: 15368 }, status: "in_progress", conclusion: null },
    ] }, trusted)).toEqual({
      status: "failure",
      summary: "total=1 success=0 failure=1 pending=0 other=0 excluded_self=1",
    });
  });

  test("does not exclude a completed publisher failure or exclude implicitly", () => {
    expect(summarizeGitHubCi({ check_runs: [
      { ...publisher, app: { id: 15368 }, status: "completed", conclusion: "failure" },
    ] }, trusted).status).toBe("failure");
    expect(summarizeGitHubCi({ check_runs: [
      { ...publisher, status: "in_progress", conclusion: null },
    ] }).status).toBe("pending");
  });

  test("requires the configured publisher name and app as defense in depth", () => {
    const pending = { ...publisher, app: { id: 999 }, status: "in_progress", conclusion: null };
    expect(summarizeGitHubCi({ check_runs: [pending] }, trusted).status).toBe("pending");
    expect(summarizeGitHubCi({ check_runs: [{ ...pending, app: { id: 15368 }, name: "other" }] }, trusted).status).toBe("pending");
  });
});
