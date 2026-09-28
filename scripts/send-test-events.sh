#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Send Setup Manager HUD test webhook events from a CSV file.

Required environment variables:
  WORKER_URL      Example: https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev
  WEBHOOK_TOKEN   The same token saved as the Cloudflare WEBHOOK_TOKEN secret

Optional environment variables:
  CSV_FILE                Default: examples/test-devices.csv
  APPLICATIONS_FILE       Default: examples/test-applications.csv
  FAILED_APPLICATION      Default: Microsoft Outlook
  DAYS                   Default: 7
  ENROLLMENTS_PER_DEVICE Default: 7
  FAILURE_RATE           Default: 5
  DRY_RUN                Default: 0. Set to 1 to validate without posting.

Example:
  WORKER_URL=https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev \
  WEBHOOK_TOKEN=your-token-here \
  scripts/send-test-events.sh

CSV columns:
  serial,macos_version,model_name,model_identifier,computer_name

Application CSV columns:
  name

Notes:
  - The script sends one Started and one Finished event per enrollment.
  - Failed enrollments fail FAILED_APPLICATION only.
  - Failed enrollments always use slow network throughput.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

WORKER_URL="${WORKER_URL:-}"
WEBHOOK_TOKEN="${WEBHOOK_TOKEN:-}"
CSV_FILE="${CSV_FILE:-examples/test-devices.csv}"
APPLICATIONS_FILE="${APPLICATIONS_FILE:-examples/test-applications.csv}"
FAILED_APPLICATION="${FAILED_APPLICATION:-Microsoft Outlook}"
DAYS="${DAYS:-7}"
ENROLLMENTS_PER_DEVICE="${ENROLLMENTS_PER_DEVICE:-7}"
FAILURE_RATE="${FAILURE_RATE:-5}"
DRY_RUN="${DRY_RUN:-0}"
SETUP_MANAGER_VERSION="${SETUP_MANAGER_VERSION:-2.0.0}"
JAMF_PRO_VERSION="${JAMF_PRO_VERSION:-11.14.0}"

if [[ -z "$WORKER_URL" || -z "$WEBHOOK_TOKEN" ]]; then
  usage
  exit 1
fi

if [[ ! -f "$CSV_FILE" ]]; then
  echo "CSV file not found: $CSV_FILE" >&2
  exit 1
fi

if [[ ! -f "$APPLICATIONS_FILE" ]]; then
  echo "Applications CSV file not found: $APPLICATIONS_FILE" >&2
  exit 1
fi

WORKER_URL="${WORKER_URL%/}"
WEBHOOK_URL="$WORKER_URL/webhook"

APPLICATIONS=()
while IFS=, read -r app_name _rest; do
  if [[ "$app_name" == "name" || -z "$app_name" ]]; then
    continue
  fi
  APPLICATIONS+=("$app_name")
done < "$APPLICATIONS_FILE"

if (( ${#APPLICATIONS[@]} == 0 )); then
  echo "Applications CSV has no applications: $APPLICATIONS_FILE" >&2
  exit 1
fi

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

macos_build_for_version() {
  case "$1" in
    26.2) printf '25C57' ;;
    26.3) printf '25D72' ;;
    26.4) printf '25E83' ;;
    26.5) printf '25F91' ;;
    *) printf '25F91' ;;
  esac
}

iso_from_offset() {
  local offset_minutes="$1"
  date -u -v-"${DAYS}"d -v+"${offset_minutes}"M '+%Y-%m-%dT%H:%M:%SZ'
}

iso_add_seconds() {
  local iso="$1"
  local seconds="$2"
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$iso" -v+"${seconds}"S '+%Y-%m-%dT%H:%M:%SZ'
}

post_json() {
  local payload="$1"
  local label="$2"
  local http_code

  if [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi

  http_code="$(
    curl -sS -o /tmp/setupmanagerhud-test-response.json -w '%{http_code}' \
      -X POST "$WEBHOOK_URL" \
      -H "Authorization: Bearer $WEBHOOK_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$payload"
  )"

  if [[ "$http_code" != "200" ]]; then
    echo "Failed to send $label. HTTP $http_code" >&2
    cat /tmp/setupmanagerhud-test-response.json >&2
    echo >&2
    exit 1
  fi
}

device_count="$(tail -n +2 "$CSV_FILE" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
total_enrollments=$((device_count * ENROLLMENTS_PER_DEVICE))
total_events=$((total_enrollments * 2))
failure_every=0

if (( FAILURE_RATE > 0 )); then
  failure_every=$((100 / FAILURE_RATE))
  if (( failure_every < 1 )); then
    failure_every=1
  fi
fi

