import SwiftUI

/// Chaves do UserDefaults usadas pelos ajustes — centralizadas aqui pra
/// SettingsView e quem consome cada valor (CanvasView, NotebookPageCanvas)
/// usarem exatamente a mesma string, sem risco de digitar diferente.
enum AppSettingsKeys {
    static let penStrokeWidth = "settings.penStrokeWidthMultiplier"
    static let markerStrokeWidth = "settings.markerStrokeWidthMultiplier"
    static let leftHandedMode = "settings.leftHandedMode"
    static let defaultPaper = "settings.defaultPaper"
    static let useSystemToolPicker = "settings.useSystemToolPicker"
    static let relayURL = "settings.relayURL"
}

/// Tela de ajustes do app — preferências de uso, não conteúdo dos cadernos,
/// por isso ficam salvas com `@AppStorage` (UserDefaults) em vez de
/// SwiftData: são do aparelho/pessoa, não fazem parte do que sincronizaria
/// pra outro dispositivo no futuro (iCloud).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // A espessura de caneta/marcador continua salva com a mesma chave, mas
    // o controle dela agora mora no próprio caderno (segurar o dedo na
    // ferramenta na PenToolbar) — mais rápido de ajustar na hora de
    // escrever do que abrir os Ajustes. Fica só a referência aqui pro botão
    // "Restaurar padrões" poder zerar tudo de uma vez.
    @AppStorage(AppSettingsKeys.penStrokeWidth) private var penWidthMultiplier: Double = 1.0
    @AppStorage(AppSettingsKeys.markerStrokeWidth) private var markerWidthMultiplier: Double = 1.0
    @AppStorage(AppSettingsKeys.leftHandedMode) private var isLeftHanded: Bool = false
    @AppStorage(AppSettingsKeys.defaultPaper) private var defaultPaper: PageBackground = .blank
    @AppStorage(AppSettingsKeys.useSystemToolPicker) private var useSystemToolPicker: Bool = true

    @State private var securityChecks: [SecurityCheck]?

    var body: some View {
        NavigationStack {
            Form {
                leftHandedSection
                paperSection
                toolSection
                phoneSection
                securitySection
                resetSection
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pronto") { dismiss() }
                }
            }
        }
    }

    // Cada Section numa propriedade separada — dentro de um único `body`
    // grande, o compilador (principalmente no Swift Playgrounds) às vezes
    // não consegue inferir os tipos a tempo e acaba reportando um erro sem
    // relação nenhuma (ex: "FormStyleConfiguration") lá no início do Form.
    // Quebrar em pedaços menores resolve esse tipo de erro confuso.
    private var leftHandedSection: some View {
        SwiftUI.Section {
            Toggle(isOn: $isLeftHanded) {
                Label("Modo canhoto", systemImage: "hand.point.left.fill")
            }
        } footer: {
            Text("Espelha a margem e os furos do papel pro lado direito da página, pra sua mão não ficar em cima deles ao escrever.")
        }
    }

    private var paperSection: some View {
        SwiftUI.Section {
            Picker(selection: $defaultPaper) {
                ForEach(PageBackground.allCases) { style in
                    Text(style.label).tag(style)
                }
            } label: {
                Label("Papel padrão", systemImage: "doc.plaintext")
            }
        } footer: {
            Text("Tipo de papel dos cadernos novos. Cada caderno pode ter o seu próprio padrão (menu ••• dentro do caderno). Seções que já existem não mudam.")
        }
    }

    private var toolSection: some View {
        SwiftUI.Section {
            Picker(selection: $useSystemToolPicker) {
                Text("Padrão do iPad").tag(true)
                Text("JustPencilIt (antiga)").tag(false)
            } label: {
                Label("Ferramenta de desenho", systemImage: "pencil.tip.crop.circle")
            }
        } footer: {
            Text("A do iPad tem todas as canetas, laço e régua, e fica igual à de outros apps. A antiga continua disponível aqui caso prefira.")
        }
    }

    private var phoneSection: some View {
        SwiftUI.Section {
            NavigationLink {
                PhonePairingView()
            } label: {
                Label("Celular (Caderneta)", systemImage: "iphone.gen3")
            }
        } footer: {
            Text("Pareie a Caderneta no seu Android: as ideias gravadas no celular chegam aqui e são transcritas, de qualquer lugar com internet.")
        }
    }

    /// Não é uma promessa em texto ("seus dados são protegidos") — é uma
    /// leitura AO VIVO do atributo de proteção que o iOS confirma pra cada
    /// arquivo, pra responder de verdade "isso tá criptografado?" sem
    /// precisar de Xcode/Console (que não existe testando pelo Playgrounds).
    private var securitySection: some View {
        SwiftUI.Section {
            Button("Verificar proteção dos arquivos") {
                securityChecks = buildSecurityChecks()
            }

            if let securityChecks {
                if securityChecks.isEmpty {
                    Text("Nada salvo ainda pra verificar.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(securityChecks) { check in
                        HStack {
                            Image(systemName: check.isProtected ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(check.isProtected ? Color.green : Color.orange)
                            Text(check.label)
                            Spacer()
                        }
                    }
                }
            }
        } header: {
            Text("Segurança dos dados")
        } footer: {
            Text("Os dados salvos neste iPad usam a proteção de arquivos do próprio iOS, atrelada à sua senha/Face ID — sem nenhuma configuração necessária.")
        }
    }

    private var resetSection: some View {
        SwiftUI.Section {
            Button("Restaurar padrões", role: .destructive) {
                penWidthMultiplier = 1.0
                markerWidthMultiplier = 1.0
                isLeftHanded = false
                defaultPaper = .blank
                useSystemToolPicker = true
            }
        }
    }

    private func buildSecurityChecks() -> [SecurityCheck] {
        var checks: [SecurityCheck] = []

        if let storeURL = modelContext.container.configurations.first?.url {
            let isProtected = FileProtection.currentProtection(of: storeURL) == FileProtection.level
            checks.append(SecurityCheck(label: "Banco de dados dos cadernos", isProtected: isProtected))
        }

        if let check = directoryCheck(label: "Desenhos", directory: DrawingStore.directory) {
            checks.append(check)
        }
        if let check = directoryCheck(label: "Áudios", directory: AudioStore.directory) {
            checks.append(check)
        }

        return checks
    }

    /// `nil` quando a pasta ainda não tem nenhum arquivo — não faz sentido
    /// mostrar "0 de 0 protegidos" como se fosse um problema.
    private func directoryCheck(label: String, directory: URL) -> SecurityCheck? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil),
              !files.isEmpty else { return nil }
        let protectedCount = files.filter { FileProtection.currentProtection(of: $0) == FileProtection.level }.count
        return SecurityCheck(
            label: "\(label) (\(protectedCount) de \(files.count))",
            isProtected: protectedCount == files.count
        )
    }
}

private struct SecurityCheck: Identifiable {
    let id = UUID()
    let label: String
    let isProtected: Bool
}
