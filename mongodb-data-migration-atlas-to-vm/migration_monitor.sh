#!/bin/bash

#==============================================================================
# MIGRATION MONITOR - Real-time dashboard for mongodb_migration.sh
#==============================================================================

set -euo pipefail

# Match paths from mongodb_migration.sh
BACKUP_DIR="/tmp/mongodb-migration"
LOG_FILE="$BACKUP_DIR/migration.log"
STATUS_DIR="$BACKUP_DIR/status"
VALIDATION_DIR="$BACKUP_DIR/validation"
TIMESTAMP_FILE="$BACKUP_DIR/migration_start_timestamp.txt"
REFRESH_INTERVAL=3

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'

print_header() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}          MongoDB Migration Monitor${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    if [ -f "$TIMESTAMP_FILE" ]; then
        echo -e "Migration started: $(cat $TIMESTAMP_FILE)"
    fi
    echo ""
}

draw_progress_bar() {
    local percent=${1:-0}
    local width=50
    local filled=$((percent * width / 100))
    printf "["
    for ((i=0;i<filled;i++)); do printf "${GREEN}█${NC}"; done
    for ((i=filled;i<width;i++)); do printf "${DIM}░${NC}"; done
    printf "] %3d%%\n" "$percent"
}

get_stats() {
    local total=0 success=0 failed=0 running=0
    [ -f "$BACKUP_DIR/database_list.txt" ] && total=$(wc -l < "$BACKUP_DIR/database_list.txt" | tr -d ' ')
    [ -d "$STATUS_DIR" ] && {
        success=$(find "$STATUS_DIR" -name "*.status" -exec grep -l "SUCCESS" {} \; 2>/dev/null | wc -l | tr -d ' ')
        failed=$(find "$STATUS_DIR" -name "*.status" -exec grep -l "FAILED" {} \; 2>/dev/null | wc -l | tr -d ' ')
        running=$(find "$STATUS_DIR" -name "*.status" -exec grep -l "RUNNING" {} \; 2>/dev/null | wc -l | tr -d ' ')
    }
    echo "$total:$success:$failed:$running"
}

display_progress() {
    local stats=$(get_stats)
    IFS=':' read -r total success failed running <<< "$stats"
    local completed=$((success + failed))
    local percent=0
    [ "$total" -gt 0 ] 2>/dev/null && percent=$((completed * 100 / total))
    local pending=$((total - completed - running))
    [ "$pending" -lt 0 ] && pending=0
    
    echo -e "${BOLD}=== MIGRATION PROGRESS ===${NC}"
    draw_progress_bar $percent
    echo ""
    echo -e "Total: ${BOLD}$total${NC} databases"
    echo -e "${GREEN}✓ Success:${NC} $success  ${RED}✗ Failed:${NC} $failed  ${BLUE}⟳ Running:${NC} $running  ${DIM}○ Pending:${NC} $pending"
    echo ""
}

display_throughput() {
    [ ! -f "$TIMESTAMP_FILE" ] && return
    
    local start_time=$(cat "$TIMESTAMP_FILE")
    local start_ts=$(date -d "$start_time" +%s 2>/dev/null || return)
    local now=$(date +%s)
    local elapsed=$((now - start_ts))
    [ $elapsed -le 0 ] && elapsed=1
    
    local stats=$(get_stats)
    IFS=':' read -r total success failed running <<< "$stats"
    local completed=$((success + failed))
    [ $completed -le 0 ] && return
    
    local speed=$(echo "scale=1; $completed * 60 / $elapsed" | bc 2>/dev/null || echo "?")
    local remaining=$((total - completed))
    local eta_sec=0
    [ $completed -gt 0 ] && eta_sec=$((elapsed * remaining / completed))
    
    echo -e "${BOLD}=== THROUGHPUT ===${NC}"
    echo "Speed: $speed DBs/min"
    printf "Elapsed: %dh %dm %ds\n" $((elapsed/3600)) $((elapsed%3600/60)) $((elapsed%60))
    printf "ETA: %dh %dm remaining\n" $((eta_sec/3600)) $((eta_sec%3600/60))
    echo ""
}

display_active() {
    echo -e "${BOLD}=== ACTIVE JOBS ===${NC}"
    
    if [ -d "$STATUS_DIR" ]; then
        local running_dbs=$(find "$STATUS_DIR" -name "*.status" -exec grep -l "RUNNING" {} \; 2>/dev/null | xargs -I{} basename {} .status 2>/dev/null)
        local running_count=$(echo "$running_dbs" | grep -c . 2>/dev/null || echo 0)
        
        if [ -n "$running_dbs" ] && [ "$running_count" -gt 0 ]; then
            echo -e "${BLUE}$running_count jobs running:${NC}"
            echo "$running_dbs" | head -15 | while read db; do
                echo -e "  ${BLUE}⟳${NC} $db"
            done
        else
            echo -e "  ${DIM}No active jobs${NC}"
        fi
    else
        echo -e "  ${DIM}No status directory${NC}"
    fi
    echo ""
}

