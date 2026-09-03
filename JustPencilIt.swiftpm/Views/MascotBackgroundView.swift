import SwiftUI
import UIKit

/// Fundo "vivo" da tela principal: uma ilustração cheia de tela no estilo
/// desenho a lápis (grafite + lápis de cor), com o lapizinho mascote
/// espiando num canto — e reagindo de verdade ao que o usuário faz: acena
/// ao abrir o app, comemora ao criar um caderno, fica triste ao excluir
/// um, fica curioso ao criar uma coleção, e os olhos acompanham o scroll
/// da lista. De vez em quando ele "escreve" uma frase à mão em algum
/// lugar da tela. Fica mais discreto conforme a lista de cadernos cresce.
struct MascotBackgroundView: View {
    var notebookCount: Int
    var scrollFraction: CGFloat
    var createTrigger: Int
    var deleteTrigger: Int
    var collectionTrigger: Int
    var recordTrigger: Int

    @State private var phrase: String?
    @State private var revealedCount = 0
    @State private var phraseOpacity: Double = 0
    @State private var phrasePosition = UnitPoint(x: 0.5, y: 0.5)
    @State private var phraseRotation: Double = 0
    @State private var isWriting = false
    @State private var writeTask: Task<Void, Never>?

    /// Onde ele fica "em repouso" — canto inferior esquerdo, bem longe do
    /// botão de + (que fica no canto oposto). Some vez em quando ele viaja
    /// dali até perto da frase que está escrevendo, e depois volta.
    private static let restAnchor = UnitPoint(x: 0.12, y: 0.88)
    @State private var mascotAnchor = MascotBackgroundView.restAnchor

    // MARK: Timing (fácil de ajustar depois)

    /// Quanto tempo depois do app abrir ele escreve a primeira frase.
    private static let firstWriteDelay: TimeInterval = 3
    /// Intervalo (mínimo...máximo, em segundos) entre o fim de uma frase e
    /// o início da próxima, depois da primeira.
    private static let rewriteDelayRange: ClosedRange<TimeInterval> = 3...6
    /// Quanto tempo o texto fica visível na tela depois de terminar de
    /// ser escrito, antes de começar a sumir.
    private static let phraseHoldDuration: TimeInterval = 15

    private static let phrases = [
        "Bora criar?",
        "Uma ideia por vez!",
        "Rabisca comigo!",
        "Página nova te espera",
        "Psst... desenha algo!",
        "Cadê o lápis? Ah, sou eu!",
        "Toque no + ali",
        "Grafite e café ☕",
        "Inspiração chegando...",
        "Nós dois, uma dupla!",
        "Bons rabiscos hoje!",
        "Vamos rabiscar juntos?",
        "Todo traço conta",
        "Sem medo da página em branco!"
    ]

    /// Quanto mais cadernos na tela, mais sutil o fundo fica (mas nunca some).
    private var presence: Double {
        let raw = 1.0 - Double(notebookCount) * 0.045
        return min(1.0, max(0.28, raw))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SketchPaperImage()
                    .opacity(presence)

                FloatingStationeryLayer()
                    .opacity(presence * 0.7)
                    .allowsHitTesting(false)

                if let phrase {
                    WrittenPhraseText(text: phrase, revealedCount: revealedCount)
                        .rotationEffect(.degrees(phraseRotation))
                        .position(x: geometry.size.width * phrasePosition.x, y: geometry.size.height * phrasePosition.y)
                        .opacity(phraseOpacity)
                }

                PencilBuddyView(
                    scrollFraction: scrollFraction,
                    createTrigger: createTrigger,
                    deleteTrigger: deleteTrigger,
                    collectionTrigger: collectionTrigger,
                    recordTrigger: recordTrigger,
                    isWriting: isWriting,
                    onTap: startWritingNow
                )
                .frame(width: 104, height: 140)
                .position(x: geometry.size.width * mascotAnchor.x, y: geometry.size.height * mascotAnchor.y)
                .opacity(max(presence, 0.5))
                .allowsHitTesting(true)
            }
            .task { await phraseLoop() }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// De vez em quando (e sempre que o mascote é tocado), ele "escreve"
    /// uma frase curta em algum canto variado da tela. A primeira frase
    /// sai logo (`firstWriteDelay`); as próximas respeitam
    /// `rewriteDelayRange`, contado a partir do fim da frase anterior.
    private func phraseLoop() async {
        try? await Task.sleep(nanoseconds: UInt64(Self.firstWriteDelay * 1_000_000_000))
        guard !Task.isCancelled else { return }
        await performScheduledWrite()

        while !Task.isCancelled {
            let delay = Double.random(in: Self.rewriteDelayRange)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await performScheduledWrite()
        }
    }

