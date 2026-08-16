#!/usr/bin/env bash
set -euo pipefail

raw_ci=$(cat)
if ! original_ci=$(jq -c '
  if type == "array" then
    if all(.[]; type == "object" and has("check_runs") and (.check_runs | type) == "array")
    then {check_runs: [.[].check_runs[]]}
    else {samorev_invalid_payload: true} end
  elif type == "object" then .
  else {samorev_invalid_payload: true} end
' <<<"$raw_ci" 2>/dev/null); then
  original_ci='{"samorev_fetch_error":true}'
fi
if [[ -z "$original_ci" ]]; then
  original_ci='{"samorev_fetch_error":true}'
fi

filtered_ci="$original_ci"
raw_ids=$(jq -cn --arg ids "${SAMOREV_IGNORED_GITHUB_CHECK_RUN_IDS:-}" '$ids | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')
trusted_ids=$(jq -c '[.[] | select(test("^[0-9]+$"))]' <<<"$raw_ids")
publisher_name=$(jq -nr --arg value "${SAMOREV_IGNORED_GITHUB_CHECK_NAME:-}" '$value | gsub("^\\s+|\\s+$"; "")')
publisher_app_id=$(jq -nr --arg value "${SAMOREV_IGNORED_GITHUB_CHECK_APP_ID:-}" '$value | gsub("^\\s+|\\s+$"; "")')
raw_id_count=$(jq 'length' <<<"$raw_ids")
trusted_id_count=$(jq 'length' <<<"$trusted_ids")
if [[ "$trusted_id_count" -ne "$raw_id_count" ]]; then
  echo "Ignoring non-numeric GitHub self-check run IDs" >&2
fi
configured=0
ids_configured=""
if [[ "$raw_id_count" -gt 0 ]]; then
  ids_configured="configured"
fi
for value in \
  "$ids_configured" \
  "$publisher_name" \
  "$publisher_app_id"; do
  if [[ -n "$value" ]]; then
    configured=$((configured + 1))
  fi
done

if [[ "$configured" -gt 0 && "$configured" -lt 3 ]]; then
  echo "Warning: incomplete or invalid GitHub self-check exclusion configuration; run IDs, exact name, and numeric app ID are all required; excluding nothing" >&2
elif [[ "$configured" -eq 3 && "$trusted_id_count" -gt 0 && "$publisher_app_id" =~ ^[0-9]+$ ]]; then
  if ! filtered_ci=$(jq -c \
    --argjson trusted_ids "$trusted_ids" \
    --arg name "$publisher_name" \
    --arg app "$publisher_app_id" '
    if has("check_runs") and (.check_runs | type) == "array" then
      .check_runs = [.check_runs[] | . as $run |
        if type == "object" then
          select((($trusted_ids | index($run.id | tostring)) != null and
            $run.name == $name and ($run.app | type) == "object" and
            ($run.app.id | tostring) == $app and
            $run.status != "completed" and $run.conclusion == null) | not)
        else . end]
    else . end
  ' <<<"$original_ci" 2>/dev/null); then
    filtered_ci='{"samorev_fetch_error":true}'
  fi
elif [[ "$configured" -gt 0 ]]; then
  echo "Warning: incomplete or invalid GitHub self-check exclusion configuration; run IDs, exact name, and numeric app ID are all required; excluding nothing" >&2
fi

original_count=$(jq -r 'if has("check_runs") and (.check_runs | type) == "array" then (.check_runs | length) else 0 end' <<<"$original_ci")
filtered_count=$(jq -r 'if has("check_runs") and (.check_runs | type) == "array" then (.check_runs | length) else 0 end' <<<"$filtered_ci")
excluded_self=$((original_count - filtered_count))

if [[ $(jq -r '.samorev_fetch_error == true' <<<"$filtered_ci") == "true" ]]; then
  excluded_self=0
  pipeline_status="fetch-error"
elif [[ "$excluded_self" -gt 0 && "$filtered_count" -eq 0 ]]; then
  pipeline_status="self-only"
else
  pipeline_status=$(jq -r '
    if .samorev_fetch_error == true then "fetch-error"
    elif (has("check_runs") and (.check_runs | type) == "array") | not then "unknown"
    else .check_runs as $runs |
      if ($runs | length) == 0 then "none"
      elif any($runs[]; type == "object" and ((.conclusion // "") as $conclusion | ["failure", "timed_out", "cancelled", "action_required", "stale"] | index($conclusion))) then "failure"
      elif any($runs[]; type == "object" and ((.conclusion // "") as $conclusion | (["success", "skipped", "neutral"] | index($conclusion)) == null) and ((.status // "") != "completed" or .conclusion == null)) then "pending"
      elif any($runs[]; type != "object") then "unknown"
      elif all($runs[]; (.conclusion // "") as $conclusion | ["success", "skipped", "neutral"] | index($conclusion)) and any($runs[]; .conclusion == "success") then "success"
      elif all($runs[]; (.conclusion // "") as $conclusion | ["success", "skipped", "neutral"] | index($conclusion)) then "none"
      else "unknown" end
    end
  ' <<<"$filtered_ci")
fi

pipeline_context="$filtered_ci"
pipeline_context=$(jq -c 'if has("check_runs") and (.check_runs | type) == "array" then .check_runs = [.check_runs[] | select(type == "object")] else {check_runs: []} end' <<<"$pipeline_context")
if ! pipeline_candidate=$(jq -c '
  def failed: (.conclusion // "") as $conclusion | ["failure", "timed_out", "cancelled", "action_required", "stale"] | index($conclusion);
  def actions: (.html_url // "") | test("/actions/runs/[0-9]+");
  (([.check_runs[] | select(failed and actions)] +
    [.check_runs[] | select(actions)] +
    [.check_runs[]]) | .[0]) // {}
' <<<"$pipeline_context" 2>/dev/null); then
  pipeline_candidate='{}'
fi
pipeline_id=$(jq -r '.html_url // "" | capture("/actions/runs/(?<id>[0-9]+)")? | .id // empty' <<<"$pipeline_candidate")
pipeline_url=$(jq -r '.html_url // empty' <<<"$pipeline_candidate")

jq -cn \
  --argjson original "$original_ci" \
  --argjson filtered "$filtered_ci" \
  --arg status "$pipeline_status" \
  --arg pipeline_id "$pipeline_id" \
  --arg pipeline_url "$pipeline_url" \
  --argjson original_count "$original_count" \
  --argjson filtered_count "$filtered_count" \
  --argjson excluded_self "$excluded_self" \
  '{original: $original, filtered: $filtered, status: $status, pipeline_id: $pipeline_id, pipeline_url: $pipeline_url, original_count: $original_count, filtered_count: $filtered_count, excluded_self: $excluded_self}'
