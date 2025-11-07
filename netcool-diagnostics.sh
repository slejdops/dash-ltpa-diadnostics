#!/bin/bash

################################################################################
# Tivoli Netcool DASH, JazzSM and WebGUI Diagnostic Script
#
# Purpose: Diagnose system issues, collect logs, and identify configuration
#          problems related to LTPA tokens, user sessions, and GUI performance
#
# Usage: ./netcool-diagnostics.sh [options]
#
# Author: Generated for Netcool diagnostics
# Date: 2025-11-06
################################################################################

set -o pipefail

trap 'on_exit' INT TERM EXIT

on_exit() {
    if [ -n "$OUTPUT_DIR" ] && [ -d "$OUTPUT_DIR" ]; then
        if [ ! -f "${OUTPUT_DIR}/diagnosis_and_recommendations.txt" ]; then
            echo "Diagnostic interrupted at $(date)" > "${OUTPUT_DIR}/diagnosis_and_recommendations.txt"
        fi
    fi
}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Script configuration
SCRIPT_VERSION="2.0.0"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="netcool_diagnostics_${TIMESTAMP}"
LOG_FILE="${OUTPUT_DIR}/diagnostic_report.log"

# Default paths (can be overridden)
DASH_HOME="${DASH_HOME:-/opt/IBM/JazzSM/profile/bin}"
WEBGUI_HOME="${WEBGUI_HOME:-/opt/IBM/tivoli/netcool/webgui}"
JAZZSM_HOME="${JAZZSM_HOME:-/opt/IBM/JazzSM}"
WAS_HOME="${WAS_HOME:-/opt/IBM/WebSphere/AppServer}"

SEARCH_ROOT="/"

# Flags
VERBOSE=0
COLLECT_FULL_LOGS=0
SKIP_SENSITIVE=0

# Excluded directories (comma-separated list)
EXCLUDE_DIRS=""
# Common directories to exclude by default (can be overridden)
DEFAULT_EXCLUDES="/proc,/sys,/dev,/run,/tmp,/var/tmp,/boot,/mnt,/media"

LTPA_KEY_AGE_THRESHOLD_DAYS=365
SESSION_TIMEOUT_MIN=30
SESSION_TIMEOUT_MAX=240
MEMORY_USAGE_THRESHOLD=80
NTP_OFFSET_THRESHOLD_MS=500

################################################################################
# Utility Functions
################################################################################

print_banner() {
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════════╗
║      Tivoli Netcool DASH/JazzSM/WebGUI Diagnostic Tool           ║
║              LTPA Token & Performance Analyzer                    ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "Version: ${SCRIPT_VERSION}"
    echo -e "Timestamp: $(date)"
    echo -e "Output Directory: ${OUTPUT_DIR}"
    echo ""
}

log_message() {
    local level=$1
    shift
    local message="$*"

    case $level in
        INFO)
            echo -e "${GREEN}[INFO]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        SECTION)
            echo -e "\n${BLUE}${BOLD}[${message}]${NC}" | tee -a "$LOG_FILE"
            echo -e "${BLUE}$(printf '=%.0s' {1..70})${NC}" | tee -a "$LOG_FILE"
            ;;
        *)
            echo -e "$message" | tee -a "$LOG_FILE"
            ;;
    esac
}

