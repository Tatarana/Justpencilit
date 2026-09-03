import SwiftUI

/// Tela modal simples pra renomear um caderno. Existe como sheet (em vez de
/// um TextField dentro de .alert) porque, rodando no Swift Playgrounds, o
/// teclado (externo e virtual) não estava recebendo foco corretamente dentro
/// de um alert — como sheet, o foco funciona de forma bem mais confiável.
struct RenameSheet: View {
    let originalTitle: String
    let onSave: (String) -> Void
    var fieldLabel: String = "Nome do caderno"
    var navigationTitleText: String = "Renomear caderno"

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @FocusState private var isFocused: Bool

    init(
        originalTitle: String,
        fieldLabel: String = "Nome do caderno",
        navigationTitleText: String = "Renomear caderno",
        onSave: @escaping (String) -> Void
    ) {
        self.originalTitle = originalTitle
        self.fieldLabel = fieldLabel
        self.navigationTitleText = navigationTitleText
        self.onSave = onSave
        _title = State(initialValue: originalTitle)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(fieldLabel, text: $title)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                // Um pequeno atraso ajuda o foco "pegar" depois da animação
                // de abertura da sheet — sem isso, o teclado às vezes não sobe.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isFocused = true
                }
            }
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}