    private func performScheduledWrite() async {
        guard phrase == nil, let next = Self.phrases.randomElement() else { return }
        await writePhrase(next)
    }

    private func startWritingNow() {
        // Evita duas escritas se sobrepondo caso ele já esteja no meio de
        // uma frase (seja do loop automático, seja de um toque anterior).
        guard phrase == nil, let next = Self.phrases.randomElement() else { return }
        writeTask?.cancel()
        writeTask = Task { await writePhrase(next) }
    }

    private func writePhrase(_ text: String) async {
        phrase = text
        revealedCount = 0
        let textSpot = UnitPoint(x: .random(in: 0.16...0.8), y: .random(in: 0.12...0.7))
        phrasePosition = textSpot
        phraseRotation = Double.random(in: -7...7)

        // Ele viaja da posição de repouso até logo ACIMA do texto (como se
        // a ponta do lápis estivesse escrevendo de cima pra baixo) —
        // sempre dentro da tela, longe do cabeçalho e do botão de +.
        let travelTarget = UnitPoint(
            x: min(max(textSpot.x, 0.1), 0.86),
            y: min(max(textSpot.y - 0.11, 0.14), 0.8)
        )
        withAnimation(.spring(response: 0.9, dampingFraction: 0.72)) {
            mascotAnchor = travelTarget
        }

        // Dá um tempinho pra ele "chegar" antes de começar a escrever.
        try? await Task.sleep(nanoseconds: 450_000_000)
        guard !Task.isCancelled else { return }

        withAnimation(.easeIn(duration: 0.2)) { phraseOpacity = 1 }
        withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true)) {
            isWriting = true
        }

        for i in 0...text.count {
            if Task.isCancelled { break }
            revealedCount = i
            try? await Task.sleep(nanoseconds: 55_000_000)
        }

        withAnimation(.easeInOut(duration: 0.2)) { isWriting = false }

        // Fica visível por `phraseHoldDuration` depois de terminar de escrever.
        try? await Task.sleep(nanoseconds: UInt64(Self.phraseHoldDuration * 1_000_000_000))
        guard !Task.isCancelled else {
            phrase = nil
            phraseOpacity = 0
            return
        }
        withAnimation(.easeOut(duration: 0.6)) { phraseOpacity = 0 }
        withAnimation(.spring(response: 0.9, dampingFraction: 0.72)) {
            mascotAnchor = Self.restAnchor
        }
        try? await Task.sleep(nanoseconds: 650_000_000)
        phrase = nil
    }
}

/// A ilustração de fundo em si — carregada como recurso do próprio app
/// (gerada no estilo "página de estudo de papelaria", a lápis grafite com
/// alguns toques de lápis de cor). Se por algum motivo o arquivo não
/// estiver disponível, cai discretamente numa cor de papel sólida, sem
/// travar o app.
private struct SketchPaperImage: View {
    private static let uiImage: UIImage? = {
        if let named = UIImage(named: "BackgroundSketch") { return named }
        if let url = Bundle.main.url(forResource: "BackgroundSketch", withExtension: "jpg"),
           let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        return nil
    }()

    var body: some View {
        GeometryReader { geometry in
            if let image = Self.uiImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                Color(red: 0.98, green: 0.96, blue: 0.91)
            }
        }
    }
}

/// A frase que o mascote "escreve" — texto solto direto sobre o fundo, no
/// estilo à mão (fonte cursiva do sistema), sem balão nem caixa branca por
/// trás. Uma sombrinha clara + uma escura ajudam a ler em cima de qualquer
/// parte da ilustração.
private struct WrittenPhraseText: View {
    var text: String
    var revealedCount: Int

