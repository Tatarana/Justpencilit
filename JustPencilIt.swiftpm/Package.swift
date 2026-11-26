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
            bundleVersion: "2",
            appIcon: .asset("AppIcon"),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [.pad],
            // A Apple exige as 4 orientações pra suportar multitarefa no
            // iPad (Split View/Slide Over) — mesmo se o app travar a UI
            // visualmente em portrait, o sistema precisa poder redimensionar
            // a janela em qualquer uma delas.
            supportedInterfaceOrientations: [
                .portrait,
                .portraitUpsideDown,
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
