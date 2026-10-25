//
//  DemoModeView.swift
//  Starwire
//
//  The demo mode (iOS Settings > Apps > Starwire > Demo mode): the app with no PC, built only from
//  StarwireKit's fakes. One "Demo PC" with its apps, a stream showing a moving test pattern on
//  the system video layer, the bitrate menu and the host metrics line, and every touch counted
//  by a recording input sink. The real screens come in phase 3; they'll use the same seams.
//

import AVFoundation
import StarwireKit
import SwiftUI
import UIKit

@objc(StarwireDemo)
final class StarwireDemo: NSObject {
    @objc static func makeViewController() -> UIViewController {
        StarwireLog.info("Demo mode: no PC is used")
        return UIHostingController(rootView: DemoHostsView(host: DemoMode.hostService()))
    }
}

struct DemoHostsView: View {
    let host: FakeHostService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        DemoAppsView(host: host)
                    } label: {
                        Label(DemoMode.hostName, systemImage: "desktopcomputer")
                            .accessibilityIdentifier("DemoHost")
                    }
                } footer: {
                    Text("Demo mode shows how Starwire works without a PC. Turn it off in iOS Settings > Apps > Starwire.")
                }
            }
            .navigationTitle("Starwire")
        }
    }
}

struct DemoAppsView: View {
    let host: FakeHostService
    @State private var apps: [HostApp] = []

    var body: some View {
        List(apps, id: \.id) { app in
            NavigationLink {
                DemoStreamScreen(host: host, app: app)
            } label: {
                VStack(alignment: .leading) {
                    Text(app.name)
                    if app.isControl {
                        Text(app.kind == .remoteInput ? "Input only, no picture" : "Your own display on the PC")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("DemoApp-\(app.name)")
        }
        .navigationTitle(DemoMode.hostName)
        .task {
            apps = (try? await host.appList()) ?? []
        }
    }
}

struct DemoStreamScreen: View {
    let host: FakeHostService
    let app: HostApp
    /// Shown full screen by the app: closes it. Pushed in a navigation stack: nil.
    var onClose: (() -> Void)?
    @State private var model = DemoStreamModel()
    @State private var showBitrates = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            DemoVideoView(model: model)
                .ignoresSafeArea()
                .accessibilityIdentifier("DemoVideo")
            VStack(alignment: .leading, spacing: 2) {
                Text(model.status)
                Text("\(model.frames) frames, \(model.inputEvents) input events")
                if !model.metrics.isEmpty {
                    Text(model.metrics)
                }
                if model.bitrate > 0 {
                    Text("Bitrate \(model.bitrate / 1000) Mbps")
                }
            }
            .font(.caption.monospacedDigit())
            .padding(8)
            .background(.black.opacity(0.6))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding()
            .accessibilityIdentifier("DemoOverlay")
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                showBitrates = true
            } label: {
                Image(systemName: "speedometer")
                    .padding(10)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .accessibilityLabel("Change bitrate")
            .padding()
            .confirmationDialog("Bitrate", isPresented: $showBitrates) {
                ForEach([10, 20, 50, 150, 300], id: \.self) { mbps in
                    Button("\(mbps) Mbps") {
                        Task { model.bitrate = (try? await host.setBitrate(kbps: mbps * 1000)) ?? 0 }
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let onClose {
                Button {
                    dismiss()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .padding(12)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .accessibilityLabel(L("ios_demo_end_stream"))
                .accessibilityIdentifier("DemoClose")
                .padding()
            }
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.start(host: host) }
        .onDisappear { model.stop() }
    }
}

/// The demo stream: DemoStreamSession on a display link, into a system video layer.
@Observable
final class DemoStreamModel {
    var status = "Starting"
    var frames = 0
    var inputEvents = 0
    var metrics = ""
    var bitrate = 0

    let input = RecordingInputSink()
    let video = SampleBufferVideoSink()
    private var session: DemoStreamSession?
    private var link: CADisplayLink?
    private var counter: CountingVideoSink?

    func start(host: FakeHostService) {
        let counter = CountingVideoSink()
        self.counter = counter
        let session = DemoStreamSession(video: TeeVideoSink([video, counter]), input: input, clock: SystemClock.shared,
                                        width: 640, height: 360, fps: 60)
        session.onStateChange = { [weak self] state in
            switch state {
            case .starting(let stage): self?.status = "Starting \(stage)"
            case .streaming: self?.status = "Streaming the demo picture at 60 FPS"
            case .ended: self?.status = "Ended"
            case .idle: break
            }
        }
        self.session = session
        session.start()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
        Task {
            if let metrics = try? await host.hardwareMetrics() {
                self.metrics = metrics.overlayText
            }
        }
    }

    @objc private func tick() {
        session?.tick()
        frames = counter?.framesShown ?? 0
        inputEvents = input.events.count
    }

    func stop() {
        link?.invalidate()
        link = nil
        session?.stop()
    }
}

/// Sends each frame to every sink.
final class TeeVideoSink: VideoSink {
    let sinks: [VideoSink]

    init(_ sinks: [VideoSink]) {
        self.sinks = sinks
    }

    func display(_ frame: VideoFrame) {
        sinks.forEach { $0.display(frame) }
    }

    func flush() {
        sinks.forEach { $0.flush() }
    }
}

/// The video layer, and touches turned into input events for the recording sink.
struct DemoVideoView: UIViewRepresentable {
    let model: DemoStreamModel

    func makeUIView(context: Context) -> DemoVideoUIView {
        let view = DemoVideoUIView()
        view.videoLayer = model.video.layer
        view.input = model.input
        view.layer.addSublayer(model.video.layer)
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: DemoVideoUIView, context: Context) {}
}

final class DemoVideoUIView: UIView {
    var videoLayer: CALayer?
    var input: InputSink?

    override func layoutSubviews() {
        super.layoutSubviews()
        videoLayer?.frame = bounds
    }

    private func send(_ touches: Set<UITouch>, _ phase: TouchPhase) {
        for touch in touches {
            let point = touch.location(in: self)
            input?.send(.touch(id: touch.hash, phase: phase, x: point.x / max(bounds.width, 1), y: point.y / max(bounds.height, 1)))
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { send(touches, .down) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { send(touches, .move) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { send(touches, .up) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { send(touches, .cancel) }
}
