#!/bin/bash
# filepath: /home/oleksiyp/dev/basic-infra/ansible/ceph/cluster-ops.sh
# Common Ceph cluster operations script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo -e "${GREEN}Ceph Cluster Operations Script${NC}"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  status          - Show cluster status"
    echo "  health          - Show cluster health"
    echo "  df              - Show cluster disk usage"
    echo "  osd-tree        - Show OSD tree"
    echo "  pools           - List pools"
    echo "  mons            - Show monitor status"
    echo "  mgrs            - Show manager status"
    echo "  dashboard       - Show dashboard URL and credentials"
    echo "  add-osd         - Interactive OSD addition"
    echo "  create-pool     - Interactive pool creation"
    echo "  performance     - Show performance statistics"
    echo "  logs            - Show recent cluster logs"
    echo "  help            - Show this help message"
    echo ""
}

# Function to check if we're on a Ceph node
check_ceph_node() {
    if ! command -v ceph &> /dev/null; then
        echo -e "${RED}Error: ceph command not found. Are you on a Ceph cluster node?${NC}"
        exit 1
    fi
}

# Function to show cluster status
show_status() {
    echo -e "${BLUE}=== Cluster Status ===${NC}"
    sudo ceph status
}

# Function to show cluster health
show_health() {
    echo -e "${BLUE}=== Cluster Health ===${NC}"
    sudo ceph health detail
}

# Function to show disk usage
show_df() {
    echo -e "${BLUE}=== Cluster Disk Usage ===${NC}"
    sudo ceph df
}

# Function to show OSD tree
show_osd_tree() {
    echo -e "${BLUE}=== OSD Tree ===${NC}"
    sudo ceph osd tree
}

# Function to list pools
show_pools() {
    echo -e "${BLUE}=== Pools ===${NC}"
    sudo ceph osd lspools
    echo ""
    echo -e "${BLUE}=== Pool Details ===${NC}"
    for pool in $(sudo ceph osd lspools | awk '{print $2}'); do
        echo -e "${YELLOW}Pool: $pool${NC}"
        sudo ceph osd pool get $pool size 2>/dev/null || true
        sudo ceph osd pool get $pool min_size 2>/dev/null || true
        echo ""
    done
}

# Function to show monitor status
show_mons() {
    echo -e "${BLUE}=== Monitor Status ===${NC}"
    sudo ceph mon stat
    echo ""
    sudo ceph quorum_status
}

# Function to show manager status
show_mgrs() {
    echo -e "${BLUE}=== Manager Status ===${NC}"
    sudo ceph mgr stat
    echo ""
    sudo ceph mgr services
}

# Function to show dashboard info
show_dashboard() {
    echo -e "${BLUE}=== Dashboard Information ===${NC}"
    echo -e "${GREEN}Dashboard URLs:${NC}"
    sudo ceph mgr services | grep dashboard || echo "Dashboard service not found"
    echo ""
    echo -e "${YELLOW}Default Credentials:${NC}"
    echo "  Username: admin"
    echo "  Password: admin123"
    echo ""
    echo -e "${RED}Important: Change the default password!${NC}"
    echo "Run: sudo ceph dashboard ac-user-set-password admin <new-password>"
}

# Function to add OSD interactively
add_osd() {
    echo -e "${BLUE}=== Add OSD ===${NC}"
    echo -e "${YELLOW}Available devices:${NC}"
    sudo ceph orch device ls
    echo ""
    read -p "Enter hostname: " hostname
    read -p "Enter device path (e.g., /dev/sdb): " device
    
    echo -e "${YELLOW}Adding OSD $hostname:$device...${NC}"
    sudo ceph orch daemon add osd $hostname:$device
    
    echo -e "${GREEN}OSD addition initiated. Check status with: $0 osd-tree${NC}"
}

# Function to create pool interactively
create_pool() {
    echo -e "${BLUE}=== Create Pool ===${NC}"
    read -p "Enter pool name: " pool_name
    read -p "Enter PG count (default 32): " pg_count
    pg_count=${pg_count:-32}
    
    echo -e "${YELLOW}Creating pool $pool_name with $pg_count PGs...${NC}"
    sudo ceph osd pool create $pool_name $pg_count
    
    echo -e "${GREEN}Pool created successfully!${NC}"
    echo "You may want to enable the pool application:"
    echo "  sudo ceph osd pool application enable $pool_name <app-name>"
    echo "Where <app-name> can be: cephfs, rbd, rgw"
}

# Function to show performance stats
show_performance() {
    echo -e "${BLUE}=== Performance Statistics ===${NC}"
    echo -e "${YELLOW}IOPS:${NC}"
    sudo ceph osd perf
    echo ""
    echo -e "${YELLOW}Client I/O:${NC}"
    sudo ceph status | grep -A 5 "client"
    echo ""
    echo -e "${YELLOW}Pool I/O:${NC}"
    sudo ceph osd pool stats
}

# Function to show recent logs
show_logs() {
    echo -e "${BLUE}=== Recent Cluster Logs ===${NC}"
    sudo ceph log last 20
}

# Main script logic
case "${1:-help}" in
    "status")
        check_ceph_node
        show_status
        ;;
    "health")
        check_ceph_node
        show_health
        ;;
    "df")
        check_ceph_node
        show_df
        ;;
    "osd-tree")
        check_ceph_node
        show_osd_tree
        ;;
    "pools")
        check_ceph_node
        show_pools
        ;;
    "mons")
        check_ceph_node
        show_mons
        ;;
    "mgrs")
        check_ceph_node
        show_mgrs
        ;;
    "dashboard")
        check_ceph_node
        show_dashboard
        ;;
    "add-osd")
        check_ceph_node
        add_osd
        ;;
    "create-pool")
        check_ceph_node
        create_pool
        ;;
    "performance")
        check_ceph_node
        show_performance
        ;;
    "logs")
        check_ceph_node
        show_logs
        ;;
    "help"|*)
        usage
        ;;
esac
