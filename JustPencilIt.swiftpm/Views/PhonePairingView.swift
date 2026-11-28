import SwiftUI
import SwiftData
import CoreImage.CIFilterBuiltins

/// Ajustes → Celular: parear a Caderneta (Android), ver como está a
/// sincronização e desfazer o pareamento.
struct PhonePairingView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettingsKeys.relayURL) private var relayURL: String = ""

    private var sync: RelaySync { RelaySync.shared }

    @State private var isWorking = false
    @State private var errorMessage: String?
    /// O código só aparece logo depois de parear, ou depois de Face ID.
    @State private var shownCode: RelayPairingCode?
    @State private var confirmUnpair = false
    @State private var unpairWarning: String?

    var body: some View {
        Form {
            if sync.isPaired {
                pairedSection
                syncSection
                pairedActions
            } else {
                setupSection
            }
            aboutSection
        }
        .navigationTitle("Celular")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { shownCode.map(IdentifiedCode.init) },
            set: { if $0 == nil { shownCode = nil } }
        )) { identified in
            PairingCodeSheet(code: identified.code)
        }
        .confirmationDialog("Desparear o celular?", isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button("Desparear", role: .destructive) { unpair() }
        } message: {
            Text("Apaga do servidor tudo que estava esperando para ir ou voltar. As fitas que já chegaram ficam aqui no iPad. Para voltar a sincronizar, é preciso ler um QR novo no celular.")
        }
        .alert("Pareamento desfeito", isPresented: Binding(
            get: { unpairWarning != nil },
            set: { if !$0 { unpairWarning = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(unpairWarning ?? "")
        }
    }

    // MARK: Não pareado

    private var setupSection: some View {
        SwiftUI.Section {
            TextField("https://justpencilit-relay.sua-conta.workers.dev", text: $relayURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                pair()
            } label: {
                if isWorking {
                    HStack {
                        ProgressView()
                        Text("Criando a caixa no servidor…")
                    }
                } else {
                    Label("Parear um celular", systemImage: "qrcode")
                }
            }
            .disabled(isWorking || relayURL.trimmingCharacters(in: .whitespaces).isEmpty)

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        } header: {
            Text("Servidor de sincronização")
        } footer: {
            Text("O endereço onde você publicou o justpencilit-relay na Cloudflare. Depois de parear, aparece um QR para ler na Caderneta.")
        }
    }

    // MARK: Pareado

    private var pairedSection: some View {
        SwiftUI.Section {
            LabeledContent("Celular", value: sync.phoneName ?? "Aguardando o primeiro envio")
            if let pairing = sync.pairing {
                LabeledContent("Pareado em", value: pairing.pairedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Servidor", value: URL(string: pairing.relayURL)?.host ?? pairing.relayURL)
            }
        } header: {
            Text("Caderneta")
        }
    }

    private var syncSection: some View {
        SwiftUI.Section {
            HStack {
                Text(statusText)
                Spacer()
                if sync.status == .running { ProgressView() }
            }
            Button("Sincronizar agora") {
                Task { await sync.syncNow(modelContext: modelContext) }
            }
            .disabled(sync.status == .running)
        } footer: {
            Text("Enquanto o app está aberto, sincroniza sozinho a cada minuto: as fitas do celular chegam e são transcritas aqui, e a transcrição volta pra lá.")
        }
    }

    private var pairedActions: some View {
        SwiftUI.Section {
            Button("Mostrar o QR de novo") { showCodeAgain() }
            Button("Desparear", role: .destructive) { confirmUnpair = true }
                .disabled(isWorking)
        }
    }

    private var aboutSection: some View {
        SwiftUI.Section {
            EmptyView()
        } footer: {
            Text("Tudo passa cifrado de ponta a ponta: a chave fica só neste iPad e no celular, e o servidor guarda e repassa sem conseguir ler nada. Cadernos protegidos não vão pro celular.")
        }
    }

    private var statusText: String {
        switch sync.status {
        case .idle:
            return "Pronto"
        case .running:
            return "Sincronizando…"
        case .offline:
            return "Sem conexão agora. Tenta de novo em instantes."
        case let .done(at, imported):
            let time = at.formatted(date: .omitted, time: .shortened)
            return imported > 0 ? "Às \(time): \(imported) fita(s) nova(s) do celular." : "Sincronizado às \(time)."
        case let .failed(message):
            return message
        }
    }

    // MARK: Ações

    private func pair() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                shownCode = try await sync.pair(relayURL: relayURL)
            } catch let error as RelayError {
                switch error {
                case .unreachable:
                    errorMessage = "Não deu pra falar com o servidor. Confira o endereço e a internet."
                case .http:
                    errorMessage = error.errorDescription
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    /// O QR é a chave: mostrar de novo pede Face ID/senha, como um caderno protegido.
    private func showCodeAgain() {
        Task {
            guard let pairing = sync.pairing else { return }
            if await BiometricLock.authenticate(reason: "Mostrar o código de pareamento do celular") {
                shownCode = pairing.code
            }
        }
    }

    private func unpair() {
        isWorking = true
        Task {
            let deletedOnServer = await sync.unpair()
            isWorking = false
            if !deletedOnServer {
                unpairWarning = "O celular foi esquecido aqui, mas não deu pra apagar a caixa no servidor (sem conexão). Ela fica inacessível sem a chave."
            }
        }
    }
}

private struct IdentifiedCode: Identifiable {
    let code: RelayPairingCode
    var id: String { code.mailboxID }
}

/// O QR em tela cheia, para ler com a Caderneta.
private struct PairingCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let code: RelayPairingCode

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Na Caderneta, toque em ⚙︎ → Ler QR code do iPad")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                if let image = QRCode.image(for: code.text) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 360)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                }

                Text("Este código é a chave da sincronização. Não mostre pra ninguém nem tire print.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

            }
            .padding(32)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pronto") { dismiss() }
                }
            }
        }
    }
}

enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
