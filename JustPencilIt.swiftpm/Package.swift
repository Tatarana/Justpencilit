// swift-tools-version: 5.9

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "JustPencilIt",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "JustPencilIt",
            targets: ["AppModule"],
            bundleIdentifier: "com.tatarana.justpencilit",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .pencil),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [.pad],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
