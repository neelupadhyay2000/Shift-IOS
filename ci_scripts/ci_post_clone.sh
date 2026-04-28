#!/bin/sh
# ci_post_clone.sh — Runs after Xcode Cloud clones the repository.
#
# Responsibilities:
#   1. Install SwiftFormat for lint-on-CI (SwiftLint runs as a build phase in Xcode).
#   2. Log environment context for debugging.
#   3. Gate: fail fast if the Xcode version is below the project minimum.
#
# Xcode Cloud environment variables available here:
#   CI_WORKFLOW, CI_BRANCH, CI_PULL_REQUEST_NUMBER, CI_PRODUCT_PLATFORM, etc.
#
# Exit code: non-zero causes the Xcode Cloud build to fail immediately.
set -e

echo "=== ci_post_clone.sh: SHIFT CI bootstrap ==="
echo "  Workflow   : ${CI_WORKFLOW:-local}"
echo "  Branch     : ${CI_BRANCH:-unknown}"
echo "  PR number  : ${CI_PULL_REQUEST_NUMBER:-(none)}"
echo "  Platform   : ${CI_PRODUCT_PLATFORM:-unknown}"
echo "  Xcode path : $(xcode-select -p)"

# ── SwiftFormat ─────────────────────────────────────────────────────────────────────────────
# Required version must match the local .swiftformat config.
REQUIRED_SWIFTFORMAT="0.54.6"

if ! command -v swiftformat > /dev/null 2>&1; then
    echo "  Installing SwiftFormat ${REQUIRED_SWIFTFORMAT} via Homebrew..."
    brew install swiftformat
else
    INSTALLED=$(swiftformat --version 2>&1 | head -1 | awk '{print $NF}')
    echo "  SwiftFormat already installed: ${INSTALLED}"
fi

echo "  SwiftFormat: $(swiftformat --version 2>&1 | head -1)"

# ── Xcode version gate ───────────────────────────────────────────────────────────────────────
# SHIFT requires Xcode 16+ for Swift 6 strict concurrency and Swift Testing.
XCODE_VERSION=$(xcodebuild -version 2>/dev/null | awk 'NR==1{print $2}')
MAJOR=$(echo "${XCODE_VERSION}" | cut -d. -f1)

if [ "${MAJOR}" -lt 16 ]; then
    echo "ERROR: SHIFT requires Xcode 16+. Found Xcode ${XCODE_VERSION}." >&2
    exit 1
fi

echo "  Xcode ${XCODE_VERSION} — OK"
echo "=== ci_post_clone.sh: done ==="
exit 0