create_output_dir() {
    if mkdir -p "${OUTPUT_DIR}"/{system_info,logs,config,performance,ltpa_analysis}; then
        log_message INFO "Created output directory: ${OUTPUT_DIR}"
    else
        log_message ERROR "Failed to create output directory"
        exit 1
    fi
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_message WARN "Script not running as root. Some checks may be limited."
        return 1
    fi
    return 0
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

safe_count_connections() {
    if command_exists netstat; then
        netstat -an 2>/dev/null | awk '/ESTABLISHED/{c++} END{print c+0}'
    elif command_exists ss; then
        ss -an 2>/dev/null | awk '/ESTAB/{c++} END{print c+0}'
    else
        echo "0"
    fi
}

redact_sensitive() {
    local input="$1"
    echo "$input" | sed -E 's/(password|passphrase|secret|token|apikey|bindDNPassword)[[:space:]]*=[[:space:]]*[^[:space:]]+/\1=****/gi'
}

run_find() {
    local search_path="$1"
    shift
    
    local exclude_list="${EXCLUDE_DIRS:-$DEFAULT_EXCLUDES}"

    if [ -z "$exclude_list" ]; then
        find "$search_path" "$@" 2>/dev/null
    else
        IFS=',' read -ra EXCLUDED_ARRAY <<< "$exclude_list"
        
        local find_args=()
        find_args+=("$search_path")
        
        if [ ${#EXCLUDED_ARRAY[@]} -gt 0 ]; then
            find_args+=("(")
            local first=1
            for dir in "${EXCLUDED_ARRAY[@]}"; do
                dir=$(echo "$dir" | xargs)
                if [ -n "$dir" ]; then
                    if [ $first -eq 1 ]; then
                        first=0
                    else
                        find_args+=("-o")
                    fi
                    find_args+=("-path" "$dir")
                fi
            done
            find_args+=(")" "-prune" "-o")
        fi
        
        find_args+=("$@")
        find_args+=("-print")
        
        find "${find_args[@]}" 2>/dev/null
    fi
}

################################################################################
# System Information Collection
################################################################################

check_time_synchronization() {
    log_message SECTION "TIME SYNCHRONIZATION CHECK"
    
    local time_sync_file="${OUTPUT_DIR}/system_info/time_synchronization.txt"
    
    {
        echo "=== Time Synchronization Status ==="
        echo "Current system time: $(date)"
        echo ""
        
        if command_exists timedatectl; then
            echo "=== timedatectl status ==="
            timedatectl status
            echo ""
            
            if timedatectl status | grep -q "System clock synchronized: yes"; then
                echo "✓ System clock is synchronized"
            else
                echo "✗ WARNING: System clock is NOT synchronized"
                echo "  This can cause LTPA token validation failures!"
            fi
            echo ""
        fi
        
        if command_exists ntpq; then
            echo "=== NTP Status (ntpq) ==="
            ntpq -p 2>/dev/null || echo "ntpq query failed"
            echo ""
            
            local offset=$(ntpq -c rv 2>/dev/null | grep -oP 'offset=\K[0-9.-]+' | head -1)
            if [ -n "$offset" ]; then
                local offset_abs=$(echo "$offset" | tr -d '-')
                echo "NTP offset: ${offset} ms"
                if (( $(echo "$offset_abs > $NTP_OFFSET_THRESHOLD_MS" | bc -l 2>/dev/null || echo 0) )); then
                    echo "⚠ WARNING: NTP offset exceeds threshold (${NTP_OFFSET_THRESHOLD_MS}ms)"
                fi
            fi
            echo ""
        elif command_exists chronyc; then
            echo "=== Chrony Status ==="
            chronyc tracking 2>/dev/null || echo "chronyc query failed"
            echo ""
        else
            echo "⚠ No NTP client detected (ntpq/chronyc not found)"
            echo "  Clock synchronization cannot be verified"
            echo "  RECOMMENDATION: Install and configure NTP or Chrony"
        fi
        
    } > "$time_sync_file"
    
    log_message INFO "Time synchronization check completed: $time_sync_file"
}

collect_system_info() {
    log_message SECTION "SYSTEM INFORMATION"

    local sys_info_file="${OUTPUT_DIR}/system_info/system_overview.txt"

    {
        echo "=== System Overview ==="
        echo "Hostname: $(hostname)"
        echo "Date/Time: $(date)"
        echo "Uptime: $(uptime)"
        echo ""

        echo "=== OS Information ==="
        uname -a
        if [ -f /etc/os-release ]; then
            cat /etc/os-release
        elif [ -f /etc/redhat-release ]; then
            cat /etc/redhat-release
        fi
        echo ""

        echo "=== CPU Information ==="
        lscpu 2>/dev/null || cat /proc/cpuinfo | grep "model name" | head -5
        echo ""

        echo "=== Memory Information ==="
        free -h
        echo ""

        echo "=== Disk Space ==="
        df -h
        echo ""

        echo "=== Network Interfaces ==="
        ip addr show 2>/dev/null || ifconfig
        echo ""

    } > "$sys_info_file"

    log_message INFO "System information collected: $sys_info_file"
}

################################################################################
# Process and Service Checks
################################################################################

check_processes() {
    log_message SECTION "PROCESS STATUS CHECKS"

    local process_file="${OUTPUT_DIR}/system_info/processes.txt"

    {
        echo "=== WebSphere Application Server Processes ==="
        ps aux | grep -i websphere | grep -v grep
        echo ""

        echo "=== DASH Processes ==="
        ps aux | grep -i dash | grep -v grep
        echo ""

        echo "=== JazzSM Processes ==="
        ps aux | grep -i jazz | grep -v grep
        echo ""

        echo "=== WebGUI Processes ==="
        ps aux | grep -i webgui | grep -v grep
        echo ""

        echo "=== Java Processes ==="
        ps aux | grep java | grep -v grep
        echo ""

    } > "$process_file"

    # Check for running WebSphere processes
    if ps aux | grep -i websphere | grep -v grep | grep -q java; then
        log_message INFO "WebSphere Application Server is running"
    else
        log_message WARN "WebSphere Application Server does not appear to be running"
    fi

    # Check listening ports
    local ports_file="${OUTPUT_DIR}/system_info/listening_ports.txt"
    {
        echo "=== Listening Ports ==="
        netstat -tuln 2>/dev/null || ss -tuln
        echo ""

        echo "=== WebSphere/Java Ports ==="
        netstat -tulnp 2>/dev/null | grep -i java || ss -tulnp 2>/dev/null | grep -i java
    } > "$ports_file"

    log_message INFO "Process information collected"
}

################################################################################
# LTPA Token Diagnostics
################################################################################

analyze_ltpa_configuration() {
    log_message SECTION "LTPA TOKEN CONFIGURATION ANALYSIS"

    local ltpa_report="${OUTPUT_DIR}/ltpa_analysis/ltpa_configuration.txt"

    {
        echo "=== LTPA Configuration Analysis ==="
        echo "Timestamp: $(date)"
        echo ""

        # Search for LTPA key files
        echo "=== Searching for LTPA Key Files ==="
        run_find / -name "ltpa.keys" -print || echo "No ltpa.keys files found"
        run_find / -name "*.ltpa" -print || echo "No .ltpa files found"
        echo ""

        # Search for security.xml files
        echo "=== Searching for security.xml Files ==="
        run_find / -name "security.xml" -print
        echo ""

    } > "$ltpa_report"

    # Analyze security.xml files for LTPA configuration
    local security_xml_files
    security_xml_files=$(run_find "$SEARCH_ROOT" -name "security.xml" -type f)

    if [ -n "$security_xml_files" ]; then
        echo "=== Analyzing security.xml Files for LTPA Configuration ===" >> "$ltpa_report"

        while IFS= read -r xml_file; do
            echo "" >> "$ltpa_report"
            echo "File: $xml_file" >> "$ltpa_report"
            echo "---" >> "$ltpa_report"

            # Check for LTPA configuration
            if grep -q "ltpa" "$xml_file" 2>/dev/null; then
                log_message INFO "Found LTPA configuration in: $xml_file"
                grep -A 10 -i "ltpa" "$xml_file" >> "$ltpa_report" 2>/dev/null

                # Copy the file for detailed analysis
                local base_name=$(basename "$xml_file")
                local dir_name=$(dirname "$xml_file" | tr '/' '_')
                cp "$xml_file" "${OUTPUT_DIR}/config/security_${dir_name}_${base_name}" 2>/dev/null
            fi
            echo "" >> "$ltpa_report"
        done <<< "$security_xml_files"
    else
        log_message WARN "No security.xml files found"
    fi

    # Check for SSO configuration
    echo "=== SSO Configuration ===" >> "$ltpa_report"
    run_find / -type f -name "*.xml" -exec grep -l "SingleSignOn\|SSO" {} \; | head -20 >> "$ltpa_report"
    echo "" >> "$ltpa_report"

    log_message INFO "LTPA configuration analysis completed"
}

analyze_ltpa_keys() {
    log_message SECTION "LTPA KEY FILE ANALYSIS"

    local ltpa_keys_report="${OUTPUT_DIR}/ltpa_analysis/ltpa_keys_analysis.txt"

    {
        echo "=== LTPA Key Files Analysis ==="
        echo ""

        local ltpa_files
        ltpa_files=$(run_find "$SEARCH_ROOT" \( -name "ltpa.keys" -o -name "*.ltpa" \) -type f)

        if [ -z "$ltpa_files" ]; then
            echo "WARNING: No LTPA key files found!"
            echo "This may indicate:"
            echo "  1. LTPA is not configured"
            echo "  2. Files are in a non-standard location"
            echo "  3. Insufficient permissions to access files"
        else
            declare -A checksum_groups
            local file_count=0
            
            while IFS= read -r ltpa_file; do
                ((file_count++))
                echo "=== File: $ltpa_file ==="
                
                local perms=$(stat -c 'Mode:%A (%a) Owner:%U:%G Size:%s Modified:%y' "$ltpa_file" 2>/dev/null)
                echo "$perms"

                if [ -r "$ltpa_file" ]; then
                    echo "Status: Readable"

                    if file "$ltpa_file" | grep -q "ASCII"; then
                        echo "Content Type: ASCII/Text (likely encrypted keys)"
                        
                        local checksum=$(sha256sum "$ltpa_file" 2>/dev/null | awk '{print $1}')
                        if [ -n "$checksum" ]; then
                            echo "SHA256 Checksum: $checksum"
                            
                            if [ -z "${checksum_groups[$checksum]}" ]; then
                                checksum_groups[$checksum]="$ltpa_file"
                            else
                                checksum_groups[$checksum]="${checksum_groups[$checksum]}|$ltpa_file"
                            fi
                        fi

                        if [ $SKIP_SENSITIVE -eq 0 ]; then
                            echo "Key entries found:"
                            grep -E "^com\.ibm\.websphere\.ltpa" "$ltpa_file" 2>/dev/null | cut -d= -f1

                            if grep -q "com.ibm.websphere.ltpa.version" "$ltpa_file"; then
                                echo "LTPA Version: $(grep 'com.ibm.websphere.ltpa.version' "$ltpa_file" | cut -d= -f2)"
                            fi

                            if grep -q "com.ibm.websphere.CreationDate" "$ltpa_file"; then
                                local creation_date=$(grep 'com.ibm.websphere.CreationDate' "$ltpa_file" | cut -d= -f2)
                                echo "Creation Date: $creation_date"
                                
                                local creation_epoch=$(date -d "$creation_date" +%s 2>/dev/null)
                                local current_epoch=$(date +%s)
                                if [ -n "$creation_epoch" ]; then
                                    local age_days=$(( (current_epoch - creation_epoch) / 86400 ))
                                    echo "Key Age: $age_days days"
                                    
                                    if [ $age_days -gt $LTPA_KEY_AGE_THRESHOLD_DAYS ]; then
                                        echo "⚠ WARNING: LTPA key is older than $LTPA_KEY_AGE_THRESHOLD_DAYS days"
                                        echo "  RECOMMENDATION: Consider rotating LTPA keys"
                                    fi
                                fi
                            fi

                            if grep -q "com.ibm.websphere.CreationHost" "$ltpa_file"; then
                                echo "Creation Host: $(grep 'com.ibm.websphere.CreationHost' "$ltpa_file" | cut -d= -f2)"
                            fi
                        fi
                    fi
                else
                    echo "Status: NOT Readable (permission denied)"
                fi

                echo ""
            done <<< "$ltpa_files"
            
            echo ""
            echo "=== LTPA Key Checksum Analysis ==="
            echo "Total LTPA key files found: $file_count"
            echo "Unique key groups: ${#checksum_groups[@]}"
            echo ""
            
            if [ ${#checksum_groups[@]} -gt 1 ]; then
                echo "✗ CRITICAL: Multiple different LTPA keys detected!"
                echo "  This will cause SSO failures when users move between servers"
                echo ""
                echo "Key groups by checksum:"
                local group_num=1
                for checksum in "${!checksum_groups[@]}"; do
                    echo "  Group $group_num (checksum: ${checksum:0:16}...):"
                    IFS='|' read -ra files <<< "${checksum_groups[$checksum]}"
                    for file in "${files[@]}"; do
                        echo "    - $file"
                    done
                    ((group_num++))
                    echo ""
                done
                echo "ACTION REQUIRED: Synchronize LTPA keys across all servers"
                echo "  1. Choose one key file as the master"
                echo "  2. Export from WebSphere Admin Console"
                echo "  3. Import to all other servers"
                echo "  4. Restart all servers"
            elif [ ${#checksum_groups[@]} -eq 1 ]; then
                echo "✓ All LTPA key files have matching checksums"
                echo "  Keys are properly synchronized across servers"
            fi
        fi

    } > "$ltpa_keys_report"

    log_message INFO "LTPA key file analysis completed"
}

check_ltpa_cookie_configuration() {
    log_message SECTION "LTPA COOKIE CONFIGURATION"

    local cookie_report="${OUTPUT_DIR}/ltpa_analysis/cookie_configuration.txt"

    {
        echo "=== LTPA Cookie Configuration Analysis ==="
        echo ""

        # Search for cookie configuration in various config files
        echo "=== Searching for Cookie Settings in Configuration Files ==="

        # WebSphere configuration
        run_find / -name "*.xml" -type f -print | while read -r config_file; do
            if grep -qi "cookie\|ltpatoken\|session" "$config_file" 2>/dev/null; then
                echo "File: $config_file"
                grep -i -A 5 -B 5 "ltpatoken\|sso.*cookie\|session.*cookie" "$config_file" 2>/dev/null | head -50
                echo "---"
            fi
        done

        echo ""
        echo "=== JVM Properties Related to Cookies ==="
        run_find / -name "*.properties" -type f -print | while read -r prop_file; do
            if grep -qi "cookie\|ltpa\|session" "$prop_file" 2>/dev/null; then
                echo "File: $prop_file"
                grep -i "cookie\|ltpa\|session" "$prop_file" 2>/dev/null
                echo "---"
            fi
        done

    } > "$cookie_report"

    log_message INFO "Cookie configuration analysis completed"
}

################################################################################
# Session Management Analysis
################################################################################

analyze_session_management() {
    log_message SECTION "SESSION MANAGEMENT ANALYSIS"

    local session_report="${OUTPUT_DIR}/ltpa_analysis/session_management.txt"

    {
        echo "=== Session Management Configuration ==="
        echo ""

        declare -A session_timeouts
        
        echo "=== Session Configuration Files ==="
        run_find "$SEARCH_ROOT" \( -name "web.xml" -o -name "ibm-web-ext.xml" \) -type f | while read -r web_xml; do
            if [ -f "$web_xml" ]; then
                echo "File: $web_xml"
                if grep -qi "session" "$web_xml" 2>/dev/null; then
                    grep -i -A 10 -B 2 "session-config\|session-timeout\|session-management" "$web_xml" 2>/dev/null
                    
                    local timeout=$(grep -oP '<session-timeout>\K[0-9]+' "$web_xml" 2>/dev/null | head -1)
                    if [ -n "$timeout" ]; then
                        echo "  → Session timeout detected: $timeout minutes"
                        
                        if [ $timeout -lt $SESSION_TIMEOUT_MIN ]; then
                            echo "  ⚠ WARNING: Session timeout ($timeout min) is below recommended minimum ($SESSION_TIMEOUT_MIN min)"
                            echo "    This may cause frequent user logouts"
                        elif [ $timeout -gt $SESSION_TIMEOUT_MAX ]; then
                            echo "  ⚠ WARNING: Session timeout ($timeout min) exceeds recommended maximum ($SESSION_TIMEOUT_MAX min)"
                            echo "    This may pose security risks"
                        else
                            echo "  ✓ Session timeout is within acceptable range"
                        fi
                    fi
                fi
                echo "---"
                echo ""
            fi
        done

        echo "=== Session Manager Configuration in server.xml/resources.xml ==="
        run_find "$SEARCH_ROOT" \( -name "server.xml" -o -name "resources.xml" \) -type f | while read -r xml_file; do
            if [ -f "$xml_file" ]; then
                echo "File: $xml_file"
                if grep -qi "sessionmanager\|sessiondatabase" "$xml_file" 2>/dev/null; then
                    grep -i -A 10 -B 2 "sessionmanager\|sessiondatabase\|session.*persistence" "$xml_file" 2>/dev/null
                    
                    if grep -qi "enable.*database.*persistence.*true" "$xml_file" 2>/dev/null; then
                        echo "  ✓ Database persistence is enabled"
                    fi
                fi
                echo "---"
                echo ""
            fi
        done

        echo "=== WebSphere Session Properties ==="
        run_find "$SEARCH_ROOT" -name "*.properties" -type f | while read -r prop_file; do
            if grep -qi "session" "$prop_file" 2>/dev/null; then
                echo "File: $prop_file"
                grep -i "session" "$prop_file" 2>/dev/null | head -20
                echo "---"
            fi
        done

    } > "$session_report"

    log_message INFO "Session management analysis completed"
}

################################################################################
# Performance Analysis
################################################################################

analyze_performance() {
    log_message SECTION "PERFORMANCE ANALYSIS"

    local perf_report="${OUTPUT_DIR}/performance/performance_metrics.txt"

    {
        echo "=== System Performance Metrics ==="
        echo "Timestamp: $(date)"
        echo ""

        echo "=== CPU Usage ==="
        top -b -n 1 | head -20
        echo ""

        echo "=== Memory Usage Details ==="
        free -m
        echo ""
        cat /proc/meminfo | grep -E "MemTotal|MemFree|MemAvailable|Cached|SwapTotal|SwapFree"
        echo ""

        echo "=== Disk I/O Statistics ==="
        if command_exists iostat; then
            iostat -x 1 2
        else
            echo "iostat not available"
        fi
        echo ""

        echo "=== Network Statistics ==="
        if command_exists netstat; then
            netstat -s | head -50
        fi
        echo ""

        echo "=== Java Process Memory Usage ==="
        ps aux | grep java | grep -v grep | awk '{print $2, $3, $4, $6, $11}' | while read pid cpu mem vsz cmd; do
            echo "PID: $pid"
            echo "CPU: ${cpu}%"
            echo "MEM: ${mem}%"
            echo "VSZ: ${vsz} KB"
            echo "CMD: $cmd"

            # Get heap information if possible
            if command_exists jstat && [ -n "$pid" ]; then
                echo "Heap Usage:"
                jstat -gc $pid 2>/dev/null | tail -1
            fi
            echo "---"
        done
        echo ""

        echo "=== Open Files and Connections ==="
        lsof -i -n 2>/dev/null | grep -i java | head -50 || echo "lsof not available or insufficient permissions"
        echo ""

        echo "=== Active Network Connections Count ==="
        echo "Established connections: $(safe_count_connections)"
        echo ""

    } > "$perf_report"

    log_message INFO "Performance metrics collected"
}

check_webgui_performance() {
    log_message SECTION "WEBGUI PERFORMANCE CHECKS"

    local webgui_perf="${OUTPUT_DIR}/performance/webgui_performance.txt"

    {
        echo "=== WebGUI Performance Configuration ==="
        echo ""

        # Check WebGUI properties
        if [ -d "$WEBGUI_HOME" ]; then
            echo "WebGUI Home: $WEBGUI_HOME"
            echo ""

            # Look for performance-related properties
            find "$WEBGUI_HOME" -name "*.properties" 2>/dev/null | while read -r prop_file; do
                echo "File: $prop_file"
                grep -i -E "cache|thread|pool|timeout|performance|memory" "$prop_file" 2>/dev/null
                echo "---"
            done
        else
            echo "WebGUI Home directory not found: $WEBGUI_HOME"
        fi

        echo ""
        echo "=== Checking for WebGUI Cache Configuration ==="
        run_find / \( -name "*cache*.xml" -o -name "*cache*.properties" \) -print | head -20

    } > "$webgui_perf"

    log_message INFO "WebGUI performance check completed"
}

################################################################################
# Log Collection
################################################################################

collect_logs() {
    log_message SECTION "LOG COLLECTION"

    local logs_summary="${OUTPUT_DIR}/logs/logs_summary.txt"

    {
        echo "=== Log Files Collection Summary ==="
        echo "Timestamp: $(date)"
        echo ""
    } > "$logs_summary"

    if [ -d "${WAS_HOME}/profiles" ]; then
        log_message INFO "Collecting WebSphere logs..."

        find "${WAS_HOME}/profiles" -type f \( -name "SystemOut.log" -o -name "SystemErr.log" \) 2>/dev/null | while read -r log_path; do
            echo "Found: $log_path" >> "$logs_summary"

            if [ $COLLECT_FULL_LOGS -eq 1 ]; then
                cp "$log_path" "${OUTPUT_DIR}/logs/" 2>/dev/null
            else
                tail -1000 "$log_path" > "${OUTPUT_DIR}/logs/$(basename "$log_path").tail" 2>/dev/null
            fi
        done
        
        find "${WAS_HOME}/profiles" -type d -name "ffdc" 2>/dev/null | while read -r ffdc_dir; do
            echo "Found FFDC directory: $ffdc_dir" >> "$logs_summary"
            local ffdc_basename=$(basename "$(dirname "$ffdc_dir")")_ffdc
            
            if [ $COLLECT_FULL_LOGS -eq 1 ]; then
                cp -r "$ffdc_dir" "${OUTPUT_DIR}/logs/${ffdc_basename}" 2>/dev/null
            else
                mkdir -p "${OUTPUT_DIR}/logs/${ffdc_basename}" 2>/dev/null
                find "$ffdc_dir" -type f -name "*.log" -o -name "*.txt" 2>/dev/null | head -10 | while read -r ffdc_file; do
                    tail -500 "$ffdc_file" > "${OUTPUT_DIR}/logs/${ffdc_basename}/$(basename "$ffdc_file").tail" 2>/dev/null
                done
            fi
        done
    fi

    if [ -d "${JAZZSM_HOME}" ]; then
        log_message INFO "Collecting JazzSM logs..."

        find "${JAZZSM_HOME}" -type f -name "*.log" 2>/dev/null | head -20 | while read -r log_path; do
            echo "Found: $log_path" >> "$logs_summary"

            if [ $COLLECT_FULL_LOGS -eq 1 ]; then
                cp "$log_path" "${OUTPUT_DIR}/logs/" 2>/dev/null
            else
                tail -1000 "$log_path" > "${OUTPUT_DIR}/logs/$(basename "$log_path").tail" 2>/dev/null
            fi
        done
    fi

    if [ -d "${DASH_HOME}" ]; then
        log_message INFO "Collecting DASH logs..."

        find "${DASH_HOME}" -type f -name "*.log" 2>/dev/null | head -20 | while read -r log_path; do
            echo "Found: $log_path" >> "$logs_summary"

            if [ $COLLECT_FULL_LOGS -eq 1 ]; then
                cp "$log_path" "${OUTPUT_DIR}/logs/" 2>/dev/null
            else
                tail -1000 "$log_path" > "${OUTPUT_DIR}/logs/$(basename "$log_path").tail" 2>/dev/null
            fi
        done
    fi

    if [ -d "${WEBGUI_HOME}" ]; then
        log_message INFO "Collecting WebGUI logs..."

        find "${WEBGUI_HOME}" -type f -name "*.log" 2>/dev/null | head -20 | while read -r log_path; do
            echo "Found: $log_path" >> "$logs_summary"

            if [ $COLLECT_FULL_LOGS -eq 1 ]; then
                cp "$log_path" "${OUTPUT_DIR}/logs/" 2>/dev/null
            else
                tail -1000 "$log_path" > "${OUTPUT_DIR}/logs/$(basename "$log_path").tail" 2>/dev/null
            fi
        done
    fi

    log_message INFO "Log collection completed. See: $logs_summary"
}

analyze_logs_for_errors() {
    log_message SECTION "LOG ERROR ANALYSIS"

    local error_report="${OUTPUT_DIR}/logs/error_analysis.txt"

    {
        echo "=== Log Error Analysis ==="
        echo "Analyzing logs for LTPA, session, and performance issues"
        echo ""

        # Search for LTPA-related errors
        echo "=== LTPA Token Errors ==="
        find "${OUTPUT_DIR}/logs" -type f -name "*.log*" -exec grep -i -H -n "ltpa\|ltpatoken" {} \; 2>/dev/null | head -100
        echo ""

        # Search for session errors
        echo "=== Session-Related Errors ==="
        find "${OUTPUT_DIR}/logs" -type f -name "*.log*" -exec grep -i -H -n "session.*error\|session.*exception\|session.*timeout" {} \; 2>/dev/null | head -100
        echo ""

        # Search for SSO errors
        echo "=== SSO Errors ==="
        find "${OUTPUT_DIR}/logs" -type f -name "*.log*" -exec grep -i -H -n "sso.*error\|sso.*fail\|single.*sign.*on" {} \; 2>/dev/null | head -100
        echo ""

        # Search for authentication errors
        echo "=== Authentication Errors ==="
        find "${OUTPUT_DIR}/logs" -type f -name "*.log*" -exec grep -i -H -n "authentication.*fail\|auth.*error\|login.*fail" {} \; 2>/dev/null | head -100
        echo ""

        # Search for performance-related warnings/errors
        echo "=== Performance Issues ==="
        find "${OUTPUT_DIR}/logs" -type f -name "*.log*" -exec grep -i -H -n "slow\|timeout\|outofmemory\|heap.*space\|thread.*pool" {} \; 2>/dev/null | head -100
        echo ""

        # Search for cookie-related issues
        echo "=== Cookie Issues ==="
        find "${OUTPUT_DIR}/logs" -type f -name "*.log*" -exec grep -i -H -n "cookie.*error\|cookie.*invalid\|cookie.*expire" {} \; 2>/dev/null | head -100
        echo ""

    } > "$error_report"

    log_message INFO "Log error analysis completed"
}

################################################################################
# Configuration Collection
################################################################################

collect_configurations() {
    log_message SECTION "CONFIGURATION FILES COLLECTION"

    # Collect important configuration files
    local configs=(
        "server.xml"
        "security.xml"
        "resources.xml"
        "web.xml"
        "ibm-web-ext.xml"
        "plugin-cfg.xml"
        "httpd.conf"
        "ssl.conf"
    )

    for config in "${configs[@]}"; do
        local found_files=$(run_find / -name "$config" -print | head -10)

        if [ ! -z "$found_files" ]; then
            while IFS= read -r config_path; do
                local safe_name=$(echo "$config_path" | tr '/' '_')
                cp "$config_path" "${OUTPUT_DIR}/config/${safe_name}" 2>/dev/null
                log_message INFO "Collected: $config_path"
            done <<< "$found_files"
        fi
    done
}

################################################################################
# Diagnosis and Recommendations
################################################################################

generate_diagnosis() {
    log_message SECTION "DIAGNOSIS AND RECOMMENDATIONS"

    local diagnosis_report="${OUTPUT_DIR}/diagnosis_and_recommendations.txt"

    {
        echo "╔═══════════════════════════════════════════════════════════════╗"
        echo "║       TIVOLI NETCOOL DIAGNOSTIC REPORT                       ║"
        echo "║       LTPA Token, Session & Performance Analysis             ║"
        echo "╚═══════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Generated: $(date)"
        echo ""

        echo "=== SUMMARY OF FINDINGS ==="
        echo ""

        # Check for LTPA keys
        local ltpa_keys_found=$(run_find / \( -name "ltpa.keys" -o -name "*.ltpa" \) -print | wc -l)
        echo "1. LTPA Configuration:"
        if [ $ltpa_keys_found -gt 0 ]; then
            echo "   ✓ Found $ltpa_keys_found LTPA key file(s)"
            echo "   → Review: ${OUTPUT_DIR}/ltpa_analysis/ltpa_keys_analysis.txt"
        else
            echo "   ✗ No LTPA key files found"
            echo "   → ISSUE: LTPA may not be properly configured"
            echo "   → ACTION REQUIRED: Configure LTPA tokens for SSO"
        fi
        echo ""

        # Check for running processes
        echo "2. Service Status:"
        if ps aux | grep -i websphere | grep -v grep | grep -q java; then
            echo "   ✓ WebSphere Application Server is running"
        else
            echo "   ✗ WebSphere Application Server not detected"
            echo "   → ACTION: Start WebSphere services"
        fi
        echo ""

        # Check memory
        local mem_usage=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
        echo "3. System Resources:"
        echo "   Memory Usage: ${mem_usage}%"
        if [ $mem_usage -gt 80 ]; then
            echo "   ⚠ High memory usage detected"
            echo "   → RECOMMENDATION: Investigate memory leaks or increase system memory"
        else
            echo "   ✓ Memory usage within acceptable range"
        fi
        echo ""

        echo "4. Log Analysis:"
        echo "   → Check error analysis: ${OUTPUT_DIR}/logs/error_analysis.txt"
        echo "   → Review system logs for LTPA, session, and authentication errors"
        echo ""

        echo "=== COMMON LTPA TOKEN ISSUES AND SOLUTIONS ==="
        echo ""
        echo "Issue 1: LTPA Token Expiration"
        echo "  Symptoms: Users being logged out unexpectedly"
        echo "  Solution: Check LTPA timeout settings in security.xml"
        echo "           Default is 120 minutes, adjust if needed"
        echo ""
        echo "Issue 2: LTPA Key Mismatch Across Servers"
        echo "  Symptoms: SSO not working between different servers"
        echo "  Solution: Ensure all servers share the same ltpa.keys file"
        echo "           Keys must be synchronized across the cluster"
        echo ""
        echo "Issue 3: Cookie Domain/Path Issues"
        echo "  Symptoms: LTPA token not being sent/received properly"
        echo "  Solution: Verify cookie domain settings in WebSphere"
        echo "           Check browser compatibility and cookie settings"
        echo ""
        echo "Issue 4: Clock Synchronization"
        echo "  Symptoms: LTPA token validation failures"
        echo "  Solution: Ensure all servers have synchronized clocks (NTP)"
        echo "           Time skew can cause token validation to fail"
        echo ""

        echo "=== SESSION MANAGEMENT RECOMMENDATIONS ==="
        echo ""
        echo "1. Session Persistence:"
        echo "   - Review session database configuration"
        echo "   - Consider enabling session replication for HA"
        echo ""
        echo "2. Session Timeout:"
        echo "   - Check session timeout values in web.xml"
        echo "   - Balance security vs. user experience"
        echo ""
        echo "3. Session Affinity:"
        echo "   - Verify load balancer session affinity settings"
        echo "   - Ensure sticky sessions are properly configured"
        echo ""

        echo "=== PERFORMANCE OPTIMIZATION RECOMMENDATIONS ==="
        echo ""
        echo "1. JVM Tuning:"
        echo "   - Review heap size settings"
        echo "   - Check for OutOfMemory errors in logs"
        echo "   - Consider adjusting garbage collection settings"
        echo ""
        echo "2. Connection Pooling:"
        echo "   - Verify database connection pool sizes"
        echo "   - Check for connection timeout issues"
        echo ""
        echo "3. Caching:"
        echo "   - Enable caching where appropriate"
        echo "   - Review cache configuration for WebGUI components"
        echo ""
        echo "4. Thread Pools:"
        echo "   - Review WebContainer thread pool settings"
        echo "   - Adjust based on concurrent user load"
        echo ""

        echo "=== NEXT STEPS ==="
        echo ""
        echo "1. Review all analysis files in: ${OUTPUT_DIR}/"
        echo "2. Check LTPA configuration: ${OUTPUT_DIR}/ltpa_analysis/"
        echo "3. Analyze error logs: ${OUTPUT_DIR}/logs/error_analysis.txt"
        echo "4. Review performance metrics: ${OUTPUT_DIR}/performance/"
        echo "5. Verify configuration files: ${OUTPUT_DIR}/config/"
        echo ""
        echo "For detailed IBM WebSphere and JazzSM documentation:"
        echo "- IBM Knowledge Center: https://www.ibm.com/docs/"
        echo "- WebSphere troubleshooting guides"
        echo "- JazzSM administration documentation"
        echo ""

    } > "$diagnosis_report"

    # Display summary to console
    cat "$diagnosis_report"
}

################################################################################
# Main Execution
################################################################################

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Tivoli Netcool DASH, JazzSM and WebGUI Diagnostic Script

OPTIONS:
    -h, --help                  Show this help message
    -v, --verbose               Enable verbose output
    -f, --full-logs             Collect full log files (default: last 1000 lines)
    -s, --skip-sensitive        Skip collecting sensitive information (enables redaction)
    --output-dir PATH           Set custom output directory (default: netcool_diagnostics_<timestamp>)
    --root PATH                 Limit filesystem search to specific root path (default: /)
    --exclude-dirs DIRS         Comma-separated list of directories to exclude from scanning
                                (default: $DEFAULT_EXCLUDES)
    --no-default-excludes       Don't use default directory exclusions
    --dash-home PATH            Set DASH home directory (default: $DASH_HOME)
    --webgui-home PATH          Set WebGUI home directory (default: $WEBGUI_HOME)
    --jazzsm-home PATH          Set JazzSM home directory (default: $JAZZSM_HOME)
    --was-home PATH             Set WebSphere home directory (default: $WAS_HOME)

EXAMPLES:
    $0
    $0 --verbose --full-logs
    $0 --was-home /opt/IBM/WebSphere/AppServer
    $0 --exclude-dirs "/backup,/archive,/home"
    $0 --root /opt/IBM --output-dir /tmp/diagnostics
    $0 --exclude-dirs "/large-dir" --no-default-excludes

OUTPUT:
    Results will be saved to: netcool_diagnostics_<timestamp>/
    Or custom directory specified with --output-dir

FOCUS AREAS:
    - LTPA Token configuration and issues (with checksum analysis)
    - User session management (with timeout policy checks)
    - GUI performance analysis
    - System resource utilization
    - Time synchronization (NTP/Chrony)
    - Log analysis for errors and warnings

NOTES:
    By default, the following directories are excluded: $DEFAULT_EXCLUDES
    Use --exclude-dirs to add additional exclusions or --no-default-excludes to scan everything.
    Use --root to limit scanning to a specific directory for faster diagnostics or testing.

EOF
}

parse_arguments() {
    EXCLUDE_DIRS="$DEFAULT_EXCLUDES"

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -f|--full-logs)
                COLLECT_FULL_LOGS=1
                shift
                ;;
            -s|--skip-sensitive)
                SKIP_SENSITIVE=1
                shift
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                LOG_FILE="${OUTPUT_DIR}/diagnostic_report.log"
                shift 2
                ;;
            --root)
                SEARCH_ROOT="$2"
                shift 2
                ;;
            --exclude-dirs)
                if [ -z "$EXCLUDE_DIRS" ]; then
                    EXCLUDE_DIRS="$2"
                else
                    EXCLUDE_DIRS="$EXCLUDE_DIRS,$2"
                fi
                shift 2
                ;;
            --no-default-excludes)
                EXCLUDE_DIRS=""
                shift
                ;;
            --dash-home)
                DASH_HOME="$2"
                shift 2
                ;;
            --webgui-home)
                WEBGUI_HOME="$2"
                shift 2
                ;;
            --jazzsm-home)
                JAZZSM_HOME="$2"
                shift 2
                ;;
            --was-home)
                WAS_HOME="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    if [ $VERBOSE -eq 1 ]; then
        [ -n "$EXCLUDE_DIRS" ] && echo "Excluding directories: $EXCLUDE_DIRS"
        [ "$SEARCH_ROOT" != "/" ] && echo "Search root limited to: $SEARCH_ROOT"
    fi
}

main() {
    print_banner

    parse_arguments "$@"

    create_output_dir

    check_root

    collect_system_info
    check_time_synchronization
    check_processes

    analyze_ltpa_configuration
    analyze_ltpa_keys
    check_ltpa_cookie_configuration

    analyze_session_management

    analyze_performance
    check_webgui_performance

    collect_logs
    analyze_logs_for_errors

    collect_configurations

    generate_diagnosis

    echo ""
    log_message INFO "Diagnostic collection completed!"
    log_message INFO "Results saved to: ${OUTPUT_DIR}"
    log_message INFO "Main report: ${OUTPUT_DIR}/diagnosis_and_recommendations.txt"
    echo ""

    log_message INFO "Creating archive..."
    tar -czf "${OUTPUT_DIR}.tar.gz" "${OUTPUT_DIR}" 2>/dev/null
    if [ $? -eq 0 ]; then
        log_message INFO "Archive created: ${OUTPUT_DIR}.tar.gz"
    fi

    echo -e "${GREEN}${BOLD}Diagnostic script completed successfully!${NC}"
}

# Run main function
main "$@"