    private var visibleText: String {
        String(text.prefix(revealedCount))
    }

    var body: some View {
        Text(visibleText.isEmpty ? " " : visibleText)
            .font(.custom("SnellRoundhand-Bold", size: 30))
            .italic()
            .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.11))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: 260)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: .white.opacity(0.85), radius: 0, x: 1, y: 1)
            .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Mascote

private enum MascotMood {
    case idle, greeting, celebrating, sad, curious, listening
}

/// O mascote: um lápis (comprido, de verdade!) com carinha e bracinhos,
/// espiando num canto da tela. Cada ação do usuário muda o jeito dele —
/// não é só decoração — e ele se remexe todo, tipo rabiscando, sempre que
/// está "escrevendo" uma frase.
private struct PencilBuddyView: View {
    var scrollFraction: CGFloat
    var createTrigger: Int
    var deleteTrigger: Int
    var collectionTrigger: Int
    var recordTrigger: Int
    var isWriting: Bool
    var onTap: () -> Void

    @State private var mood: MascotMood = .idle
    @State private var isBlinking = false
    @State private var idleEyeOffset: CGSize = .zero
    @State private var bobUp = false
    @State private var showSparkle = false
    @State private var didGreet = false
    @State private var moodTask: Task<Void, Never>?

    private var eyeOffset: CGSize {
        CGSize(width: idleEyeOffset.width, height: idleEyeOffset.height + scrollFraction * 3.5)
    }

    private var armAngle: Double {
        switch mood {
        case .idle: return 18
        case .greeting: return -120
        case .celebrating: return -150
        case .sad: return 34
        case .curious: return -60
        case .listening: return -100 // mão em concha perto da "orelha"
        }
    }

    private var mouthCurvature: CGFloat {
        switch mood {
        case .idle: return 3
        case .greeting: return 6
        case .celebrating: return 9
        case .sad: return -6
        case .curious: return 2
        case .listening: return 5
        }
    }

    private var mouthWidth: CGFloat {
        mood == .celebrating ? 20 : (mood == .sad ? 12 : 15)
    }

    private var bounceAmount: CGFloat {
        switch mood {
        case .celebrating: return -14
        case .greeting: return -8
        case .sad: return 3
        case .listening: return -4
        default: return bobUp ? -6 : 0
        }
    }

    var body: some View {
        ZStack {
            if showSparkle {
                SparkleBurst()
                    .offset(y: -70)
                    .transition(.scale.combined(with: .opacity))
            }

            PencilBuddyShape(
                isBlinking: isBlinking,
                eyeOffset: eyeOffset,
                armAngle: armAngle,
                mouthCurvature: mouthCurvature,
                mouthWidth: mouthWidth,
                headTilt: (mood == .curious || mood == .listening) ? -8 : 0,
                writeWiggle: isWriting
            )
        }
        .offset(y: bounceAmount)
        .animation(.spring(response: 0.4, dampingFraction: 0.55), value: mood)
        .onTapGesture {
            trigger(mood: .greeting, sparkle: false)
            onTap()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                bobUp = true
            }
            if !didGreet {
                didGreet = true
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    trigger(mood: .greeting, sparkle: false)
                }
            }
        }
        .task { await blinkLoop() }
        .task { await lookLoop() }
        .onChange(of: createTrigger) { _, _ in trigger(mood: .celebrating, sparkle: true) }
        .onChange(of: deleteTrigger) { _, _ in trigger(mood: .sad, sparkle: false) }
        .onChange(of: collectionTrigger) { _, _ in trigger(mood: .curious, sparkle: false) }
        .onChange(of: recordTrigger) { _, _ in trigger(mood: .listening, sparkle: true) }
    }

    private func blinkLoop() async {
        while !Task.isCancelled {
            let delay = Double.random(in: 2.4...5.0)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.09)) { isBlinking = true }
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(.easeInOut(duration: 0.12)) { isBlinking = false }
        }
    }

    private func lookLoop() async {
        while !Task.isCancelled {
            let dx = CGFloat.random(in: -3.5...3.5)
            let dy = CGFloat.random(in: -2.0...2.0)
            withAnimation(.easeInOut(duration: 0.7)) { idleEyeOffset = CGSize(width: dx, height: dy) }
            let delay = Double.random(in: 1.6...3.2)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private func trigger(mood newMood: MascotMood, sparkle: Bool) {
        moodTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
            mood = newMood
            if sparkle { showSparkle = true }
        }
        moodTask = Task {
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                mood = .idle
                showSparkle = false
            }
        }
    }
}

