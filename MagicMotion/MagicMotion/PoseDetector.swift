//
//  PoseDetector.swift
//  MagicMotion
//
//  Vision-based pose detector.
//  Returns the Vision-native PoseFrame (wraps VNHumanBodyPoseObservation).
//  When MediaPipe is linked, swap the implementation inside detect(image:).
//

import AVFoundation
import Vision

// MARK: - Delegate

protocol PoseDetectorDelegate: AnyObject {
    func poseDetector(_ detector: PoseDetector, didDetect frame: PoseFrame)
    func poseDetector(_ detector: PoseDetector, didFailWith error: Error)
}

// MARK: - PoseDetector

final class PoseDetector {

    // MARK: - Properties

    weak var delegate: PoseDetectorDelegate?
    var onPoseDetected: ((PoseFrame) -> Void)?

    private var frameCounter = 0

    private lazy var poseRequest: VNDetectHumanBodyPoseRequest = {
        let request = VNDetectHumanBodyPoseRequest()
        request.revision = VNDetectHumanBodyPoseRequestRevision1
        return request
    }()

    // MARK: - Init

    init() {}

    // MARK: - Public API

    /// Process a live camera frame.
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameCounter += 1

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .right,
            options: [:]
        )

        do {
            try handler.perform([poseRequest])
            guard let observation = poseRequest.results?.first else { return }
            let frame = PoseFrame(observation: observation, timestamp: Date())
            onPoseDetected?(frame)
            delegate?.poseDetector(self, didDetect: frame)
        } catch {
            delegate?.poseDetector(self, didFailWith: error)
        }
    }

    /// Synchronous detect from a sample buffer.
    func detect(image: CMSampleBuffer) -> PoseFrame? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(image) else { return nil }

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .right,
            options: [:]
        )

        do {
            try handler.perform([poseRequest])
            guard let observation = poseRequest.results?.first else { return nil }
            frameCounter += 1
            return PoseFrame(observation: observation, timestamp: Date())
        } catch {
            return nil
        }
    }

    /// Asynchronous detect.
    func detectAsync(image: CMSampleBuffer, completion: @escaping (PoseFrame?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.detect(image: image)
            DispatchQueue.main.async { completion(result) }
        }
    }

    func stop() {
        // No-op for Vision; add MediaPipe teardown here when integrated
    }
}
