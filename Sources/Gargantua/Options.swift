import Foundation

enum Strategy: String, Sendable {
    case march, bake
}

enum Preset: String, CaseIterable, Sendable {
    case small
    case standard = "default"
    case max
}

/// How the soak harness ends the run, so each quit path can be exercised.
enum QuitPath: String, Sendable {
    case direct
    case escape = "esc"
    case menu = "cmd-q"
}

enum Command: Equatable, Sendable {
    case interactive
    case still(path: String)
    case bench
    case validate
    case version
    case constants
}

struct UsageError: Error {
    let sentence: String
}

/// Parsed command line. Parsing is pure so it can be exercised without a GPU.
struct Options: Sendable {
    var command: Command = .interactive
    var preset: Preset = .standard
    var particles: Int?
    var volume: Int?
    var seed: UInt64 = 1
    var strategy: Strategy = .march
    var fpsCap: Int = 60
    var upscale = true
    var width = 3840
    var height = 2160
    /// Development harness: run the window for this many seconds, print a
    /// frame time summary and a screenshot path, then quit.
    var soakSeconds: Double?
    var quitPath: QuitPath = .direct
    /// Development harness: make `bench` table step policies and threadgroup sizes.
    var sweep = false
    /// With --still: also render this many consecutive native frames with the
    /// simulation advancing, for temporal artifact hunting.
    var sequence: Int?
    /// Starting camera as azimuth, elevation, distance.
    var camera: (azimuth: Double, elevation: Double, distance: Double)?

    static let usage = """
    usage: gargantua [--preset small|default|max] [--particles N] [--volume 96|128|192|256] [--seed S] \
    [--strategy march|bake] [--fps-cap 30|60] [--no-upscale] [--still out.png --width W --height H] | bench | validate | version
    """

    static func parse(_ arguments: [String]) -> Result<Options, UsageError> {
        var options = Options()
        var index = 0

        func value(for flag: String) throws -> String {
            index += 1
            guard index < arguments.count else { throw UsageError(sentence: "\(flag) needs a value. \(usage)") }
            return arguments[index]
        }

        func integer(for flag: String) throws -> Int {
            let text = try value(for: flag)
            guard let number = Int(text), number > 0 else { throw UsageError(sentence: "\(flag) needs a positive integer, not \(text).") }
            return number
        }

        do {
            while index < arguments.count {
                let argument = arguments[index]
                switch argument {
                case "bench": options.command = .bench
                case "validate": options.command = .validate
                case "version": options.command = .version
                case "constants": options.command = .constants
                case "--preset":
                    let name = try value(for: argument)
                    guard let preset = Preset(rawValue: name) else { throw UsageError(sentence: "unknown preset \(name); choose small, default or max.") }
                    options.preset = preset
                case "--particles": options.particles = try integer(for: argument)
                case "--volume":
                    let volume = try integer(for: argument)
                    guard [96, 128, 192, 256].contains(volume) else { throw UsageError(sentence: "volume must be 96, 128, 192 or 256.") }
                    options.volume = volume
                case "--seed":
                    let text = try value(for: argument)
                    guard let seed = UInt64(text) else { throw UsageError(sentence: "seed must be an unsigned 64 bit integer, not \(text).") }
                    options.seed = seed
                case "--strategy":
                    let name = try value(for: argument)
                    guard let strategy = Strategy(rawValue: name) else { throw UsageError(sentence: "unknown strategy \(name); choose march or bake.") }
                    options.strategy = strategy
                case "--fps-cap":
                    let cap = try integer(for: argument)
                    guard cap == 30 || cap == 60 else { throw UsageError(sentence: "fps cap must be 30 or 60.") }
                    options.fpsCap = cap
                case "--no-upscale": options.upscale = false
                case "--still": options.command = .still(path: try value(for: argument))
                case "--width": options.width = try integer(for: argument)
                case "--height": options.height = try integer(for: argument)
                case "--soak":
                    let text = try value(for: argument)
                    guard let seconds = Double(text), seconds > 0 else { throw UsageError(sentence: "soak needs a positive number of seconds.") }
                    options.soakSeconds = seconds
                case "--sweep": options.sweep = true
                case "--sequence": options.sequence = try integer(for: argument)
                case "--camera":
                    let text = try value(for: argument)
                    let parts = text.split(separator: ",").compactMap { Double($0) }
                    guard parts.count == 3, parts[2] > 2.5, parts[2] < 60 else {
                        throw UsageError(sentence: "camera needs azimuth,elevation,distance with distance between 2.5 and 60.")
                    }
                    options.camera = (parts[0], parts[1], parts[2])
                case "--quit":
                    let name = try value(for: argument)
                    guard let path = QuitPath(rawValue: name) else { throw UsageError(sentence: "unknown quit path \(name); choose direct, esc or cmd-q.") }
                    options.quitPath = path
                default:
                    throw UsageError(sentence: "unknown argument \(argument). \(usage)")
                }
                index += 1
            }
        } catch let error as UsageError {
            return .failure(error)
        } catch {
            return .failure(UsageError(sentence: usage))
        }
        return .success(options)
    }
}
