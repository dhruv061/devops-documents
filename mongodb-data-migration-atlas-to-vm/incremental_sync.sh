#!/bin/bash

#==============================================================================
# INCREMENTAL SYNC - BSON TYPE PRESERVING
# 
# Features:
# - Preserves ALL BSON types (Date, ObjectId, Decimal128, Binary, etc.)
# - Syncs index changes (createIndexes, dropIndexes)
# - Reads start timestamp from migration script
# - Uses native BSON operations (no JSON conversion)
# - Handles: insert, update, replace, delete, drop, rename, createIndexes, dropIndexes
# - Resume capability with token persistence
#==============================================================================

set -euo pipefail

#------------------------------------------------------------------------------
# CONFIGURATION
#------------------------------------------------------------------------------

# Source: MongoDB Atlas (NO database name)
ATLAS_URI="mongodb+srv://username:password@<cluster-url>/?retryWrites=true&w=majority"

# Destination: Azure VM MongoDB
TARGET_URI="mongodb://username:password@<ip-address>/?replicaSet=artha-rs"

# Directories - use same base as migration script
MIGRATION_DIR="/tmp/mongodb-migration"
SYNC_DIR="$MIGRATION_DIR/sync"
LOG_FILE="$SYNC_DIR/incremental_sync.log"
RESUME_TOKEN_FILE="$SYNC_DIR/resume_token.json"

# Start time from migration script
MIGRATION_TIMESTAMP_FILE="$MIGRATION_DIR/migration_start_timestamp.txt"

# Performance tuning
BATCH_SIZE=500
BATCH_TIMEOUT_SECONDS=10
SYNC_INTERVAL_SECONDS=5

EXCLUDE_DBS="admin,local,config"

#------------------------------------------------------------------------------
# COLORS
#------------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
DIM='\033[2m'
BOLD='\033[1m'

#------------------------------------------------------------------------------
# LOGGING
#------------------------------------------------------------------------------

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo -e "$msg" | tee -a "$LOG_FILE"
}

log_info() { log "${GREEN}[INFO]${NC} $*"; }
log_warn() { log "${YELLOW}[WARN]${NC} $*"; }
log_error() { log "${RED}[ERROR]${NC} $*"; }
log_sync() { log "${CYAN}[SYNC]${NC} $*"; }

#------------------------------------------------------------------------------
# INITIALIZATION
#------------------------------------------------------------------------------

init() {
    mkdir -p "$SYNC_DIR"
    
    if command -v mongosh &>/dev/null; then
        MONGO_CMD="mongosh"
    elif command -v mongo &>/dev/null; then
        MONGO_CMD="mongo"
    else
        log_error "mongosh/mongo not found"
        exit 1
    fi
    
    export MONGO_CMD
    log_info "Incremental Sync initialized (BSON-preserving)"
    log_info "Using MongoDB shell: $MONGO_CMD"
}

#------------------------------------------------------------------------------
# GET START TIMESTAMP FROM MIGRATION SCRIPT
#------------------------------------------------------------------------------

get_start_time_from_migration() {
    if [ -f "$MIGRATION_TIMESTAMP_FILE" ]; then
        local datetime=$(cat "$MIGRATION_TIMESTAMP_FILE")
        log_info "Using migration start time: $datetime"
        echo "$datetime"
    else
        log_error "Migration timestamp file not found: $MIGRATION_TIMESTAMP_FILE"
        log_error "Please run migration script first: ./mongodb_migration.sh start"
        exit 1
    fi
}

