import SwiftUI
import UIKit

/// Ponte fina pro `UIActivityViewController` nativo (AirDrop, Mail,
/// Mensagens, Salvar em Arquivos etc). Usada em vez do `ShareLink` puro do
/// SwiftUI porque aqui o fluxo é "gera o PDF primeiro, só depois abre o
/// compartilhamento" — e o `ShareLink` só abre a partir de um toque direto
/// nele, não dá pra disparar de dentro de uma função depois que o arquivo
/// fica pronto.
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
