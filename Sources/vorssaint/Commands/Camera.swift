// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import AppKit
import ArgumentParser
import CoreImage
import Foundation

// Single-frame camera capture via AVFoundation. A CLI has no bundle Info.plist,
// so TCC attributes camera access to the launching terminal; when permission is
// absent the command fails with a clear message rather than hanging.

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

private final class FrameGrabber: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var buffer: CMSampleBuffer?

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        lock.lock()
        if buffer == nil { buffer = sampleBuffer }
        lock.unlock()
        semaphore.signal()
    }

    func firstFrame(timeout: TimeInterval) -> CMSampleBuffer? {
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

enum CameraError: Error, CustomStringConvertible {
    case permission
    case noCamera
    case noFrame

    var description: String {
        switch self {
        case .permission:
            return "Camera access denied — grant Camera permission to your terminal (or vorssaint) in System Settings → Privacy & Security → Camera"
        case .noCamera:
            return "no camera found — this Mac has none connected, or the device is in use"
        case .noFrame:
            return "the camera produced no frame — it may be in use by another app, or permission was denied"
        }
    }
}

struct Camera: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Camera devices and single-frame capture",
        subcommands: [List.self, Shot.self],
        defaultSubcommand: List.self
    )

    static func devices() -> [AVCaptureDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified)
        return session.devices
    }

    static func ensureAccess() throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            let granted = Box(false)
            let sem = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .video) { ok in
                granted.value = ok
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 30)
            guard granted.value else { throw CameraError.permission }
        default:
            throw CameraError.permission
        }
    }

    static func positionName(_ p: AVCaptureDevice.Position) -> String {
        switch p {
        case .front: return "front"
        case .back: return "back"
        default: return "unspecified"
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List camera devices")
        @OptionGroup var g: GlobalOptions

        struct Device: Encodable {
            var index: Int, id: String, name: String, model: String, position: String, connected: Bool
        }

        func run() throws {
            wireOutput(g, command: "vorssaint camera list")
            let devices = Camera.devices().enumerated().map { i, dev in
                Device(index: i, id: dev.uniqueID, name: dev.localizedName, model: dev.modelID,
                       position: Camera.positionName(dev.position), connected: dev.isConnected)
            }
            if Out.json { Out.emit(devices) { "" }; return }
            if devices.isEmpty { print("no cameras found") }
            else {
                Out.table(["#", "NAME", "MODEL", "POSITION", "ID"], rows: devices.map {
                    [String($0.index), $0.name, $0.model, $0.position, $0.id]
                })
            }
        }
    }

    struct Shot: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Capture a single camera frame to PNG/JPEG",
            discussion: """
              vorssaint camera shot                     → ~/Pictures/vorssaint-camera-<time>.png
              vorssaint camera shot me.jpg --device 0
              vorssaint camera shot --device "FaceTime HD Camera" out.png
            """
        )
        @OptionGroup var g: GlobalOptions
        @Argument(help: "Output file (.png/.jpg); default ~/Pictures/vorssaint-camera-<time>.png") var output: String = ""
        @Option(name: .long, help: "Device index, unique id or name substring") var device: String?
        @Option(name: .long, help: "Seconds to wait for a frame") var timeout: Double = 8

        struct Result: Encodable {
            var path: String, bytes: Int, width: Int, height: Int, device: String
        }

        func run() throws {
            wireOutput(g, command: "vorssaint camera shot")
            guard timeout > 0 else { throw ValidationError("--timeout must be positive") }

            let path = output.isEmpty ? Self.defaultPath() : (output as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: path)
            let ext = url.pathExtension.lowercased()
            guard ["png", "jpg", "jpeg"].contains(ext) else {
                throw ValidationError("output must be .png, .jpg or .jpeg")
            }
            if FileManager.default.fileExists(atPath: url.path) {
                Out.fail("exists", "\(url.path) already exists — choose another output path")
            }

            let all = Camera.devices()
            guard let device = Self.resolve(device, in: all) else {
                Out.fail("not_found", CameraError.noCamera.description, exit: .notFound)
            }
            do { try Camera.ensureAccess() } catch let e as CameraError {
                Out.fail("permission", e.description, exit: .permission)
            }

            let session = AVCaptureSession()
            session.beginConfiguration()
            session.sessionPreset = .photo
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    Out.fail("camera_failed", "camera \(device.localizedName) cannot be added to a capture session")
                }
                session.addInput(input)
            } catch {
                Out.fail("camera_failed", "cannot open \(device.localizedName): \(error.localizedDescription)")
            }

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            let grabber = FrameGrabber()
            let queue = DispatchQueue(label: "vorssaint.camera.frames", qos: .userInitiated)
            output.setSampleBufferDelegate(grabber, queue: queue)
            guard session.canAddOutput(output) else {
                Out.fail("camera_failed", "camera \(device.localizedName) has no usable video output")
            }
            session.addOutput(output)
            session.commitConfiguration()

            session.startRunning()
            defer { session.stopRunning() }

            guard let sample = grabber.firstFrame(timeout: timeout) else {
                Out.fail("camera_timeout", CameraError.noFrame.description)
            }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else {
                Out.fail("camera_failed", "camera frame had no pixel buffer")
            }
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let ci = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ci, from: ci.extent) else {
                Out.fail("camera_failed", "could not convert the camera frame")
            }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            let fileType: NSBitmapImageRep.FileType = ext == "png" ? .png : .jpeg
            let props: [NSBitmapImageRep.PropertyKey: Any] = fileType == .jpeg ? [.compressionFactor: 0.9] : [:]
            guard let data = rep.representation(using: fileType, properties: props) else {
                Out.fail("camera_failed", "could not encode the camera frame")
            }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try data.write(to: url)
            } catch {
                Out.fail("write_failed", "cannot write \(url.path): \(error.localizedDescription)")
            }

            let r = Result(path: url.path, bytes: data.count, width: width, height: height,
                           device: device.localizedName)
            Out.emit(r) {
                "saved \(r.path) (\(r.width)×\(r.height), \(fmtBytes(UInt64(r.bytes)))) from \(r.device)"
            }
        }

        static func resolve(_ query: String?, in devices: [AVCaptureDevice]) -> AVCaptureDevice? {
            guard let query, !query.isEmpty else { return devices.first }
            if let index = Int(query), devices.indices.contains(index) { return devices[index] }
            return devices.first { $0.uniqueID == query }
                ?? devices.first { $0.localizedName.lowercased().contains(query.lowercased()) }
        }

        static func defaultPath() -> String {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd-HHmmss"
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures", isDirectory: true)
                .appendingPathComponent("vorssaint-camera-\(df.string(from: Date())).png").path
        }
    }
}
