#!/bin/bash
# Fork-only helper for syncing this fork with upstream (ganeshmshetty/openclip).
# Usage:
#   ./scripts/fork_sync.sh report [<upstream-ref>]   before merging: what upstream brings, what it touches
#   ./scripts/fork_sync.sh verify [--runs N]          after merging: fork invariants + tests vs baseline
#
# It does not merge or resolve conflicts: that needs judgment. `report` only reads (git fetch plus a
# trial merge via `git merge-tree`, which leaves the working tree alone). `verify` regenerates the
# Xcode project and the string catalog; it exits non-zero on a broken invariant or on a test that
# fails in every run and is not in the known-failures baseline (docs/architecture/known-debt.md).
#
# Environment:
#   OPENSELECTION_DIR  local OpenSelection clone for its changelog (default: ../OpenSelection)

set -eo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

OPENSELECTION_DIR="${OPENSELECTION_DIR:-$PROJECT_DIR/../OpenSelection}"
KNOWN_DEBT="docs/architecture/known-debt.md"

# Code upstream may change without a textual conflict that still matters to the fork.
# One entry per line: <path prefix>|<why it matters>. Keep in step with AGENTS.md "This is a fork".
HOT_SPOTS='project.yml|version suffix, Sparkle feed/key (must stay absent), package versions
Sources/OpenClip/UI/Popup/|palette placement/size, source footer, row accessories, dismissal rules
Sources/OpenClip/Platform/HotkeyManager.swift|palette hotkey reads the selection on demand
Sources/OpenClip/Platform/MacSelectionMonitor.swift|passive monitor is never started in the fork
Sources/OpenClip/Platform/Selection/|selection retrieval used by the hotkey
Sources/OpenClip/StatusBarController.swift|hidden pause / Report Issue menu items
Sources/OpenClip/AppDelegate.swift|startup wiring: monitor off, Sparkle off
Sources/OpenClip/Platform/AppUpdateManager.swift|auto-updates must stay off
Sources/OpenClip/UI/Preferences/GeneralTabView.swift|hidden monitor/update settings
Sources/OpenClip/UI/Preferences/AppRulesTab.swift|hidden monitor settings
Sources/OpenClip/OpenClip.entitlements|verify_signing.sh compares it to the signed artifact
scripts/sign_artifact.sh|fork: no hardened runtime without a Team ID
scripts/package_app.sh|fork signing path, local certificate
scripts/dev_run.sh|fork signing path, local certificate
scripts/signing_config.sh|fork signing path, local certificate
.github/workflows/|runs in the fork too; pushing it needs a token with the workflow scope'

section() { printf '\n== %s ==\n' "$1"; }

yml_value() { # <git rev> <key>: value of `key:` in project.yml at that revision
    git show "$1:project.yml" 2>/dev/null | grep -E "^[[:space:]]*$2:" | head -1 \
        | sed -E "s/^[[:space:]]*$2:[[:space:]]*//; s/\"//g"
}

version_at() { # <git rev>: MARKETING_VERSION with the fork's mod revision expanded
    local rev="$1" version
    version="$(yml_value "$rev" MARKETING_VERSION)"
    echo "${version//\$(OPENCLIP_MOD_REVISION)/$(yml_value "$rev" OPENCLIP_MOD_REVISION)} (build $(yml_value "$rev" CURRENT_PROJECT_VERSION))"
}

