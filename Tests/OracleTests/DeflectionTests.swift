import Testing
import Foundation
import Oracle

@Suite struct DeflectionTests {
    @Test func nearlyRadialRaysSweepByBOverR() {
        let sweep = Deflection.sweep(fromRadius: 100.0, impactParameter: 0.01)
        #expect(abs(sweep - 0.01 / 100.0) < 1e-9)
    }

    @Test func periapsisMatchesTheOrbitEquation() {
        for b in [6.0, 10.0, 30.0, 1000.0] {
            let peri = Deflection.periapsis(impactParameter: b)
            let residual = 1.0 - b * b / (peri * peri) * (1.0 - 2.0 / peri)
            #expect(abs(residual) < 1e-12, "b \(b)")
            #expect(peri < b && peri > 3.0)
        }
    }

    @Test func turningSweepReproducesWeakFieldDeflection() {
        let b = 1000.0
        let peri = Deflection.periapsis(impactParameter: b)
        let deflection = 2.0 * Deflection.sweep(fromRadius: peri, impactParameter: b) - Double.pi
        #expect(abs(deflection - 4.0 / b) / (4.0 / b) < 0.005, "deflection \(deflection)")
        let total = Deflection.escapeSweep(fromRadius: 1e7, impactParameter: b)
        #expect(abs(total - (deflection + Double.pi - b / 1e7)) < 1e-7)
    }

    @Test func tableCoordinateRoundTrips() {
        for t in [0.0, 0.1, 0.5, 0.9, 1.0] {
            let b = Deflection.tableImpactParameter(low: 2.0, high: 30.0, t: t)
            #expect(abs(Deflection.tableCoordinate(low: 2.0, high: 30.0, impactParameter: b) - t) < 1e-12)
        }
    }

    @Test func sweepAgreesWithTheIntegrator() {
        let b = 10.0
        let launch = Schwarzschild.launch(radius: 50_000.0, impactParameter: b)
        var settings = Schwarzschild.Settings(stepMax: 2.0, escapeRadius: 50_000.0, stepCap: 200_000)
        settings.stepFactor = 0.01
        let result = Schwarzschild.integrate(launch, settings: settings)
        #expect(result.outcome == .escaped)
        let expected = Deflection.turningSweep(fromRadius: 50_000.0, impactParameter: b)
        #expect(abs(result.ray.state.phi - expected) < 1e-5, "integrated \(result.ray.state.phi) table \(expected)")
    }

    @Test func tablesAreMonotoneAndBounded() {
        let sphere = Deflection.sweepTable(fromRadius: 30.0, count: 256)
        #expect(sphere.first == 0.0)
        #expect(zip(sphere, sphere.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(sphere.last! < Double.pi)
        let sky = Deflection.skyTable(cameraRadius: 52.0, sphereRadius: 30.0, count: 256)
        #expect(sky.allSatisfy { $0 > 0.0 && $0 < 2.0 * Double.pi })
    }
}
