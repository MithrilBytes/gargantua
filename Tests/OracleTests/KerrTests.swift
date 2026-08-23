import Testing
import Foundation
import Oracle

@Suite struct KerrTests {
    @Test func photonOrbitRadiiBracketSchwarzschild() {
        let orbits = KerrGeodesic.equatorialPhotonOrbits(spin: 0.9)
        #expect(abs(orbits.prograde - 2.0 * (1.0 + cos(2.0 / 3.0 * acos(-0.9)))) < 1e-12)
        #expect(orbits.prograde < 3.0 && orbits.retrograde > 3.0)
        let zero = KerrGeodesic.equatorialPhotonOrbits(spin: 1e-9)
        #expect(abs(zero.prograde - 3.0) < 1e-3 && abs(zero.retrograde - 3.0) < 1e-3)
        for rc in [orbits.prograde, orbits.retrograde] {
            #expect(abs(KerrGeodesic.criticalEta(spin: 0.9, orbitRadius: rc)) < 1e-9)
        }
    }

    @Test func zeroSpinReducesToSchwarzschild() {
        let kerr = KerrGeodesic.Spacetime(spin: 0.0)
        let launchPoint = SIMD3(50.0, 0.0, 0.0)
        for aim in [0.15, 0.3] {
            let direction = SIMD3(-1.0, aim, 0.0)
            let kerrLaunch = KerrGeodesic.launch(kerr, from: launchPoint, direction: direction)
            let kerrResult = KerrGeodesic.integrate(kerr, from: kerrLaunch, settings: KerrGeodesic.Settings(stepCap: 100_000))
            let schwarzschild = Schwarzschild.integrate(Schwarzschild.launch(from: launchPoint, direction: direction),
                                                        settings: Schwarzschild.Settings(stepCap: 100_000))
            #expect(kerrResult.outcome == .escaped && schwarzschild.outcome == .escaped)
            // Same physical ray, both integrations to r = 60; the sweep is
            // the equatorial phi in both pictures.
            #expect(abs(kerrResult.state.phi - schwarzschild.ray.state.phi) < 2e-4,
                    "kerr \(kerrResult.state.phi) schwarzschild \(schwarzschild.ray.state.phi)")
        }
    }

    @Test func carterAndNullResidualHold() {
        let s = KerrGeodesic.Spacetime(spin: 0.9)
        for direction in [SIMD3(-1.0, 0.12, 0.0), SIMD3(-1.0, -0.09, 0.05), SIMD3(-0.9, 0.05, -0.2)] {
            let launch = KerrGeodesic.launch(s, from: SIMD3(45.0, 12.0, 9.0), direction: direction)
            #expect(abs(KerrGeodesic.nullResidual(s, launch)) < 1e-10)
            let result = KerrGeodesic.integrate(s, from: launch, settings: KerrGeodesic.Settings(stepCap: 100_000))
            #expect(result.outcome != .exhausted)
            #expect(result.drift < 1e-7, "drift \(result.drift)")
        }
    }

    @Test func shadowEdgesMatchBardeen() {
        let a = 0.9
        let s = KerrGeodesic.Spacetime(spin: a)
        let radius = 5000.0
        let settings = KerrGeodesic.Settings(stepMax: 1e9, escapeRadius: radius, stepCap: 40_000)
        // Bisect the capture boundary in aim angle on each side of the
        // equatorial line of sight and report the conserved xi = L / E at
        // the boundary, the impact parameter Bardeen's formulas predict.
        func criticalXi(side: Double) -> Double {
            var low = 0.0
            var high = 12.0 / radius
            for _ in 0..<48 {
                let aim = 0.5 * (low + high)
                let direction = SIMD3(-1.0, side * aim, 0.0)
                let launch = KerrGeodesic.launch(s, from: SIMD3(radius, 0.0, 0.0), direction: direction)
                let result = KerrGeodesic.integrate(s, from: launch, settings: settings)
                if result.outcome == .captured { low = aim } else { high = aim }
            }
            let boundary = KerrGeodesic.launch(s, from: SIMD3(radius, 0.0, 0.0), direction: SIMD3(-1.0, side * 0.5 * (low + high), 0.0))
            return boundary.angularMomentum / boundary.energy
        }
        let orbits = KerrGeodesic.equatorialPhotonOrbits(spin: a)
        let prograde = KerrGeodesic.criticalXi(spin: a, orbitRadius: orbits.prograde)
        let retrograde = KerrGeodesic.criticalXi(spin: a, orbitRadius: orbits.retrograde)
        let measuredPrograde = criticalXi(side: 1.0)
        let measuredRetrograde = criticalXi(side: -1.0)
        #expect(abs(measuredPrograde - prograde) / abs(prograde) < 1e-3,
                "prograde measured \(measuredPrograde) analytic \(prograde)")
        #expect(abs(measuredRetrograde - retrograde) / abs(retrograde) < 1e-3,
                "retrograde measured \(measuredRetrograde) analytic \(retrograde)")
        // The asymmetry the golden will hold the GPU to.
        #expect(abs(measuredRetrograde / measuredPrograde) > 2.0)
    }

    @Test func zeroAngularMomentumRaysAreDragged() {
        let s = KerrGeodesic.Spacetime(spin: 0.9)
        var launch = KerrGeodesic.launch(s, from: SIMD3(20.0, 0.0, 0.0), direction: SIMD3(-1.0, 0.0, 0.0))
        // Aim so the conserved axial angular momentum vanishes exactly.
        launch.angularMomentum = 0.0
        let result = KerrGeodesic.integrate(s, from: launch, settings: KerrGeodesic.Settings(stepCap: 100_000))
        #expect(result.outcome == .captured)
        #expect(result.state.phi > 0.05, "phi \(result.state.phi)")
    }
}