/// Desenho do lápis-mascote: bem mais comprido que antes (pra parecer
/// lápis de verdade), com capuz rosa (borracha), corpo amarelo/laranja,
/// pontinha grafite, bracinhos, e a carinha (olhos + boca que mudam de
/// expressão). Sombra dura ao estilo gibi, igual às capas dos cadernos.
/// Enquanto `writeWiggle` está ativo, o corpo inteiro balança em torno da
/// ponta (como se estivesse rabiscando de verdade) e o braço direito
/// ganha uma tremidinha extra.
private struct PencilBuddyShape: View {
    var isBlinking: Bool
    var eyeOffset: CGSize
    var armAngle: Double
    var mouthCurvature: CGFloat
    var mouthWidth: CGFloat
    var headTilt: Double
    var writeWiggle: Bool = false

    private let bodyWidth: CGFloat = 42
    private let bodyHeight: CGFloat = 84

    var body: some View {
        ZStack {
            silhouette(color: .black)
                .offset(x: 3, y: 3)

            arm(side: -1)
            arm(side: 1)

            ZStack {
                Capsule()
                    .fill(Color.pink)
                    .frame(width: 32, height: 16)
                    .overlay(Capsule().strokeBorder(Color.black, lineWidth: 2))
                    .offset(y: -(bodyHeight / 2 + 8))

                RoundedRectangle(cornerRadius: 13)
                    .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.black, lineWidth: 2.5))
                    .frame(width: bodyWidth, height: bodyHeight)

                Triangle()
                    .fill(Color(red: 0.94, green: 0.8, blue: 0.62))
                    .overlay(Triangle().stroke(Color.black, lineWidth: 2))
                    .frame(width: 20, height: 20)
                    .offset(y: bodyHeight / 2 + 10)

                Circle()
                    .fill(Color.black)
                    .frame(width: 5, height: 5)
                    .offset(y: bodyHeight / 2 + 21)
            }

            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    EyeView(isBlinking: isBlinking, offset: eyeOffset)
                    EyeView(isBlinking: isBlinking, offset: eyeOffset)
                }
                MouthCurve(curvature: mouthCurvature)
                    .stroke(Color.black, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .frame(width: mouthWidth, height: 8)
            }
            .offset(y: -bodyHeight * 0.22)
        }
        .rotationEffect(.degrees(headTilt))
        .rotationEffect(.degrees(writeWiggle ? 6 : -6), anchor: .bottom)
        .offset(x: writeWiggle ? 2.5 : -2.5)
        .frame(width: 60, height: 130)
    }

    /// O braço direito (side == 1) ganha uma pequena "tremidinha" extra
    /// enquanto ele está escrevendo, feito segurando um lápis invisível
    /// fazendo gestos rápidos.
    private func arm(side: CGFloat) -> some View {
        let writingExtra: Double = (side == 1 && writeWiggle) ? 18 : 0
        return Capsule()
            .fill(Color.orange)
            .overlay(Capsule().strokeBorder(Color.black, lineWidth: 2))
            .frame(width: 9, height: 30)
            .offset(y: 14)
            .rotationEffect(.degrees(side * armAngle + writingExtra), anchor: .top)
            .offset(x: side * 21, y: -bodyHeight * 0.1)
    }

    private func silhouette(color: Color) -> some View {
        ZStack {
            Capsule().fill(color).frame(width: 32, height: 16).offset(y: -(bodyHeight / 2 + 8))
            RoundedRectangle(cornerRadius: 13).fill(color).frame(width: bodyWidth, height: bodyHeight)
            Triangle().fill(color).frame(width: 20, height: 20).offset(y: bodyHeight / 2 + 10)
            Circle().fill(color).frame(width: 5, height: 5).offset(y: bodyHeight / 2 + 21)
        }
    }
}

private struct EyeView: View {
    var isBlinking: Bool
    var offset: CGSize

