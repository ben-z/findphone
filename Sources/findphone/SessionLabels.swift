struct SessionNumbers<Key: Hashable> {
    private var numbers: [Key: Int] = [:]
    private var next = 1

    mutating func number(for key: Key) -> Int {
        if let existing = numbers[key] { return existing }
        let assigned = next
        numbers[key] = assigned
        next += 1
        return assigned
    }
}

func surveyPrefix(_ number: Int) -> String {
    let prefix = "#\(number)"
    return prefix + String(repeating: " ", count: max(0, 4 - prefix.count))
}
