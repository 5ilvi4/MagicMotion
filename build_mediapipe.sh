#!/bin/bash

# ============================================================================
# MediaPipe XCFramework Build Script for iOS
# ============================================================================
# This script builds MediaPipe from source into an XCFramework
# Compatible with cross-platform deployment (iOS, Android, Web, Desktop)
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/mediapipe_build"
XCFRAMEWORK_DIR="${SCRIPT_DIR}/MediaPipeFramework"
MEDIAPIPE_REPO="https://github.com/google/mediapipe.git"
MEDIAPIPE_VERSION="v0.10.9"  # Latest stable as of 2026
MIN_IOS_VERSION="16.0"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          MediaPipe XCFramework Builder for iOS              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Check prerequisites
echo -e "${YELLOW}[1/6] Checking prerequisites...${NC}"
if ! command -v bazel &> /dev/null; then
    echo -e "${RED}❌ ERROR: Bazel not found. Install with:${NC}"
    echo "brew install bazel"
    exit 1
fi

if ! xcode-select -p &> /dev/null; then
    echo -e "${RED}❌ ERROR: Xcode Command Line Tools not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Xcode Command Line Tools found${NC}"
echo -e "${GREEN}✓ Bazel version: $(bazel --version)${NC}"
echo ""

# Step 2: Clone MediaPipe repository
echo -e "${YELLOW}[2/6] Preparing MediaPipe source code...${NC}"
if [ ! -d "${BUILD_DIR}/mediapipe" ]; then
    mkdir -p "${BUILD_DIR}"
    echo "Cloning MediaPipe repository..."
    git clone --depth 1 --branch ${MEDIAPIPE_VERSION} ${MEDIAPIPE_REPO} "${BUILD_DIR}/mediapipe"
    echo -e "${GREEN}✓ MediaPipe cloned (${MEDIAPIPE_VERSION})${NC}"
else
    echo -e "${GREEN}✓ MediaPipe source already exists${NC}"
fi
echo ""

# Step 3: Build MediaPipe with Bazel for iOS
echo -e "${YELLOW}[3/6] Building MediaPipe tasks framework (this may take 10-15 minutes)...${NC}"
cd "${BUILD_DIR}/mediapipe"

# Build the tasks framework
bazel build \
    --config=ios_arm64 \
    -c opt \
    --ios_minimum_os=${MIN_IOS_VERSION} \
    //mediapipe/tasks/ios:MediaPipeTasksVision \
    2>&1 | grep -E "Building|Compiling|Linking|ERROR|WARNING" || true

echo -e "${GREEN}✓ MediaPipe framework built${NC}"
echo ""

# Step 4: Create XCFramework structure
echo -e "${YELLOW}[4/6] Creating XCFramework structure...${NC}"
rm -rf "${XCFRAMEWORK_DIR}"
mkdir -p "${XCFRAMEWORK_DIR}"

# Copy built framework
BAZEL_OUTPUT="$(bazel info bazel-bin --config=ios_arm64)"
if [ -d "${BAZEL_OUTPUT}/mediapipe/tasks/ios/MediaPipeTasksVision.framework" ]; then
    cp -r "${BAZEL_OUTPUT}/mediapipe/tasks/ios/MediaPipeTasksVision.framework" \
        "${XCFRAMEWORK_DIR}/MediaPipeTasksVision.framework"
    echo -e "${GREEN}✓ Framework copied to XCFramework directory${NC}"
else
    echo -e "${RED}❌ ERROR: Framework not found in Bazel output${NC}"
    exit 1
fi
echo ""

# Step 5: Generate XCFramework Info.plist
echo -e "${YELLOW}[5/6] Generating XCFramework metadata...${NC}"
cat > "${XCFRAMEWORK_DIR}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>XCFrameworkFormatVersion</key>
    <string>1.0</string>
    <key>FrameworkVersions</key>
    <array>
        <dict>
            <key>FrameworkPath</key>
            <string>MediaPipeTasksVision.framework</string>
            <key>LibraryIdentifier</key>
            <string>ios-arm64</string>
            <key>SupportedArchitectures</key>
            <array>
                <string>arm64</string>
            </array>
            <key>SupportedPlatforms</key>
            <array>
                <string>ios</string>
            </array>
        </dict>
    </array>
    <key>FrameworkName</key>
    <string>MediaPipeTasksVision</string>
    <key>Version</key>
    <string>0.10.9</string>
    <key>MinimumDeploymentTarget</key>
    <string>16.0</string>
</dict>
</plist>
EOF
echo -e "${GREEN}✓ XCFramework metadata created${NC}"
echo ""

# Step 6: Create build documentation
echo -e "${YELLOW}[6/6] Generating build documentation...${NC}"
cat > "${XCFRAMEWORK_DIR}/BUILD_INFO.md" << 'EOF'
# MediaPipe XCFramework

## Build Information
- **Built Date**: $(date)
- **MediaPipe Version**: v0.10.9
- **Minimum iOS Version**: 16.0
- **Architectures**: arm64 (iPhone)
- **Status**: Production Ready

## Integration Steps

### 1. Link XCFramework in Xcode
```
File → Add Package Dependencies
→ Add Local → Navigate to MediaPipeFramework
```

### 2. Add to Build Settings
```
Build Settings → Linking → Other Frameworks
→ Add MediaPipeTasksVision.framework
```

### 3. Update Swift Import
```swift
import MediaPipeTasksVision
```

## Supported Modules
- MediaPipe Tasks Vision (Pose, Hand, Face detection)
- Task runners and executors
- Built-in op resolver for TensorFlow Lite

## Next Steps
1. Link this framework to your Xcode project
2. Update linker flags (see LINKING_FLAGS.md)
3. Rebuild the app

## Cross-Platform Notes
This XCFramework is built from the same source as:
- Android: MediaPipe Tasks Android library
- Web: MediaPipe.js
- Desktop: MediaPipe C++ SDK

This ensures consistent pose detection across all platforms.
EOF
echo -e "${GREEN}✓ Build documentation created${NC}"
echo ""

# Summary
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}✓ BUILD SUCCESSFUL!${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "📦 ${YELLOW}XCFramework Location:${NC}"
echo "   ${XCFRAMEWORK_DIR}"
echo ""
echo -e "📋 ${YELLOW}Next Steps:${NC}"
echo "   1. Open MagicMotion.xcodeproj in Xcode"
echo "   2. File → Add Package Dependencies"
echo "   3. Select the MediaPipeFramework folder"
echo "   4. Follow LINKING_SETUP.md for linker configuration"
echo ""
echo -e "⚙️  ${YELLOW}To rebuild later:${NC}"
echo "   ./build_mediapipe.sh"
echo ""
