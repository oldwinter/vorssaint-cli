// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

/// Mutable hand-off between a completion handler and the thread waiting on it.
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

// In-process screen recording built on ScreenCaptureKit + AVAssetWriter.
//
// The public SCK APIs used here (SCShareableContent, SCStream,
// SCContentFilter) are the supported replacement for the deprecated
// CGWindowListCreateImage path.

enum ScreenRecorderError: Error, CustomStringConvertible {
    case permission
    case noDisplays
    case displayNotFound(UInt32)
    case startFailed(String)
    case writerFailed(String)
    case noFrames

    var description: String {
        switch self {
        case .permission:
            return "Screen Recording permission not granted — enable it for your terminal (or vorssaint) in System Settings → Privacy & Security → Screen Recording"
        case .noDisplays:
            return "no displays available to capture"
        case .displayNotFound(let id):
            return "no display with id \(id) — see `vorssaint display list`"
        case .startFailed(let m):
            return "could not start capture: \(m)"
        case .writerFailed(let m):
            return "could not write video: \(m)"
        case .noFrames:
            return "no frames were captured (recording is empty)"
        }
    }
}

/// Synchronous facade so commands can stay plain top-level code while the
/// capture callback runs on its own queue.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    struct Result {
        var path: String
        var bytes: Int
        var seconds: Double
        var frames: Int
        var display: String
        var displayID: UInt32
    }

    private let outputURL: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let lock = NSLock()
    private var sessionStarted = false
    private var frames = 0
    private var firstPTS: CMTime?
    private var lastPTS: CMTime?
    private var failure: Error?

    private init(outputURL: URL, width: Int, height: Int) throws {
        self.outputURL = outputURL
        let fileType: AVFileType = outputURL.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
        } catch {
            throw ScreenRecorderError.writerFailed(error.localizedDescription)
        }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw ScreenRecorderError.writerFailed("H.264 input rejected at \(width)×\(height)")
        }
        writer.add(input)
        super.init()
    }

    /// Record the primary display (or `displayID`) for `duration` seconds.
    /// A duration of 0 records until SIGINT. `progress` runs once capture starts.
    static func record(outputURL: URL, displayID: UInt32?, duration: Double, fps: Int,
                       showsCursor: Bool, progress: (String) -> Void) throws -> Result {
        guard CGPreflightScreenCaptureAccess() else { throw ScreenRecorderError.permission }

        let content = try shareableContent()
        guard !content.displays.isEmpty else { throw ScreenRecorderError.noDisplays }
        let targetID = displayID ?? CGMainDisplayID()
        let display: SCDisplay
        if let match = content.displays.first(where: { $0.displayID == targetID }) {
            display = match
        } else if displayID == nil, let first = content.displays.first {
            display = first
        } else {
            throw ScreenRecorderError.displayNotFound(targetID)
        }

        // SCK reports display dimensions in pixels; CG is a cross-check so
        // H.264 always gets even dimensions.
        var width = CGDisplayPixelsWide(display.displayID)
        var height = CGDisplayPixelsHigh(display.displayID)
        if width <= 0 { width = display.width }
        if height <= 0 { height = display.height }
        width -= width % 2
        height -= height % 2

        let recorder = try ScreenRecorder(outputURL: outputURL, width: width, height: height)
        return try recorder.run(display: display, duration: duration, fps: fps,
                                showsCursor: showsCursor, progress: progress)
    }

    private func run(display: SCDisplay, duration: Double, fps: Int,
                     showsCursor: Bool, progress: (String) -> Void) throws -> Result {
        guard writer.startWriting() else {
            throw ScreenRecorderError.writerFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }

        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = showsCursor
        config.queueDepth = 8

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        let queue = DispatchQueue(label: "vorssaint.record.frames", qos: .userInitiated)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        } catch {
            throw ScreenRecorderError.startFailed(error.localizedDescription)
        }

        try startCapture(stream)
        progress("recording \(display.displayID) (\(display.width)×\(display.height)) → \(outputURL.path)")

        // Ctrl-C stops early; --duration stops at the deadline.
        nonisolated(unsafe) var interrupted = false
        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        sigint.setEventHandler { interrupted = true }
        sigint.resume()
        defer { sigint.cancel() }

        let deadline = duration > 0 ? Date().addingTimeInterval(duration) : .distantFuture
        while !interrupted {
            if Date() >= deadline { break }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        stopCapture(stream)
        try finishWriting()

        if let failure { throw ScreenRecorderError.writerFailed(failure.localizedDescription) }
        guard frames > 0, let first = firstPTS, let last = lastPTS else {
            try? FileManager.default.removeItem(at: outputURL)
            throw ScreenRecorderError.noFrames
        }

        let seconds = max(0, CMTimeGetSeconds(CMTimeSubtract(last, first)))
        let bytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
        return Result(path: outputURL.path, bytes: bytes, seconds: seconds,
                      frames: frames, display: displayName(display), displayID: display.displayID)
    }

    // MARK: - Stream lifecycle

    private func startCapture(_ stream: SCStream) throws {
        let error = Box<Error?>(nil)
        let sem = DispatchSemaphore(value: 0)
        stream.startCapture { error.value = $0; sem.signal() }
        guard sem.wait(timeout: .now() + 15) == .success else {
            throw ScreenRecorderError.startFailed("timed out waiting for ScreenCaptureKit")
        }
        if let error = error.value { throw ScreenRecorderError.startFailed(error.localizedDescription) }
    }

    private func stopCapture(_ stream: SCStream) {
        let sem = DispatchSemaphore(value: 0)
        stream.stopCapture { _ in sem.signal() }
        _ = sem.wait(timeout: .now() + 10)
    }

    private func finishWriting() throws {
        lock.lock()
        let started = sessionStarted
        lock.unlock()
        if started { input.markAsFinished() }
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        guard sem.wait(timeout: .now() + 20) == .success else {
            throw ScreenRecorderError.writerFailed("timed out finalizing the file")
        }
        if writer.status == .failed, let e = writer.error {
            throw ScreenRecorderError.writerFailed(e.localizedDescription)
        }
    }

    // MARK: - SCStreamOutput / SCStreamDelegate

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        lock.lock()
        defer { lock.unlock() }
        if failure != nil { return }
        if !sessionStarted {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: pts)
            firstPTS = pts
            sessionStarted = true
        }
        guard input.isReadyForMoreMediaData else { return }
        if input.append(sampleBuffer) {
            frames += 1
            lastPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        } else {
            failure = writer.error
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        if failure == nil { failure = error }
        lock.unlock()
    }

    // MARK: - Helpers

    private static func shareableContent() throws -> SCShareableContent {
        let content = Box<SCShareableContent?>(nil)
        let error = Box<Error?>(nil)
        let sem = DispatchSemaphore(value: 0)
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { c, e in
            content.value = c
            error.value = e
            sem.signal()
        }
        guard sem.wait(timeout: .now() + 15) == .success else {
            throw ScreenRecorderError.startFailed("timed out asking ScreenCaptureKit for displays")
        }
        if let error = error.value {
            if (error as NSError).code == -3801 { throw ScreenRecorderError.permission }
            throw ScreenRecorderError.startFailed(error.localizedDescription)
        }
        guard let content = content.value else {
            throw ScreenRecorderError.startFailed("ScreenCaptureKit returned no content")
        }
        return content
    }

    private func displayName(_ display: SCDisplay) -> String {
        let id = display.displayID
        return NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == id
        }?.localizedName ?? "display \(id)"
    }
}
