#!/bin/bash

# Script to render Helmfile templates grouped by namespace
# Usage: ./render-manifests.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELMFILE_DIR="${SCRIPT_DIR}/helmfile"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting Helmfile manifest rendering...${NC}"

# Change to helmfile directory
cd "${HELMFILE_DIR}"

# Get list of releases and their namespaces
echo -e "${YELLOW}📋 Getting list of releases...${NC}"

releases_output=$(helmfile list --output json 2>/dev/null)

if [[ $? -ne 0 ]] || [[ -z "$releases_output" ]]; then
    echo -e "${RED}❌ Error: Failed to get helmfile list. Trying without JSON output...${NC}"
    # Try without JSON first to see the error
    helmfile list
    exit 1
fi

# Parse JSON and group by namespace
echo -e "${YELLOW}📊 Grouping releases by namespace...${NC}"

# Create associative array to store namespace -> releases mapping
declare -A namespace_releases

# Parse JSON output and group by namespace
while IFS= read -r line; do
    if [[ -n "$line" ]]; then
        namespace=$(echo "$line" | jq -r '.namespace // "default"')
        name=$(echo "$line" | jq -r '.name')
        
        if [[ "$namespace" != "null" ]] && [[ "$name" != "null" ]]; then
            if [[ -z "${namespace_releases[$namespace]}" ]]; then
                namespace_releases[$namespace]="$name"
            else
                namespace_releases[$namespace]="${namespace_releases[$namespace]} $name"
            fi
        fi
    fi
done < <(echo "$releases_output" | jq -c '.[]')

# Display grouped releases
echo -e "${BLUE}📝 Found releases grouped by namespace:${NC}"
for namespace in "${!namespace_releases[@]}"; do
    echo -e "  ${GREEN}$namespace${NC}: ${namespace_releases[$namespace]}"
done

# Create manifests directory structure and render templates
echo -e "${YELLOW}🏗️  Creating manifest directory structure and rendering templates...${NC}"

for namespace in "${!namespace_releases[@]}"; do
  
    echo -e "${BLUE}Processing namespace: ${GREEN}$namespace${NC}"
    
    # Create directory structure
    manifest_dir="${MANIFESTS_DIR}/${namespace}/dev"
    mkdir -p "$manifest_dir"
    
    # Get releases for this namespace
    releases="${namespace_releases[$namespace]}"
    
    # Create selector for releases in this namespace
    release_names_array=($releases)
    selector_parts=()
    for release_name in "${release_names_array[@]}"; do
        selector_parts+=("-l name=$release_name")
    done
    
    # Join selector parts with commas
    selector=$(IFS=' '; echo "${selector_parts[*]}")
    
    echo -e "  ${YELLOW}📋 Releases: ${releases}${NC}"
    echo -e "  ${YELLOW}🎯 Selector: ${selector}${NC}"
    
    # Render templates for this namespace
    output_file="${manifest_dir}/manifest.yaml"
    echo -e "  ${YELLOW}📄 Rendering to: ${output_file}${NC}"
    
    # Use helmfile template with selector
    error_file=$(mktemp)
    
    if helmfile template $selector --skip-deps > "$output_file" 2>"$error_file"; then
        file_size=$(wc -l < "$output_file")
        echo -e "  ${GREEN}✅ Successfully rendered $file_size lines to $output_file${NC}"
        rm -f "$error_file"
    else
        echo -e "  ${RED}❌ Failed to render templates for namespace $namespace${NC}"
        echo -e "  ${YELLOW}🔍 Error output:${NC}"
        cat "$error_file" | sed 's/^/    /'
        
        rm -f "$error_file"
    fi
done

# Summary
echo -e "${GREEN}🎉 Manifest rendering completed!${NC}"
echo -e "${BLUE}📂 Manifests saved to: ${MANIFESTS_DIR}${NC}"
echo -e "${BLUE}📁 Directory structure:${NC}"

# Show the directory tree
if command -v tree >/dev/null 2>&1; then
    tree "$MANIFESTS_DIR" 2>/dev/null || find "$MANIFESTS_DIR" -type f -name "*.yaml" | sort
else
    find "$MANIFESTS_DIR" -type f -name "*.yaml" | sort
fi

echo -e "${GREEN}✨ Done!${NC}"
