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

    private final class Target: NSObject {
        @objc func tick(_ link: CADisplayLink) {}
    }

    static var isWanted: Bool {
        UserDefaults.standard.object(forKey: "StarwireTouchUpdateLink") == nil
            || UserDefaults.standard.bool(forKey: "StarwireTouchUpdateLink")
    }

    func start(in view: UIView) {
        guard Self.isWanted, updateLink == nil, displayLink == nil else { return }
        let maximum = Float(view.window?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond)
        let range = CAFrameRateRange(minimum: min(80, maximum), maximum: maximum, preferred: maximum)
        if #available(iOS 18.0, *) {
            let link = UIUpdateLink(view: view)
            link.addAction { _, _ in }
            link.requiresContinuousUpdates = true
            link.wantsLowLatencyEventDispatch = true
            link.preferredFrameRateRange = range
            link.isEnabled = true
            updateLink = link
            StarwireLog.info("Input: touch delivery at up to \(Int(maximum)) Hz (update link, low-latency events)")
        } else {
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
