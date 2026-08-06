func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

var repeated = SessionNumbers<String>()
expectEqual(repeated.number(for: "phone-a"), 1, "first label")
expectEqual(repeated.number(for: "phone-a"), 1, "reused label")

var ordered = SessionNumbers<Int>()
for key in 1...12 {
    expectEqual(ordered.number(for: key), key, "discovery order")
}

expectEqual(surveyPrefix(7), "#7  ", "single-digit prefix")
expectEqual(surveyPrefix(12), "#12 ", "double-digit prefix")

print("session label tests passed")
