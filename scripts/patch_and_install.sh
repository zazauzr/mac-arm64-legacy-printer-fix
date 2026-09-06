#!/bin/bash

# ==============================================================================
# Script Name: patch_and_install.sh
# Description: Automates extraction, patching, and installation of legacy macOS
#              printer drivers on modern ARM64 (Apple Silicon) architectures.
# Author:      DevOps Engineer / Team Lead Portfolio Case
# ==============================================================================

set -euo pipefail

# --- Configuration & Environment Variables ---
TARGET_PKG="HewlettPackardPrinterDrivers.pkg"
TMP_DIR="extracted_drivers_tmp"
PATCHED_PKG="LegacyDrivers-ARM64-Fixed.pkg"
PRINTER_NAME="Enterprise_LaserJet_P1102"
PRINTER_DISPLAY_NAME="HP LaserJet P1102 (ARM64 Patched)"

log() {
    echo -e "[$(date +'%Y-%m-%dT%H:%M:%S%z')] [INFO] $1"
}

error_exit() {
    echo -e "[$(date +'%Y-%m-%dT%H:%M:%S%z')] [ERROR] $1" >&2
    exit 1
}

# --- Step 1: Pre-flight checks ---
log "Starting pre-flight environment checks..."

if [[ ! -f "$TARGET_PKG" ]]; then
    error_exit "Source package '$TARGET_PKG' not found in the current directory."
fi

# Ensure Rosetta 2 is installed for ARM64 compatibility with legacy Intel binaries
if ! pkgutil --pkg-info com.apple.pkg.RosettaExternalVersionSoftwareCheck > /dev/null 2>&1; then
    log "Rosetta 2 not detected. Initiating automatic installation..."
    softwareupdate --install-rosetta --agree-to-license || error_exit "Failed to install Rosetta 2."
else
    log "Rosetta 2 is already installed."
fi

# --- Step 2: Extract the legacy package ---
log "Extracting target package structure..."
rm -rf "$TMP_DIR"
pkgutil --expand "$TARGET_PKG" "$TMP_DIR" || error_exit "Failed to expand package."

# --- Step 3: Patch OS Compatibility Check ---
log "Patching distribution configuration to bypass OS version enforcement..."
DIST_FILE="$TMP_DIR/Distribution"

if [[ -f "$DIST_FILE" ]]; then
    # Bypass logic: Replace strict system version checks with universal fallback '99'
    if grep -q "system.version.ProductVersion" "$DIST_FILE"; then
        sed -i '' "s/system.version.ProductVersion/ '99' \/\/ Bypassed /g" "$DIST_FILE"
    else
        # Alternative fallback if specific function is used
        sed -i '' 's/InstallationCheck()/true/g' "$DIST_FILE"
    fi
    log "Patch applied successfully to $DIST_FILE"
else
    error_exit "Distribution configuration file not found in extracted package."
fi

# --- Step 4: Rebuild the package ---
log "Flattening and rebuilding the patched package..."
pkgutil --flatten "$TMP_DIR" "$PATCHED_PKG" || error_exit "Failed to rebuild package."
rm -rf "$TMP_DIR"

# --- Step 5: Unattended Silent Installation ---
log "Deploying the patched package to the system (Sudo permissions required)..."
sudo installer -pkg "$PATCHED_PKG" -target / || error_exit "Package installation failed."

# --- Step 6: Automating CUPS Spooler Provisioning ---
log "Provisioning the printer device using CUPS subsystem..."
# Resetting the specific printer if it already exists to prevent conflict
lpadmin -x "$PRINTER_NAME" 2>/dev/null || true

# Add printer using the universal PCL driver to guarantee hardware compatibility
lpadmin -p "$PRINTER_NAME" \
        -E \
        -v "usb://example-mock-device-id" \
        -m "drv:///sample.drv/generic.ppd" \
        -v "usb://dev/null" \
        -o printer-is-shared=false

log "System deployment successfully completed."
log "Please connect your physical USB device and pair it via Settings -> Printers using Generic PCL Driver."
