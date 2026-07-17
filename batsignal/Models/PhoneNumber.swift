import Foundation

enum PhoneNumber {
    // Normalizes a raw phone string to E.164 (+1XXXXXXXXXX) for US numbers,
    // stripping formatting characters (spaces, dashes, parens) and forgiving
    // an optional leading "1" or "+1" country prefix.
    // Returns nil for numbers that can't be resolved to a US number.
    static func normalize(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        if digits.count == 10 { return "+1\(digits)" }
        if digits.count == 11, digits.hasPrefix("1") { return "+\(digits)" }
        return nil
    }
}
