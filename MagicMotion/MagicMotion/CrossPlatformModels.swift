import Foundation
import AVFoundation

/// Universal PoseFrame model - designed for cross-platform porting
/// This same struct can be ported to Kotlin, TypeScript, C++ with zero logic changes
public struct CPPoseFrame: Codable {
    /// 33 MediaPipe landmarks (nose, shoulders, elbows, wrists, hips, knees, ankles, etc.)
    public let landmarks: [Landmark]
    
    /// Timestamp when pose was detected
    public let timestamp: TimeInterval
    
    /// Detection confidence (0.0 - 1.0)
    public let confidence: Float
    
    /// Whether the frame is valid for gesture recognition
    public let isValid: Bool
    
    /// Unique frame identifier
    public let frameId: Int
    
    public struct Landmark: Codable {
        /// Normalized X coordinate (0.0 - 1.0, left to right)
        public let x: Float
        
        /// Normalized Y coordinate (0.0 - 1.0, top to bottom)
        public let y: Float
        
        /// Depth coordinate (0.0 - 1.0, near to far)
        public let z: Float
        
        /// Visibility score (0.0 - 1.0, how confident is detection)
        public let visibility: Float
        
        /// Index in MediaPipe's 33-point skeleton
        public let index: Int
        
        /// Whether this landmark should be used (visibility > threshold)
        public var isVisible: Bool {
            visibility > 0.5
        }
    }
    
    /// MediaPipe landmark indices (same across all platforms)
    public enum BodyPart: Int, CaseIterable {
        // Face (8)
        case nose = 0
        case leftEyeInner = 1
        case leftEye = 2
        case leftEyeOuter = 3
        case rightEyeInner = 4
        case rightEye = 5
        case rightEyeOuter = 6
        case leftEar = 7
        case rightEar = 8
        
        // Mouth (4)
        case mouthLeft = 9
        case mouthRight = 10
        
        // Shoulders (2)
        case leftShoulder = 11
        case rightShoulder = 12
        
        // Arms (4)
        case leftElbow = 13
        case rightElbow = 14
        case leftWrist = 15
        case rightWrist = 16
        
        // Torso (4)
        case leftHip = 23
        case rightHip = 24
        case leftKnee = 25
        case rightKnee = 26
        
        // Legs (4)
        case leftAnkle = 27
        case rightAnkle = 28
        
        public var name: String {
            switch self {
            case .nose: return "Nose"
            case .leftEye: return "Left Eye"
            case .rightEye: return "Right Eye"
            case .leftShoulder: return "Left Shoulder"
            case .rightShoulder: return "Right Shoulder"
            case .leftElbow: return "Left Elbow"
            case .rightElbow: return "Right Elbow"
            case .leftWrist: return "Left Wrist"
            case .rightWrist: return "Right Wrist"
            case .leftHip: return "Left Hip"
            case .rightHip: return "Right Hip"
            case .leftKnee: return "Left Knee"
            case .rightKnee: return "Right Knee"
            case .leftAnkle: return "Left Ankle"
            case .rightAnkle: return "Right Ankle"
            default: return "Unknown"
            }
        }
    }
    
    // MARK: - Gesture-Friendly Accessors
    
    /// Get landmark by body part
    public func landmark(for part: BodyPart) -> Landmark? {
        landmarks.first { $0.index == part.rawValue }
    }
    
    /// Get multiple landmarks (for compound gestures)
    public func landmarks(for parts: [BodyPart]) -> [Landmark] {
        parts.compactMap { landmark(for: $0) }
    }
    
    /// Calculate distance between two landmarks
    public func distance(from: BodyPart, to: BodyPart) -> Float? {
        guard let l1 = landmark(for: from),
              let l2 = landmark(for: to),
              l1.isVisible && l2.isVisible else {
            return nil
        }
        
        let dx = l1.x - l2.x
        let dy = l1.y - l2.y
        let dz = l1.z - l2.z
        
        return sqrt(dx * dx + dy * dy + dz * dz)
    }
    
    /// Calculate angle between three landmarks (in degrees)
    public func angle(from: BodyPart, vertex: BodyPart, to: BodyPart) -> Float? {
        guard let p1 = landmark(for: from),
              let p2 = landmark(for: vertex),
              let p3 = landmark(for: to),
              p1.isVisible && p2.isVisible && p3.isVisible else {
            return nil
        }
        
        let v1 = (x: p1.x - p2.x, y: p1.y - p2.y)
        let v2 = (x: p3.x - p2.x, y: p3.y - p2.y)
        
        let dotProduct = v1.x * v2.x + v1.y * v2.y
        let mag1 = sqrt(v1.x * v1.x + v1.y * v1.y)
        let mag2 = sqrt(v2.x * v2.x + v2.y * v2.y)
        
        guard mag1 > 0 && mag2 > 0 else { return nil }
        
        let cosAngle = dotProduct / (mag1 * mag2)
        let angle = acos(max(-1, min(1, cosAngle))) * 180 / .pi
        
        return angle
    }
    
