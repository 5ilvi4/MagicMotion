// SyntheticFrameSource.swift
// MotionMind
//
// A fake FrameSource that fires dummy frames at 30fps from a Timer.
// Used in debug/test builds to drive the pipeline without a real camera.

import AVFoundation
import Combine
import CoreMedia
import CoreVideo

/// Fires synthetic CMSampleBuffers on a 30fps timer.
/// Zero camera dependencies — runs in Simulator and on device.
class SyntheticFrameSource: FrameSource {

    // MARK: - FrameSource

    var onNewFrame: ((CMSampleBuffer, CGImagePropertyOrientation) -> Void)?

    private(set) var isRunning: Bool = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        scheduleTimer()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private var timer: Timer?

    private func scheduleTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.fireFrame()
        }
    }

    private func fireFrame() {
        guard let buffer = makeDummySampleBuffer() else { return }
        onNewFrame?(buffer, .up)
    }

    // MARK: - Dummy CMSampleBuffer factory

    /// Creates a 1×1 black pixel buffer wrapped in a CMSampleBuffer.
    /// The content doesn't matter — MotionEngine uses this only to drive timing;
    /// in a real fake-pose scenario FakeMotionSource bypasses the camera entirely.
    private func makeDummySampleBuffer() -> CMSampleBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1,
            kCVPixelBufferHeightKey as String: 1,
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, 1, 1,
                                  kCVPixelFormatType_32BGRA,
                                  attrs as CFDictionary,
                                  &pixelBuffer) == kCVReturnSuccess,
              let pb = pixelBuffer else { return nil }

        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pb,
            formatDescriptionOut: &formatDesc
        )
        guard let fd = formatDesc else { return nil }
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pb,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fd,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }
}
