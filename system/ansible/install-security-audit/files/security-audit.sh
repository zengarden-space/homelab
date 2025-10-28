#!/bin/bash
#
# Security Audit Script for Homelab Blade Servers
# Performs comprehensive security checks to detect potential breaches
#
# Usage: ./security-audit.sh [--verbose] [--json]
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
VERBOSE=0
JSON_OUTPUT=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        --json)
            JSON_OUTPUT=1
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--verbose] [--json]"
            echo "  --verbose, -v  Show detailed output"
            echo "  --json         Output results in JSON format"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Global status
OVERALL_STATUS="SECURE"
ISSUES=0
WARNINGS=0

# Output functions
log_info() {
    if [[ $JSON_OUTPUT -eq 0 ]]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

log_success() {
    if [[ $JSON_OUTPUT -eq 0 ]]; then
        echo -e "${GREEN}[✓]${NC} $1"
    fi
}

log_warning() {
    if [[ $JSON_OUTPUT -eq 0 ]]; then
        echo -e "${YELLOW}[WARNING]${NC} $1"
    fi
    WARNINGS=$((WARNINGS + 1))
}

log_critical() {
    if [[ $JSON_OUTPUT -eq 0 ]]; then
        echo -e "${RED}[CRITICAL]${NC} $1"
    fi
    ISSUES=$((ISSUES + 1))
    OVERALL_STATUS="COMPROMISED"
}

log_section() {
    if [[ $JSON_OUTPUT -eq 0 ]]; then
        echo ""
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}$1${NC}"
        echo -e "${BLUE}========================================${NC}"
    fi
}

# JSON output array
declare -a JSON_RESULTS=()

add_json_result() {
    local category="$1"
    local status="$2"
    local message="$3"
    JSON_RESULTS+=("{\"category\":\"$category\",\"status\":\"$status\",\"message\":\"$message\"}")
}

# Check 1: Authentication logs
check_authentication() {
    log_section "1. Authentication Analysis"

    local failed_logins=$(sudo journalctl -u ssh --since yesterday --no-pager 2>/dev/null | grep -c "Failed password" | tr -d ' \n' || echo 0)
    local invalid_users=$(sudo journalctl -u ssh --since yesterday --no-pager 2>/dev/null | grep -c "Invalid user" | tr -d ' \n' || echo 0)

    if [[ $failed_logins -gt 10 ]]; then
        log_critical "High number of failed login attempts: $failed_logins in last 24h"
        add_json_result "authentication" "critical" "High failed login attempts: $failed_logins"
    elif [[ $failed_logins -gt 0 ]]; then
        log_warning "Failed login attempts detected: $failed_logins in last 24h"
        add_json_result "authentication" "warning" "Failed login attempts: $failed_logins"
    else
        log_success "No failed login attempts in last 24 hours"
        add_json_result "authentication" "ok" "No failed logins"
    fi

    if [[ $invalid_users -gt 5 ]]; then
        log_critical "Multiple invalid user login attempts: $invalid_users"
        add_json_result "authentication" "critical" "Invalid user attempts: $invalid_users"
    elif [[ $invalid_users -gt 0 ]]; then
        log_warning "Invalid user login attempts: $invalid_users"
        add_json_result "authentication" "warning" "Invalid user attempts: $invalid_users"
    fi

    # Check for successful logins
    if [[ $VERBOSE -eq 1 ]]; then
        log_info "Recent successful logins:"
        sudo journalctl -u ssh --since yesterday --no-pager 2>/dev/null | grep "Accepted publickey" | tail -5 || echo "  None"
    fi

    # Check currently logged in users
    local logged_in=$(who | wc -l | tr -d ' \n')
    log_info "Currently logged in users: $logged_in"
    if [[ $VERBOSE -eq 1 ]]; then
        who
    fi
}

