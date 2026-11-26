import Foundation
import PencilKit
import UIKit

/// Gera PDFs a partir do conteúdo desenhado. Cada página do caderno vira uma
/// página do PDF, renderizada a partir do `PKDrawing` salvo em disco (mesma
/// técnica das miniaturas da grade e do OCR: `drawing.image(from:scale:)`) —
/// não é uma captura da tela, então funciona pra qualquer página, mesmo uma
/// que não esteja visível no momento.
enum PDFExportService {
    // Tamanho de página do PDF: A4 em pontos (72pt/polegada). Como a folha
    // do app também é A4 (ver PageGeometry), cada página sai igualzinha ao
    // que se vê na tela: mesma posição, papel e margem, só redimensionada.
    private static let pageSize = CGSize(width: 595, height: 842)

    /// Exporta um conjunto de páginas, na ordem recebida — uma por página do
    /// PDF. Usado tanto pra uma seção/caderno inteiros quanto pra uma
    /// seleção específica feita na grade de miniaturas. Devolve `nil` se não
    /// houver páginas ou se a escrita falhar.
    static func export(pages: [NotebookPage], suggestedName: String) -> URL? {
        guard !pages.isEmpty else { return nil }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitized(suggestedName))-\(UUID().uuidString.prefix(8)).pdf")

        // Usamos `pageSize` (o mesmo tamanho passado pro renderer) direto,
        // em vez de ler `context.pdfContextBounds` depois do beginPage() —
        // mais simples e sem depender de exatamente quando essa propriedade
        // fica disponível, já que toda página tem o mesmo tamanho fixo aqui.
        let pageBounds = CGRect(origin: .zero, size: pageSize)

        do {
            try renderer.writePDF(to: fileURL) { context in
                for page in pages {
                    draw(page: page, in: pageBounds, context: context)
                }
            }
            // O UIGraphicsPDFRenderer escreve o arquivo sozinho — a
            // proteção é aplicada depois, já com o PDF pronto.
            FileProtection.apply(to: fileURL)
            return fileURL
        } catch {
            print("PDFExportService: falha ao gerar PDF: \(error)")
            return nil
        }
    }

    /// Todas as páginas de uma seção, na ordem em que aparecem no carrossel.
    static func export(section: Section) -> URL? {
        export(pages: section.sortedPages, suggestedName: section.title)
    }

    /// O caderno inteiro, seção por seção, na ordem das abas.
    static func export(notebook: Notebook) -> URL? {
        let pages = notebook.sortedSections.flatMap { $0.sortedPages }
        return export(pages: pages, suggestedName: notebook.title)
    }

    /// Desenha uma página do caderno. A folha inteira (não só o recorte do
    /// que foi escrito) é encaixada na largura do A4. Páginas antigas mais
    /// compridas que um A4 viram várias páginas no PDF, em vez de encolher.
    private static func draw(page: NotebookPage, in bounds: CGRect, context: UIGraphicsPDFRendererContext) {
        let background = page.section?.backgroundStyle ?? .blank
        let isLeftHanded = UserDefaults.standard.bool(forKey: AppSettingsKeys.leftHandedMode)
        let drawing = DrawingStore.load(fileName: page.drawingFileName)
        let paper = PageGeometry.size(fitting: drawing)

        // Papel → PDF: encaixa a largura da folha na largura do A4.
        let scale = bounds.width / paper.width
        // Altura de folha que cabe numa página do PDF, em pontos de papel.
        let sliceHeight = bounds.height / scale
        let sliceCount = max(1, Int((paper.height / sliceHeight).rounded(.up)))

        for slice in 0..<sliceCount {
            context.beginPage()
            let sliceTop = CGFloat(slice) * sliceHeight
            let sliceRect = CGRect(x: 0, y: sliceTop, width: paper.width, height: sliceHeight)

            // Papel e margem, em coordenadas de papel (mesmas do canvas).
            let cg = context.cgContext
            cg.saveGState()
            cg.scaleBy(x: scale, y: scale)
            cg.translateBy(x: 0, y: -sliceTop)
            background.makeBackgroundColor().setFill()
            UIRectFill(sliceRect)
            if let marginX = background.marginX {
                let x = isLeftHanded ? paper.width - marginX : marginX
                UIColor.systemRed.withAlphaComponent(0.4).setFill()
                UIRectFill(CGRect(x: x, y: sliceTop, width: 1.5, height: sliceHeight))
            }
            cg.restoreGState()

            // Página em branco: fica só o papel (não pula a folha, pra não
            // bagunçar a numeração das seguintes).
            guard !drawing.strokes.isEmpty else { continue }

            // O PencilKit adapta a cor da tinta ao modo claro/escuro "atual";
            // fora de uma view isso pode esmaecer a tinta — força o claro.
            var strokesImage = UIImage()
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                strokesImage = drawing.image(from: sliceRect, scale: 2)
            }

            // A imagem do PencilKit nem sempre é um bitmap "comum" e pode
            // não aparecer desenhada direto no PDF — achata antes.
            let format = UIGraphicsImageRendererFormat()
            format.scale = strokesImage.scale
            format.opaque = false
            let flattenedImage = UIGraphicsImageRenderer(size: strokesImage.size, format: format).image { _ in
                strokesImage.draw(at: .zero)
            }
            flattenedImage.draw(in: bounds)
        }
    }

    /// Nome de arquivo seguro — troca qualquer caractere problemático (barra,
    /// dois-pontos etc.) por um traço, já que títulos de caderno/seção podem
    /// ter praticamente qualquer coisa.
    private static func sanitized(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = title.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Caderno" : cleaned
    }
}
