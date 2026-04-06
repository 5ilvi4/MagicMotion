// LeanRecognizer.swift
// MagicMotion
//
// BodyRecognizer: detects leftward and rightward body lean from PoseSnapshot.
//
// Logic mirrors the existing MotionInterpreter lean detection exactly,
// so behaviour is identical when migrated from the monolith.
//
// Config keys (all optional — defaults match current MotionInterpreter values):
//   "threshold"  Double   hip-to-shoulder lateral offset required to call a lean (default 0.08)

import Foundation

final class LeanRecognizer: BodyRecognizer {

    let id: RecognizerID = .bodyLean

    // MARK: - Tuning

    /// Hip-centre x must differ from shoulder-centre x by at least this amount.
    var threshold: Float = 0.08

    // MARK: - BodyRecognizer

    func configure(with config: RecognizerConfig) {
        if let v = config["threshold"] { threshold = Float(v) }
    }

    func reset() {}

    func process(snapshot: PoseSnapshot) -> AppIntent? {
        guard let hip      = snapshot.hipCenter,
              let shoulder = snapshot.shoulderCenter else { return nil }

        if hip.x < shoulder.x - threshold { return .leanLeft  }
        if hip.x > shoulder.x + threshold { return .leanRight }
        return nil
    }
}