# Check 2: User accounts
check_user_accounts() {
    log_section "2. User Account Analysis"

    # Check for users with shell access
    local shell_users=$(grep -E "bash|sh$" /etc/passwd | grep -v "nologin" | cut -d: -f1)
    log_info "Users with shell access:"
    echo "$shell_users" | while read user; do
        if [[ $VERBOSE -eq 1 ]] || [[ "$user" != "root" ]] && [[ "$user" != "oleksiyp" ]] && [[ "$user" != "ansible" ]]; then
            log_info "  - $user"
        fi
    done

    # Check for new users (created in last 7 days)
    log_info "Checking for recently added users..."
    local new_users=0
    while IFS=: read -r username _ uid _ _ _ _; do
        if [[ $uid -ge 1000 ]] && [[ $uid -lt 60000 ]]; then
            local user_created=$(sudo stat -c %Y /home/$username 2>/dev/null || echo 0)
            local week_ago=$(($(date +%s) - 604800))
            if [[ $user_created -gt $week_ago ]]; then
                log_warning "Recently created user: $username"
                add_json_result "users" "warning" "New user: $username"
                new_users=$((new_users + 1))
            fi
        fi
    done < /etc/passwd

    if [[ $new_users -eq 0 ]]; then
        log_success "No recently added users"
        add_json_result "users" "ok" "No new users"
    fi

    # Check for users with UID 0 (root privileges)
    local root_users=$(awk -F: '$3 == 0 {print $1}' /etc/passwd)
    if [[ "$root_users" != "root" ]]; then
        log_critical "Multiple users with UID 0: $root_users"
        add_json_result "users" "critical" "Multiple UID 0 users: $root_users"
    else
        log_success "Only root has UID 0"
        add_json_result "users" "ok" "Single root user"
    fi
}

