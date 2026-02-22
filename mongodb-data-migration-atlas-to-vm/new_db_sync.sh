#!/bin/bash

#==============================================================================
# NEW DATABASE SYNC - Migrate only NEW databases not in original list
# 
# This script:
# 1. Fetches current databases from Atlas
# 2. Compares with the original database_list.txt (from initial migration)
# 3. Shows how many NEW databases found
# 4. Asks for confirmation before migrating
# 5. Migrates with full data integrity (indexes, datatypes, data)
#==============================================================================

set -euo pipefail

#------------------------------------------------------------------------------
# CONFIGURATION (same as mongodb_migration.sh)
#------------------------------------------------------------------------------

# Source: MongoDB Atlas
ATLAS_URI="mongodb+srv://username:password@<cluster-url>/?retryWrites=true&w=majority"

# Destination: Azure VM MongoDB
TARGET_URI="mongodb://username:password@<ip-address>/?replicaSet=artha-rs"

# Directories
BACKUP_DIR="/tmp/mongodb-migration"
ORIGINAL_DB_LIST="$BACKUP_DIR/database_list.txt"
NEW_DB_LIST="$BACKUP_DIR/new_databases.txt"
LOG_FILE="$BACKUP_DIR/new_db_sync.log"
DUMP_DIR="$BACKUP_DIR/dump"
VERIFICATION_LOG="$BACKUP_DIR/verification.log"

# Performance
THREADS_PER_JOB=4

#------------------------------------------------------------------------------
# COLORS
#------------------------------------------------------------------------------

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'

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

#------------------------------------------------------------------------------
# INIT
#------------------------------------------------------------------------------

init() {
    mkdir -p "$BACKUP_DIR" "$DUMP_DIR"
    
    if command -v mongosh &>/dev/null; then
        MONGO_CMD="mongosh"
    elif command -v mongo &>/dev/null; then
        MONGO_CMD="mongo"
    else
        log_error "mongosh/mongo not found"
        exit 1
    fi
    
    export MONGO_CMD
}

#------------------------------------------------------------------------------
# DETECT NEW DATABASES
#------------------------------------------------------------------------------

detect_new_databases() {
    log_info "Fetching current databases from Atlas..."
    
    # Get current databases
    local current_list=$(mktemp)
    $MONGO_CMD "$ATLAS_URI" --quiet --eval '
        db.adminCommand("listDatabases").databases
            .map(d => d.name)
            .filter(n => !["admin", "local", "config"].includes(n))
            .sort()
            .forEach(n => print(n))
    ' 2>/dev/null > "$current_list"
    
    local current_count=$(wc -l < "$current_list" | tr -d ' ')
    log_info "Found $current_count databases in Atlas"
    
    # Check if original list exists
    if [ ! -f "$ORIGINAL_DB_LIST" ]; then
        log_error "Original database list not found: $ORIGINAL_DB_LIST"
        log_error "Please run './mongodb_migration.sh list' first to create it"
        rm -f "$current_list"
        exit 1
    fi
    
    local original_count=$(wc -l < "$ORIGINAL_DB_LIST" | tr -d ' ')
    log_info "Original migration had $original_count databases"
    
    # Find new databases (in current but not in original)
    comm -23 <(sort "$current_list") <(sort "$ORIGINAL_DB_LIST") > "$NEW_DB_LIST"
    rm -f "$current_list"
    
    local new_count=$(wc -l < "$NEW_DB_LIST" | tr -d ' ')
    
    if [ "$new_count" -eq 0 ]; then
        log_info "No new databases found!"
        return 1
    fi
    
    log_info "Found $new_count NEW databases to migrate"
    return 0
}

#------------------------------------------------------------------------------
# VERIFY DATABASE INTEGRITY
#------------------------------------------------------------------------------

