// swift-tools-version: 6.1
//
// Thin wrapper package. It exists only to turn on AetherEngine's optional components
// ("package traits"), which the XcodeGen project spec cannot express directly.
// The app depends on the `HostDeps` product, which re-exports `AetherEngine`.
//
// The traits compile in code that may be subject to third-party patent licensing
// (the engine's own comment: "an integrator that enables one is responsible for its
// own licensing"). This app is for private use on one device. Remove a trait from
// the list below to leave that component out; the matching setting then does nothing
// and the Settings screen says so.
import PackageDescription

let package = Package(
    name: "HostDeps",
    platforms: [.tvOS(.v18)],
    products: [
        .library(name: "HostDeps", targets: ["HostDeps"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/superuser404notfound/AetherEngine",
            from: "7.64.0",
            traits: [
                "TrueHDObjectAudio",   // TrueHD Atmos -> 5.1.2 / 7.1.4 ... rendering
                "DTSXObjectAudio",     // DTS:X heights rendering
                "DualLayerDolbyVision",// full Profile 7 FEL dual-layer composition
                "DolbyVisionFelCurves",// FEL luma residual folded into the 8.1 RPU
            ]
        ),
    ],
    targets: [
        .target(
            name: "HostDeps",
            dependencies: [.product(name: "AetherEngine", package: "AetherEngine")]
        ),
    ]
)