# Convert datetime string to MongoDB timestamp
get_start_option() {
    # Check for resume token first
    if [ -f "$RESUME_TOKEN_FILE" ]; then
        local token=$(cat "$RESUME_TOKEN_FILE")
        if [ -n "$token" ] && [ "$token" != "null" ]; then
            log_info "Resuming from saved token"
            echo "resumeAfter: $token"
            return
        fi
    fi
    
    # Fall back to migration start time
    if [ -f "$MIGRATION_TIMESTAMP_FILE" ]; then
        local datetime=$(cat "$MIGRATION_TIMESTAMP_FILE")
        # Convert to unix timestamp
        local ts=$(date -d "$datetime" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$datetime" +%s 2>/dev/null)
        if [ -n "$ts" ]; then
            log_info "Starting from migration time: $datetime (ts: $ts)"
            echo "startAtOperationTime: Timestamp($ts, 0)"
            return
        fi
    fi
    
    log_error "No start time available!"
    exit 1
}

#------------------------------------------------------------------------------
# SYNC CYCLE - BSON PRESERVING
# 
# Key: We use mongosh's native BSON handling
# Documents are copied directly without JSON serialization
#------------------------------------------------------------------------------

run_sync_cycle() {
    # Get timestamp from file
    local start_ts=""
    local resume_token=""
    
    if [ -f "$RESUME_TOKEN_FILE" ]; then
        resume_token=$(cat "$RESUME_TOKEN_FILE")
    elif [ -f "$MIGRATION_TIMESTAMP_FILE" ]; then
        local datetime=$(cat "$MIGRATION_TIMESTAMP_FILE")
        start_ts=$(date -d "$datetime" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$datetime" +%s 2>/dev/null)
    else
        return 0
    fi
    
    local sync_script=$(mktemp)
    cat > "$sync_script" << MONGOSCRIPT
// Configuration embedded directly
const targetUri = '${TARGET_URI}';
const startTs = ${start_ts:-0};
const resumeToken = '${resume_token}';
const batchSize = ${BATCH_SIZE};
const timeoutMs = $((BATCH_TIMEOUT_SECONDS * 1000));
const excludeDBs = ['admin', 'local', 'config'];

// Stats
const stats = {
    inserts: 0, updates: 0, deletes: 0, 
    indexes: 0, drops: 0, skips: 0, errors: 0,
    nullDocs: 0
};

let lastToken = null;
let processedCount = 0;

try {
    // Connect to target
    const targetConn = connect(targetUri);
    
    // Build change stream options
    const csOptions = {
        fullDocument: 'updateLookup',
        fullDocumentBeforeChange: 'whenAvailable',
        batchSize: batchSize
    };
    
    // Set start option
    if (resumeToken && resumeToken !== "") {
        try {
            csOptions.resumeAfter = JSON.parse(resumeToken);
        } catch(e) {}
    } else if (startTs > 0) {
        csOptions.startAtOperationTime = Timestamp(startTs, 0);
    }
    
    // Open change stream on source (cluster-wide)
    const pipeline = [{ \$match: { 'ns.db': { \$nin: excludeDBs } } }];
    const cs = db.getMongo().watch(pipeline, csOptions);
    
    const endTime = Date.now() + timeoutMs;
    
    while (Date.now() < endTime && processedCount < batchSize) {
        const change = cs.tryNext();
        
        if (!change) {
            if (processedCount > 0) break;
            continue;
        }
        
        lastToken = change._id;
        processedCount++;
        
        const dbName = change.ns?.db;
        const collName = change.ns?.coll;
        
        if (!dbName) {
            stats.skips++;
            continue;
        }
        
        try {
            const targetDb = targetConn.getSiblingDB(dbName);
            
            switch (change.operationType) {
                
                //----------------------------------------------------------
                // INSERT - Copy document directly (preserves BSON types)
                //----------------------------------------------------------
                case 'insert':
                    if (change.fullDocument && collName) {
                        targetDb.getCollection(collName).replaceOne(
                            { _id: change.fullDocument._id },
                            change.fullDocument,
                            { upsert: true }
                        );
                        stats.inserts++;
                    } else {
                        stats.skips++;
                    }
                    break;
                
                //----------------------------------------------------------
                // UPDATE/REPLACE - Use fullDocument for complete replacement
                //----------------------------------------------------------
                case 'update':
                case 'replace':
                    if (!change.documentKey) {
                        stats.skips++;
                    } else if (!change.fullDocument) {
                        targetDb.getCollection(collName).deleteOne(change.documentKey);
                        stats.nullDocs++;
                    } else {
                        targetDb.getCollection(collName).replaceOne(
                            change.documentKey,
                            change.fullDocument,
                            { upsert: true }
                        );
                        stats.updates++;
                    }
                    break;
                
                //----------------------------------------------------------
                // DELETE
                //----------------------------------------------------------
                case 'delete':
                    if (change.documentKey && collName) {
                        targetDb.getCollection(collName).deleteOne(change.documentKey);
                        stats.deletes++;
                    }
                    break;
                
                //----------------------------------------------------------
                // DROP COLLECTION
                //----------------------------------------------------------
                case 'drop':
                    if (collName) {
                        try { targetDb.getCollection(collName).drop(); } catch(e) {}
                        stats.drops++;
                    }
                    break;
                
                //----------------------------------------------------------
                // DROP DATABASE
                //----------------------------------------------------------
                case 'dropDatabase':
                    try { targetDb.dropDatabase(); } catch(e) {}
                    stats.drops++;
                    break;
                
                //----------------------------------------------------------
                // RENAME COLLECTION
                //----------------------------------------------------------
                case 'rename':
                    if (collName && change.to?.coll) {
                        try {
                            targetDb.getCollection(collName).renameCollection(change.to.coll);
                        } catch(e) {}
                        stats.drops++;
                    }
                    break;
                
                //----------------------------------------------------------
                // CREATE INDEXES - Sync index creation
                //----------------------------------------------------------
                case 'createIndexes':
                    if (change.operationDescription?.indexes && collName) {
                        const indexes = change.operationDescription.indexes;
                        indexes.forEach(idx => {
                            try {
                                const options = {};
                                if (idx.name) options.name = idx.name;
                                if (idx.unique) options.unique = true;
                                if (idx.sparse) options.sparse = true;
                                if (idx.expireAfterSeconds !== undefined) {
                                    options.expireAfterSeconds = idx.expireAfterSeconds;
                                }
                                if (idx.partialFilterExpression) {
                                    options.partialFilterExpression = idx.partialFilterExpression;
                                }
                                
                                targetDb.getCollection(collName).createIndex(idx.key, options);
                                stats.indexes++;
                            } catch(e) {
                                if (!e.message.includes('already exists')) {
                                    stats.errors++;
                                }
                            }
                        });
                    }
                    break;
                
                //----------------------------------------------------------
                // DROP INDEXES
                //----------------------------------------------------------
                case 'dropIndexes':
                    if (collName) {
                        if (change.operationDescription?.indexName) {
                            try {
                                targetDb.getCollection(collName).dropIndex(
                                    change.operationDescription.indexName
                                );
                                stats.indexes++;
                            } catch(e) {}
                        }
                    }
                    break;
                
                //----------------------------------------------------------
                // CREATE (new collection)
                //----------------------------------------------------------
                case 'create':
                    if (collName) {
                        try {
                            targetDb.createCollection(collName);
                        } catch(e) {}
                    }
                    break;
                
                default:
                    stats.skips++;
            }
            
        } catch(e) {
            stats.errors++;
        }
    }
    
    cs.close();
    
    // Output result
    print(JSON.stringify({
        success: true,
        count: processedCount,
        stats: stats,
        lastToken: lastToken
    }));
    
} catch(e) {
    print(JSON.stringify({
        success: false,
        error: e.message,
        count: processedCount,
        stats: stats,
        lastToken: lastToken
    }));
}
MONGOSCRIPT

    # Run sync - capture stderr too for debugging
    local result=$($MONGO_CMD "$ATLAS_URI" --quiet --file "$sync_script" 2>&1)
    local exit_code=$?
    rm -f "$sync_script"
    
    # Debug: check exit code
    if [ $exit_code -ne 0 ]; then
        log_error "mongosh exited with code $exit_code: $result"
        return 1
    fi
    
    # Check for empty result
    if [ -z "$result" ]; then
        return 0
    fi
    
    # Check if result is valid JSON
    if ! echo "$result" | jq -e '.' >/dev/null 2>&1; then
        log_error "Invalid JSON response: $result"
        return 1
    fi
    
    # Parse result
    local success=$(echo "$result" | jq -r '.success // false' 2>/dev/null)
    local count=$(echo "$result" | jq -r '.count // 0' 2>/dev/null)
    local error=$(echo "$result" | jq -r '.error // empty' 2>/dev/null)
    
    if [ "$success" = "false" ] && [ -n "$error" ]; then
        log_error "Sync error: $error"
        return 1
    fi
    
    if [ "$count" = "0" ] || [ -z "$count" ]; then
        return 0
    fi
    
    # Parse stats
    local inserts=$(echo "$result" | jq -r '.stats.inserts // 0' 2>/dev/null)
    local updates=$(echo "$result" | jq -r '.stats.updates // 0' 2>/dev/null)
    local deletes=$(echo "$result" | jq -r '.stats.deletes // 0' 2>/dev/null)
    local nullDocs=$(echo "$result" | jq -r '.stats.nullDocs // 0' 2>/dev/null)
    local indexes=$(echo "$result" | jq -r '.stats.indexes // 0' 2>/dev/null)
    local drops=$(echo "$result" | jq -r '.stats.drops // 0' 2>/dev/null)
    local skips=$(echo "$result" | jq -r '.stats.skips // 0' 2>/dev/null)
    local errors=$(echo "$result" | jq -r '.stats.errors // 0' 2>/dev/null)
    
    # Save resume token
    local last_token=$(echo "$result" | jq -c '.lastToken // empty' 2>/dev/null)
    if [ -n "$last_token" ] && [ "$last_token" != "null" ]; then
        echo "$last_token" > "$RESUME_TOKEN_FILE"
    fi
    
    # Log summary
    log_sync "Processed $count: ${GREEN}+$inserts${NC} ${YELLOW}~$updates${NC} ${RED}-$deletes${NC} ${BLUE}idx:$indexes${NC} ${MAGENTA}null:$nullDocs${NC} ${DIM}skip:$skips err:$errors${NC}"
}

#------------------------------------------------------------------------------
# CONTINUOUS MODE
#------------------------------------------------------------------------------

run_continuous() {
    log_info "Starting continuous sync..."
    log_info "Batch size: $BATCH_SIZE | Interval: ${SYNC_INTERVAL_SECONDS}s"
    
    if [ -f "$MIGRATION_TIMESTAMP_FILE" ]; then
        log_info "Migration start time: $(cat $MIGRATION_TIMESTAMP_FILE)"
    fi
    
    log_info "Legend: ${GREEN}+insert${NC} ${YELLOW}~update${NC} ${RED}-delete${NC} ${BLUE}idx=index${NC} ${MAGENTA}null=deleted-on-source${NC}"
    echo ""
    
    trap 'log_info "Stopping sync..."; exit 0' INT TERM
    
    local cycle=0
    while true; do
        cycle=$((cycle + 1))
        local start=$(date +%s)
        
        run_sync_cycle || true  # Don't exit on sync errors
        
        local elapsed=$(($(date +%s) - start))
        local sleep_time=$((SYNC_INTERVAL_SECONDS - elapsed))
        [ $sleep_time -gt 0 ] && sleep $sleep_time
    done
}

#------------------------------------------------------------------------------
# RUN ONCE
#------------------------------------------------------------------------------

run_once() {
    log_info "Running single sync cycle..."
    run_sync_cycle
    log_info "Done"
}

#------------------------------------------------------------------------------
# LAG CHECK
#------------------------------------------------------------------------------

check_lag() {
    log_info "Checking sync lag..."
    
    # Get timestamp from file
    local start_ts=""
    local resume_token=""
    
    if [ -f "$RESUME_TOKEN_FILE" ]; then
        resume_token=$(cat "$RESUME_TOKEN_FILE")
        log_info "Using resume token"
    elif [ -f "$MIGRATION_TIMESTAMP_FILE" ]; then
        local datetime=$(cat "$MIGRATION_TIMESTAMP_FILE")
        start_ts=$(date -d "$datetime" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$datetime" +%s 2>/dev/null)
        log_info "Using start time: $datetime (ts: $start_ts)"
    else
        log_error "No start time set!"
        return 1
    fi
    
    # Create temp script with values embedded
    local lag_script=$(mktemp)
    cat > "$lag_script" << MONGOSCRIPT
const excludeDBs = ["admin", "local", "config"];
const maxCheck = 5000;
const startTs = ${start_ts:-0};
const resumeToken = '${resume_token}';

let count = 0;
const byOp = {};
const byDb = {};

try {
    const csOptions = { batchSize: 1000 };
    
    if (resumeToken && resumeToken !== "") {
        try {
            csOptions.resumeAfter = JSON.parse(resumeToken);
        } catch(e) {}
    } else if (startTs > 0) {
        csOptions.startAtOperationTime = Timestamp(startTs, 0);
    }
    
    const pipeline = [{ \$match: { "ns.db": { \$nin: excludeDBs } } }];
    const cs = db.getMongo().watch(pipeline, csOptions);
    
    const endTime = Date.now() + 10000;
    
    while (Date.now() < endTime && count < maxCheck) {
        const c = cs.tryNext();
        if (c) {
            count++;
            const op = c.operationType;
            const dbName = c.ns?.db || "unknown";
            byOp[op] = (byOp[op] || 0) + 1;
            byDb[dbName] = (byDb[dbName] || 0) + 1;
        } else if (count > 0) {
            break;
        }
    }
    cs.close();
    
    print(JSON.stringify({ count, capped: count >= maxCheck, byOp, byDb }));
} catch(e) {
    print(JSON.stringify({ error: e.message }));
}
MONGOSCRIPT

    local result=$($MONGO_CMD "$ATLAS_URI" --quiet --file "$lag_script" 2>/dev/null)
    rm -f "$lag_script"
    
    # Debug: show raw result if empty
    if [ -z "$result" ]; then
        log_warn "No result from change stream - trying direct connection test..."
        local test=$($MONGO_CMD "$ATLAS_URI" --quiet --eval 'print("connected")' 2>/dev/null)
        if [ "$test" != "connected" ]; then
            log_error "Cannot connect to Atlas"
            return 1
        fi
        result='{"count":0,"byOp":{},"byDb":{}}'
    fi
    
    local error=$(echo "$result" | jq -r '.error // empty' 2>/dev/null)
    if [ -n "$error" ]; then
        log_error "$error"
        return 1
    fi
    
    local count=$(echo "$result" | jq -r '.count // 0' 2>/dev/null)
    local capped=$(echo "$result" | jq -r '.capped // false' 2>/dev/null)
    
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}                         SYNC LAG REPORT                        ${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Pending changes: ${YELLOW}$count${NC}$( [ "$capped" = "true" ] && echo "+ (capped at 5000)" )"
    echo ""
    
    echo -e "${BOLD}By Operation Type:${NC}"
    echo "$result" | jq -r '.byOp | to_entries[] | "  \(.key): \(.value)"' 2>/dev/null || true
    echo ""
    
    echo -e "${BOLD}By Database (top 10):${NC}"
    echo "$result" | jq -r '.byDb | to_entries | sort_by(-.value) | .[:10][] | "  \(.key): \(.value)"' 2>/dev/null || true
    echo ""
    
    if [ "$count" = "0" ]; then
        log_info "✓ All caught up! No pending changes."
    else
        log_info "Run './incremental_sync.sh continuous' to sync these changes"
    fi
}

#------------------------------------------------------------------------------
# STATUS
#------------------------------------------------------------------------------

show_status() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}              INCREMENTAL SYNC STATUS                          ${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${CYAN}Migration Timestamp:${NC}"
    if [ -f "$MIGRATION_TIMESTAMP_FILE" ]; then
        echo "  File: $MIGRATION_TIMESTAMP_FILE"
        echo "  Time: $(cat $MIGRATION_TIMESTAMP_FILE)"
    else
        echo "  ${RED}NOT SET${NC} - Run migration script first!"
    fi
    echo ""
    
    echo -e "${CYAN}Resume Token:${NC}"
    if [ -f "$RESUME_TOKEN_FILE" ]; then
        echo "  File: $RESUME_TOKEN_FILE"
        echo "  Status: Saved (will resume from last position)"
    else
        echo "  Status: None (will start from migration timestamp)"
    fi
    echo ""
    
    echo -e "${CYAN}Configuration:${NC}"
    echo "  Source: Atlas"
    echo "  Target: Self-hosted MongoDB"
    echo "  Batch Size: $BATCH_SIZE"
    echo "  Sync Interval: ${SYNC_INTERVAL_SECONDS}s"
    echo ""
    
    echo -e "${CYAN}Log File:${NC} $LOG_FILE"
    echo ""
}

#------------------------------------------------------------------------------
# RESET
#------------------------------------------------------------------------------

reset_sync() {
    log_warn "Resetting sync state..."
    rm -f "$RESUME_TOKEN_FILE"
    log_info "Resume token cleared - will restart from migration timestamp"
}

#------------------------------------------------------------------------------
# SET MANUAL TIMESTAMP
#------------------------------------------------------------------------------

set_manual_time() {
    local datetime="$1"
    
    if [ -z "$datetime" ]; then
        log_error "Usage: $0 set-time \"YYYY-MM-DD HH:MM:SS\""
        exit 1
    fi
    
    # Validate format
    if ! date -d "$datetime" &>/dev/null && ! date -j -f "%Y-%m-%d %H:%M:%S" "$datetime" &>/dev/null; then
        log_error "Invalid date format. Use: YYYY-MM-DD HH:MM:SS"
        exit 1
    fi
    
    echo "$datetime" > "$MIGRATION_TIMESTAMP_FILE"
    rm -f "$RESUME_TOKEN_FILE"  # Clear resume token to use new time
    log_info "Start time set to: $datetime"
    log_info "Resume token cleared - sync will start from this time"
}

#------------------------------------------------------------------------------
# SET CURRENT TIME FROM ATLAS
#------------------------------------------------------------------------------

set_start_time_now() {
    log_info "Capturing current Atlas oplog time..."
    
    local result=$($MONGO_CMD "$ATLAS_URI" --quiet --eval '
        var r = db.adminCommand({isMaster: 1});
        if (r.operationTime) {
            var ts = r.operationTime.getTime ? r.operationTime.getTime() : r.operationTime.t;
            print(new Date(ts * 1000).toISOString().replace("T", " ").substring(0, 19));
        } else {
            print(new Date().toISOString().replace("T", " ").substring(0, 19));
        }
    ' 2>/dev/null)
    
    if [ -n "$result" ]; then
        echo "$result" > "$MIGRATION_TIMESTAMP_FILE"
        rm -f "$RESUME_TOKEN_FILE"
        log_info "Start time captured: $result"
        log_info "Resume token cleared - sync will start from this time"
    else
        log_error "Failed to get time from Atlas"
        exit 1
    fi
}

#------------------------------------------------------------------------------
# MAIN
#------------------------------------------------------------------------------

print_banner() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Incremental Sync - BSON Type Preserving                   ║${NC}"
    echo -e "${CYAN}║     • Preserves Date, ObjectId, Decimal128, Binary            ║${NC}"
    echo -e "${CYAN}║     • Syncs index changes (create/drop)                       ║${NC}"
    echo -e "${CYAN}║     • Reads start time from migration script                  ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  continuous                      - Run continuous sync (recommended)"
    echo "  once                            - Run single sync cycle"
    echo "  lag                             - Check pending changes"
    echo "  status                          - Show sync status"
    echo ""
    echo "Time Management:"
    echo "  set-time \"YYYY-MM-DD HH:MM:SS\"  - Set manual start timestamp"
    echo "  set-start-time                  - Capture current Atlas time as start"
    echo "  reset                           - Reset resume token (restart from start time)"
    echo ""
    echo "Examples:"
    echo "  $0 set-time \"2026-01-15 06:00:00\"   # Set custom start time"
    echo "  $0 set-start-time                    # Use current Atlas time"
    echo "  $0 continuous                        # Start syncing"
    echo ""
}

main() {
    print_banner
    init
    
    case "${1:-}" in
        continuous)
            run_continuous
            ;;
        once)
            run_once
            ;;
        lag)
            check_lag
            ;;
        status)
            show_status
            ;;
        reset)
            reset_sync
            ;;
        set-time)
            set_manual_time "${2:-}"
            ;;
        set-start-time)
            set_start_time_now
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"