    var body: some View {
        ZStack {
            Circle().fill(Color.white).frame(width: 13, height: 13)
            Circle().strokeBorder(Color.black, lineWidth: 1.5).frame(width: 13, height: 13)
            if isBlinking {
                Rectangle().fill(Color.black).frame(width: 8, height: 1.6)
            } else {
                Circle().fill(Color.black).frame(width: 5.5, height: 5.5).offset(offset)
            }
        }
    }
}

/// Curva simples pra boca: curvatura positiva vira sorriso, negativa vira
/// bico/tristeza.
private struct MouthCurve: Shape {
    var curvature: CGFloat

    var animatableData: CGFloat {
        get { curvature }
        set { curvature = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let left = CGPoint(x: rect.minX, y: rect.midY)
        let right = CGPoint(x: rect.maxX, y: rect.midY)
        let control = CGPoint(x: rect.midX, y: rect.midY + curvature)
        path.move(to: left)
        path.addQuadCurve(to: right, control: control)
        return path
    }
}

/// Estrelinhas ao redor do mascote quando ele comemora.
private struct SparkleBurst: View {
    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                let angle = Double(i) / 6 * 2 * .pi
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.yellow)
                    .offset(x: cos(angle) * 26, y: sin(angle) * 20)
            }
        }
    }
}

/// Triângulo simples, usado como pontinha do lápis-mascote.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Um punhado extra de itens de papelaria flutuando bem de leve por cima
/// da ilustração de fundo, pra dar uma sensação de movimento sutil — a
/// própria imagem de fundo já cuida da fartura de canetas/lápis/borrachas.
private struct FloatingStationeryLayer: View {
    private struct Item {
        let symbol: String
        let size: CGFloat
        let baseX: CGFloat // fração da largura (0...1)
        let baseY: CGFloat // fração da altura (0...1)
        let speed: Double
        let phase: Double
        let amplitude: CGFloat
        let color: Color
    }

    private let items: [Item] = [
        Item(symbol: "pencil", size: 20, baseX: 0.16, baseY: 0.14, speed: 0.35, phase: 0.4, amplitude: 12, color: .blue),
        Item(symbol: "paperclip", size: 18, baseX: 0.8, baseY: 0.1, speed: 0.28, phase: 1.6, amplitude: 9, color: .gray),
        Item(symbol: "star.fill", size: 12, baseX: 0.3, baseY: 0.38, speed: 0.5, phase: 2.4, amplitude: 10, color: .orange),
        Item(symbol: "highlighter", size: 20, baseX: 0.66, baseY: 0.46, speed: 0.22, phase: 0.9, amplitude: 14, color: .pink),
        Item(symbol: "eraser.fill", size: 16, baseX: 0.12, baseY: 0.64, speed: 0.32, phase: 3.1, amplitude: 10, color: .teal),
        Item(symbol: "ruler.fill", size: 20, baseX: 0.88, baseY: 0.58, speed: 0.26, phase: 1.1, amplitude: 9, color: .purple),
        Item(symbol: "pencil.tip", size: 14, baseX: 0.4, baseY: 0.2, speed: 0.44, phase: 2.0, amplitude: 8, color: .green),
        Item(symbol: "paintpalette.fill", size: 20, baseX: 0.58, baseY: 0.78, speed: 0.3, phase: 0.6, amplitude: 12, color: .indigo)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            GeometryReader { geometry in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    let x = item.baseX * geometry.size.width + CGFloat(cos(t * item.speed + item.phase)) * item.amplitude
                    let y = item.baseY * geometry.size.height + CGFloat(sin(t * item.speed + item.phase)) * item.amplitude
                    let rotation = sin(t * item.speed + item.phase) * 12

                    Image(systemName: item.symbol)
                        .font(.system(size: item.size, weight: .semibold))
                        .foregroundStyle(item.color.opacity(0.4))
                        .rotationEffect(.degrees(rotation))
                        .position(x: x, y: y)
                }
            }
        }
    }
}

#Preview {
    MascotBackgroundView(notebookCount: 0, scrollFraction: 0, createTrigger: 0, deleteTrigger: 0, collectionTrigger: 0, recordTrigger: 0)
        .background(Color(.systemGroupedBackground))
}
