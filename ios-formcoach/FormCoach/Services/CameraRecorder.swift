//
//  CameraRecorder.swift
//  FormCoach
//
//  On-device video capture for filming workout clips: AVCaptureSession +
//  movie file output, with permission and hardware availability states.
//  The recorded file is handed back like a library pick, so the rest of the
//  analyze pipeline doesn't know the difference.
//

import AVFoundation
import CoreMedia
import Foundation
import SwiftUI
import UIKit

@MainActor
@Observable
final class CameraRecorder: NSObject {

    enum Availability {
        case checking
        case ready
        case unauthorized
        case unavailable
    }

    /// Called with the recorded clip's temporary URL.
    var onFinish: (URL) -> Void = { _ in }

    private(set) var availability: Availability = .checking
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var position: AVCaptureDevice.Position = .back

    let session = AVCaptureSession()

    private let movieOutput = AVCaptureMovieFileOutput()
    private let maxDuration: TimeInterval = 300
    private var elapsedTask: Task<Void, Never>?

    /// Checks permissions, wires up the capture session, and starts the preview.
    func start() async {
        guard availability == .checking else { return }

        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraStatus == .denied || cameraStatus == .restricted {
            availability = .unauthorized
            return
        }
        if cameraStatus != .authorized {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                availability = .unauthorized
                return
            }
        }
        // Mic is optional — a silent clip still analyzes fine.
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }

        let configured = await Self.configure(session: session, output: movieOutput, position: position)
        guard configured else {
            availability = .unavailable
            return
        }
        await Self.run(session: session)
        availability = .ready
    }

    func shutdown() {
        stopRecording()
        elapsedTask?.cancel()
        Self.stop(session: session)
    }

    // MARK: - Recording

    func startRecording() {
        guard availability == .ready, !isRecording else { return }
        let fileName = UUID().uuidString
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
            .appendingPathExtension("mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
        isRecording = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        elapsedTask = Task { [weak self, output = movieOutput] in
            while !Task.isCancelled {
                self?.elapsed = output.recordedDuration.seconds
                try? await Task.sleep(for: .seconds(0.2))
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        elapsedTask?.cancel()
        movieOutput.stopRecording()
    }

    /// Switches between front and back cameras, keeping the session alive.
    func flipCamera() {
        guard availability == .ready, !isRecording else { return }
        position = position == .back ? .front : .back
        Task {
            let reconfigured = await Self.replaceVideoInput(session: session, position: position)
            if !reconfigured { position = position == .back ? .front : .back }
        }
    }

    // MARK: - Session plumbing (nonisolated: session work shouldn't hitch the UI)

    private nonisolated static func configure(
        session: AVCaptureSession,
        output: AVCaptureMovieFileOutput,
        position: AVCaptureDevice.Position
    ) async -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1920x1080

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: position
        )
        guard let device = discovery.devices.first else { return false }
        guard let videoInput = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(videoInput) else { return false }
        session.addInput(videoInput)

        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           let mic = AVCaptureDevice.default(.builtInMicrophone, for: .audio, position: .unspecified),
           let audioInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        output.maxRecordedDuration = CMTime(seconds: 300, preferredTimescale: 600)
        if let connection = output.connection(with: .video) {
            if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
            if connection.isVideoMirroringSupported, device.position == .front {
                connection.isVideoMirrored = true
            }
        }
        return true
    }

    private nonisolated static func replaceVideoInput(
        session: AVCaptureSession,
        position: AVCaptureDevice.Position
    ) async -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        for input in session.inputs where input is AVCaptureDeviceInput {
            session.removeInput(input)
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: position
        )
        guard let device = discovery.devices.first,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        return true
    }

    private nonisolated static func run(session: AVCaptureSession) async {
        session.startRunning()
    }

    private nonisolated static func stop(session: AVCaptureSession) {
        session.stopRunning()
    }
}

// MARK: - Recording delegate

// Delegate callbacks arrive off the main actor and hop back for state updates.
extension CameraRecorder: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        Task { @MainActor in
            isRecording = false
            elapsed = 0
            // Max-duration auto-stop may report an error; the file is still good.
            guard FileManager.default.fileExists(atPath: outputFileURL.path) else { return }
            onFinish(outputFileURL)
        }
    }
}

// MARK: - Preview layer

/// Live viewfinder backed by the shared capture session.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
