// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AINewsAggregator",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AINewsAggregator", targets: ["AINewsAggregator"])
    ],
    dependencies: [
        // Database
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        // RSS Parsing
        .package(url: "https://github.com/nmdias/FeedKit.git", from: "9.1.2"),
        // HTML Parsing for scraping
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.1"),
        // Networking
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.8.1"),
        // Date handling
        .package(url: "https://github.com/malcommac/SwiftDate.git", from: "7.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "AINewsAggregator",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "FeedKit",
                "SwiftSoup",
                "Alamofire",
                "SwiftDate",
            ],
            path: "Sources"
        )
    ]
)
