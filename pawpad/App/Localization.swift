import Foundation

/// Every string a player sees goes through L, as in Recall (app/Sources/Localization.swift): the
/// English is the key, and a Localizable.strings in the bundle can translate it. Pawpad ships
/// English only for now. {0}, {1}… stand for VALUES, in order, filled in after the lookup.
func L(_ english: String, _ values: String...) -> String {
    let text=Bundle.main.localizedString(forKey:english,value:english,table:nil)
    guard !values.isEmpty else { return text }
    var result="", rest=Substring(text)
    while let open=rest.firstIndex(of:"{") {
        result+=rest[..<open]
        let after=rest[rest.index(after:open)...]
        if let close=after.firstIndex(of:"}"),let index=Int(after[..<close]),values.indices.contains(index) {
            result+=values[index];rest=after[after.index(after:close)...]
        } else { result+="{";rest=after }
    }
    return result+rest
}
