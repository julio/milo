// swift-tools-version: 5.9
// Test harness for Milo's core logic. The app itself builds via
// Milo.xcodeproj; this package compiles the non-UI sources into a
// library so `swift test` can run the suite headless with coverage.
import PackageDescription

let package = Package(
    name: "MiloCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    targets: [
        .target(
            name: "WorkoutTracker",
            path: "WorkoutTracker/Sources",
            exclude: [
                "WorkoutTrackerApp.swift",
                "ContentView.swift",
                "MainView.swift",
                "TrainingPlanView.swift",
            ]
        ),
        .testTarget(
            name: "WorkoutTrackerTests",
            dependencies: ["WorkoutTracker"],
            path: "WorkoutTracker/Tests"
        ),
    ]
)
