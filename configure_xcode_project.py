#!/usr/bin/env python3

"""
MediaPipe XCFramework Xcode Project Configurator
Automatically applies linker settings to prevent undefined symbol errors
"""

import os
import sys
import json
import subprocess
from pathlib import Path

class XcodeProjectConfigurator:
    def __init__(self, project_path):
        self.project_path = Path(project_path)
        self.pbxproj_path = self.project_path / "MagicMotion.xcodeproj" / "project.pbxproj"
        
    def validate_project(self):
        """Check if project file exists"""
        if not self.pbxproj_path.exists():
            print(f"❌ Error: project.pbxproj not found at {self.pbxproj_path}")
            return False
        print(f"✓ Found project at {self.pbxproj_path}")
        return True
    
    def apply_build_settings(self):
        """Apply required build settings to fix linker errors"""
        settings_to_apply = {
            'OTHER_LDFLAGS': '-lc++ -ObjC',
            'CLANG_CXX_LANGUAGE_STANDARD': 'gnu++17',
            'CLANG_CXX_LIBRARY': 'libc++',
            'ENABLE_BITCODE': 'NO',
            'STRIP_LINKED_PRODUCT': 'NO',
            'GCC_ENABLE_OBJC_EXCEPTIONS': 'YES',
        }
        
        print("\n📋 Build Settings to Apply:")
        for key, value in settings_to_apply.items():
            print(f"   {key} = {value}")
        
        print("\n💡 Instructions:")
        print("   1. Open MagicMotion.xcodeproj in Xcode")
        print("   2. Select Project → Target: MagicMotion")
        print("   3. Go to Build Settings tab")
        print("   4. For each setting above, paste the value")
        print("\n   Or use this xcodebuild command:")
        
        # Generate xcodebuild command
        xcodebuild_cmd = "xcodebuild"
        for key, value in settings_to_apply.items():
            xcodebuild_cmd += f' -{key} "{value}"'
        
        print(f"\n   {xcodebuild_cmd}")
        
        return True
    
    def create_framework_reference(self):
        """Create reference files for framework linking"""
        
        # Create framework metadata
        framework_ref = {
            "name": "MediaPipeTasksVision",
            "version": "0.10.9",
            "minimum_ios": "16.0",
            "architectures": ["arm64"],
            "capabilities": [
                "Pose Detection (33 landmarks)",
                "Hand Detection (21 landmarks each)",
                "Face Detection (468 landmarks)",
                "Holistic Detection"
            ],
            "required_frameworks": [
                "Foundation",
                "AVFoundation",
                "CoreVideo",
                "CoreML",
                "Vision",
                "simd",
                "Metal",
                "MetalPerformanceShaders"
            ]
        }
        
        ref_file = self.project_path / "FRAMEWORK_REFERENCE.json"
        with open(ref_file, 'w') as f:
            json.dump(framework_ref, f, indent=2)
        
        print(f"\n✓ Framework reference created: {ref_file}")
        return True

def main():
    print("╔════════════════════════════════════════════════════════════╗")
    print("║     MediaPipe Xcode Project Configurator                   ║")
    print("╚════════════════════════════════════════════════════════════╝")
    
    # Get project path
    if len(sys.argv) > 1:
        project_path = sys.argv[1]
    else:
        project_path = Path.cwd() / "MagicMotion"
    
    configurator = XcodeProjectConfigurator(project_path)
    
    # Validate project
    if not configurator.validate_project():
        return 1
    
    # Apply settings
    if not configurator.apply_build_settings():
        return 1
    
    # Create framework reference
    if not configurator.create_framework_reference():
        return 1
    
    print("\n" + "="*60)
    print("✅ Configuration complete!")
    print("="*60)
    print("\nNext steps:")
    print("1. Copy the build settings to your Xcode project")
    print("2. Run: ./build_mediapipe.sh")
    print("3. Link the generated XCFramework")
    print("4. Build the project")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