display_validation() {
    echo -e "${BOLD}=== VALIDATION ===${NC}"
    if [ -d "$VALIDATION_DIR" ]; then
        # Count databases with validation files
        local idx_count=$(find "$VALIDATION_DIR" -name "*_indexes.json" 2>/dev/null | wc -l | tr -d ' ')
        local type_count=$(find "$VALIDATION_DIR" -name "*_types.json" 2>/dev/null | wc -l | tr -d ' ')
        
        # Check for type validation failures
        local type_fail=$(find "$VALIDATION_DIR" -name "*_types.json" -exec grep -l '"passed": false' {} \; 2>/dev/null | wc -l | tr -d ' ')
        
        echo -e "  Indexes checked: $idx_count"
        if [ "$type_fail" -gt 0 ]; then
            echo -e "  ${GREEN}✓${NC} Types passed: $((type_count - type_fail))"
            echo -e "  ${RED}✗${NC} Types failed: $type_fail"
        else
            echo -e "  ${GREEN}✓${NC} Types validated: $type_count"
        fi
    else
        echo -e "  ${DIM}No validation data yet${NC}"
    fi
    echo ""
}

display_recent_log() {
    echo -e "${BOLD}=== RECENT ACTIVITY ===${NC}"
    if [ -f "$LOG_FILE" ]; then
        tail -8 "$LOG_FILE" | while read line; do
            if [[ "$line" == *"SUCCESS"* ]] || [[ "$line" == *"✓"* ]]; then
                echo -e "  ${GREEN}${line:0:70}${NC}"
            elif [[ "$line" == *"ERROR"* ]] || [[ "$line" == *"FAILED"* ]]; then
                echo -e "  ${RED}${line:0:70}${NC}"
            elif [[ "$line" == *"WARN"* ]]; then
                echo -e "  ${YELLOW}${line:0:70}${NC}"
            else
                echo -e "  ${line:0:70}"
            fi
        done
    else
        echo -e "  ${DIM}No log file found${NC}"
    fi
    echo ""
}

display_disk() {
    echo -e "${BOLD}=== DISK USAGE ===${NC}"
    [ -d "$BACKUP_DIR" ] && echo "Temp files: $(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)"
    echo "Free space: $(df -h "$BACKUP_DIR" 2>/dev/null | awk 'NR==2{print $4}')"
    echo ""
}

display_errors() {
    if [ -d "$STATUS_DIR" ]; then
        local failed=$(find "$STATUS_DIR" -name "*.status" -exec grep -l "FAILED" {} \; 2>/dev/null | wc -l | tr -d ' ')
        if [ "$failed" -gt 0 ]; then
            echo -e "${RED}${BOLD}=== ERRORS: $failed ===${NC}"
            find "$STATUS_DIR" -name "*.status" -exec grep -l "FAILED" {} \; 2>/dev/null | xargs -I{} basename {} .status | head -5 | while read db; do
                echo -e "  ${RED}✗${NC} $db"
            done
            echo ""
        fi
    fi
}

monitor_live() {
    while true; do
        print_header
        display_progress
        display_throughput
        display_active
        display_validation
        display_disk
        display_errors
        display_recent_log
        echo -e "${DIM}Ctrl+C to exit | Refresh: ${REFRESH_INTERVAL}s${NC}"
        sleep $REFRESH_INTERVAL
    done
}

show_summary() {
    print_header
    display_progress
    display_throughput
    display_validation
    display_disk
    display_errors
    
    echo -e "${BOLD}=== LOG FILE ===${NC}"
    echo "Path: $LOG_FILE"
    if [ -f "$LOG_FILE" ]; then
        local success_count=$(grep -c "SUCCESS" "$LOG_FILE" 2>/dev/null || echo 0)
        local error_count=$(grep -c "ERROR" "$LOG_FILE" 2>/dev/null || echo 0)
        echo "Entries: $success_count successes, $error_count errors"
    fi
}

tail_log() {
    if [ -f "$LOG_FILE" ]; then
        tail -f "$LOG_FILE"
    else
        echo "Log file not found: $LOG_FILE"
    fi
}

case "${1:-live}" in
    live) monitor_live ;;
    summary) show_summary ;;
    log) tail_log ;;
    *) echo "Usage: $0 [live|summary|log]"; exit 1 ;;
esac
