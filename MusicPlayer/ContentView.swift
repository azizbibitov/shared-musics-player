//
//  ContentView.swift
//  MusicPlayer
//
//  Created by Aziz Bibitov on 17.04.2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var player = AudioPlayerManager()

    var body: some View {
        VStack(spacing: 30) {
            Text("Simple Music Player")
                .font(.title)

            Slider(value: Binding(
                get: { player.currentTime },
                set: { player.seek(to: $0) }
            ), in: 0...player.duration)

            HStack {
                Text(formatTime(player.currentTime))
                Spacer()
                Text(formatTime(player.duration))
            }
            .font(.caption)

            Button(action: {
                player.togglePlay()
            }) {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
            }
        }
        .padding()
        .onAppear {
            player.loadAudio(named: "sample") // Add sample.mp3 to bundle
        }
    }

    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ContentView()
}
