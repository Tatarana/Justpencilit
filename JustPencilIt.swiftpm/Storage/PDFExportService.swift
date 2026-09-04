import Foundation
import PencilKit
import UIKit

/// Gera PDFs a partir do conteúdo desenhado. Cada página do caderno vira uma
/// página do PDF, renderizada a partir do `PKDrawing` salvo em disco (mesma
/// técnica das miniaturas da grade e do OCR: `drawing.image(from:scale:)`) —
/// não é uma captura da tela, então funciona pra qualquer página, mesmo uma
/// que não esteja visível no momento.
enum PDFExportService {
    // Tamanho de página do PDF: A4 em pontos (72pt/polegada). O desenho de
    // cada página é escalado mantendo a proporção ("aspect fit") e
    // centralizado dentro dessa moldura, com uma margem em volta.
    private static let pageSize = CGSize(width: 595, height: 842)
    private static let margin: CGFloat = 28

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
                    context.beginPage()
                    draw(page: page, in: pageBounds)
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

    private static func draw(page: NotebookPage, in bounds: CGRect) {
        // Fundo da página — mesmo estilo (liso/pautado/quadriculado) da
        // seção a que ela pertence. `UIColor(patternImage:)` (usado pro
        // pautado/quadriculado) preenche certinho via UIRectFill — é a
        // mesma técnica que o próprio PageBackground usa pra desenhar as
        // texturas dos padrões, então sabemos que funciona num contexto
        // gráfico do UIKit como este.
        let background = page.section?.backgroundStyle ?? .blank
        background.makeBackgroundColor().setFill()
        UIRectFill(bounds)

        // Linha de margem (estilo pautado escolar), quando o estilo tiver
        // uma — mesma posição/cor usada ao vivo no canvas.
        if let marginX = background.marginX {
            UIColor.systemRed.withAlphaComponent(0.4).setFill()
            UIRectFill(CGRect(x: marginX, y: 0, width: 1.5, height: bounds.height))
        }

        let drawing = DrawingStore.load(fileName: page.drawingFileName)

        // Página em branco (nada desenhado ainda) — para por aqui, deixando
        // só o papel/fundo no PDF, em vez de pular a folha inteira (o que
        // bagunçaria a numeração das páginas seguintes).
        guard !drawing.strokes.isEmpty else { return }

        let sourceBounds = drawing.bounds.insetBy(dx: -20, dy: -20)
        guard sourceBounds.width > 0, sourceBounds.height > 0 else { return }

        let contentRect = bounds.insetBy(dx: margin, dy: margin)
        let fitScale = min(contentRect.width / sourceBounds.width, contentRect.height / sourceBounds.height)
        guard fitScale.isFinite, fitScale > 0 else { return }

        // Renderiza numa resolução maior que o tamanho final no PDF (até um
        // teto de 4x), pra sair nítido na impressão sem gerar uma imagem
        // gigante à toa quando o desenho já é pequeno.
        let renderScale = min(max(fitScale * 2, 1), 4)

        // O PencilKit adapta a cor da tinta sozinho conforme o modo
        // claro/escuro "atual" no momento da renderização (mesma causa do
        // bug do "traço branco" que já resolvemos no canvas ao vivo,
        // forçando `overrideUserInterfaceStyle = .light` na PKCanvasView).
        // Só que `drawing.image(from:scale:)`, chamado aqui fora de
        // qualquer view, não tem esse contexto — sem isso, a tinta sai
        // esmaecida (resolvida como se estivesse em modo escuro). Força-se
        // o modo claro só durante esta renderização.
        var strokesImage = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            strokesImage = drawing.image(from: sourceBounds, scale: renderScale)
        }

        // A imagem que o PencilKit devolve aqui nem sempre é um bitmap
        // "comum" por baixo dos panos — ela aparece certinho numa `Image`
        // do SwiftUI (como na miniatura da grade), mas desenhada direto num
        // contexto de PDF pode simplesmente não aparecer. "Achatamos" ela
        // num bitmap garantido antes de colocar no PDF, o que resolve isso.
        let format = UIGraphicsImageRendererFormat()
        format.scale = strokesImage.scale
        format.opaque = false
        let flattenedImage = UIGraphicsImageRenderer(size: strokesImage.size, format: format).image { _ in
            strokesImage.draw(at: .zero)
        }

        // Alinhado ao topo da página (não centralizado verticalmente) —
        // como em qualquer documento normal, o conteúdo começa colado na
        // margem superior, e o espaço sobrando (quando o desenho não
        // preenche a folha inteira) fica embaixo, não dos dois lados.
        // Horizontalmente ainda centraliza, já que isso é normal pra uma
        // página mais estreita que a folha.
        let drawSize = CGSize(width: sourceBounds.width * fitScale, height: sourceBounds.height * fitScale)
        let origin = CGPoint(
            x: contentRect.minX + (contentRect.width - drawSize.width) / 2,
            y: contentRect.minY
        )
        flattenedImage.draw(in: CGRect(origin: origin, size: drawSize))
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