# Check 3: SSH keys
check_ssh_keys() {
    log_section "3. SSH Key Analysis"

    # Check authorized_keys for all users
    for home_dir in /root /home/*; do
        if [[ -d "$home_dir/.ssh" ]]; then
            local user=$(basename "$home_dir")
            local auth_keys="$home_dir/.ssh/authorized_keys"

            if [[ -f "$auth_keys" ]]; then
                local key_count=$(grep -c "^ssh-" "$auth_keys" 2>/dev/null | tr -d ' \n' || echo 0)
                log_info "User $user has $key_count authorized SSH key(s)"

                if [[ $VERBOSE -eq 1 ]]; then
                    sudo grep "^ssh-" "$auth_keys" 2>/dev/null | while read key; do
                        echo "  ${key: -50}"
                    done
                fi
            fi
        fi
    done

    log_success "SSH key check completed"
    add_json_result "ssh_keys" "ok" "SSH keys reviewed"
}

# Check 4: Network connections
check_network() {
    log_section "4. Network Analysis"

    # Check for suspicious listening ports
    log_info "Checking listening ports..."
    local suspicious_ports=0

    # Known good ports for K3s cluster
    local known_ports="22 53 2379 2380 2381 2382 2601 2605 2616 2617 2623 4240 4244 5001 5555 6443 6444 7472 7473 7946 9878 9879 9890 9964 10010 10248 10249 10250 10256 10257 10258 10259"

    if [[ $VERBOSE -eq 1 ]]; then
        sudo ss -tulpn | grep LISTEN | head -20
    fi

    # Check for established connections to external IPs (non-RFC1918)
    log_info "Checking external connections..."
    local external_conn=$(sudo ss -tunp state established 2>/dev/null | grep -v "127.0.0" | grep -v "192.168" | grep -v "10\." | grep -v "Address:Port" | wc -l | tr -d ' \n' || echo 0)

    if [[ $external_conn -gt 50 ]]; then
        log_warning "High number of external connections: $external_conn"
        add_json_result "network" "warning" "Many external connections: $external_conn"
    else
        log_success "External connections: $external_conn (normal)"
        add_json_result "network" "ok" "Normal connection count"
    fi
}

# Check 5: Running processes
check_processes() {
    log_section "5. Process Analysis"

    # Check for suspicious process names
    # Look for known malicious patterns, excluding legitimate system processes
    local suspicious_procs=$(ps aux | grep -iE "\b(nc|netcat|ncat)\b.*-[el]|backdoor|cryptominer|xmrig|mirai|botnet" | grep -v grep | wc -l | tr -d ' \n' || echo 0)

    if [[ $suspicious_procs -gt 0 ]]; then
        log_critical "Suspicious processes detected!"
        ps aux | grep -iE "\b(nc|netcat|ncat)\b.*-[el]|backdoor|cryptominer|xmrig|mirai|botnet" | grep -v grep
        add_json_result "processes" "critical" "Suspicious processes found"
    else
        log_success "No suspicious processes detected"
        add_json_result "processes" "ok" "All processes normal"
    fi

    # Check for processes running executables from /tmp or /dev/shm
    log_info "Checking for suspicious temp file execution..."
    local tmp_execs=$(sudo lsof +D /tmp 2>/dev/null | grep -E "\.sh$|\.exe$|\.bin$|\.elf$" | wc -l | tr -d ' \n' || echo 0)

    if [[ $tmp_execs -gt 0 ]]; then
        log_warning "Suspicious executables in /tmp: $tmp_execs"
        add_json_result "processes" "warning" "Temp executables: $tmp_execs"
    fi
}

# Check 6: Cron jobs
check_cron() {
    log_section "6. Scheduled Tasks Analysis"

    # Check root crontab
    if sudo crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" > /dev/null; then
        log_warning "Root has custom cron jobs"
        add_json_result "cron" "warning" "Root crontab exists"
        if [[ $VERBOSE -eq 1 ]]; then
            sudo crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$"
        fi
    else
        log_success "No root crontab"
        add_json_result "cron" "ok" "No root crontab"
    fi

    # Check user crontabs
    local user_crons=0
    for user in $(cut -f1 -d: /etc/passwd); do
        if sudo crontab -u "$user" -l 2>/dev/null | grep -v "^#" | grep -v "^$" > /dev/null; then
            log_info "User $user has cron jobs"
            user_crons=$((user_crons + 1))
        fi
    done

    if [[ $user_crons -eq 0 ]]; then
        log_success "No user crontabs configured"
    fi

    # Check /etc/cron.d for suspicious entries
    if [[ -d /etc/cron.d ]]; then
        local cron_d_files=$(find /etc/cron.d -type f 2>/dev/null | wc -l | tr -d ' \n')
        log_info "Files in /etc/cron.d: $cron_d_files"
    fi
}

# Check 7: File integrity
check_file_integrity() {
    log_section "7. File Integrity Check"

    # Check for recently modified files in sensitive locations
    log_info "Checking for recently modified system files..."

    local modified_passwd=$(find /etc/passwd /etc/shadow /etc/group -mtime -7 2>/dev/null | wc -l | tr -d ' \n')
    if [[ $modified_passwd -gt 0 ]]; then
        log_warning "User/password files modified in last 7 days"
        add_json_result "files" "warning" "System files recently modified"
    else
        log_success "No recent modifications to user/password files"
        add_json_result "files" "ok" "No suspicious modifications"
    fi

    # Check for SUID/SGID files
    if [[ $VERBOSE -eq 1 ]]; then
        log_info "Checking for SUID/SGID files in uncommon locations..."
        local suid_count=$(find /home /tmp /var/tmp -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | wc -l | tr -d ' \n')
        if [[ $suid_count -gt 0 ]]; then
            log_warning "SUID/SGID files in unusual locations: $suid_count"
            find /home /tmp /var/tmp -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | head -10
        fi
    fi

    # Check for hidden files in /tmp
    local hidden_tmp=$(find /tmp -name ".*" -type f 2>/dev/null | wc -l | tr -d ' \n')
    if [[ $hidden_tmp -gt 5 ]]; then
        log_warning "Multiple hidden files in /tmp: $hidden_tmp"
        add_json_result "files" "warning" "Hidden files in /tmp: $hidden_tmp"
    fi
}

# Check 8: System logs
check_system_logs() {
    log_section "8. System Log Analysis"

    # Check for security-related keywords
    local security_keywords="breach|attack|exploit|malware|rootkit|backdoor"
    local security_hits=$(sudo journalctl --since yesterday --no-pager 2>/dev/null | grep -icE "$security_keywords" | tr -d ' \n' || echo 0)

    # Exclude restrictive-proxy UNAUTHORIZED (expected)
    local filtered_hits=$(sudo journalctl --since yesterday --no-pager 2>/dev/null | grep -iE "$security_keywords" | grep -v "restrictive-proxy.*UNAUTHORIZED" | wc -l | tr -d ' \n' || echo 0)

    if [[ $filtered_hits -gt 0 ]]; then
        log_critical "Security-related keywords found in logs: $filtered_hits"
        add_json_result "logs" "critical" "Security keywords in logs"
        if [[ $VERBOSE -eq 1 ]]; then
            sudo journalctl --since yesterday --no-pager 2>/dev/null | grep -iE "$security_keywords" | grep -v "restrictive-proxy.*UNAUTHORIZED" | tail -10
        fi
    else
        log_success "No security keywords in system logs"
        add_json_result "logs" "ok" "Clean system logs"
    fi

    # Check for kernel panics or OOM kills
    local oom_kills=$(sudo journalctl --since yesterday --no-pager 2>/dev/null | grep -c "Out of memory" | tr -d ' \n' || echo 0)
    if [[ $oom_kills -gt 0 ]]; then
        log_warning "OOM (Out of Memory) kills detected: $oom_kills"
        add_json_result "logs" "warning" "OOM kills: $oom_kills"
    fi
}

# Check 9: System resources
check_resources() {
    log_section "9. System Resource Check"

    # Check disk usage
    local disk_usage=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        log_critical "Root filesystem usage critical: ${disk_usage}%"
        add_json_result "resources" "critical" "Disk usage: ${disk_usage}%"
    elif [[ $disk_usage -gt 80 ]]; then
        log_warning "Root filesystem usage high: ${disk_usage}%"
        add_json_result "resources" "warning" "Disk usage: ${disk_usage}%"
    else
        log_success "Root filesystem usage: ${disk_usage}%"
        add_json_result "resources" "ok" "Disk usage normal"
    fi

    # Check memory usage
    local mem_available=$(free -m | awk 'NR==2{printf "%.0f", $7*100/$2}')
    log_info "Available memory: ${mem_available}%"

    # Check load average
    local load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_count=$(nproc)
    log_info "Load average: $load (CPUs: $cpu_count)"

    if [[ $VERBOSE -eq 1 ]]; then
        echo ""
        free -h
        echo ""
        df -h
    fi
}

# Check 10: Restrictive proxy status (custom homelab security)
check_restrictive_proxy() {
    log_section "10. Restrictive Proxy Status"

    if systemctl is-active --quiet restrictive-proxy 2>/dev/null; then
        log_success "Restrictive proxy is running"
        add_json_result "proxy" "ok" "Proxy active"

        # Check recent unauthorized attempts
        local unauth_24h=$(sudo journalctl -u restrictive-proxy --since yesterday --no-pager 2>/dev/null | grep -c "UNAUTHORIZED" | tr -d ' \n' || echo 0)
        if [[ $unauth_24h -gt 100 ]]; then
            log_warning "High number of unauthorized proxy requests: $unauth_24h in 24h"
            add_json_result "proxy" "warning" "Unauthorized requests: $unauth_24h"
        elif [[ $unauth_24h -gt 0 ]]; then
            log_info "Unauthorized proxy requests (expected): $unauth_24h in 24h"
        fi
    else
        log_info "Restrictive proxy not running (may not be master node)"
        add_json_result "proxy" "info" "Proxy not running"
    fi
}

# Generate report
generate_report() {
    log_section "Security Audit Summary"

    local hostname=$(hostname)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ $JSON_OUTPUT -eq 1 ]]; then
        echo "{"
        echo "  \"hostname\": \"$hostname\","
        echo "  \"timestamp\": \"$timestamp\","
        echo "  \"status\": \"$OVERALL_STATUS\","
        echo "  \"issues\": $ISSUES,"
        echo "  \"warnings\": $WARNINGS,"
        echo "  \"checks\": ["
        local first=1
        for result in "${JSON_RESULTS[@]}"; do
            if [[ $first -eq 1 ]]; then
                first=0
            else
                echo ","
            fi
            echo "    $result"
        done
        echo ""
        echo "  ]"
        echo "}"
    else
        echo ""
        echo "Hostname: $hostname"
        echo "Timestamp: $timestamp"
        echo "Status: $OVERALL_STATUS"
        echo "Critical Issues: $ISSUES"
        echo "Warnings: $WARNINGS"
        echo ""

        if [[ "$OVERALL_STATUS" == "SECURE" ]] && [[ $ISSUES -eq 0 ]]; then
            echo -e "${GREEN}✓ System appears secure. No security breaches detected.${NC}"
        elif [[ $ISSUES -gt 0 ]]; then
            echo -e "${RED}✗ SECURITY ISSUES DETECTED! Immediate investigation required.${NC}"
        else
            echo -e "${YELLOW}! Warnings detected. Review recommended.${NC}"
        fi
    fi
}

# Main execution
main() {
    if [[ $JSON_OUTPUT -eq 0 ]]; then
        echo ""
        echo "=========================================="
        echo "  Homelab Security Audit"
        echo "  $(hostname) - $(date)"
        echo "=========================================="
    fi

    check_authentication
    check_user_accounts
    check_ssh_keys
    check_network
    check_processes
    check_cron
    check_file_integrity
    check_system_logs
    check_resources
    check_restrictive_proxy

    generate_report

    # Exit with appropriate code
    if [[ $ISSUES -gt 0 ]]; then
        exit 2
    elif [[ $WARNINGS -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run main
main