    /// Check if a landmark is above/below a threshold
    public func isAbove(_ part: BodyPart, yThreshold: Float) -> Bool? {
        guard let lm = landmark(for: part) else { return nil }
        return lm.y < yThreshold
    }
    
    /// Check if landmarks are aligned horizontally (within tolerance)
    public func areHorizontallyAligned(_ parts: [BodyPart], tolerance: Float = 0.05) -> Bool {
        let visibleLandmarks = parts.compactMap { landmark(for: $0) }.filter { $0.isVisible }
        guard visibleLandmarks.count >= 2 else { return false }
        
        let yValues = visibleLandmarks.map { $0.y }
        let maxY = yValues.max() ?? 0
        let minY = yValues.min() ?? 0
        
        return (maxY - minY) < tolerance
    }
}

/// Protocol for platform-agnostic pose detection
/// This same protocol can be implemented in Kotlin, TypeScript, C++
public protocol PoseDetectorProtocol {
    associatedtype ImageType
    
    /// Initialize detector with model
    init(modelPath: String) throws
    
    /// Detect pose in image
    func detect(image: ImageType) -> CPPoseFrame?
    
    /// Detect pose asynchronously
    func detectAsync(image: ImageType, completion: @escaping (CPPoseFrame?) -> Void)
    
    /// Clean up resources
    func stop()
}

/// Base class for gesture classification - designed for cross-platform porting
open class CPGestureClassifier {
    /// Minimum confidence for gesture detection
    open var confidenceThreshold: Float = 0.7
    
    /// Smoothing factor for landmark positions (0.0 = no smoothing, 1.0 = full smoothing)
    open var smoothingFactor: Float = 0.3
    
    /// State tracking for complex gestures
    private var gestureState: [String: Any] = [:]
    
    public init() {}
    
    /// Classify gesture from pose frame - override in subclasses
    open func classify(frame: CPPoseFrame) -> CPGesture? {
        // Subclasses implement gesture-specific logic
        // This keeps the interface platform-agnostic
        nil
    }
    
    // MARK: - Helper Methods (Platform-Independent Logic)
    
    /// Smooth landmark positions over time
    public func smooth(current: Float, previous: Float) -> Float {
        previous * smoothingFactor + current * (1 - smoothingFactor)
    }
    
    /// Check if pose is valid for gesture recognition
    public func isPoseValid(_ frame: CPPoseFrame) -> Bool {
        // Must have at least 20 visible landmarks
        let visibleCount = frame.landmarks.filter { $0.isVisible }.count
        return visibleCount >= 20 && frame.confidence > confidenceThreshold
    }
    
    /// Store gesture state (for multi-frame gestures)
    public func setState(_ key: String, value: Any) {
        gestureState[key] = value
    }
    
    /// Retrieve gesture state
    public func getState(_ key: String) -> Any? {
        gestureState[key]
    }
    
    /// Clear gesture state
    public func clearState() {
        gestureState.removeAll()
    }
}

/// Platform-independent gesture enum
public enum CPGesture: String, Codable, Equatable {
    // Movement gestures
    case idle
    case swipeLeft
    case swipeRight
    case swipeUp
    case swipeDown
    case jump
    case duck
    
    // Hand gestures
    case thumbsUp
    case thumbsDown
    case pointLeft
    case pointRight
    case openHands
    case closedFists
    
    // Pose gestures
    case tPose
    case raiseArms
    case standingSideways
    case none
    
    public var description: String {
        switch self {
        case .idle: return "Idle"
        case .swipeLeft: return "Swipe Left"
        case .swipeRight: return "Swipe Right"
        case .swipeUp: return "Swipe Up"
        case .swipeDown: return "Swipe Down"
        case .jump: return "Jump"
        case .duck: return "Duck"
        case .thumbsUp: return "Thumbs Up"
        case .thumbsDown: return "Thumbs Down"
        case .pointLeft: return "Point Left"
        case .pointRight: return "Point Right"
        case .openHands: return "Open Hands"
        case .closedFists: return "Closed Fists"
        case .tPose: return "T-Pose"
        case .raiseArms: return "Raise Arms"
        case .standingSideways: return "Standing Sideways"
        case .none: return "No Gesture"
        }
    }
}

/// Cross-platform game command generated from gestures
public struct CPGameCommand: Codable {
    public let gesture: CPGesture
    public let timestamp: TimeInterval
    public let confidence: Float
    
    /// Game action (same across all platforms)
    public enum Action: String, Codable {
        case moveLeft
        case moveRight
        case jump
        case duck
        case idle
    }
    
    public var action: Action {
        switch gesture {
        case .swipeLeft, .pointLeft: return .moveLeft
        case .swipeRight, .pointRight: return .moveRight
        case .jump, .raiseArms: return .jump
        case .duck, .openHands: return .duck
        default: return .idle
        }
    }
    
    public init(gesture: CPGesture, timestamp: TimeInterval = Date().timeIntervalSince1970, confidence: Float = 1.0) {
        self.gesture = gesture
        self.timestamp = timestamp
        self.confidence = confidence
    }
}
