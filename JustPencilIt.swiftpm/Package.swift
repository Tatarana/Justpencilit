// swift-tools-version: 5.9

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "JustPencilIt",
    platforms: [
        // 26.0 pra poder usar o SpeechAnalyzer/SpeechTranscriber (áudio →
        // texto dos memos de voz), que só existe a partir daqui.
        .iOS("26.0")
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
            ],
            // Chaves de uso (Face ID, microfone, reconhecimento de fala) —
            // exigidas pelo sistema pra Face ID, gravar áudio e transcrever.
            additionalInfoPlistContentFilePath: "Support/Info-Additions.plist"
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
