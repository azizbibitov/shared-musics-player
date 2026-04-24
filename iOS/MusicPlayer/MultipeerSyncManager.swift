import MultipeerConnectivity
import Foundation
import UIKit

private struct SyncMessage: Codable {
    enum Kind: String, Codable { case trackList, requestFile }
    let kind: Kind
    let tracks: [Track]?
    let filename: String?
    let tombstoneIDs: [UUID]?
}

struct FileTransfer: Identifiable {
    let id: String // filename
    let trackName: String
    var fraction: Double
}

@Observable
final class MultipeerSyncManager: NSObject {
    static let serviceType = "azico-music"

    var connectedPeers: [MCPeerID] = []
    var activeTransfers: [FileTransfer] = []

    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    private var pendingTracks: [MCPeerID: [String: Track]] = [:]
    private var progressObservations: [String: NSKeyValueObservation] = [:]
    private var sendQueue: [(filename: String, peer: MCPeerID)] = []
    private var activeSendCount = 0
    private let maxConcurrentSends = 3

    weak var tracksViewModel: TracksViewModel? {
        didSet { if tracksViewModel != nil { syncWithConnectedPeers() } }
    }

    private let instanceID = UUID().uuidString

    override init() {
        super.init()
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .optional)
        session.delegate = self
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: ["id": instanceID], serviceType: Self.serviceType)
        advertiser.delegate = self
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        browser.delegate = self
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func syncWithConnectedPeers() {
        print("[Sync] syncWithConnectedPeers - peers: \(session.connectedPeers.map { $0.displayName }), tracksVM: \(tracksViewModel != nil)")
        for peer in session.connectedPeers {
            sendTrackList(to: peer)
        }
    }

    private func sendTrackList(to peer: MCPeerID) {
        guard let vm = tracksViewModel else {
            print("[Sync] sendTrackList - SKIPPED, tracksViewModel is nil")
            return
        }
        print("[Sync] sendTrackList to \(peer.displayName) - \(vm.tracks.count) tracks")
        let msg = SyncMessage(kind: .trackList, tracks: vm.tracks, filename: nil, tombstoneIDs: Array(vm.tombstoneIDs))
        guard let data = try? JSONEncoder().encode(msg) else {
            print("[Sync] sendTrackList - FAILED to encode")
            return
        }
        do {
            try session.send(data, toPeers: [peer], with: .reliable)
            print("[Sync] sendTrackList - sent \(data.count) bytes")
        } catch {
            print("[Sync] sendTrackList - send error: \(error)")
        }
    }

    private func requestMissingTracks(from peer: MCPeerID, theirTracks: [Track], theirTombstones: Set<UUID>) {
        guard let vm = tracksViewModel else {
            print("[Sync] requestMissingTracks - SKIPPED, tracksViewModel is nil")
            return
        }
        // Delete any local tracks the peer has tombstoned
        vm.applyTombstones(theirTombstones)

        let myIDs = Set(vm.tracks.map { $0.id })
        // Don't request tracks we've deleted ourselves
        let missing = theirTracks.filter { !myIDs.contains($0.id) && !vm.tombstoneIDs.contains($0.id) }
        print("[Sync] requestMissingTracks from \(peer.displayName) - they have \(theirTracks.count), I have \(vm.tracks.count), missing \(missing.count)")
        guard !missing.isEmpty else { return }
        missing.forEach { pendingTracks[peer, default: [:]][$0.filename] = $0 }
        for track in missing {
            print("[Sync] requesting file: \(track.filename) (\(track.name))")
            let msg = SyncMessage(kind: .requestFile, tracks: nil, filename: track.filename, tombstoneIDs: nil)
            guard let data = try? JSONEncoder().encode(msg) else { continue }
            try? session.send(data, toPeers: [peer], with: .reliable)
        }
    }

    private func enqueueSendFile(named filename: String, to peer: MCPeerID) {
        sendQueue.append((filename: filename, peer: peer))
        processSendQueue()
    }

    private func processSendQueue() {
        while activeSendCount < maxConcurrentSends, !sendQueue.isEmpty {
            let item = sendQueue.removeFirst()
            let fileURL = Storage.baseURL.appendingPathComponent(item.filename)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("[Sync] sendFile - file NOT FOUND: \(item.filename)")
                continue
            }
            activeSendCount += 1
            print("[Sync] sendFile \(item.filename) to \(item.peer.displayName) (active: \(activeSendCount))")
            let filename = item.filename
            let progress = session.sendResource(at: fileURL, withName: filename, toPeer: item.peer) { [weak self] error in
                if let error = error {
                    print("[Sync] sendResource error: \(error)")
                } else {
                    print("[Sync] sendResource completed: \(filename)")
                }
                DispatchQueue.main.async {
                    self?.activeSendCount -= 1
                    self?.removeTransfer(filename: filename)
                    self?.processSendQueue()
                }
            }
            if let progress {
                addTransfer(filename: filename, trackName: filename, progress: progress)
            }
        }
    }

    private func addTransfer(filename: String, trackName: String, progress: Progress) {
        let observation = progress.observe(\.fractionCompleted) { [weak self] p, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                guard let idx = self.activeTransfers.firstIndex(where: { $0.id == filename }) else { return }
                self.activeTransfers[idx].fraction = p.fractionCompleted
            }
        }
        DispatchQueue.main.async {
            if !self.activeTransfers.contains(where: { $0.id == filename }) {
                self.activeTransfers.append(FileTransfer(id: filename, trackName: trackName, fraction: 0))
            }
            self.progressObservations[filename] = observation
        }
    }

    private func removeTransfer(filename: String) {
        activeTransfers.removeAll { $0.id == filename }
        progressObservations.removeValue(forKey: filename)
    }
}

