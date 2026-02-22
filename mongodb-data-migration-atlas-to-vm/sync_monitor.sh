#!/bin/bash

#==============================================================================
# SYNC MONITOR - Dashboard for incremental_sync.sh
#==============================================================================

# Match paths from incremental_sync.sh
ATLAS_URI="mongodb+srv://username:password@<cluster-url>?retryWrites=true&w=majority"
MIGRATION_DIR="/tmp/mongodb-migration"
SYNC_DIR="$MIGRATION_DIR/sync"
LOG_FILE="$SYNC_DIR/incremental_sync.log"
TIMESTAMP_FILE="$MIGRATION_DIR/migration_start_timestamp.txt"
RESUME_TOKEN_FILE="$SYNC_DIR/resume_token.json"

# Mongo command
MONGO_CMD="mongosh"
command -v mongosh &>/dev/null || MONGO_CMD="mongo"

# Colors
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; C='\033[0;36m'; B='\033[1m'; D='\033[2m'; N='\033[0m'

clear
echo -e "${C}╔═══════════════════════════════════════════════════════════════╗${N}"
echo -e "${C}║${N}         ${B}⚡ INCREMENTAL SYNC MONITOR ⚡${N}         $(date '+%H:%M:%S')    ${C}║${N}"
echo -e "${C}╚═══════════════════════════════════════════════════════════════╝${N}"
echo ""

#--- SYNC STATUS ---
echo -e "${B}📡 SYNC STATUS${N}"
if [ -f "$TIMESTAMP_FILE" ]; then
    echo -e "   Start time:  $(cat $TIMESTAMP_FILE)"
else
    echo -e "   Start time:  ${R}NOT SET${N}"
fi

if [ -f "$RESUME_TOKEN_FILE" ]; then
    mod_time=$(stat -c %Y "$RESUME_TOKEN_FILE" 2>/dev/null || stat -f %m "$RESUME_TOKEN_FILE" 2>/dev/null)
    now=$(date +%s)
    age=$((now - mod_time))
    if [ $age -lt 30 ]; then
        echo -e "   Token:       ${G}Active${N} (${age}s ago)"
    elif [ $age -lt 300 ]; then
        echo -e "   Token:       ${Y}Recent${N} (${age}s ago)"
    else
        echo -e "   Token:       ${D}Stale${N} ($((age/60))m ago)"
    fi
else
    echo -e "   Token:       ${D}None (using start time)${N}"
fi
echo ""

#--- LAG CHECK ---
echo -e "${B}⏳ PENDING CHANGES${N}"
echo -e "   ${D}Checking Atlas change stream...${N}"

# Get start timestamp
start_ts=""
resume_token=""

if [ -f "$RESUME_TOKEN_FILE" ]; then
    resume_token=$(cat "$RESUME_TOKEN_FILE")
