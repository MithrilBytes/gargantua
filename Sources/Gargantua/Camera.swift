import simd

/// Orbit camera looking at the hole. The disk lies in the xy plane with z up.
struct OrbitCamera: Equatable {
    var azimuth: Float = 0.6
    var elevation: Float = 0.32
    var distance: Float = 52.0
    var fovY: Float = 50.0 * .pi / 180.0

    static let minimumDistance: Float = 6.0
    /// Inside the escape radius, so every ray still starts inside the scene.
    static let maximumDistance: Float = 56.0
    static let near: Float = 0.1
    static let far: Float = 1000.0

    var position: SIMD3<Float> {
        let c = cos(elevation)
        return distance * SIMD3(c * cos(azimuth), c * sin(azimuth), sin(elevation))
    }

    var forward: SIMD3<Float> { simd_normalize(-position) }
    var right: SIMD3<Float> { simd_normalize(simd_cross(forward, SIMD3(0, 0, 1))) }
    var up: SIMD3<Float> { simd_cross(right, forward) }

    mutating func orbit(deltaX: Float, deltaY: Float) {
        azimuth -= deltaX * 0.005
        elevation = min(max(elevation + deltaY * 0.005, -1.5), 1.5)
    }

    mutating func dolly(_ amount: Float) {
        distance = min(max(distance * exp(-amount * 0.05), OrbitCamera.minimumDistance), OrbitCamera.maximumDistance)
    }

    func viewMatrix() -> float4x4 {
        let eye = position
        let f = forward
        let s = right
        let u = up
        return float4x4(columns: (
            SIMD4(s.x, u.x, -f.x, 0),
            SIMD4(s.y, u.y, -f.y, 0),
            SIMD4(s.z, u.z, -f.z, 0),
            SIMD4(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)))
    }

    func projectionMatrix(aspect: Float) -> float4x4 {
        let y = 1.0 / tan(fovY * 0.5)
        let x = y / aspect
        let range = OrbitCamera.far - OrbitCamera.near
        return float4x4(columns: (
            SIMD4(x, 0, 0, 0),
            SIMD4(0, y, 0, 0),
            SIMD4(0, 0, -OrbitCamera.far / range, -1),
            SIMD4(0, 0, -OrbitCamera.far * OrbitCamera.near / range, 0)))
    }

    /// Pixels per world unit at unit depth for a viewport of the given height.
    func pixelsPerUnit(viewportHeight: Float) -> Float {
        viewportHeight / (2.0 * tan(fovY * 0.5))
    }
}
