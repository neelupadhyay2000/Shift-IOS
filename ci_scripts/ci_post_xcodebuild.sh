#!/bin/sh
# ci_post_xcodebuild.sh — Runs after xcodebuild on Xcode Cloud, even on failure.
#
# Responsibilities:
#   1. On nightly-full workflow failure: POST to the Slack webhook.
#   2. Log the .xcresult bundle path for artifact tracing.
#   3. Never fail this script (exit 0 always) — it must not mask the real failure.
#
# Required secret (set in App Store Connect Workflow → Environment, mark as Secret):
#   SLACK_WEBHOOK_URL — Slack incoming webhook URL
#
# Xcode Cloud environment variables used:
#   CI_XCODEBUILD_EXIT_CODE — 0 on success, non-zero on failure
#   CI_WORKFLOW              — workflow name (e.g. "nightly-full")
#   CI_BUILD_URL             — direct link to the failing build in App Store Connect
#   CI_BRANCH                — branch that triggered the build
#   CI_RESULT_BUNDLE_PATH    — path to the .xcresult bundle on disk
set -u  # treat unset variables as errors (except where guarded below)

echo "=== ci_post_xcodebuild.sh ==="
echo "  Workflow   : ${CI_WORKFLOW:-local}"
echo "  Exit code  : ${CI_XCODEBUILD_EXIT_CODE:-0}"
echo "  Result     : ${CI_RESULT_BUNDLE_PATH:-(no bundle)}"

# ── Log artifact location ────────────────────────────────────────────────────────────────────
if [ -n "${CI_RESULT_BUNDLE_PATH:-}" ] && [ -e "${CI_RESULT_BUNDLE_PATH}" ]; then
    BUNDLE_SIZE=$(du -sh "${CI_RESULT_BUNDLE_PATH}" 2>/dev/null | awk '{print $1}')
    echo "  .xcresult  : ${CI_RESULT_BUNDLE_PATH} (${BUNDLE_SIZE})"
fi

# ── Slack notification on nightly failure ────────────────────────────────────────────────────
# Only fire on the nightly-full workflow when tests go red.
WORKFLOW="${CI_WORKFLOW:-local}"
EXIT_CODE="${CI_XCODEBUILD_EXIT_CODE:-0}"

if echo "${WORKFLOW}" | grep -q "^nightly" && [ "${EXIT_CODE}" != "0" ]; then
    WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"

    if [ -z "${WEBHOOK_URL}" ]; then
        echo "WARNING: SLACK_WEBHOOK_URL is not set. Skipping Slack notification."
    else
        BUILD_URL="${CI_BUILD_URL:-https://appstoreconnect.apple.com}"
        BRANCH="${CI_BRANCH:-unknown}"
        PLAN="${CI_TEST_PLAN:-(all)}"

        PAYLOAD=$(printf '{"text":":red_circle: *SHIFT nightly-full FAILED*\\nBranch: `%s` | Plan: `%s`\\n<%s|View build in App Store Connect>"}' \
            "${BRANCH}" "${PLAN}" "${BUILD_URL}")

        HTTP_STATUS=$(curl --silent --output /dev/null --write-out "%{http_code}" \
            --max-time 15 \
            -X POST \
            -H "Content-Type: application/json" \
            -d "${PAYLOAD}" \
            "${WEBHOOK_URL}")

        if [ "${HTTP_STATUS}" = "200" ]; then
            echo "  Slack      : notification sent (HTTP 200)"
        else
            echo "WARNING: Slack webhook returned HTTP ${HTTP_STATUS}. Check SLACK_WEBHOOK_URL."
        fi
    fi
else
    echo "  Slack      : skipped (workflow=${WORKFLOW}, exit=${EXIT_CODE})"
fi

echo "=== ci_post_xcodebuild.sh: done ==="
exit 0   # always exit 0 — do not mask the real test failure
