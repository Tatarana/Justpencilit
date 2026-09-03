import LocalAuthentication

/// Ponte fina com o `LocalAuthentication` do sistema, usada pra proteger
/// cadernos e coleções específicas (ex: cadernos de trabalho, que a
/// sobrinha do usuário não deveria conseguir abrir sozinha).
///
/// Usa a política `.deviceOwnerAuthentication`, que já tenta Face ID/Touch
/// ID primeiro e cai automaticamente pra tela de senha do iPad se a
/// biometria falhar, não estiver configurada, ou o próprio usuário tocar em
/// "Usar senha" — exatamente as duas opções pedidas, sem precisarmos
/// implementar uma senha própria do app (que seria mais um código pra
/// lembrar, e menos seguro que o que o sistema já oferece).
enum BiometricLock {
    /// Pede a autenticação com uma explicação (`reason`) mostrada na tela
    /// do sistema. Retorna `true` só se o dono do aparelho confirmar.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Usar senha"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Nem biometria nem senha configuradas no aparelho — não dá pra
            // proteger nada, então não bloqueia (evita trancar o usuário
            // pra fora do próprio caderno num iPad sem nenhuma trava).
            return false
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
