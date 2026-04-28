#!/bin/sh
# ci_pre_xcodebuild.sh — Runs immediately before xcodebuild on Xcode Cloud.
#
# Responsibilities:
#   1. Log the active test plan so shard assignment is visible in build logs.
#   2. Validate that $CI_TEST_PLAN is set when running a test action.
#   3. Confirm the test plan file exists in TestPlans/ (catches merge mistakes early).
#
# Exit code: non-zero causes the Xcode Cloud build to fail before xcodebuild starts.
set -e

echo "=== ci_pre_xcodebuild.sh ==="
echo "  Action     : ${CI_XCODEBUILD_ACTION:-build}"
echo "  Workflow   : ${CI_WORKFLOW:-local}"
echo "  Test plan  : ${CI_TEST_PLAN:-(none)}"

# ── Validate test plan presence when running tests ───────────────────────────────────────────
if [ "${CI_XCODEBUILD_ACTION}" = "test-without-building" ] || \
   [ "${CI_XCODEBUILD_ACTION}" = "test" ]; then

    if [ -z "${CI_TEST_PLAN}" ]; then
        echo "WARNING: CI_TEST_PLAN is empty. Xcode Cloud will use the scheme's default plan."
    else
        # Resolve from repo root — test plans live in shiftTimeline/TestPlans/
        PLAN_FILE="${CI_PRIMARY_REPOSITORY_PATH}/shiftTimeline/TestPlans/${CI_TEST_PLAN}.xctestplan"

        if [ ! -f "${PLAN_FILE}" ]; then
            echo "ERROR: Test plan file not found: ${PLAN_FILE}" >&2
            echo "       Ensure '${CI_TEST_PLAN}.xctestplan' exists in shiftTimeline/TestPlans/" >&2
            exit 1
        fi

        echo "  Plan file  : ${PLAN_FILE} — found OK"
    fi
fi

echo "=== ci_pre_xcodebuild.sh: done ==="
exit 0
