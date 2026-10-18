//
//  PoseAnalyzer.swift
//  FormCoach
//
//  Reads a workout video frame by frame, runs on-device body pose detection,
//  steadies the skeleton against camera drift, and feeds the results into a
//  rep tracker. Nothing leaves the device.
//

import Foundation
import AVFoundation
import Vision

nonisolated final class PoseAnalyzer {

    struct Progress: Sendable {
        var fraction: Double = 0
        var framesProcessed: Int = 0
        var repsFound: Int = 0
    }

    static let jointOrder: [VNHumanBodyPoseObservation.JointName] = [
        .nose, .neck, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
        .leftWrist, .rightWrist, .leftHip, .rightHip, .leftKnee, .rightKnee,
        .leftAnkle, .rightAnkle, .root, .leftEar, .rightEar, .leftEye, .rightEye,
    ]

    /// Analyzes the video at ~12 samples per second, capped at 5 minutes.
    func analyze(
        videoURL: URL,
        exercise: Exercise,
        onProgress: @escaping @Sendable (Progress) -> Void
    ) async throws -> WorkoutAnalysis {
        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw AnalysisError.videoUnavailable
        }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw AnalysisError.videoUnavailable }
        let size = try await track.load(.naturalSize)
        let videoAspect = Float(abs(size.width) / max(abs(size.height), 0.001))
        let maxDuration = Float(min(duration, 300))

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()

        let tracker = RepTracker(exercise: exercise)
        let request = VNDetectHumanBodyPoseRequest()
        var frames: [PoseFrame] = []
        var lastAnalyzed: Double = -1
        var framesProcessed = 0
        var confidentFrames = 0
        let step: Double = 1.0 / 12.0

        // Camera-motion tracking: every sample aligns the whole frame with the
        // previous one. Only the camera can shift the background, so the shift
        // is the camera's movement — and subtracting it steadies the person.
        var previousBuffer: CVPixelBuffer?
        var sampleShifts: [CGPoint?] = []
        var movingSamples = 0

        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                throw CancellationError()
            }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard time.isFinite else { continue }
            guard lastAnalyzed < 0 || time - lastAnalyzed >= step else { continue }
            lastAnalyzed = time
            guard time <= Double(maxDuration) else { break }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }

            var shift: CGPoint?
            if let previous = previousBuffer {
                shift = Self.cameraShift(reference: previous, floating: pixelBuffer)
                if let shift, Float(hypot(shift.x, shift.y)) > Self.movingShiftThreshold {
                    movingSamples += 1
                }
            }
            previousBuffer = pixelBuffer
            sampleShifts.append(shift)

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            try? handler.perform([request])

            if let observation = (request.results as? [VNHumanBodyPoseObservation])?.first,
               let recognized = try? observation.recognizedPoints(.all) {
                var points = [JointPoint](repeating: JointPoint(), count: Self.jointOrder.count)
                var validCount = 0
                for (index, name) in Self.jointOrder.enumerated() {
                    if let point = recognized[name] {
                        points[index] = JointPoint(
                            x: Float(point.location.x),
                            y: Float(point.location.y),
                            confidence: Float(point.confidence)
                        )
                        if point.confidence > 0.3 { validCount += 1 }
                    }
                }
                if validCount >= 6 { confidentFrames += 1 }

                let frame = PoseFrame(time: Float(time), points: points)
                tracker.process(frame: frame)
                frames.append(frame)
                framesProcessed += 1
            }

            if framesProcessed % 12 == 0 {
                onProgress(Progress(
                    fraction: min(time / Double(max(maxDuration, 1)), 0.99),
                    framesProcessed: framesProcessed,
                    repsFound: tracker.reps.count
                ))
                await Task.yield()
            }
        }

        tracker.finalize(duration: maxDuration)

        guard confidentFrames >= 5 else { throw AnalysisError.noPersonDetected }

        // Shake correction: when the camera drifted but not too wildly, strip
        // its movement from the skeleton and score the steadied motion instead.
        var correctedFrames = frames
        var corrected = false
        var finalTracker = tracker
        if let offsets = Self.cameraOffsets(sampleShifts) {
            correctedFrames = zip(frames, offsets).map { $0.offsetBy(dx: -Float($1.x), dy: -Float($1.y)) }
            let steadied = RepTracker(exercise: exercise)
            for frame in correctedFrames { steadied.process(frame: frame) }
            steadied.finalize(duration: maxDuration)
            finalTracker = steadied
            corrected = true
        }

        let motionSamples = max(sampleShifts.count - 1, 0)
        let maxPairShift = sampleShifts.compactMap { $0.map { Float(hypot($0.x, $0.y)) } }.max()
        let cameraMotion = CameraMotion(
            unstableFraction: motionSamples > 0 ? Float(movingSamples) / Float(motionSamples) : 0,
            maxPairShift: maxPairShift,
            corrected: corrected
        )

        let tempoLabel: String
        if exercise.isHold, let last = finalTracker.reps.first {
            tempoLabel = "Held for \(Int(last.end)) sec"
        } else if finalTracker.reps.isEmpty {
            tempoLabel = "No \(exercise.unitSingular)s detected"
        } else if let summary = finalTracker.summaryLabel {
            tempoLabel = summary
        } else {
            tempoLabel = String(format: "%.1f sec down · %.1f sec up", finalTracker.averageDown, finalTracker.averageUp)
        }

        onProgress(Progress(fraction: 1, framesProcessed: framesProcessed, repsFound: finalTracker.reps.count))

        return FormEvaluator.evaluate(
            exercise: exercise,
            reps: finalTracker.reps,
            duration: maxDuration,
            videoAspect: videoAspect,
            // Replay draws over the original, unsteadied video, so keep the
            // raw skeleton for display; correction only feeds the scoring.
            frames: frames,
            tempoLabel: tempoLabel,
            unverifiedChecks: finalTracker.unverifiedChecks,
            cameraMotion: cameraMotion
        )
    }

    /// Per-sample whole-frame shift (as a fraction of frame width, samples ~1/12 s
    /// apart) above which the camera counts as moving. Roughly 12% of the frame
    /// width per second — well above handheld jitter, so only real panning trips it.
    fileprivate static let movingShiftThreshold: Float = 0.02

    /// A single pair shift above this is a violent pan or a scene cut; drift that
    /// big can't be corrected reliably, so the clip keeps its raw pose data and
    /// distance-based checks get skipped instead.
    fileprivate static let correctableShiftLimit: Float = 0.08

    /// Whole-frame shift between two buffers, in normalized coordinates, or nil
    /// when registration fails (frame lost track, scene cut, no overlap).
    private static func cameraShift(reference: CVPixelBuffer, floating: CVPixelBuffer) -> CGPoint? {
        let request = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: floating, options: [:])
        let handler = VNSequenceRequestHandler()
        try? handler.perform([request], on: reference)
        guard let observation = request.results?.first as? VNImageTranslationAlignmentObservation else { return nil }
        var tx = CGFloat(observation.alignmentTransform.tx)
        var ty = CGFloat(observation.alignmentTransform.ty)
        // The transform arrives either normalized (0–1) or in pixels depending on
        // the pipeline path; anything above 4 can only be pixels, so rescale it.
        // Pixel space is top-left origin; Vision coordinates are bottom-left, so
        // the vertical component flips sign on the way in.
        let magnitude = Float(hypot(tx, ty))
        if magnitude > 4 {
            tx /= CGFloat(max(CVPixelBufferGetWidth(reference), 1))
            ty = -ty / CGFloat(max(CVPixelBufferGetHeight(reference), 1))
        }
        return CGPoint(x: tx, y: ty)
    }

    /// Cumulative camera drift at each sample, smoothed so registration noise
    /// doesn't inject jitter into the skeleton. Returns nil when tracking was
    /// lost too often or any single shift was too violent to correct.
    private static func cameraOffsets(_ shifts: [CGPoint?]) -> [CGPoint]? {
        guard shifts.count > 12 else { return nil }
        let measured = shifts.compactMap { $0 }
        guard Float(measured.count) / Float(shifts.count - 1) >= 0.9 else { return nil }
        guard let maxShift = measured.map({ Float(hypot($0.x, $0.y)) }).max(),
              maxShift <= correctableShiftLimit else { return nil }

        var cumulative: [CGPoint] = []
        cumulative.reserveCapacity(shifts.count)
        var current = CGPoint.zero
        for shift in shifts {
            if let shift {
                current = CGPoint(x: current.x + shift.x, y: current.y + shift.y)
            }
            cumulative.append(current)
        }

        // Moving average over ~0.75 s of samples removes per-pair noise while
        // still following a real pan.
        let window = 9
        guard cumulative.count > window else { return nil }
        var smoothed: [CGPoint] = []
        smoothed.reserveCapacity(cumulative.count)
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for (index, offset) in cumulative.enumerated() {
            sumX += offset.x
            sumY += offset.y
            if index >= window {
                sumX -= cumulative[index - window].x
                sumY -= cumulative[index - window].y
            }
            let divisor = min(index + 1, window)
            smoothed.append(CGPoint(x: sumX / CGFloat(divisor), y: sumY / CGFloat(divisor)))
        }
        return smoothed
    }
}
