#!/bin/bash
# ──────────────────────────────────────────────────────────────
# Slacktive Verification Script
#
# Monitors the mechanisms Slacktive uses to keep you "active"
# and reports whether each one is working.
#
# Usage:
#   ./scripts/verify.sh          # Monitor for 5 minutes
#   ./scripts/verify.sh 600      # Monitor for 10 minutes
# ──────────────────────────────────────────────────────────────
set -euo pipefail

DURATION=${1:-300}  # Default 5 minutes
INTERVAL=5          # Check every 5 seconds
CHECKS=$((DURATION / INTERVAL))

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Helpers ──────────────────────────────────────────────────

get_idle_time_seconds() {
    local idle_ns
    idle_ns=$(ioreg -c IOHIDSystem -d 4 | grep HIDIdleTime | head -1 | awk '{print $NF}')
    if [ -z "$idle_ns" ]; then
        echo "-1"
        return
    fi
    echo "$idle_ns / 1000000000" | bc
}

get_mouse_position() {
    osascript -e '
        use framework "AppKit"
        set mouseLoc to current application'\''s class "NSEvent"'\''s mouseLocation()
        set x to (mouseLoc'\''s x) as integer
        set y to (mouseLoc'\''s y) as integer
        return (x as text) & "," & (y as text)
    ' 2>/dev/null || echo "?,?"
}

check_power_assertion() {
    local slacktive_pid
    slacktive_pid=$(pgrep -x Slacktive 2>/dev/null)
    if [ -z "$slacktive_pid" ]; then
        return 1
    fi
    pmset -g assertions 2>/dev/null | grep -q "pid ${slacktive_pid}(Slacktive)"
    return $?
}

check_slacktive_running() {
    pgrep -x "Slacktive" > /dev/null 2>&1
    return $?
}

# ── Pre-flight checks ───────────────────────────────────────

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║         Slacktive Verification Suite             ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
echo ""

# Check if Slacktive is running
if ! check_slacktive_running; then
    echo -e "${RED}✗ Slacktive is not running!${RESET}"
    echo ""
    echo "  Start Slacktive first, toggle it ON, then run this script."
    echo ""
    exit 1
fi
echo -e "${GREEN}✓ Slacktive process detected (PID: $(pgrep -x Slacktive))${RESET}"

# Check power assertion
if check_power_assertion; then
    echo -e "${GREEN}✓ Power assertion is active${RESET}"
else
    echo -e "${YELLOW}⚠ No power assertion detected — is Slacktive toggled ON?${RESET}"
fi

echo ""
echo -e "${DIM}Monitoring for ${DURATION}s (every ${INTERVAL}s). Keep your hands off the mouse/keyboard.${RESET}"
echo -e "${DIM}Mouse jiggle fires every 4-5 min. HIDIdleTime should reset when it does.${RESET}"
echo -e "${DIM}Slack's away threshold is 600s — idle should never reach that.${RESET}"
echo ""
echo -e "${BOLD}  Time  │ Idle(s) │ Mouse Position  │ Status${RESET}"
echo -e "  ──────┼─────────┼─────────────────┼──────────────────"

# ── Monitoring loop ──────────────────────────────────────────

prev_mouse=""
idle_resets=0
max_idle=0
mouse_moves=0
assertion_present=0
assertion_checks=0

for ((i=1; i<=CHECKS; i++)); do
    elapsed=$((i * INTERVAL))
    
    # Get current metrics
    idle=$(get_idle_time_seconds)
    mouse=$(get_mouse_position)
    
    # Track max idle
    if [ "$idle" -gt "$max_idle" ] 2>/dev/null; then
        max_idle=$idle
    fi
    
    # Check if idle timer was reset (dropped significantly)
    if [ -n "$prev_idle" ] && [ "$idle" -lt "$((prev_idle - 10))" ] 2>/dev/null; then
        ((idle_resets++)) || true
    fi
    prev_idle=$idle
    
    # Check mouse movement
    if [ -n "$prev_mouse" ] && [ "$mouse" != "$prev_mouse" ]; then
        ((mouse_moves++)) || true
    fi
    
    # Check power assertion
    ((assertion_checks++)) || true
    if check_power_assertion; then
        ((assertion_present++)) || true
    fi
    
    # Format status — Slack threshold is 600s, so anything under that is fine
    if [ "$idle" -lt 300 ] 2>/dev/null; then
        status="${GREEN}● OK${RESET}"
    elif [ "$idle" -lt 600 ] 2>/dev/null; then
        status="${YELLOW}◐ approaching Slack threshold${RESET}"
    else
        status="${RED}○ OVER Slack threshold!${RESET}"
    fi
    
    if [ "$mouse" != "$prev_mouse" ] && [ -n "$prev_mouse" ]; then
        status="$status ${CYAN}↗ mouse moved (idle reset!)${RESET}"
    fi
    
    printf "  %4ds │ %5ss  │ %-15s │ " "$elapsed" "$idle" "$mouse"
    echo -e "$status"
    
    prev_mouse="$mouse"
    sleep "$INTERVAL"
done

# ── Summary ──────────────────────────────────────────────────

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Results Summary${RESET}"
echo -e "${BOLD}══════════════════════════════════════════════════${RESET}"
echo ""

# Verdict: Idle timer — Slack's threshold is 600s
if [ "$max_idle" -lt 600 ]; then
    echo -e "  ${GREEN}✓ Idle Timer${RESET}          Max: ${max_idle}s (Slack threshold: 600s)"
    if [ "$idle_resets" -gt 0 ]; then
        echo -e "    ${DIM}Reset ${idle_resets} time(s) via mouse circle jiggle${RESET}"
    fi
else
    echo -e "  ${RED}✗ Idle Timer${RESET}          Max: ${max_idle}s (EXCEEDED Slack threshold of 600s!)"
fi

# Verdict: Power assertion
if [ "$assertion_present" -gt 0 ]; then
    echo -e "  ${GREEN}✓ Power Assertion${RESET}     Active (${assertion_present}/${assertion_checks} checks)"
else
    echo -e "  ${RED}✗ Power Assertion${RESET}     Not detected — is Slacktive toggled ON?"
fi

# Verdict: Mouse movement
if [ "$mouse_moves" -gt 0 ]; then
    echo -e "  ${GREEN}✓ Mouse Jiggle${RESET}        Detected ${mouse_moves} movement(s)"
    echo -e "    ${DIM}Circle pattern is working — cursor returns to original position${RESET}"
else
    if [ "$DURATION" -lt 240 ]; then
        echo -e "  ${YELLOW}◐ Mouse Jiggle${RESET}        Not seen (test too short — jiggle fires every 4-5 min)"
    else
        echo -e "  ${RED}✗ Mouse Jiggle${RESET}        Not detected"
        echo -e "    ${DIM}Check Accessibility: System Settings > Privacy > Accessibility${RESET}"
    fi
fi

echo ""

# Overall verdict
if [ "$max_idle" -lt 600 ]; then
    echo -e "  ${GREEN}${BOLD}VERDICT: Slacktive is keeping you active ✓${RESET}"
    echo -e "  ${DIM}Slack will not mark you as away (idle never reached 600s threshold).${RESET}"
else
    echo -e "  ${RED}${BOLD}VERDICT: Issues detected — idle time exceeded Slack's away threshold${RESET}"
fi
echo ""