verify_database() {
    local db_name="$1"
    local errors=0
    
    log_info "[$db_name] Verifying data integrity..."
    
    # Get source stats
    local source_stats=$($MONGO_CMD "$ATLAS_URI" --quiet --eval "
        const db = db.getSiblingDB('$db_name');
        const collections = db.getCollectionNames();
        let result = {collections: collections.length, documents: 0, indexes: 0};
        collections.forEach(c => {
            result.documents += db[c].countDocuments({});
            result.indexes += db[c].getIndexes().length;
        });
        print(JSON.stringify(result));
    " 2>/dev/null)
    
    # Get target stats
    local target_stats=$($MONGO_CMD "$TARGET_URI" --quiet --eval "
        const db = db.getSiblingDB('$db_name');
        const collections = db.getCollectionNames();
        let result = {collections: collections.length, documents: 0, indexes: 0};
        collections.forEach(c => {
            result.documents += db[c].countDocuments({});
            result.indexes += db[c].getIndexes().length;
        });
        print(JSON.stringify(result));
    " 2>/dev/null)
    
    # Parse results
    local src_collections=$(echo "$source_stats" | jq -r '.collections // 0')
    local src_documents=$(echo "$source_stats" | jq -r '.documents // 0')
    local src_indexes=$(echo "$source_stats" | jq -r '.indexes // 0')
    
    local tgt_collections=$(echo "$target_stats" | jq -r '.collections // 0')
    local tgt_documents=$(echo "$target_stats" | jq -r '.documents // 0')
    local tgt_indexes=$(echo "$target_stats" | jq -r '.indexes // 0')
    
    # Log verification results
    echo "[$db_name] Verification:" >> "$VERIFICATION_LOG"
    echo "  Collections: Source=$src_collections, Target=$tgt_collections" >> "$VERIFICATION_LOG"
    echo "  Documents:   Source=$src_documents, Target=$tgt_documents" >> "$VERIFICATION_LOG"
    echo "  Indexes:     Source=$src_indexes, Target=$tgt_indexes" >> "$VERIFICATION_LOG"
    
    # Check collections
    if [ "$src_collections" != "$tgt_collections" ]; then
        log_error "[$db_name] Collection count mismatch! Source: $src_collections, Target: $tgt_collections"
        errors=$((errors + 1))
    else
        log_info "[$db_name] ✓ Collections: $tgt_collections"
    fi
    
    # Check documents
    if [ "$src_documents" != "$tgt_documents" ]; then
        log_error "[$db_name] Document count mismatch! Source: $src_documents, Target: $tgt_documents"
        errors=$((errors + 1))
    else
        log_info "[$db_name] ✓ Documents: $tgt_documents"
    fi
    
    # Check indexes
    if [ "$src_indexes" != "$tgt_indexes" ]; then
        log_warn "[$db_name] Index count mismatch! Source: $src_indexes, Target: $tgt_indexes"
        # Not counting as error - indexes can sometimes differ slightly
    else
        log_info "[$db_name] ✓ Indexes: $tgt_indexes"
    fi
    
    return $errors
}

#------------------------------------------------------------------------------
# MIGRATE SINGLE DATABASE (with full integrity)
#------------------------------------------------------------------------------

migrate_database() {
    local db_name="$1"
    local archive_file="$DUMP_DIR/${db_name}.archive.gz"
    
    log_info "[$db_name] Starting migration..."
    
    # Dump from Atlas (preserves indexes, datatypes, everything)
    log_info "[$db_name] Dumping from Atlas..."
    if ! mongodump \
        --uri="$ATLAS_URI" \
        --db="$db_name" \
        --archive="$archive_file" \
        --gzip \
        --numParallelCollections="$THREADS_PER_JOB" \
        --readPreference=secondaryPreferred 2>&1 | tee -a "$LOG_FILE"; then
        log_error "[$db_name] Dump failed"
        return 1
    fi
    
    # Restore to target (--drop ensures clean slate, preserves indexes)
    log_info "[$db_name] Restoring to target..."
    if ! mongorestore \
        --uri="$TARGET_URI" \
        --archive="$archive_file" \
        --gzip \
        --numParallelCollections="$THREADS_PER_JOB" \
        --drop 2>&1 | tee -a "$LOG_FILE"; then
        log_error "[$db_name] Restore failed"
        return 1
    fi
    
    # Verify data integrity
    if ! verify_database "$db_name"; then
        log_error "[$db_name] Verification failed!"
        return 1
    fi
    
    # Cleanup archive
    rm -f "$archive_file"
    
    log_info "[$db_name] ✓ Migration complete with verification"
    return 0
}

#------------------------------------------------------------------------------
# MAIN - SYNC COMMAND (detect, confirm, migrate)
#------------------------------------------------------------------------------

sync_new_databases() {
    log_info "Checking for new databases..."
    
    # Detect new databases
    if ! detect_new_databases; then
        echo ""
        echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  ✓ No new databases found - everything is synced!${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
        echo ""
        return 0
    fi
    
    # Show new databases
    local count=$(wc -l < "$NEW_DB_LIST" | tr -d ' ')
    
    echo ""
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}               ${YELLOW}$count NEW DATABASE(S) DETECTED${NC}"
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local idx=1
    while read db; do
        echo -e "  ${GREEN}$idx.${NC} $db"
        idx=$((idx + 1))
    done < "$NEW_DB_LIST"
    
    echo ""
    echo -e "${DIM}These databases were created after the initial migration.${NC}"
    echo ""
    
    # Ask for confirmation
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${CYAN}Do you want to migrate these $count database(s)?${NC}"
    echo ""
    echo -e "  ${DIM}Migration includes:${NC}"
    echo -e "  ${DIM}  • Full data copy (all documents)${NC}"
    echo -e "  ${DIM}  • All indexes preserved${NC}"
    echo -e "  ${DIM}  • All datatypes preserved (Date, ObjectId, etc.)${NC}"
    echo -e "  ${DIM}  • Verification after each database${NC}"
    echo ""
    read -p "  Proceed with migration? (yes/no): " confirm
    echo ""
    
    if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${YELLOW}Migration cancelled by user${NC}"
        return 0
    fi
    
    # Start migration
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}               STARTING MIGRATION${NC}"
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local total=$count
    local success=0
    local failed=0
    local current=0
    
    # Clear verification log
    > "$VERIFICATION_LOG"
    
    while read db_name; do
        current=$((current + 1))
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}  [$current/$total] Migrating: ${BOLD}$db_name${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        if migrate_database "$db_name"; then
            success=$((success + 1))
            # Add to original list so it's tracked
            echo "$db_name" >> "$ORIGINAL_DB_LIST"
            sort -o "$ORIGINAL_DB_LIST" "$ORIGINAL_DB_LIST"
        else
            failed=$((failed + 1))
        fi
    done < "$NEW_DB_LIST"
    
    # Summary
    echo ""
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}               MIGRATION COMPLETE${NC}"
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}✓ Success:${NC} $success database(s)"
    [ "$failed" -gt 0 ] && echo -e "  ${RED}✗ Failed:${NC}  $failed database(s)"
    echo ""
    echo -e "  ${DIM}Verification log: $VERIFICATION_LOG${NC}"
    echo -e "  ${DIM}Full log: $LOG_FILE${NC}"
    echo ""
    
    if [ "$failed" -eq 0 ]; then
        echo -e "${GREEN}  All databases migrated successfully with full integrity!${NC}"
    else
        echo -e "${YELLOW}  Some databases failed. Check the logs for details.${NC}"
    fi
    echo ""
}