elif [ -f "$TIMESTAMP_FILE" ]; then
    datetime=$(cat "$TIMESTAMP_FILE")
    start_ts=$(date -d "$datetime" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$datetime" +%s 2>/dev/null)
fi

if [ -n "$start_ts" ] || [ -n "$resume_token" ]; then
    # Create lag check script
    lag_script=$(mktemp)
    cat > "$lag_script" << MONGOSCRIPT
const excludeDBs = ["admin", "local", "config"];
const startTs = ${start_ts:-0};
const resumeToken = '${resume_token}';
const maxCheck = 5000;

let count = 0;
const byOp = {insert: 0, update: 0, delete: 0, other: 0};

try {
    const csOptions = { batchSize: 1000 };
    
    if (resumeToken && resumeToken !== "") {
        try { csOptions.resumeAfter = JSON.parse(resumeToken); } catch(e) {}
    } else if (startTs > 0) {
        csOptions.startAtOperationTime = Timestamp(startTs, 0);
    }
    
    const pipeline = [{ \$match: { "ns.db": { \$nin: excludeDBs } } }];
    const cs = db.getMongo().watch(pipeline, csOptions);
    
    const endTime = Date.now() + 8000;
    while (Date.now() < endTime && count < maxCheck) {
        const c = cs.tryNext();
        if (c) {
            count++;
            if (c.operationType === 'insert') byOp.insert++;
            else if (c.operationType === 'update' || c.operationType === 'replace') byOp.update++;
            else if (c.operationType === 'delete') byOp.delete++;
            else byOp.other++;
        } else if (count > 0) break;
    }
    cs.close();
    
    print(JSON.stringify({ count, capped: count >= maxCheck, byOp }));
} catch(e) {
    print(JSON.stringify({ error: e.message }));
}
MONGOSCRIPT

    result=$($MONGO_CMD "$ATLAS_URI" --quiet --file "$lag_script" 2>/dev/null)
    rm -f "$lag_script"
    
    if echo "$result" | jq -e '.' >/dev/null 2>&1; then
        total=$(echo "$result" | jq -r '.count // 0' 2>/dev/null)
        ins=$(echo "$result" | jq -r '.byOp.insert // 0' 2>/dev/null)
        upd=$(echo "$result" | jq -r '.byOp.update // 0' 2>/dev/null)
        del=$(echo "$result" | jq -r '.byOp.delete // 0' 2>/dev/null)
        capped=$(echo "$result" | jq -r '.capped // false' 2>/dev/null)
        error=$(echo "$result" | jq -r '.error // empty' 2>/dev/null)
        
        if [ -n "$error" ]; then
            echo -e "\r   ${R}Error: $error${N}"
        elif [ "$capped" = "true" ]; then
            echo -e "\r   Pending:  ${Y}${total}+${N} (max reached)"
            echo -e "   ${G}+ins:${N}$ins  ${Y}~upd:${N}$upd  ${R}-del:${N}$del"
        elif [ "$total" = "0" ]; then
            echo -e "\r   Pending:  ${G}0${N} ✓ All caught up!"
        else
            echo -e "\r   Pending:  ${Y}${total}${N}"
            echo -e "   ${G}+ins:${N}$ins  ${Y}~upd:${N}$upd  ${R}-del:${N}$del"
        fi
    else
        echo -e "\r   ${R}Failed to parse response${N}"
    fi
else
    echo -e "\r   ${R}No start time configured${N}"
fi
echo ""

#--- SYNCED STATS FROM LOG ---
echo -e "${B}📊 SYNCED OPERATIONS${N}"
if [ -f "$LOG_FILE" ]; then
    inserts=0; updates=0; deletes=0; nulls=0; batches=0
    
    while IFS= read -r line; do
        if [[ "$line" == *"[SYNC]"* ]] && [[ "$line" == *"Processed"* ]]; then
            batches=$((batches + 1))
            # Extract numbers: +6 ~26 -0 idx:0 null:0
            i=$(echo "$line" | grep -oP '\+\d+' | head -1 | tr -d '+')
            u=$(echo "$line" | grep -oP '~\d+' | head -1 | tr -d '~')
            d=$(echo "$line" | grep -oP '\-\d+' | head -1 | tr -d '-')
            n=$(echo "$line" | grep -oP 'null:\d+' | head -1 | cut -d: -f2)
            [ -z "$i" ] && i=0; [ -z "$u" ] && u=0; [ -z "$d" ] && d=0; [ -z "$n" ] && n=0
            inserts=$((inserts + i))
            updates=$((updates + u))
            deletes=$((deletes + d))
            nulls=$((nulls + n))
        fi
    done < "$LOG_FILE"
    
    total=$((inserts + updates + deletes + nulls))
    
    echo -e "   ${G}+ins:${N} $inserts  ${Y}~upd:${N} $updates  ${R}-del:${N} $deletes  ${D}null:${N} $nulls"
    echo -e "   ${B}Total:${N} $total operations in $batches sync cycles"
else
    echo -e "   ${D}No log file found${N}"
fi
echo ""

#--- RECENT LOG ---
echo -e "${B}📜 RECENT ACTIVITY${N}"
if [ -f "$LOG_FILE" ]; then
    tail -6 "$LOG_FILE" | while read line; do
        line="${line:0:68}"
        if [[ "$line" == *"[SYNC]"* ]]; then
            echo -e "   ${G}$line${N}"
        elif [[ "$line" == *"[ERROR]"* ]]; then
            echo -e "   ${R}$line${N}"
        elif [[ "$line" == *"[WARN]"* ]]; then
            echo -e "   ${Y}$line${N}"
        else
            echo -e "   ${D}$line${N}"
        fi
    done
else
    echo -e "   ${D}No log file${N}"
fi
echo ""

#--- COMMANDS ---
echo -e "${D}─────────────────────────────────────────────────────────────────${N}"
echo -e "${D}Commands:${N}"
echo -e "  ${B}./incremental_sync.sh continuous${N}  - Start sync"
echo -e "  ${B}./incremental_sync.sh lag${N}         - Check pending"
echo -e "  ${B}./sync_monitor.sh${N}                 - Refresh this view"
echo ""