report() {
    local ref="${1:-upstream/main}"
    git fetch upstream --tags --quiet
    local base
    base="$(git merge-base HEAD "$ref")"

    section "Sync point"
    echo "ours:     $(git log -1 --format='%h %s' HEAD)"
    echo "upstream: $(git log -1 --format='%h %s' "$ref")"
    echo "base:     $(git log -1 --format='%h %s' "$base")"
    echo "version:  ours $(version_at HEAD) -> upstream $(version_at "$ref")"
    local tags
    tags="$(git tag --merged "$ref" --no-merged "$base" --sort=creatordate | tr '\n' ' ')"
    echo "new tags: ${tags:-none}"

    if [ "$(git rev-list --count "$base..$ref")" = 0 ]; then
        echo; echo "Nothing to sync: $ref is already merged."
        return 0
    fi

    section "Upstream commits (no merges)"
    git log --no-merges --format='%h %ad %s' --date=short "$base..$ref"

    section "Upstream files"
    git diff --stat=100 "$base" "$ref" | tail -n 200

    section "Changed on both sides (since base)"
    local both
    both="$(comm -12 <(git diff --name-only "$base" "$ref" | sort) <(git diff --name-only "$base" HEAD | sort))"
    echo "${both:-none}"

    section "Trial merge (working tree untouched)"
    local merge_out
    if merge_out="$(git merge-tree --write-tree --name-only --no-messages HEAD "$ref" 2>&1)"; then
        echo "merges cleanly"
    else
        echo "conflicts in:"
        echo "$merge_out" | tail -n +2 | sed 's/^/  /'
    fi

    section "Hot spots touched upstream"
    local upstream_files hit=0
    upstream_files="$(git diff --name-only "$base" "$ref")"
    while IFS='|' read -r prefix why; do
        [ -n "$prefix" ] || continue
        local files
        files="$(echo "$upstream_files" | awk -v p="$prefix" 'index($0, p) == 1')"
        [ -n "$files" ] || continue
        hit=1
        echo "* $prefix — $why"
        echo "$files" | sed 's/^/    /'
    done <<< "$HOT_SPOTS"
    [ "$hit" = 1 ] || echo "none"

    local sparkle
    sparkle="$(git diff "$base" "$ref" -- project.yml | grep -E '^\+[^+].*(SUFeedURL|SUPublicEDKey)' || true)"
    if [ -n "$sparkle" ]; then
        echo; echo "!! upstream edits Sparkle keys in project.yml — do NOT take them:"
        echo "$sparkle"
    fi

    section "OpenSelection"
    local os_old os_new
    os_old="$(git show "HEAD:project.yml" | grep -A3 '^  OpenSelection:' | grep -E 'exactVersion|from:' | awk '{print $2}')"
    os_new="$(git show "$ref:project.yml" | grep -A3 '^  OpenSelection:' | grep -E 'exactVersion|from:' | awk '{print $2}')"
    if [ "$os_old" = "$os_new" ]; then
        echo "unchanged ($os_old)"
    else
        echo "$os_old -> $os_new"
        if [ -d "$OPENSELECTION_DIR/.git" ]; then
            git -C "$OPENSELECTION_DIR" fetch --tags --quiet || true
            local from="v$os_old" to="v$os_new"
            git -C "$OPENSELECTION_DIR" rev-parse -q --verify "$from" >/dev/null || from="$os_old"
            git -C "$OPENSELECTION_DIR" rev-parse -q --verify "$to" >/dev/null || to="$os_new"
            local range="$from..$to"
            if git -C "$OPENSELECTION_DIR" merge-base --is-ancestor "$to" "$from" 2>/dev/null; then
                range="$to..$from"
                echo "!! DOWNGRADE — the fork loses these OpenSelection commits (find upstream's reason):"
            fi
            git -C "$OPENSELECTION_DIR" log --no-merges --format='  %h %s' "$range"
            git -C "$OPENSELECTION_DIR" diff --stat "$from" "$to" -- Sources | tail -n 30
            echo "(full messages: git -C $OPENSELECTION_DIR log $range)"
        else
            echo "no clone at $OPENSELECTION_DIR — clone it to see what changed"
        fi
    fi
}

# Test names listed under "Known failures" in known-debt.md, as Class.test.
baseline_failures() {
    sed -n '/Known failures/,/^- \*\*Removed/p' "$KNOWN_DEBT" \
        | grep -oE '`[A-Za-z0-9_]+Tests\.[A-Za-z0-9_]+`' | tr -d '`' | sort -u
}

