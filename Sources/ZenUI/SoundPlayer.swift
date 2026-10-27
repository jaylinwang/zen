import AVFoundation
import ZenCore

@MainActor final class SoundPlayer {
    private(set) var player: AVAudioPlayer?
    private var signature = ""
    func stop() { player?.stop(); player = nil; signature = "" }
    func play(choice: SoundChoice, volume: Double, interval: Double) throws {
        guard choice != .silent && choice != .bell else { stop(); return }
        let key = choice == .wood ? "\(choice.rawValue)-\(interval)" : choice.rawValue
        if signature == key {
            player?.volume = Float(volume)
            if let player, !player.isPlaying { player.play() }
            return
        }
        try activateSession()
        let next = try AVAudioPlayer(data: Self.wave(choice: choice, interval: interval), fileTypeHint: "wav")
        next.numberOfLoops = Self.loopCount(for: choice); next.volume = Float(volume); next.prepareToPlay()
        guard next.play() else { throw RecordError.unavailable("声音无法播放") }
        player?.stop(); player = next; signature = key
    }
    private func activateSession() throws {
        #if os(iOS)
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try AVAudioSession.sharedInstance().setActive(true)
        #endif
    }
    static func loopCount(for choice: SoundChoice) -> Int { choice == .bell || choice == .silent ? 0 : -1 }
    func completion(volume: Double) {
        stop()
        guard volume > 0 else { return }
        do {
            try activateSession()
            let chime = try AVAudioPlayer(data: Self.wave(choice: .bell, interval: 1), fileTypeHint: "wav")
            chime.volume = Float(volume); chime.numberOfLoops = 0; chime.play(); player = chime
        } catch { NSLog("Zen completion sound: %@", error.localizedDescription) }
    }
    private static func resource(_ name: String) throws -> URL {
        let embedded = Bundle.main.resourceURL?.appendingPathComponent("Zen_ZenUI.bundle")
        let bundle = embedded.flatMap { Bundle(url: $0) } ?? Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: "wav") else {
            throw RecordError.unavailable("声音录音资源缺失，请重新安装应用")
        }
        return url
    }
    private static let bellData = Result { try Data(contentsOf: resource("qing")) }
    private static let pineData = Result { try Data(contentsOf: resource("pine")) }
    private static let rainData = Result { try Data(contentsOf: resource("rain")) }
    // Custom notification sounds must live in Library/Sounds and be shorter than 30 seconds.
    // Bake in this round's volume so an iPhone can still ring while the app is suspended.
    static func installBellNotificationSound(volume: Double, directory: URL? = nil) throws -> URL {
        let folder = try directory ?? FileManager.default.url(for: .libraryDirectory, in: .userDomainMask,
                                                              appropriateFor: nil, create: true).appendingPathComponent("Sounds")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("personal-zen-qing.wav")
        let source = try bellData.get()
        let gain = volume.isFinite ? max(0, min(1, volume)) : 0.35
        var samples: [Int16] = []; samples.reserveCapacity((source.count - 44) / 2)
        // qing.wav is our canonical 44-byte-header, mono 16-bit PCM asset.
        for offset in stride(from: 44, to: source.count, by: 2) {
            let bits = UInt16(source[offset]) | (UInt16(source[offset + 1]) << 8)
            samples.append(Int16(Double(Int16(bitPattern: bits)) * gain))
        }
        try pcmWave(samples, sampleRate: 44100).write(to: url, options: .atomic)
        return url
    }
    // A real mokugyo struck with its cloth-covered beater, recorded by jonopodmore (CC0).
    // Resource lookup also supports standalone command-line-built .app bundles.
    private static let recordedWood: Result<[Int16], Error> = Result {
        let url = try resource("mokugyo")
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: false)
        guard file.processingFormat.sampleRate == 44100, file.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw RecordError.unavailable("木鱼录音格式无法读取")
        }
        try file.read(into: buffer)
        guard let samples = buffer.int16ChannelData?[0], buffer.frameLength > 0 else {
            throw RecordError.unavailable("木鱼录音内容为空")
        }
        return Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
    }
    static func woodRecording() throws -> [Int16] { try recordedWood.get() }
    // Process once, then reuse the short mono tail. No engine or continuous DSP is needed.
    private static let spaciousWood: Result<[Double], Error> = Result {
        let source = try recordedWood.get()
        let count = 79380 // 1.8 seconds, leaving air between the default two-second strikes.
        var dry = [Double](repeating: 0, count: count)
        var low = 0.0
        let alpha = 1 - exp(-2 * Double.pi * 3200 / 44100)
        for i in source.indices {
            let sample = Double(source[i]) / 32768
            low += alpha * (sample - low)
            // Keep the wooden attack; soften only the brightest part of the transient.
            dry[i] = 0.78 * (0.72 * low + 0.28 * sample)
        }
        var wet = [Double](repeating: 0, count: count)
        // Unequal, damped combs give a diffuse room tail without a distinct repeated echo.
        for delay in [1499, 1601, 1867, 2053] {
            var buffer = [Double](repeating: 0, count: delay)
            var damped = 0.0
            for i in 0..<count {
                let slot = i % delay
                let echo = buffer[slot]
                damped += 0.62 * (echo - damped)
                buffer[slot] = dry[i] + damped * 0.89
                wet[i] += echo * 0.25
            }
        }
        // All-pass diffusion smears early reflections while preserving their energy.
        for delay in [211, 337] {
            var buffer = [Double](repeating: 0, count: delay)
            for i in 0..<count {
                let slot = i % delay
                let input = wet[i]
                let output = buffer[slot] - 0.5 * input
                buffer[slot] = input + 0.5 * output
                wet[i] = output
            }
        }
        return (0..<count).map { i in
            let fade = min(1, Double(count - 1 - i) / 8820)
            return (dry[i] + 0.48 * wet[i]) * fade
        }
    }
    static func wave(choice: SoundChoice, interval: Double) throws -> Data {
        if choice == .wood {
            let recording = try spaciousWood.get()
            let seconds = interval.isFinite ? max(1, min(15, interval)) : 2
            let frames = Int(seconds * 44100)
            var mixed = [Double](repeating: 0, count: frames)
            // Fold the decay into the next cycle at short intervals instead of truncating it.
            for (index, value) in recording.enumerated() { mixed[index % frames] += value }
            let peak = mixed.map { abs($0) }.max() ?? 0
            let gain = peak > 0.9 ? 0.9 / peak : 1
            let samples = mixed.map { Int16(max(-1, min(1, $0 * gain)) * 32767) }
            return pcmWave(samples, sampleRate: 44100)
        }
        switch choice {
        case .bell: return try bellData.get()
        case .pine: return try pineData.get()
        case .rain: return try rainData.get()
        case .silent: return pcmWave(Array(repeating: 0, count: 44100), sampleRate: 44100)
        case .wood: preconditionFailure("Wood handled above")
        }
    }
    private static func pcmWave(_ values: [Int16], sampleRate: Int) -> Data {
        var samples = Data(capacity: values.count * 2)
        for value in values {
            var sample = value.littleEndian
            withUnsafeBytes(of: &sample) { samples.append(contentsOf: $0) }
        }
        var wave = Data()
        func tag(_ s: String) { wave.append(contentsOf: s.utf8) }
        func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { wave.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { wave.append(contentsOf: $0) } }
        tag("RIFF"); u32(UInt32(36 + samples.count)); tag("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16); tag("data"); u32(UInt32(samples.count)); wave.append(samples)
        return wave
    }
}
