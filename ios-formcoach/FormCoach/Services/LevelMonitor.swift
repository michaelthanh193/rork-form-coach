//
//  LevelMonitor.swift
//  FormCoach
//
//  Live tilt from CoreMotion while filming: how far the phone leans away from
//  upright, and how steady it's held. Together they decide when the camera
//  screen's level turns green. When motion data isn't available (simulator,
//  external camera) the level reads steady so recording is never blocked.
//

import CoreMotion
import Foundation

@MainActor
@Observable
final class LevelMonitor {

    /// Signed left/right lean in degrees, driving the level bar's floating dot.
    private(set) var rollDegrees: Double = 0
    /// True when the phone is upright enough and not wobbling.
    private(set) var isLevel = true
    /// False when the device has no motion data — the level then stays green.
    private(set) var isAvailable = false

    static let tiltTolerance: Double = 8
    static let wobbleTolerance: Double = 2.5
    /// Roll that drives the dot to the edge of the level bar.
    static let fullScaleRoll: Double = 15

    private let manager = CMMotionManager()
    private var recentTilts: [Double] = []

    func start() {
        guard manager.isDeviceMotionAvailable else {
            isAvailable = false
            return
        }
        isAvailable = true
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            let gravity = motion?.gravity
            Task { @MainActor in
                guard let self, let gravity else { return }
                self.ingest(gravity: gravity)
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        recentTilts.removeAll()
    }

    private func ingest(gravity: CMAcceleration) {
        // 0° means the phone's long axis is vertical — the side-on filming pose.
        let tilt = acos(min(1, max(-1, -gravity.y))) * 180 / .pi
        rollDegrees = atan2(gravity.x, -gravity.y) * 180 / .pi

        recentTilts.append(tilt)
        if recentTilts.count > 15 { recentTilts.removeFirst() }
        let mean = recentTilts.reduce(0, +) / Double(recentTilts.count)
        let wobble = sqrt(recentTilts.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(recentTilts.count))

        isLevel = tilt < Self.tiltTolerance && wobble < Self.wobbleTolerance
    }
}
