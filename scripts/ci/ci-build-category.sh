#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# CI Category Builder
# ============================================================================
# Build specific categories of flake outputs for GitHub Actions matrix jobs.
# Designed to minimize disk space usage per job by building subsets of outputs.
#
# Usage:
#   ci-build-category.sh <system> <category>
#
# Arguments:
#   system    - Target system (x86_64-linux, aarch64-linux, aarch64-darwin)
#   category  - Output category to build (lowercase):
#               - packages: all packages for system
#               - checks: checks only
#               - devshells: devshells only (maps to devShells flake attr)
#
# Examples:
#   ci-build-category.sh x86_64-linux packages
#   ci-build-category.sh x86_64-linux checks
#   ci-build-category.sh x86_64-linux devshells
# ============================================================================

# ============================================================================
# Argument parsing
# ============================================================================

if [ $# -lt 2 ]; then
    echo "usage: $0 <system> <category>"
    echo ""
    echo "system: x86_64-linux, aarch64-linux, aarch64-darwin"
    echo "category: packages, checks, devshells"
    exit 1
fi

SYSTEM="$1"
CATEGORY="$2"

# ============================================================================
# Validation
# ============================================================================

case "$SYSTEM" in
    x86_64-linux|aarch64-linux|aarch64-darwin)
        ;;
    *)
        echo "error: unsupported system '$SYSTEM'"
        echo "supported: x86_64-linux, aarch64-linux, aarch64-darwin"
        exit 1
        ;;
esac

case "$CATEGORY" in
    packages|checks|devshells)
        ;;
    *)
        echo "error: unknown category '$CATEGORY'"
        echo "valid: packages, checks, devshells"
        exit 1
        ;;
esac

# Map lowercase category arg to the flake attribute name
map_flake_attr() {
    case "$1" in
        packages)  echo "packages" ;;
        checks)    echo "checks" ;;
        devshells) echo "devShells" ;;
    esac
}

FLAKE_ATTR=$(map_flake_attr "$CATEGORY")

# ============================================================================
# Helper functions
# ============================================================================

print_header() {
    local title="$1"
    echo ""
    echo "---"
    echo "$title"
    echo "---"
}

print_step() {
    local step="$1"
    echo ""
    echo "step: $step"
}

report_disk_usage() {
    echo ""
    echo "disk usage:"
    df -h / | tail -1
}

# ============================================================================
# Generic build function
# ============================================================================

build_category() {
    local system="$1"
    local flake_attr="$2"
    local label="$3"

    print_header "building $label for $system"

    print_step "discovering $label"
    local attrs
    attrs=$(nix eval ".#${flake_attr}.${system}" --apply 'builtins.attrNames' --json 2>/dev/null | jq -r '.[]' || echo "")

    # Exclude multi-arch manifest packages from single-system CI builds.
    # Manifests reference packages from other systems and are built by
    # the dedicated build-nix-images workflow instead.
    if [ "$flake_attr" = "packages" ]; then
        attrs=$(echo "$attrs" | grep -v 'Manifest$' || echo "")
    fi

    if [ -z "$attrs" ]; then
        echo "no $label found for $system"
        return 0
    fi

    local count
    count=$(echo "$attrs" | wc -l | tr -d ' ')
    echo "found $count $label"

    print_step "building $label"
    local failed=0
    while read -r attr; do
        if [ -n "$attr" ]; then
            echo ""
            echo "building ${flake_attr}.${system}.${attr}"
            if ! nix build ".#${flake_attr}.${system}.${attr}" -L --no-link --accept-flake-config; then
                echo "failed to build ${flake_attr}.${system}.${attr}"
                failed=$((failed + 1))
            fi
        fi
    done <<< "$attrs"

    if [ $failed -gt 0 ]; then
        echo ""
        echo "failed to build $failed $label"
        return 1
    fi

    echo ""
    echo "successfully built $count $label"
}

# ============================================================================
# Main execution
# ============================================================================

echo "system: $SYSTEM"
echo "category: $CATEGORY (flake attr: $FLAKE_ATTR)"

START_TIME=$(date +%s)
echo "start time: $(date)"
report_disk_usage

build_category "$SYSTEM" "$FLAKE_ATTR" "$CATEGORY"
BUILD_STATUS=$?

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

print_header "build summary"
echo ""
echo "category: $CATEGORY"
echo "duration: ${DURATION}s"
report_disk_usage
echo ""

if [ $BUILD_STATUS -eq 0 ]; then
    echo "status: success"
    exit 0
else
    echo "status: failed"
    exit 1
fi