extension MultipeerSyncManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let stateStr = state == .connected ? "connected" : state == .notConnected ? "notConnected" : "connecting"
        print("[Sync] peer \(peerID.displayName) state -> \(stateStr)")
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) { self.connectedPeers.append(peerID) }
                self.sendTrackList(to: peerID)
            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
                self.pendingTracks.removeValue(forKey: peerID)
                self.sendQueue.removeAll { $0.peer == peerID }
                if self.session.connectedPeers.isEmpty {
                    self.activeSendCount = 0
                    self.activeTransfers.removeAll()
                    self.progressObservations.removeAll()
                }
            default: break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let msg = try? JSONDecoder().decode(SyncMessage.self, from: data) else {
            print("[Sync] didReceive - failed to decode \(data.count) bytes from \(peerID.displayName)")
            return
        }
        print("[Sync] didReceive \(msg.kind.rawValue) from \(peerID.displayName)")
        switch msg.kind {
        case .trackList:
            guard let theirTracks = msg.tracks else { return }
            let theirTombstones = Set(msg.tombstoneIDs ?? [])
            DispatchQueue.main.async { self.requestMissingTracks(from: peerID, theirTracks: theirTracks, theirTombstones: theirTombstones) }
        case .requestFile:
            guard let filename = msg.filename else { return }
            DispatchQueue.main.async { self.enqueueSendFile(named: filename, to: peerID) }
        }
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        let trackName = pendingTracks[peerID]?[resourceName]?.name ?? resourceName
        addTransfer(filename: resourceName, trackName: trackName, progress: progress)
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        print("[Sync] didFinishReceivingResource \(resourceName) from \(peerID.displayName) error: \(String(describing: error))")
        DispatchQueue.main.async { self.removeTransfer(filename: resourceName) }
        guard error == nil, let tempURL = localURL,
              let track = pendingTracks[peerID]?[resourceName] else {
            print("[Sync] didFinishReceivingResource - guard failed: error=\(String(describing: error)), tempURL=\(String(describing: localURL)), trackFound=\(pendingTracks[peerID]?[resourceName] != nil)")
            return
        }
        Task {
            let dest = Storage.baseURL.appendingPathComponent(track.filename)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.copyItem(at: tempURL, to: dest)
            }
            await MainActor.run {
                self.tracksViewModel?.addSyncedTrack(track)
                self.pendingTracks[peerID]?.removeValue(forKey: resourceName)
                print("[Sync] addSyncedTrack: \(track.name)")
            }
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
}

extension MultipeerSyncManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Accept only if the inviter has a lower instanceID (they are the designated inviter)
        if let data = context, let theirID = String(data: data, encoding: .utf8) {
            let accept = theirID < instanceID
            invitationHandler(accept, accept ? session : nil)
        } else {
            invitationHandler(true, session)
        }
    }
}

extension MultipeerSyncManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard peerID.displayName != myPeerID.displayName else { return }
        guard !session.connectedPeers.contains(peerID) else { return }
        // Only invite if our instanceID is lower - prevents both sides inviting simultaneously
        guard let theirID = info?["id"], instanceID < theirID else { return }
        let context = instanceID.data(using: .utf8)
        browser.invitePeer(peerID, to: session, withContext: context, timeout: 10)
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