verify() {
    local runs=3
    if [ "${1:-}" = "--runs" ]; then runs="${2:?--runs needs a number}"; fi
    local problems=0

    section "Invariants"
    local markers
    markers="$(git grep -n -E '^(<<<<<<<|>>>>>>>) ' || true)"
    if [ -n "$markers" ]; then
        echo "FAIL conflict markers left:"; echo "$markers" | head -20; problems=1
    else
        echo "ok   no conflict markers"
    fi
    if grep -E '^[[:space:]]*[^#[:space:]].*(SUFeedURL|SUPublicEDKey)' project.yml >/dev/null; then
        echo "FAIL project.yml sets a Sparkle feed/key — upstream's would replace this build"; problems=1
    else
        echo "ok   no Sparkle feed/key in project.yml"
    fi
    local version revision
    version="$(grep -E '^[[:space:]]*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*: *//; s/"//g')"
    revision="$(grep -E '^[[:space:]]*OPENCLIP_MOD_REVISION:' project.yml | head -1 | sed -E 's/.*: *//; s/"//g')"
    if echo "$version" | grep -qF '+mod.$(OPENCLIP_MOD_REVISION)'; then
        echo "ok   version ${version%%+*}+mod.$revision"
    else
        echo "FAIL MARKETING_VERSION lost the +mod suffix: $version"; problems=1
    fi

    local tmp
    tmp="$(mktemp -d)"
    cp OpenClip.xcodeproj/project.pbxproj "$tmp/project.pbxproj"
    xcodegen generate --quiet >/dev/null
    if cmp -s "$tmp/project.pbxproj" OpenClip.xcodeproj/project.pbxproj; then
        echo "ok   project.pbxproj matches project.yml"
    else
        echo "note project.pbxproj was stale and has been regenerated — commit it"
    fi
    cp Sources/OpenClip/Resources/Localizable.xcstrings "$tmp/Localizable.xcstrings"
    python3 scripts/generate_localizable.py >/dev/null
    if cmp -s "$tmp/Localizable.xcstrings" Sources/OpenClip/Resources/Localizable.xcstrings; then
        echo "ok   string catalog matches scripts/translations"
    else
        echo "note string catalog was regenerated from scripts/translations — review and commit it"
    fi

    section "Tests ($runs full runs)"
    local baseline all_failed="" i
    baseline="$(baseline_failures)"
    for i in $(seq 1 "$runs"); do
        local log="$tmp/test-$i.log"
        ./scripts/test.sh > "$log" 2>&1 || true
        local executed failed
        executed="$(grep -E 'Executed [0-9]+ tests' "$log" | tail -1 | sed -E 's/^[[:space:]]*//')"
        failed="$(grep -oE 'error: -\[OpenClipTests\.[A-Za-z0-9_]+ [A-Za-z0-9_]+\]' "$log" \
            | sed -E 's/error: -\[OpenClipTests\.([A-Za-z0-9_]+) ([A-Za-z0-9_]+)\]/\1.\2/' | sort -u)"
        echo "run $i: ${executed:-no summary (build failed? see $log)}"
        if [ -z "$executed" ]; then problems=1; continue; fi
        local name
        for name in $failed; do
            if echo "$baseline" | grep -qx "$name"; then echo "  known  $name"; else echo "  NEW    $name"; fi
        done
        all_failed="$all_failed$failed"$'\n'
    done

    local new_names name count
    new_names="$(echo "$all_failed" | grep -v '^$' | sort -u | grep -vxF "$baseline" || true)"
    if [ -n "$new_names" ]; then
        echo
        for name in $new_names; do
            count="$(echo "$all_failed" | grep -cx "$name")"
            if [ "$count" = "$runs" ]; then
                echo "FAIL $name failed in every run — a real regression"; problems=1
            else
                echo "flaky $name failed in $count/$runs runs — run it alone, then add it to the baseline"
            fi
        done
    fi
    echo "logs: $tmp"

    section "Result"
    if [ "$problems" = 0 ]; then echo "verify passed"; else echo "verify FAILED"; fi
    return "$problems"
}

case "${1:-}" in
    report) shift; report "$@" ;;
    verify) shift; verify "$@" ;;
    *) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
