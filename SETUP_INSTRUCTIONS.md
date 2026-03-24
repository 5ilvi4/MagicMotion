# SubwaySurferMotion — Setup Instructions

Follow every step in order. This takes about 10 minutes.

---

## Step 1 — Create a new Xcode project

1. Open **Xcode** (latest version).
2. From the menu bar: **File → New → Project…**
3. Choose **iOS → App** and click **Next**.
4. Fill in the fields:
   - **Product Name:** `SubwaySurferMotion`
   - **Team:** select your Apple ID (add one via Xcode → Settings → Accounts if needed)
   - **Organization Identifier:** `com.yourname` (e.g. `com.silvia`)
   - **Interface:** `SwiftUI`
   - **Language:** `Swift`
   - **Use Core Data:** ☐ unchecked
   - **Include Tests:** ☐ unchecked
5. Click **Next**, then choose your Desktop as the save location → **Create**.

---

## Step 2 — Replace Xcode's default files with our Swift files

Xcode generates `ContentView.swift` and `<AppName>App.swift` for you.
We need to **replace** those with our versions.

1. In the Xcode **Project Navigator** (left sidebar), click `ContentView.swift`.
2. Select all (⌘A) and delete the content.
3. Open **Finder → Desktop → SubwaySurferMotion** and open `ContentView.swift` in a text editor.
4. Copy everything and paste it into Xcode's `ContentView.swift`. Save (⌘S).
5. Do the same for `SubwaySurferMotionApp.swift`:
   - The file Xcode created is named `SubwaySurferMotionApp.swift` — open it, replace with our version.

---

## Step 3 — Add the remaining Swift files

We have 5 more files to add: `CameraManager.swift`, `PoseDetector.swift`,
`GestureClassifier.swift`, `TouchInjector.swift`, `AirPlayManager.swift`,
and `SkeletonOverlayView.swift`.

**For each file:**

1. In Xcode's Project Navigator, right-click the **yellow folder** with your app name.
2. Choose **Add Files to "SubwaySurferMotion"…**
3. Navigate to Desktop → SubwaySurferMotion, select the `.swift` file.
4. Make sure **"Copy items if needed"** is checked and the Target checkbox next to your app is ticked.
5. Click **Add**.

Repeat for all 6 files.

When you're done, the Project Navigator should show:
```
SubwaySurferMotion/
├── SubwaySurferMotionApp.swift
├── ContentView.swift
├── CameraManager.swift
├── PoseDetector.swift
├── GestureClassifier.swift
├── TouchInjector.swift
├── SkeletonOverlayView.swift
├── AirPlayManager.swift
└── Assets.xcassets
```

---

## Step 4 — Add the camera permission to Info.plist

1. In the Project Navigator, click **Info.plist**.
2. Hover over any row — a **+** button appears on the right. Click it.
3. Type `NSCameraUsageDescription` and press Return.
4. Set the **Type** to `String`.
5. Set the **Value** to:
   `SubwaySurferMotion needs your front camera to detect body pose gestures.`

---

## Step 5 — Set deployment target to iPadOS 16

1. Click the **blue project icon** at the very top of the Project Navigator.
2. Under **Targets**, click your app name.
3. Click the **General** tab.
4. Find **Minimum Deployments** → set iOS to **16.0**.

---

## Step 6 — Add the Vision and AVFoundation frameworks

These are Apple system frameworks — they're free and built into every iPad.

1. Still in the **General** tab, scroll down to **Frameworks, Libraries, and Embedded Content**.
2. Click **+**.
3. Search for `Vision` → click **Add**.
4. Click **+** again.
5. Search for `AVFoundation` → click **Add**.

---

## Step 7 — Connect your iPad Air

1. Plug your iPad Air into your Mac with a USB-C cable.
2. On the iPad: tap **Trust** when the dialog appears and enter your passcode.
3. In Xcode's toolbar (top), click the device selector (it probably says "Any iOS Device").
4. Your iPad Air should appear in the list — select it.

---

## Step 8 — Sign the app

1. In Xcode, click the **blue project icon** → select your target → **Signing & Capabilities**.
2. Tick **Automatically manage signing**.
3. Under **Team**, select your Apple ID.
4. Xcode may ask you to register a device — click **Register Device**.

---

## Step 9 — Build and Run!

Press **⌘R** (or the ▶ Play button in the toolbar).

Xcode will:
- Compile all the Swift files (~30 seconds the first time)
- Install the app on your iPad
- Launch it automatically

On your iPad, tap **OK** when asked for camera permission.

You should see:
- Live front camera feed filling the screen
- Green skeleton dots and lines drawn on top of your body
- Big white labels popping up when you lean, jump, or squat

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "Untrusted Developer" on iPad | iPad → Settings → General → VPN & Device Management → tap your email → Trust |
| "No front camera" error in console | Make sure you're running on a real iPad, not the Simulator |
| Skeleton doesn't appear | Stand 1–2 metres back from the iPad so your whole body is in frame |
| Build error "Cannot find type 'PoseFrame'" | Make sure all .swift files were added to the target (Step 3) |
| Gray screen, no camera | Check that NSCameraUsageDescription was added to Info.plist (Step 4) |

---

## How the gesture detection works (plain English)

```
Camera frame (1280×720 pixels, ~30 fps)
    ↓
PoseDetector runs Apple Vision → finds 19 body joints
    ↓
GestureClassifier keeps last 10 frames (~333ms of history)
  • LEAN LEFT/RIGHT  → hip midpoint X shifts > 15% from centre
  • JUMP             → both ankles rise > 20% of frame height in 3 frames
  • SQUAT            → hip midpoint drops > 20% of frame height in 3 frames
  • HOVERBOARD       → wrists converge within 10% of width, twice in 500ms
    ↓
TouchInjector logs the gesture + posts a NotificationCenter event
    ↓
SkeletonOverlayView draws the skeleton in real time
```

---

## Why it can't automatically control Subway Surfers

iOS sandboxes every app — no app can send touch events into another app.
This is a security feature Apple enforces at the OS level.

**What you CAN do:**
- Build your own Subway Surfers–style mini-game *inside this Xcode project* and wire it to the `touchInjector.onSwipe` callback in `ContentView.swift`.
- Use this app as a research prototype / portfolio piece showing motion control.
- If you want a full game, look into building with **SpriteKit** inside this project.
