import Testing
import Foundation
import Oracle

@Suite struct PotentialTests {
    @Test func paczynskiWiitaAngularMomentumIsMinimalAtIsco() {
        let potential = Potential.paczynskiWiita
        var best = 3.0
        var bestL = Double.infinity
        var r = 3.0
        while r <= 20.0 {
            let l = potential.circularAngularMomentum(r)
            if l < bestL { bestL = l; best = r }
            r += 1e-4
        }
        #expect(abs(best - Constants.isco.value) < 1e-3)
    }

    @Test func paczynskiWiitaMarginallyBoundOrbitHasZeroEnergy() {
        let energy = Potential.paczynskiWiita.circularEnergy(Constants.marginallyBound.value)
        #expect(abs(energy) < 1e-12)
    }

    @Test func circularSpeedsMatchClosedForms() {
        #expect(abs(Potential.paczynskiWiita.circularSpeed(6.0) - 6.0.squareRoot() / 4.0) < 1e-12)
        #expect(abs(Potential.newtonian.circularSpeed(4.0) - 0.5) < 1e-12)
        #expect(abs(Potential.paczynskiWiita.angularFrequency(6.0) - 1.0 / 96.0.squareRoot()) < 1e-12)
    }

    @Test func accelerationPointsInward() {
        let a = Potential.paczynskiWiita.acceleration(at: SIMD3(3.0, 4.0, 0.0))
        #expect(a.x < 0 && a.y < 0 && a.z == 0)
        #expect(abs((a * a).sum().squareRoot() - 1.0 / 9.0) < 1e-12)
    }
}

@Suite struct DynamicsTests {
    @Test func circularOrbitStaysCircularWithoutDrag() {
        let potential = Potential.paczynskiWiita
        let dynamics = ParticleDynamics(potential: potential, alpha: 0.0)
        var state = DiskModel.circularOrbit(radius: 8.0, azimuth: 0.3, potential: potential)
        let period = 2.0 * Double.pi / potential.angularFrequency(8.0)
        let steps = Int(100.0 * period / dynamics.dt)
        let energy0 = dynamics.specificEnergy(state)
        let lz0 = dynamics.angularMomentumZ(state)
        var low = 8.0, high = 8.0
        for _ in 0..<steps {
            dynamics.step(&state)
            low = min(low, state.radius)
            high = max(high, state.radius)
        }
        #expect(high - low < 0.1)
        #expect(abs(dynamics.specificEnergy(state) - energy0) / abs(energy0) < 1e-4)
        #expect(abs(dynamics.angularMomentumZ(state) - lz0) / abs(lz0) < 1e-9)
    }

    @Test func dragSpiralsInward() {
        let potential = Potential.paczynskiWiita
        let dynamics = ParticleDynamics(potential: potential)
        var state = DiskModel.circularOrbit(radius: 12.0, azimuth: 0.0, potential: potential)
        let period = 2.0 * Double.pi / potential.angularFrequency(12.0)
        dynamics.step(&state, count: Int(2.0 * period / dynamics.dt))
        #expect(state.radius < 11.5)
        #expect(state.radius > 9.5)
    }

    @Test func orbitInsideIscoPlunges() {
        let potential = Potential.paczynskiWiita
        let dynamics = ParticleDynamics(potential: potential, alpha: 0.0)
        var state = DiskModel.circularOrbit(radius: 5.0, azimuth: 0.0, potential: potential)
        state.velocity *= 0.99
        var captured = false
        for _ in 0..<20_000 {
            dynamics.step(&state)
            if state.radius < Constants.captureRadius.value { captured = true; break }
        }
        #expect(captured)
    }

    @Test func orbitOutsideIscoSurvivesTheSameNudge() {
        let potential = Potential.paczynskiWiita
        let dynamics = ParticleDynamics(potential: potential, alpha: 0.0)
        var state = DiskModel.circularOrbit(radius: 8.0, azimuth: 0.0, potential: potential)
        state.velocity *= 0.99
        var low = 8.0
        for _ in 0..<20_000 {
            dynamics.step(&state)
            low = min(low, state.radius)
        }
        #expect(low > Constants.isco.value - 1.0)
    }
}

@Suite struct DiskModelTests {
    @Test func temperaturePeaksAtFortyNineOverThirtySixIsco() {
        let peak = DiskModel.temperature(radius: DiskModel.peakRadius)
        #expect(abs(peak - Constants.peakTemperature.value) < 1e-9)
        #expect(DiskModel.temperature(radius: 7.5) < peak)
        #expect(DiskModel.temperature(radius: 9.0) < peak)
        #expect(DiskModel.temperature(radius: 24.0) < 0.7 * peak)
    }

    @Test func temperatureStaysFiniteInsideIsco() {
        let edge = DiskModel.temperature(radius: 6.0)
        #expect(edge > 0.0)
        #expect(edge < 0.8 * Constants.peakTemperature.value)
        #expect(DiskModel.temperature(radius: 3.0) > edge)
    }

    @Test func steadyProfileVanishesAtIscoAndOuterEdge() {
        #expect(DiskModel.steadySurfaceDensity(radius: 6.0) == 0.0)
        #expect(DiskModel.steadySurfaceDensity(radius: 24.0) == 0.0)
        #expect(DiskModel.steadySurfaceDensity(radius: 10.0) > 0.0)
        let ratio = DiskModel.steadySurfaceDensity(radius: 6.2) / DiskModel.steadySurfaceDensity(radius: 6.1)
        #expect(abs(ratio - 2.0 * pow(6.1 / 6.2, 1.5)) < 1e-9)
    }

