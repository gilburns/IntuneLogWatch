#!/bin/zsh

# IntuneLogWatch Release Build Script
# This script builds, signs, notarizes, and packages the app

set -e  # Exit on any error

# Configuration
APP_NAME="IntuneLogWatch"
SCHEME="IntuneLogWatch"
PROJECT_PATH="IntuneLogWatch.xcodeproj"
APP_SIGN_ID="Developer ID Application: Gil Burns (G4MQ57TVLE)"
NOTARY_PROFILE="apple-notary-profile"
BUNDLE_ID="com.gilburns.IntuneLogWatch"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directories
BUILD_DIR="build"
RELEASE_DIR="release"
APP_PATH="${BUILD_DIR}/Release/${APP_NAME}.app"

# Function to get app version from built app
get_app_version() {
    if [[ -f "${APP_PATH}/Contents/Info.plist" ]]; then
        /usr/bin/plutil -extract CFBundleShortVersionString raw "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "1.0"
    else
        echo "1.0"
    fi
}

# Generate filenames with date and version (will be set after app is built)
generate_filenames() {
    local APP_VERSION=$(get_app_version)
    local DATE_PREFIX=$(date +%Y%m%d)
    DMG_NAME="${APP_NAME}-${DATE_PREFIX}-${APP_VERSION}.dmg"
    ZIP_NAME="${APP_NAME}-${DATE_PREFIX}-${APP_VERSION}.zip"
}

print_status() {
    echo "${BLUE}==>${NC} $1"
}

print_success() {
    echo "${GREEN}✓${NC} $1"
}

print_error() {
    echo "${RED}✗${NC} $1"
}

print_warning() {
    echo "${YELLOW}⚠${NC} $1"
}

