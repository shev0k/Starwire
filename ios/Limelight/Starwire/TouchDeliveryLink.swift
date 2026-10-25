//
//  TouchDeliveryLink.swift
//  Starwire
//
//  Asks UIKit to deliver touches at the display's full rate during a stream. Batch 4.5 measured
//  60 touch deliveries a second on the 120 Hz iPad Pro, about 5 samples bundled in each and about
//  10 ms late: the video's display link runs on its own thread, so nothing on the main thread
//  asked for more, and finger scrolling felt laggy. iOS 18's UIUpdateLink with low-latency event
//  dispatch delivers touches as soon as they arrive; on iOS 17 a main-thread display link that
//  asks for 120 Hz is the fallback.
//
//  -StarwireTouchUpdateLink NO turns it off, to measure the difference.
//

import QuartzCore
import UIKit

final class TouchDeliveryLink {
    private var updateLink: AnyObject?
    private var displayLink: CADisplayLink?
    private let target = Target()

    /// Called at every display refresh while the link runs
    var onRefresh: () -> Void = {}

    private final class Target: NSObject {
        var onRefresh: () -> Void = {}
        @objc func tick(_ link: CADisplayLink) { onRefresh() }
    }

    /// Wanted for the touches, or for the paced scrolling's refreshes
    static var isWanted: Bool {
        UserDefaults.standard.object(forKey: "StarwireTouchUpdateLink") == nil
            || UserDefaults.standard.bool(forKey: "StarwireTouchUpdateLink")
    }

    /// Low-latency touch dispatch; off with -StarwireTouchUpdateLink NO, while the link may still
    /// run for the scroll pacing's refreshes
    static var lowLatencyTouches: Bool { isWanted }

    func start(in view: UIView) {
        guard Self.isWanted || StarwireStreamInput.pacesScrolling, updateLink == nil, displayLink == nil else { return }
        let maximum = Float(view.window?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond)
        let range = CAFrameRateRange(minimum: min(80, maximum), maximum: maximum, preferred: maximum)
        if #available(iOS 18.0, *) {
            let link = UIUpdateLink(view: view)
            link.addAction { [weak self] _, _ in self?.onRefresh() }
            link.requiresContinuousUpdates = true
            link.wantsLowLatencyEventDispatch = Self.lowLatencyTouches
            link.preferredFrameRateRange = range
            link.isEnabled = true
            updateLink = link
            StarwireLog.info("Input: touch delivery at up to \(Int(maximum)) Hz (update link, low-latency events)")
        } else {
            target.onRefresh = { [weak self] in self?.onRefresh() }
            let link = CADisplayLink(target: target, selector: #selector(Target.tick(_:)))
            link.preferredFrameRateRange = range
            link.add(to: .main, forMode: .common)
            displayLink = link
            StarwireLog.info("Input: touch delivery at up to \(Int(maximum)) Hz (display link)")
        }
    }

    func stop() {
        if #available(iOS 18.0, *), let link = updateLink as? UIUpdateLink {
            link.isEnabled = false
        }
        updateLink = nil
        displayLink?.invalidate()
        displayLink = nil
    }
}