    @Test func inverseCdfIsMonotoneAndSpansTheDisk() {
        let table = DiskModel.radialInverseCdf(count: 1024)
        #expect(table.first == 6.0)
        #expect(table.last == 24.0)
        #expect(zip(table, table.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(table[512] > 10.0 && table[512] < 20.0)
    }

    @Test func inverseCdfReproducesTheProfile() {
        let table = DiskModel.radialInverseCdf(count: 4096)
        let bins = 36
        var counts = [Double](repeating: 0.0, count: bins)
        let draws = 200_000
        for i in 0..<draws {
            let u = Hash.unit(Hash.draw(seed: 7, index: UInt32(i), event: 0).x)
            let position = u * Double(table.count - 1)
            let k = min(Int(position), table.count - 2)
            let r = table[k] + (position - Double(k)) * (table[k + 1] - table[k])
            counts[min(Int((r - 6.0) / 0.5), bins - 1)] += 1.0
        }
        var expected = (0..<bins).map { DiskModel.radialNumberDensity(radius: 6.0 + (Double($0) + 0.5) * 0.5) }
        let scale = Double(draws) / expected.reduce(0, +)
        expected = expected.map { $0 * scale }
        for b in 1..<(bins - 1) where expected[b] > 2000 {
            #expect(abs(counts[b] - expected[b]) / expected[b] < 0.05)
        }
    }
}

@Suite struct BlackbodyTests {
    @Test func sixtyFiveHundredKelvinSitsOnThePlanckianLocus() {
        let c = Blackbody.chromaticity(temperature: 6500.0)
        #expect(abs(c.x - 0.3135) < 0.01)
        #expect(abs(c.y - 0.3237) < 0.01)
    }

    @Test func coolIsRedAndHotIsBlue() {
        let cool = Blackbody.normalizedColor(temperature: 2000.0)
        let hot = Blackbody.normalizedColor(temperature: 20000.0)
        #expect(cool.x == 1.0 && cool.y < cool.x && cool.z < cool.y)
        #expect(hot.z == 1.0 && hot.x < hot.z)
    }

    @Test func tableIsWellFormed() {
        let table = Blackbody.table()
        #expect(table.count == Int(Constants.blackbodyTableSize.value))
        #expect(table.allSatisfy { $0.max() == 1.0 && $0.min() >= 0.0 })
        #expect(Blackbody.tableCoordinate(temperature: 1000.0) == 0.0)
        #expect(Blackbody.tableCoordinate(temperature: 40000.0) == 1.0)
        #expect(Blackbody.tableCoordinate(temperature: 5000.0) > Blackbody.tableCoordinate(temperature: 3000.0))
    }
}

@Suite struct HashTests {
    @Test func pcg4dIsDeterministic() {
        let a = Hash.draw(seed: 42, index: 7, event: 3)
        let b = Hash.draw(seed: 42, index: 7, event: 3)
        #expect(a == b)
        #expect(Hash.draw(seed: 43, index: 7, event: 3) != a)
        #expect(Hash.draw(seed: 42, index: 8, event: 3) != a)
        #expect(Hash.draw(seed: 42, index: 7, event: 4) != a)
        #expect(Hash.draw(seed: 42, index: 7, event: 3, lane: 1) != a)
    }

    @Test func unitDeviatesAreUniform() {
        var sum = 0.0
        var low = 1.0, high = 0.0
        let n = 100_000
        for i in 0..<n {
            let u = Hash.unit(Hash.draw(seed: 1, index: UInt32(i), event: 0).y)
            sum += u
            low = min(low, u)
            high = max(high, u)
        }
        #expect(abs(sum / Double(n) - 0.5) < 0.005)
        #expect(low >= 0.0 && high < 1.0)
    }

    @Test func gaussianPairHasUnitVariance() {
        var sum = 0.0, sumSquares = 0.0
        let n = 100_000
        for i in 0..<n {
            let h = Hash.draw(seed: 3, index: UInt32(i), event: 1)
            let (g1, g2) = Hash.gaussianPair(Hash.unit(h.x), Hash.unit(h.y))
            sum += g1 + g2
            sumSquares += g1 * g1 + g2 * g2
        }
        let mean = sum / Double(2 * n)
        let variance = sumSquares / Double(2 * n) - mean * mean
        #expect(abs(mean) < 0.01)
        #expect(abs(variance - 1.0) < 0.02)
    }
}

@Suite struct ConstantsTests {
    @Test func symbolsAreUnique() {
        let symbols = Constants.all.map(\.symbol)
        #expect(Set(symbols).count == symbols.count)
    }

    @Test func everyConstantCitesASourceAndDesignChoicesExplainThemselves() {
        for entry in Constants.all {
            #expect(!entry.source.isEmpty, "\(entry.symbol) has no source")
            if entry.source == Constants.design {
                #expect(!entry.note.isEmpty, "\(entry.symbol) is a design choice without a note")
            }
        }
    }

    @Test func metalLiteralsAreWellFormed() {
        for entry in Constants.all {
            let literal = entry.metalLiteral
            #expect(literal.hasSuffix("f") || literal.hasSuffix("u"), "\(entry.symbol): \(literal)")
            #expect(!literal.contains(" "))
        }
        #expect(2.0.metalLiteral == "2.0f")
        #expect(UInt32(256).metalLiteral == "256u")
        #expect(1e-5.metalLiteral == "1e-05f")
    }

    @Test func headerListsEverySymbolOnce() {
        let header = MetalHeader.render()
        for entry in Constants.all {
            let needle = "#define \(entry.symbol) "
            #expect(header.components(separatedBy: needle).count == 2, Comment(rawValue: entry.symbol))
        }
        #expect(header.hasPrefix("// Generated from"))
        #expect(header.hasSuffix("#endif\n"))
    }
}