# Clean up function
cleanup() {
    print_status "Cleaning up temporary files..."
    
    # Preserve notarization log if it exists
    if [[ -f "${BUILD_DIR}/notarization-log.json" ]]; then
        mkdir -p "${RELEASE_DIR}"
        cp "${BUILD_DIR}/notarization-log.json" "${RELEASE_DIR}/notarization-log-$(date +%Y%m%d-%H%M).json"
        print_warning "Notarization log preserved in: ${RELEASE_DIR}/notarization-log-$(date +%Y%m%d-%H%M).json"
    fi
    
    if [[ -d "${BUILD_DIR}" ]]; then
        rm -rf "${BUILD_DIR}"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Xcode is installed
    if ! command -v xcodebuild &> /dev/null; then
        print_error "Xcode command line tools not found"
        exit 1
    fi
    
    # Check if jq is available (native in macOS 15+ or via brew)
    if ! command -v jq &> /dev/null; then
        print_error "jq not found. On macOS 15+, it should be at /usr/bin/jq"
        print_warning "If on older macOS, install with: brew install jq"
        exit 1
    else
        JQ_PATH=$(which jq)
        print_success "Using jq at: ${JQ_PATH}"
    fi
    
    # Check if project exists
    if [[ ! -d "${PROJECT_PATH}" ]]; then
        print_error "Project not found: ${PROJECT_PATH}"
        exit 1
    fi
    
    # Check signing identity
    if ! security find-identity -v -p codesigning | grep -q "${APP_SIGN_ID}"; then
        print_error "Signing identity not found: ${APP_SIGN_ID}"
        print_warning "Make sure your Developer ID certificate is installed in Keychain"
        exit 1
    fi
    
    # Check notary profile
    if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" &> /dev/null; then
        print_error "Notary profile not found: ${NOTARY_PROFILE}"
        print_warning "Run: xcrun notarytool store-credentials ${NOTARY_PROFILE}"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Build the app
build_app() {
    print_status "Building ${APP_NAME} for release..."
    
    # Clean build directory
    if [[ -d "${BUILD_DIR}" ]]; then
        rm -rf "${BUILD_DIR}"
    fi
    
    # Build for release
    xcodebuild \
        -project "${PROJECT_PATH}" \
        -scheme "${SCHEME}" \
        -configuration Release \
        -derivedDataPath "${BUILD_DIR}" \
        -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
        archive \
        CODE_SIGN_IDENTITY="${APP_SIGN_ID}" \
        CODE_SIGN_STYLE=Manual \
        DEVELOPMENT_TEAM="G4MQ57TVLE"
    
    # Export the app
    cat > "${BUILD_DIR}/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>G4MQ57TVLE</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
EOF
    
    xcodebuild \
        -exportArchive \
        -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
        -exportPath "${BUILD_DIR}/Release" \
        -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist"
    
    if [[ ! -d "${APP_PATH}" ]]; then
        print_error "Build failed - app not found at ${APP_PATH}"
        exit 1
    fi
    
    print_success "Build completed successfully"
}

# Sign the app
sign_app() {
    print_status "Signing ${APP_NAME}..."
    
    # Sign the app bundle with hardened runtime (required for notarization)
    codesign --force --deep \
        --sign "${APP_SIGN_ID}" \
        --options runtime \
        --timestamp \
        "${APP_PATH}"
    
    # Verify the signature
    codesign --verify --verbose "${APP_PATH}"
    
    # Check that hardened runtime is enabled
    if codesign --display --verbose "${APP_PATH}" 2>&1 | grep -q "runtime"; then
        print_success "App signed with hardened runtime enabled"
    else
        print_warning "Hardened runtime may not be properly enabled"
    fi
    
    print_success "App signed successfully"
}

# Notarize the app
notarize_app() {
    print_status "Creating zip for notarization..."
    
    # Create zip for notarization
    NOTARY_ZIP="${BUILD_DIR}/${APP_NAME}-notarization.zip"
    (cd "${BUILD_DIR}/Release" && zip -r "../../${NOTARY_ZIP}" "${APP_NAME}.app")
    
    print_status "Submitting app for notarization..."
    
    # Submit for notarization
    SUBMISSION_ID=$(xcrun notarytool submit "${NOTARY_ZIP}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait \
        --output-format json | jq -r '.id')
    
    if [[ -z "${SUBMISSION_ID}" || "${SUBMISSION_ID}" == "null" ]]; then
        print_error "Notarization submission failed"
        exit 1
    fi
    
    print_status "Notarization submitted with ID: ${SUBMISSION_ID}"
    
    # Wait for notarization to complete and check status
    print_status "Waiting for notarization to complete..."
    
    NOTARY_STATUS=$(xcrun notarytool info "${SUBMISSION_ID}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --output-format json | jq -r '.status')
    
    if [[ "${NOTARY_STATUS}" != "Accepted" ]]; then
        print_error "Notarization failed with status: ${NOTARY_STATUS}"
        # Get the log for debugging
        xcrun notarytool log "${SUBMISSION_ID}" \
            --keychain-profile "${NOTARY_PROFILE}" \
            "${BUILD_DIR}/notarization-log.json"
        
        # Copy log to release directory immediately for preservation
        mkdir -p "${RELEASE_DIR}"
        LOG_FILE="${RELEASE_DIR}/notarization-log-$(date +%Y%m%d-%H%M).json"
        cp "${BUILD_DIR}/notarization-log.json" "${LOG_FILE}"
        
        print_error "Notarization log saved to: ${LOG_FILE}"
        print_warning "Common issues:"
        print_warning "- Missing entitlements"
        print_warning "- Unsigned/improperly signed binaries"
        print_warning "- Invalid bundle structure"
        exit 1
    fi
    
    print_success "Notarization completed successfully"
    
    # Staple the notarization
    print_status "Stapling notarization ticket..."
    xcrun stapler staple "${APP_PATH}"
    
    print_success "Notarization stapled successfully"
}

# Create DMG
create_dmg() {
    print_status "Creating DMG..."
    
    # Generate filenames with current app version
    generate_filenames
    
    # Create release directory
    mkdir -p "${RELEASE_DIR}"
    
    # Create temporary DMG directory
    DMG_TEMP_DIR="${BUILD_DIR}/dmg_temp"
    mkdir -p "${DMG_TEMP_DIR}"
    
    # Copy app to DMG directory
    cp -R "${APP_PATH}" "${DMG_TEMP_DIR}/"
    
    # Create Applications symlink
    ln -s /Applications "${DMG_TEMP_DIR}/Applications"
    
    # Create DMG
    DMG_PATH="${RELEASE_DIR}/${DMG_NAME}"
    
    # Calculate size needed
    SIZE=$(du -sm "${DMG_TEMP_DIR}" | cut -f1)
    SIZE=$((SIZE + 10))  # Add some padding
    
    # Create the DMG
    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "${DMG_TEMP_DIR}" \
        -ov -format UDZO \
        -size "${SIZE}m" \
        "${DMG_PATH}"
    
    print_success "DMG created: ${DMG_PATH}"
}

# Create ZIP (alternative to DMG)
create_zip() {
    print_status "Creating ZIP archive..."
    
    # Generate filenames with current app version
    generate_filenames
    
    # Create release directory
    mkdir -p "${RELEASE_DIR}"
    
    # Create ZIP
    ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"
    
    (cd "${BUILD_DIR}/Release" && zip -r "../../${ZIP_PATH}" "${APP_NAME}.app")
    
    print_success "ZIP created: ${ZIP_PATH}"
}

# Main execution
main() {
    print_status "Starting release build for ${APP_NAME}"
    echo
    
    check_prerequisites
    echo
    
    build_app
    echo
    
    sign_app
    echo
    
    notarize_app
    echo
    
    # Ask user for packaging preference only if not set via command line
    if [[ -z "${PACKAGE_CHOICE:-}" ]]; then
        echo "${BLUE}Choose packaging format:${NC}"
        echo "1) DMG (recommended)"
        echo "2) ZIP"
        echo "3) Both"
        echo
        read -p "Enter choice (1-3): " PACKAGE_CHOICE
    else
        case $PACKAGE_CHOICE in
            1) print_status "Creating DMG (from command line option)" ;;
            2) print_status "Creating ZIP (from command line option)" ;;
            3) print_status "Creating both DMG and ZIP (from command line option)" ;;
        esac
    fi
    
    case $PACKAGE_CHOICE in
        1)
            create_dmg
            ;;
        2)
            create_zip
            ;;
        3)
            create_dmg
            echo
            create_zip
            ;;
        *)
            print_warning "Invalid choice, creating DMG by default"
            create_dmg
            ;;
    esac
    
    echo
    print_success "Release build completed successfully!"
    echo
    print_status "Release files created in: ${RELEASE_DIR}/"
    ls -la "${RELEASE_DIR}/"
}

# Handle command line arguments
case "${1:-}" in
    "--zip-only")
        PACKAGE_CHOICE=2
        ;;
    "--dmg-only")
        PACKAGE_CHOICE=1
        ;;
    "--both")
        PACKAGE_CHOICE=3
        ;;
    "--help"|"-h")
        echo "Usage: $0 [--dmg-only|--zip-only|--both|--help]"
        echo
        echo "Options:"
        echo "  --dmg-only   Create DMG only"
        echo "  --zip-only   Create ZIP only" 
        echo "  --both       Create both DMG and ZIP"
        echo "  --help       Show this help"
        exit 0
        ;;
esac

# Run main function
main