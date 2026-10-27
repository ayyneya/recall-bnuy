import Foundation

/// Pawpad's public identity in one place, and the credit to the project it is built on.
enum Brand {
    static let name="Pawpad"
    static var tagline:String { L("Aniimo on your Mac, on Apple Silicon.") }
    static let repositoryPath="ayyneya/recall-Aniimo"
    static let repository=URL(string:"https://github.com/\(repositoryPath)")!
    static let releases=URL(string:"https://github.com/\(repositoryPath)/releases")!
    static let bundleIdentifier="dev.neya.pawpad"
    /// The data folder in Application Support (the worker's default root).
    static let dataFolder="Pawpad"
    static var trademarks:String { L("Not affiliated with or endorsed by Pawprint Studio, FunPlus or Apple. Aniimo is a trademark of its owner. Mac is a trademark of Apple Inc.") }

    /// Pawpad is Recall, the Overwatch app for Mac, made to run Aniimo.
    enum Recall {
        static let name="Recall"
        static let author="Joshua Asher Nelson"
        static let handle="AsherJN"
        static let repository=URL(string:"https://github.com/AsherJN/recall")!
    }
}