echo "Worker: $WORKER_URL"
echo "CSV: $CSV_FILE"
echo "Applications CSV: $APPLICATIONS_FILE"
echo "Devices: $device_count"
echo "Applications: ${#APPLICATIONS[@]}"
echo "Enrollments per device: $ENROLLMENTS_PER_DEVICE"
echo "Date range: last $DAYS days"
echo "Target failure rate: $FAILURE_RATE%"
echo "Failed application: $FAILED_APPLICATION"
echo "Total events to send: $total_events"
if [[ "$DRY_RUN" == "1" ]]; then
  echo "Dry run: yes"
fi
echo

if [[ "$DRY_RUN" != "1" ]]; then
  curl -fsS "$WORKER_URL/api/health" >/tmp/setupmanagerhud-health.json
  echo "Health check:"
  cat /tmp/setupmanagerhud-health.json
  echo
  echo
fi

enrollment_index=0
started_sent=0
finished_sent=0
failed_enrollments=0

while IFS=, read -r serial macos_version model_name model_identifier computer_name; do
  if [[ "$serial" == "serial" || -z "$serial" ]]; then
    continue
  fi

  macos_build="$(macos_build_for_version "$macos_version")"
  model_identifier="${model_identifier//-/,}"

  for ((run = 1; run <= ENROLLMENTS_PER_DEVICE; run++)); do
    enrollment_index=$((enrollment_index + 1))
    offset_minutes=$((20 + ((enrollment_index - 1) * DAYS * 24 * 60 / total_enrollments)))
    started="$(iso_from_offset "$offset_minutes")"

    failed=false
    if (( failure_every > 0 && enrollment_index % failure_every == 0 )); then
      failed=true
      failed_enrollments=$((failed_enrollments + 1))
      duration=$((900 + (enrollment_index % 5) * 90))
      upload_throughput=$((350000 + (enrollment_index % 7) * 50000))
      download_throughput=$((900000 + (enrollment_index % 9) * 65000))
    else
      duration=$((240 + (enrollment_index % 8) * 45))
      upload_throughput=$((20000000 + (enrollment_index % 13) * 2500000))
      download_throughput=$((80000000 + (enrollment_index % 17) * 7000000))
    fi

    finished="$(iso_add_seconds "$started" "$duration")"

    started_payload="$(
      printf '{"name":"Started","event":"com.jamf.setupmanager.started","timestamp":"%s","started":"%s","modelName":"%s","modelIdentifier":"%s","macOSBuild":"%s","macOSVersion":"%s","serialNumber":"%s","setupManagerVersion":"%s","jamfProVersion":"%s"}' \
        "$started" \
        "$started" \
        "$(json_escape "$model_name")" \
        "$(json_escape "$model_identifier")" \
        "$macos_build" \
        "$(json_escape "$macos_version")" \
        "$(json_escape "$serial")" \
        "$(json_escape "$SETUP_MANAGER_VERSION")" \
        "$(json_escape "$JAMF_PRO_VERSION")"
    )"

    actions_json="["
    for app_index in "${!APPLICATIONS[@]}"; do
      app="${APPLICATIONS[$app_index]}"
      status="finished"
      if [[ "$failed" == "true" && "$app" == "$FAILED_APPLICATION" ]]; then
        status="failed"
      fi
      if (( app_index > 0 )); then
        actions_json+=","
      fi
      actions_json+="$(printf '{"label":"%s","status":"%s"}' "$(json_escape "$app")" "$status")"
    done
    actions_json+="]"

    finished_payload="$(
      printf '{"name":"Finished","event":"com.jamf.setupmanager.finished","timestamp":"%s","started":"%s","finished":"%s","duration":%s,"modelName":"%s","modelIdentifier":"%s","macOSBuild":"%s","macOSVersion":"%s","serialNumber":"%s","setupManagerVersion":"%s","jamfProVersion":"%s","computerName":"%s","enrollmentActions":%s,"uploadThroughput":%s,"downloadThroughput":%s}' \
        "$finished" \
        "$started" \
        "$finished" \
        "$duration" \
        "$(json_escape "$model_name")" \
        "$(json_escape "$model_identifier")" \
        "$macos_build" \
        "$(json_escape "$macos_version")" \
        "$(json_escape "$serial")" \
        "$(json_escape "$SETUP_MANAGER_VERSION")" \
        "$(json_escape "$JAMF_PRO_VERSION")" \
        "$(json_escape "$computer_name")" \
        "$actions_json" \
        "$upload_throughput" \
        "$download_throughput"
    )"

    post_json "$started_payload" "started event for $serial"
    started_sent=$((started_sent + 1))
    post_json "$finished_payload" "finished event for $serial"
    finished_sent=$((finished_sent + 1))
  done
done < "$CSV_FILE"

echo
echo "Sent $started_sent started events and $finished_sent finished events."
echo "Failed enrollments: $failed_enrollments of $total_enrollments"
echo "Failed application: $FAILED_APPLICATION"
echo
if [[ "$DRY_RUN" != "1" ]]; then
  echo "Current stats:"
  curl -fsS "$WORKER_URL/api/stats"
  echo
fi
