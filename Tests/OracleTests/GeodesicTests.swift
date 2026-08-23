import Testing
import Foundation
import Oracle

@Suite struct GeodesicTests {
    @Test func launchReproducesOriginDirectionAndNullCondition() {
        let origin = SIMD3(30.0, -10.0, 12.0)
        let direction = SIMD3(-0.8, 0.3, -0.1)
        let ray = Schwarzschild.launch(from: origin, direction: direction)
        let unit = direction / (direction * direction).sum().squareRoot()
        #expect((ray.position - origin).max() < 1e-12 && (origin - ray.position).max() < 1e-12)
        #expect(abs((ray.direction * unit).sum() - 1.0) < 1e-12)
        #expect(abs(Schwarzschild.nullResidual(ray.state)) < 1e-12)
        let r0 = (origin * origin).sum().squareRoot()
        #expect(abs(ray.energy - Schwarzschild.f(r0).squareRoot()) < 1e-12)
    }

    @Test func impactParameterLaunchMatchesItsDefinition() {
        let ray = Schwarzschild.launch(radius: 50.0, impactParameter: 5.0)
        #expect(abs(ray.impactParameter - 5.0) < 1e-12)
        #expect(ray.state.rDot < 0)
    }

    @Test func conservedQuantitiesHoldInDoublePrecision() {
        let ray = Schwarzschild.launch(from: SIMD3(40.0, 5.0, 15.0), direction: SIMD3(-0.95, -0.2, -0.3))
        let result = Schwarzschild.integrate(ray, settings: .still)
        #expect(result.outcome != .exhausted)
        // The step policy, not the precision, sets this floor: halving the
        // step factor drops the drift by about sixteen, as fourth order does.
        #expect(result.drift < 1e-6)
        #expect(abs(Schwarzschild.nullResidual(result.ray.state)) < 1e-6)
        var finer = Schwarzschild.Settings.still
        finer.stepFactor *= 0.5
        finer.stepMin *= 0.5
        finer.stepMax *= 0.5
        let refined = Schwarzschild.integrate(ray, settings: finer)
        #expect(refined.drift < result.drift / 8.0)
    }

    @Test func criticalImpactParameterIsThreeRootThree() {
        let critical = Schwarzschild.criticalImpactParameter(launchRadius: 50.0, settings: .still)
        #expect(abs(critical - Constants.criticalImpactParameter.value) / Constants.criticalImpactParameter.value < 1e-4)
    }

    @Test func raysInsideAndOutsideTheCriticalImpactParameterBehave() {
        let inside = Schwarzschild.integrate(Schwarzschild.launch(radius: 50.0, impactParameter: 4.0), settings: .still)
        let outside = Schwarzschild.integrate(Schwarzschild.launch(radius: 50.0, impactParameter: 7.0), settings: .still)
        #expect(inside.outcome == .captured)
        #expect(outside.outcome == .escaped)
    }

    @Test func weakFieldDeflectionIsFourOverB() {
        let b = 1000.0
        let radius = 50_000.0
        let settings = Schwarzschild.Settings(stepMax: .infinity, escapeRadius: radius, stepCap: 4096)
        let launch = Schwarzschild.launch(radius: radius, impactParameter: b)
        let result = Schwarzschild.integrate(launch, settings: settings)
        #expect(result.outcome == .escaped)
        let deflection = Schwarzschild.deflection(from: launch, to: result)
        let expected = Constants.weakDeflectionCoefficient.value / b
        #expect(abs(deflection - expected) / expected < 0.005, "deflection \(deflection) expected \(expected)")
    }

    @Test func radialRayFallsStraightIn() {
        let ray = Schwarzschild.launch(from: SIMD3(20.0, 0.0, 0.0), direction: SIMD3(-1.0, 0.0, 0.0))
        let result = Schwarzschild.integrate(ray, settings: .interactive)
        #expect(result.outcome == .captured)
        #expect(abs(result.ray.state.phi) < 1e-12)
        #expect(abs(ray.angularMomentum) < 1e-12)
    }
}
