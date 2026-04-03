# 🔧 Fix for MediaPipe Framework Linking Issues

## Your New Errors (Signs of Progress!)

```
Could not find or use auto-linked framework 'CoreAudioTypes'
Could not find or use auto-linked framework 'UIUtilities'  
Could not parse or use implicit file 'SwiftUICore.framework'
Undefined symbol: mediapipe::tasks::core::regular_tflite::TaskRunner::...
```

**Good news:** The linker is now **trying to link** MediaPipe, but hitting framework dependency issues.

---

## ⚠️ The Real Issue

MediaPipe's XCFramework has complex internal dependencies that are very difficult to resolve manually. The framework was built with assumptions about how it will be linked.

---

## ✅ The Best Solution: Use CocoaPods (Recommended)

CocoaPods is designed specifically to handle complex framework dependencies like MediaPipe.

### Step 1: Remove Manual Framework Linking

In Xcode:
1. **Project → Target: MagicMotion**
2. **Build Phases → Link Binary With Libraries**
3. **Remove:** MediaPipeTasksVision.framework (if you added it)
4. Keep: AVFoundation, CoreML, Vision, CoreVideo, libc++

### Step 2: Create Podfile

```bash
cd /Users/silviadinda/Desktop/MagicMotion/MagicMotion
pod init
```

This creates a `Podfile`.

### Step 3: Edit Podfile

Open `Podfile` and replace contents with:

```ruby
platform :ios, '16.0'

target 'MagicMotion' do
  # MediaPipe Tasks Vision
  pod 'MediaPipeTasksVision', '0.10.9'
  
  # Ensure C++ linking
  pod 'OpenSSL-Universal'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # Fix for C++ standard
      config.build_settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'gnu++17'
      config.build_settings['CLANG_CXX_LIBRARY'] = 'libc++'
      config.build_settings['GCC_ENABLE_OBJC_EXCEPTIONS'] = 'YES'
    end
  end
end
```

### Step 4: Install Pods

```bash
cd /Users/silviadinda/Desktop/MagicMotion/MagicMotion
pod install
```

### Step 5: Close Xcode, Open Workspace

```bash
# Close Xcode
killall Xcode

# Open the workspace (NOT the project)
open MagicMotion.xcworkspace
```

### Step 6: Build

In Xcode: **Cmd+B**

Expected result: **✅ Build Succeeded!**

---

## Alternative: Fallback to Vision Framework (If CocoaPods Doesn't Work)

If CocoaPods fails, we can use Apple's native Vision framework instead:

```bash
# Remove the manual framework setup
rm -rf /workspaces/MagicMotion/MediaPipeFramework/
```

Then update `PoseDetector.swift` to use only Vision framework (already partially done):

```swift
// PoseDetector.swift will use only Vision framework
// No MediaPipe dependency needed
// Less accurate but fully supported on iOS
```

---

## ⚡ Quick Reference: Which to Choose?

| Option | Pros | Cons |
|--------|------|------|
| **CocoaPods** | ✅ Handles dependencies automatically | ⚠️ Slower to install first time |
| **Vision Only** | ✅ No external dependencies | ❌ Less accurate than MediaPipe |

**Recommendation:** Try CoCoaPods first (5 minutes).

---

## Troubleshooting CocoaPods Installation

### Pod Command Not Found

```bash
sudo gem install cocoapods
```

### Pod Install Fails

```bash
cd /Users/silviadinda/Desktop/MagicMotion/MagicMotion
pod repo update
pod install
```

### Still Have Linker Errors?

```bash
# Clean everything
cd /Users/silviadinda/Desktop/MagicMotion/MagicMotion
rm -rf Pods Podfile.lock
pod install
```

Then in Xcode:
```
Cmd+Shift+K (Clean)
Cmd+B (Build)
```

---

## Success Indicators

✅ After `pod install`, you should have:
- `Podfile`
- `Podfile.lock`  
- `Pods/` directory
- `MagicMotion.xcworkspace` (NEW - use this instead of .xcodeproj)

✅ In Xcode:
- Open `.xcworkspace` (not `.xcodeproj`)
- No "Could not find" framework errors
- No undefined symbol errors
- Build succeeds

---

## Next Steps

1. **Try CoCoaPods** (recommended) - Follow steps above
2. **If CoCoaPods fails**, use Vision-only fallback
3. **Message me** if you need help with either approach

The good news: You're making progress! The linker is now recognizing MediaPipe, we just need to resolve its internal dependencies properly.

