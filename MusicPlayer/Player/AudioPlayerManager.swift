import AVFoundation
import MediaPlayer
import Observation

@Observable
final class AudioPlayerManager: NSObject, AVAudioPlayerDelegate {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 1
    var currentTrack: Track?
    var isPlayerViewOpen = false

    private var player: AVAudioPlayer?
    private var timer: Timer?

    override init() {
        super.init()
        setupAudioSession()
        setupRemoteControls()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    private func setupRemoteControls() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlay()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: e.positionTime)
            return .success
        }
    }

    func load(_ track: Track, autoPlay: Bool = false) {
        stop()
        currentTrack = track
        currentTime = 0
        Task { @MainActor in
            do {
                self.player = try AVAudioPlayer(contentsOf: track.url)
                self.player?.delegate = self
                self.player?.prepareToPlay()
                self.duration = self.player?.duration ?? 1
                self.updateNowPlaying()
                if autoPlay { self.play() }
            } catch {
                print("Error loading audio: \(error)")
            }
        }
    }

    func play() {
        player?.play()
        isPlaying = player?.isPlaying ?? false
        if isPlaying { startTimer() }
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
        updateNowPlaying()
    }

    func stop() {
        player?.stop()
        isPlaying = false
        stopTimer()
        currentTime = 0
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func dismiss() {
        stop()
        currentTrack = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func seek(to value: TimeInterval) {
        player?.currentTime = value
        currentTime = value
        updateNowPlaying()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.currentTime = self.player?.currentTime ?? 0
            self.updateNowPlaying()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let track = currentTrack {
            info[MPMediaItemPropertyTitle] = track.name
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        stopTimer()
        updateNowPlaying()
    }
}
