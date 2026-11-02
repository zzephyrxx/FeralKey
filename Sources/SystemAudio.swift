// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

// Audio output only: no screen output callback, microphone, recording or upload.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var generation = 0
    private let queue = DispatchQueue(label: "feralkey.system-audio")
    private var lastEmission: TimeInterval = 0
    private var analyzer = AudioSpectrumAnalyzer()
    private let onFrame: (Double,[Double]) -> Void
    private let onFailure: () -> Void
    init(onFrame: @escaping (Double,[Double]) -> Void, onFailure: @escaping () -> Void) {
        self.onFrame = onFrame; self.onFailure = onFailure
    }
    @MainActor func start() async throws {
        generation += 1; let current = generation
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard current == generation else { return }
        guard let display = content.displays.first else { throw RKError.message("没有可用于系统音频采集的显示器。") }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = 2; config.height = 2
        config.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 1)
        config.capturesAudio = true; config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000; config.channelCount = 2
        if #available(macOS 15.0, *) { config.captureMicrophone = false }
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        stream = newStream
        do { try await newStream.startCapture() }
        catch { if current == generation { stream = nil }; try? await newStream.stopCapture(); throw error }
        if current != generation { try? await newStream.stopCapture() }
    }
    func stop() {
        generation += 1
        let previous = stream; stream = nil
        if let previous { Task { try? await previous.stopCapture() } }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self, weak stream] in
            guard let self, let stream, self.stream === stream else { return }
            self.stream = nil; self.onFailure()
        }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, buffer.isValid,
              let description = buffer.formatDescription else { return }
        let count = CMSampleBufferGetNumSamples(buffer)
        guard count > 0, count <= 96000 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: asbd) else { return }
        guard (1...8).contains(format.channelCount), format.commonFormat == .pcmFormatFloat32 else { return }
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return }
        pcm.frameLength = AVAudioFrameCount(count)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(buffer, at: 0, frameCount: Int32(count), into: pcm.mutableAudioBufferList) == noErr else { return }
        var mono = [Double](repeating:0,count:count)
        var channelCounts = [Int](repeating:0,count:count)
        // A single interleaved buffer and multiple planar buffers have
        // different pointer layouts. Honor each buffer's actual byte bound.
        for audioBuffer in UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList) {
            let channels = Int(audioBuffer.mNumberChannels)
            guard (1...8).contains(channels), let data = audioBuffer.mData else { continue }
            let frames = min(count, Int(audioBuffer.mDataByteSize)/(MemoryLayout<Float>.size*channels))
            let values = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frames {
                for channel in 0..<channels {
                    let value = Double(values[frame*channels+channel])
                    if value.isFinite { mono[frame] += value; channelCounts[frame] += 1 }
                }
            }
        }
        for index in mono.indices where channelCounts[index] > 0 { mono[index] /= Double(channelCounts[index]) }
        analyzer.append(mono)
        guard now-lastEmission >= 1.0/Double(LightingRate.maximumFPS) else { return }; lastEmission = now
        let level = AudioEnvelope.level(sumSquares:mono.reduce(0) { $0+$1*$1 },count:mono.count)
        let bands = analyzer.bands(sampleRate:asbd.pointee.mSampleRate)
        DispatchQueue.main.async { [weak self, weak stream] in
            guard let self, let stream, self.stream === stream else { return }
            self.onFrame(level,bands)
        }
    }
}
