# 📦 MediaPipe Setup Guide

## Step-by-Step Installation

### **Method 1: Swift Package Manager (Recommended)**

1. **Download MediaPipe Model**
   - Go to: https://developers.google.com/mediapipe/solutions/vision/pose_landmarker
   - Download: `pose_landmarker_heavy.task` (or lite/full version)
   - Add to your Xcode project

2. **Add MediaPipe Framework**
   
   In Xcode:
   ```
   File → Add Package Dependencies
   ```
   
   Add this URL:
   ```
   https://github.com/google/mediapipe
   ```
   
   Or for iOS-specific:
   ```
   https://github.com/google-ai-edge/mediapipe-samples
   ```

3. **Add Model File to Project**
   - Drag `pose_landmarker_heavy.task` into your Xcode project
   - ✅ Check "Copy items if needed"
   - ✅ Check your target

4. **Update Info.plist**
   Already done! (Camera permission is set)

---

### **Method 2: CocoaPods**

1. Create `Podfile` in project root:
   ```ruby
   platform :ios, '14.0'
   use_frameworks!

   target 'MagicMotion' do
     pod 'MediaPipeTasksVision'
   end
   ```

2. Install:
   ```bash
   pod install
   ```

3. **Use `.xcworkspace` file** instead of `.xcodeproj`

---

## 🔧 After Installation

### **1. Uncomment Code in MediaPipePoseDetector.swift**

Find all the `/* Uncomment when MediaPipe is installed: */` blocks and uncomment them.

### **2. Update Imports**

At the top of `MediaPipePoseDetector.swift`:
```swift
import MediaPipeTasksVision
```

### **3. Test It**

Run the app - you should see:
```
✅ MediaPipe initialized successfully
```

---

## 📱 Cross-Platform Architecture

### **iOS (Current)**
```
MagicMotion (iOS)
├── MediaPipePoseDetector.swift
├── GestureClassifier.swift (shared)
├── GameModels.swift (shared)
└── GameView.swift (SwiftUI)
```

### **Android (Future)**
```
MagicMotion (Android)
├── MediaPipePoseDetector.kt
├── GestureClassifier.kt (port from Swift)
├── GameModels.kt (port from Swift)
└── GameView.kt (Jetpack Compose)
```

### **Web (Future)**
```
MagicMotion (Web)
├── mediapipe-pose-detector.js
├── gesture-classifier.js (port from Swift)
├── game-models.js (port from Swift)
└── game-view.jsx (React)
```

---

## 🎯 Shared Logic Strategy

### **What's Cross-Platform:**
- ✅ Gesture recognition logic (thresholds, algorithms)
- ✅ Game logic (obstacles, scoring, physics)
- ✅ UI layout concepts
- ✅ MediaPipe landmark processing

### **What's Platform-Specific:**
- Camera APIs (AVFoundation vs Android Camera2 vs WebRTC)
- UI frameworks (SwiftUI vs Compose vs React)
- Graphics (Metal vs OpenGL vs WebGL)

---

## 🔄 Migration Checklist

- [ ] Download MediaPipe model file
- [ ] Add MediaPipe package dependency
- [ ] Add model file to Xcode project
- [ ] Uncomment MediaPipe code
- [ ] Test pose detection
- [ ] Update GestureClassifier to use MediaPipe landmarks
- [ ] Test game with new detector
- [ ] Verify cross-platform compatibility

---

## 📚 Resources

- MediaPipe iOS Guide: https://developers.google.com/mediapipe/solutions/vision/pose_landmarker/ios
- MediaPipe Android: https://developers.google.com/mediapipe/solutions/vision/pose_landmarker/android
- MediaPipe Web: https://developers.google.com/mediapipe/solutions/vision/pose_landmarker/web
- Sample Code: https://github.com/google-ai-edge/mediapipe-samples

---

## ⚡ Quick Start

**If you want me to help with the full integration:**

1. Download the model file
2. Add it to your project
3. Tell me when it's ready
4. I'll uncomment and wire everything up!

---

## 🆚 Vision vs MediaPipe Code Comparison

### **Before (Vision):**
```swift
// 19 joints
let wrist = pose.point(for: .rightWrist)
```

### **After (MediaPipe):**
```swift
// 33 landmarks + hands!
let wrist = pose.landmark(.rightWrist)
let index = pose.landmark(.rightIndex)  // NEW!
let thumb = pose.landmark(.rightThumb)  // NEW!
```

**More precision, more possibilities!** 🎯