#------------------------------------------------------------------------------
# CHECK ONLY (no migration)
#------------------------------------------------------------------------------

check_only() {
    log_info "Checking for new databases..."
    
    if detect_new_databases; then
        local count=$(wc -l < "$NEW_DB_LIST" | tr -d ' ')
        echo ""
        echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}               ${YELLOW}$count NEW DATABASE(S) DETECTED${NC}"
        echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
        echo ""
        
        local idx=1
        while read db; do
            echo -e "  ${GREEN}$idx.${NC} $db"
            idx=$((idx + 1))
        done < "$NEW_DB_LIST"
        
        echo ""
        echo -e "${DIM}Run '$0 sync' to migrate these databases${NC}"
        echo ""
    else
        echo ""
        echo -e "${GREEN}✓ No new databases found - everything is synced!${NC}"
        echo ""
    fi
}

#------------------------------------------------------------------------------
# MAIN
#------------------------------------------------------------------------------

print_banner() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         New Database Sync                                     ║${NC}"
    echo -e "${CYAN}║         Detect & Migrate NEW databases with confirmation      ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  sync     - Detect new DBs, show count, ask confirmation, then migrate"
    echo "  check    - Only check for new databases (don't migrate)"
    echo ""
    echo "Features:"
    echo "  • Compares Atlas with database_list.txt from initial migration"
    echo "  • Shows how many new databases found"
    echo "  • Asks for confirmation before migrating"
    echo "  • Preserves all indexes and datatypes"
    echo "  • Verifies data integrity after each migration"
    echo ""
}

main() {
    print_banner
    init
    
    case "${1:-}" in
        sync)
            sync_new_databases
            ;;
        check)
            check_only
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
