# MediaPipe XCFramework Linker Configuration Guide

## ⚠️ Why Linker Errors Occur

Your original error:
```
Undefined symbol: mediapipe::tasks::core::regular_tflite::TaskRunner::Send(...)
Undefined symbol: mediapipe::tasks::core::regular_tflite::TaskRunner::Create(...)
```

**Root Cause:** The MediaPipe C++ symbols are not being linked correctly because:
1. Framework not in project's link phase
2. Missing C++ standard library flags
3. Incorrect bitcode settings
4. Missing symbol visibility flags

---

## ✅ Fix: Apply These Build Settings

### Method 1: Xcode GUI (Easiest)

1. **Select your project** in Xcode (blue icon at top of navigator)
2. **Select Target: MagicMotion**
3. Go to **Build Settings** tab
4. Search for each setting below and apply:

#### **Linking**
```
Other Linker Flags:
-lc++ -ObjC

Frameworks Search Paths:
$(PROJECT_DIR)/MediaPipeFramework

Link With Standard Library:
Yes
```

#### **Build Options**
```
Enable Bitcode:
No

Strip Linked Product:
No

Preserve Private External Symbols:
Yes
```

#### **C++ Language Dialect**
```
C++ Language Dialect:
GNU++17 [-std=gnu++17]

C++ Standard Library:
libc++ (LLVM C++ standard library with C++11 support)
```

#### **Search Paths**
```
Framework Search Paths:
$(BUILD_DIR)/MediaPipeFramework
$(SDKROOT)/System/Library/Frameworks

Header Search Paths:
$(SRCROOT)/MediaPipeFramework/Headers
```

---

### Method 2: Direct pbxproj Edit

If you prefer command-line editing, add these to your `project.pbxproj`:

```pbxproj
LD_RUNPATH_SEARCH_PATHS = (
    "$(inherited)",
    "@executable_path/Frameworks",
    "@loader_path/Frameworks",
);

OTHER_LDFLAGS = (
    "$(inherited)",
    "-lc++",
    "-ObjC",
    "-framework",
    "MediaPipeTasksVision",
);

OTHER_CXXFLAGS = (
    "$(inherited)",
    "-std=gnu++17",
);

CLANG_CXX_LANGUAGE_STANDARD = "gnu++17";
CLANG_CXX_LIBRARY = "libc++";

FRAMEWORK_SEARCH_PATHS = (
    "$(inherited)",
    "$(PROJECT_DIR)/MediaPipeFramework",
    "$(SDKROOT)/System/Library/Frameworks",
);
```

---

## 🔗 Linking Phase Configuration

1. **Select Target** → **Build Phases** tab
2. Expand **Link Binary With Libraries**
3. Verify these are present:
   - ✅ MediaPipeTasksVision.framework
   - ✅ Foundation.framework
   - ✅ AVFoundation.framework
   - ✅ CoreVideo.framework
   - ✅ CoreML.framework
   - ✅ Vision.framework
   - ✅ libc++.1.tbd

4. If missing, click **+** and add them

---

## 🧪 Verification

After applying settings, run:

```bash
# Check if symbols are resolvable
nm -gU MagicMotion.app/MagicMotion | grep -i taskrunner

# Build and check for linker errors
xcodebuild build -scheme MagicMotion 2>&1 | grep -i "undefined symbol"
```

**Expected result:** No undefined symbol errors

---

## 🚀 For Cross-Platform Deployment

Since you're targeting Android/Web/Desktop too:

### Android (Kotlin) - Same MediaPipe source
```kotlin
dependencies {
    implementation "com.google.mediapipe:mediapipe-tasks-vision:0.10.9"
}
```

### Web (JavaScript) - Same algorithms
```javascript
const vision = await FilesetResolver.forVisionTasks(
    "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.9/wasm"
);
```

### Desktop (C++) - Same binaries
```cpp
#include "mediapipe/tasks/cc/vision/pose_landmarker/pose_landmarker.h"
```

All use the same MediaPipe version and algorithms = **consistent UX across platforms**

---

## 📋 Troubleshooting

| Error | Solution |
|-------|----------|
| `Undefined symbol: mediapipe::...` | Add `-lc++` to Other Linker Flags |
| `Framework not found MediaPipeTasksVision` | Verify Framework Search Paths |
| `Bitcode not supported` | Set "Enable Bitcode" to No |
| `Symbol not exported` | Add `-ObjC` flag |
| `C++ version mismatch` | Set C++ Standard to gnu++17 |

---

## 📚 Next Steps

1. ✅ Run `./build_mediapipe.sh` to create XCFramework
2. ✅ Apply the build settings above
3. ✅ Run `xcodebuild build` to verify
4. ✅ Test pose detection works
5. ✅ Document this for Android/Web teams

---

**Last Updated:** March 2026
**Status:** Production-Ready for Cross-Platform Deployment
