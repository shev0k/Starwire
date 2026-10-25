import Foundation

// "Emulate gamepad motion sensor support" (checkbox_gamepad_motion_fallback): when the first
// controller has no motion sensors of its own, the device's gyro and accelerometer stand in for
// them. The axis table and units are Starwire for Android's ControllerHandler.createSensorListener
// (GPL-3.0); the conversion from Core Motion's units is new.

public enum MotionFallback {
    /// The interface's rotation from the device's natural (portrait) orientation, as Android's
    /// Display.getRotation(). iPadOS's landscape-right (Home button or USB-C port on the right)
    /// is Android's 90.
    public enum Rotation: Int, Sendable {
        case r0 = 0, r90 = 90, r180 = 180, r270 = 270
    }

    /// The host can ask for any rate; Android caps it at 200 Hz.
    public static let maxRateHz = 200
    public static let degreesPerRadian: Float = 57.2957795
    public static let standardGravity: Float = 9.80665

    public static func rate(requested: Int) -> Int {
        min(max(requested, 0), maxRateHz)
    }

    /// Turns a reading in Android's sensor axes (x right, y up, z out of the screen, in the
    /// natural orientation) into the controller's, for the screen's rotation.
    public static func controllerAxes(_ v: (x: Float, y: Float, z: Float), rotation: Rotation) -> (x: Float, y: Float, z: Float) {
        switch rotation {
        case .r0: return (v.x, v.z, -v.y)
        case .r90: return (-v.y, v.z, -v.x)
        case .r180: return (-v.x, v.z, v.y)
        case .r270: return (v.y, v.z, v.x)
        }
    }

    /// Core Motion's gyro (radians per second, right-handed like Android's) to the event the host
    /// gets: degrees per second, in the controller's axes.
    public static func gyroEvent(number: Int, radiansPerSecond r: (x: Double, y: Double, z: Double), rotation: Rotation) -> InputEvent {
        let a = controllerAxes((Float(r.x) * degreesPerRadian, Float(r.y) * degreesPerRadian, Float(r.z) * degreesPerRadian),
                               rotation: rotation)
        return .controllerMotion(number: number, sensor: .gyroscope, x: a.x, y: a.y, z: a.z)
    }

    /// Core Motion's accelerometer (in g, pointing the way gravity pulls: -1 on z lying face up)
    /// to the event: m/s² as Android's sensor reports it (+9.8 on z face up), in the controller's
    /// axes.
    public static func accelerometerEvent(number: Int, g: (x: Double, y: Double, z: Double), rotation: Rotation) -> InputEvent {
        let s = -standardGravity
        let a = controllerAxes((Float(g.x) * s, Float(g.y) * s, Float(g.z) * s), rotation: rotation)
        return .controllerMotion(number: number, sensor: .accelerometer, x: a.x, y: a.y, z: a.z)
    }
}
