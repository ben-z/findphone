import Foundation

enum ParseError: Error, Equatable {
    case unknownFlag(String)
    case tooManyNames(Int)
    case selectWithName
    case missingNameForSound
    case selectWithList
}

struct ParsedArguments {
    let targetName: String?
    let redact: Bool
    let wantsList: Bool
    let wantsSound: Bool
    let wantsSelect: Bool
    let wantsHelp: Bool
}

let usageText = """
findphone — locate a nearby Bluetooth device by signal strength

  findphone            survey every nearby Apple handheld
  findphone <name>     track one device by name (case-insensitive)
  findphone --list     show paired devices and their addresses
  findphone --select   choose a nearby device from numbered list

  --sound              click faster as you get closer (hunt mode)
  --redact             mask Bluetooth addresses, for screen recording
"""

let knownFlags: Set<String> = ["-h", "--help", "--list", "--redact", "--sound", "--select"]

func usageError(_ message: String) -> Never {
    FileHandle.standardError.write(Data("findphone: \(message)\n\n\(usageText)\n".utf8))
    exit(2)
}

func parseArguments(_ args: ArraySlice<String>) throws -> ParsedArguments {
    let parsedArgs = Array(args)

    if parsedArgs.contains("-h") || parsedArgs.contains("--help") {
        return ParsedArguments(
            targetName: nil,
            redact: false,
            wantsList: false,
            wantsSound: false,
            wantsSelect: false,
            wantsHelp: true)
    }

    if let unknown = parsedArgs.first(where: { $0.hasPrefix("-") && !knownFlags.contains($0) }) {
        throw ParseError.unknownFlag(unknown)
    }

    let names = parsedArgs.filter { !$0.hasPrefix("-") }
    if names.count > 1 {
        throw ParseError.tooManyNames(names.count)
    }

    let redact = parsedArgs.contains("--redact")
    let wantsList = parsedArgs.contains("--list")
    let wantsSound = parsedArgs.contains("--sound")
    let wantsSelect = parsedArgs.contains("--select")

    if wantsSelect && wantsList {
        throw ParseError.selectWithList
    }

    if wantsSelect && !names.isEmpty {
        throw ParseError.selectWithName
    }

    if wantsSound && names.isEmpty && !wantsSelect {
        throw ParseError.missingNameForSound
    }

    let targetName = wantsList ? nil : names.first

    return ParsedArguments(
        targetName: targetName,
        redact: redact,
        wantsList: wantsList,
        wantsSound: wantsSound,
        wantsSelect: wantsSelect,
        wantsHelp: false)
}
