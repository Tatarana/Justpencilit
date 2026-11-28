import SwiftUI
import SwiftData
import CoreImage.CIFilterBuiltins

/// Ajustes → Celulares: parear um ou mais celulares com a Caderneta
/// (Android), ver como está a sincronização de cada um e desparear.
struct PhonePairingView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettingsKeys.relayURL) private var relayURL: String = ""

    private var sync: RelaySync { RelaySync.shared }

    @State private var isWorking = false
    @State private var errorMessage: String?
    /// O código só aparece logo depois de parear, ou depois de Face ID.
    @State private var shownCode: RelayPairingCode?
    @State private var unpairing: RelayPairing?
    @State private var unpairWarning: String?

    var body: some View {
        Form {
            if sync.isPaired {
                phonesSection
                syncSection
            }
            setupSection
            aboutSection
        }
        .navigationTitle("Celulares")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { shownCode.map(IdentifiedCode.init) },
            set: { if $0 == nil { shownCode = nil } }
        )) { identified in
            PairingCodeSheet(code: identified.code)
        }
        .confirmationDialog(
            "Desparear \(unpairing?.displayName ?? "o celular")?",
            isPresented: Binding(get: { unpairing != nil }, set: { if !$0 { unpairing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Desparear", role: .destructive) {
                if let unpairing { unpair(unpairing) }
            }
        } message: {
            Text("Apaga do servidor tudo que estava esperando para ir ou voltar desse celular. As fitas que já chegaram ficam aqui no iPad. Para voltar a sincronizar, é preciso ler um QR novo nele.")
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

    // MARK: Celulares pareados

    private var phonesSection: some View {
        SwiftUI.Section {
            ForEach(sync.pairings) { pairing in
                PhoneRow(pairing: pairing, status: statusText(sync.status(of: pairing)))
                    .swipeActions {
                        Button("Desparear", role: .destructive) { unpairing = pairing }
                        Button("QR") { showCodeAgain(for: pairing) }
                    }
                    .contextMenu {
                        Button("Mostrar o QR de novo", systemImage: "qrcode") { showCodeAgain(for: pairing) }
                        Button("Desparear", systemImage: "xmark.circle", role: .destructive) { unpairing = pairing }
                    }
            }
        } header: {
            Text("Caderneta")
        } footer: {
            Text("Toque e segure (ou deslize) um celular para mostrar o QR de novo ou desparear.")
        }
    }

    private var syncSection: some View {
        SwiftUI.Section {
            Button {
                Task { await sync.syncNow(modelContext: modelContext) }
            } label: {
                HStack {
                    Text(sync.isRunning ? "Sincronizando…" : "Sincronizar agora")
                    Spacer()
                    if sync.isRunning { ProgressView() }
                }
            }
            .disabled(sync.isRunning)
        } footer: {
            Text("Enquanto o app está aberto, sincroniza sozinho a cada minuto: as fitas dos celulares chegam e são transcritas aqui, e a transcrição volta pra lá.")
        }
    }

    // MARK: Parear

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
                    Label(sync.isPaired ? "Parear outro celular" : "Parear um celular", systemImage: "qrcode")
                }
            }
            .disabled(isWorking || relayURL.trimmingCharacters(in: .whitespaces).isEmpty)

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        } header: {
            Text("Servidor de sincronização")
        } footer: {
            Text("O endereço onde você publicou o justpencilit-relay na Cloudflare. Cada celular ganha a própria caixa e a própria chave.")
        }
    }

    private var aboutSection: some View {
        SwiftUI.Section {
            EmptyView()
        } footer: {
            Text("Tudo passa cifrado de ponta a ponta: as chaves ficam só neste iPad e nos celulares, e o servidor guarda e repassa sem conseguir ler nada. Cadernos protegidos não vão pros celulares.")
        }
    }

    private func statusText(_ status: RelaySync.Status) -> String {
        switch status {
        case .idle:
            return "Pronto"
        case .running:
            return "Sincronizando…"
        case .offline:
            return "Sem conexão agora. Tenta de novo em instantes."
        case let .done(at, imported):
            let time = at.formatted(date: .omitted, time: .shortened)
            return imported > 0 ? "Às \(time): \(imported) fita(s) nova(s)." : "Sincronizado às \(time)."
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
    private func showCodeAgain(for pairing: RelayPairing) {
        Task {
            if await BiometricLock.authenticate(reason: "Mostrar o código de pareamento do celular") {
                shownCode = pairing.code
            }
        }
    }

    private func unpair(_ pairing: RelayPairing) {
        isWorking = true
        Task {
            let deletedOnServer = await sync.unpair(pairing)
            isWorking = false
            if !deletedOnServer {
                unpairWarning = "O celular foi esquecido aqui, mas não deu pra apagar a caixa no servidor (sem conexão). Ela fica inacessível sem a chave, e o servidor a apaga sozinho depois de 180 dias parada."
            }
        }
    }
}

/// Uma linha da lista de celulares. Separada para o compilador do
/// Playgrounds não se perder num `ForEach` grande.
private struct PhoneRow: View {
    let pairing: RelayPairing
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pairing.displayName).font(.headline)
            Text(status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Pareado em \(pairing.pairedAt.formatted(date: .abbreviated, time: .shortened)) · \(URL(string: pairing.relayURL)?.host ?? pairing.relayURL)")
                .font(.caption)
                .foregroundStyle(.secondary)
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
