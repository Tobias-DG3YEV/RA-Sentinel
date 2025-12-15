#!/bin/bash
# STM32 Project Cleaner
# Removes build artifacts while preserving source code and configuration

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in a project directory
if [ ! -f "*.ioc" ] && [ ! -f "Makefile" ] && [ ! -d "Core" ] && [ ! -d "Src" ]; then
    print_warn "This doesn't look like an STM32 project directory. Continue anyway? (y/n)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

print_info "Starting STM32 project cleanup..."

# Build directories
DIRS_TO_CLEAN=(
    "build"
    "Build"
    "Debug"
    "Release"
    ".build"
)

# File patterns to remove
FILES_TO_CLEAN=(
    "*.o"
    "*.obj"
    "*.d"
    "*.elf"
    "*.bin"
    "*.hex"
    "*.map"
    "*.lst"
    "*.su"
    "*.axf"
    "*.out"
    "*.s19"
)

# IDE-specific files/directories
IDE_ARTIFACTS=(
    ".settings"
    ".cproject"
    ".project"
    ".mxproject"
    "*.launch"
)

removed_count=0

# Remove build directories
for dir in "${DIRS_TO_CLEAN[@]}"; do
    if [ -d "$dir" ]; then
        print_info "Removing directory: $dir"
        rm -rf "$dir"
        ((removed_count++))
    fi
done

# Remove build artifacts
for pattern in "${FILES_TO_CLEAN[@]}"; do
    while IFS= read -r -d '' file; do
        print_info "Removing: $file"
        rm -f "$file"
        ((removed_count++))
    done < <(find . -name "$pattern" -type f -print0)
done

# Ask before removing IDE-specific files
if [[ "$1" == "--full" ]]; then
    print_warn "Full clean requested - removing IDE artifacts..."
    for pattern in "${IDE_ARTIFACTS[@]}"; do
        while IFS= read -r -d '' file; do
            print_info "Removing: $file"
            rm -rf "$file"
            ((removed_count++))
        done < <(find . -name "$pattern" -print0)
    done
fi

# Summary
print_info "Cleanup complete! Removed/cleaned $removed_count items."

# Show disk space saved (optional)
if command -v du &> /dev/null; then
    SIZE=$(du -sh . 2>/dev/null | cut -f1)
    print_info "Current directory size: $SIZE"
fi

echo ""
echo "Usage: $0 [--full]"
echo "  --full  : Also remove IDE configuration files (.settings, .project, etc.)"
