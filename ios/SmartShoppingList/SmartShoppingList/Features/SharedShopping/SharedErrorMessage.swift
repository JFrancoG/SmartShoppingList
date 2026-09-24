import Foundation

enum SharedErrorMessage {
    static func message(for error: any Error) -> LocalizedStringResource {
        guard let error = error as? SharedAPIError else {
            return "No se ha podido completar la operación. Los datos pendientes se conservan; vuelve a intentarlo."
        }
        switch error {
        case .configuration:
            return "La conexión del grupo todavía no está configurada. Puedes preparar tu borrador a mano."
        case .invalidInvitation:
            return "El enlace de invitación no es válido para esta app."
        case .requestTooLarge:
            return "El envío es demasiado grande. Revisa el borrador antes de confirmarlo."
        case .transport, .invalidResponse:
            return "No se ha podido confirmar el resultado. Conservamos el envío original para reintentarlo sin duplicar productos."
        case .server(_, let code, _, _):
            switch code {
            case "invalid_session": return "La sesión ha caducado o se ha revocado. Accede de nuevo con la misma cuenta de Apple."
            case "invalid_apple_credentials", "challenge_expired", "challenge_consumed":
                return "Este intento de acceso ya no es válido. Inicia de nuevo el acceso con Apple."
            case "already_in_group": return "Tu cuenta ya pertenece a un grupo. Actualiza para consultar su estado."
            case "invitation_expired": return "La invitación ha caducado. Pide un enlace nuevo."
            case "invitation_revoked": return "La invitación se ha revocado. Pide un enlace nuevo."
            case "invitation_consumed": return "Otra persona ya ha utilizado esta invitación. Pide un enlace nuevo."
            case "not_found": return "El recurso no está disponible o no tienes acceso. Actualiza e inténtalo de nuevo."
            case "creator_required": return "Solo la persona que creó el grupo puede gestionar invitaciones."
            case "idempotency_key_reused", "item_conflict":
                return "El envío tiene un conflicto. Actualiza y revisa los datos antes de volver a confirmar."
            case "invalid_request", "body_too_large": return "Revisa los datos del formulario antes de volver a enviarlos."
            case "rate_limited": return "Hay demasiados intentos. Espera un momento antes de reintentar."
            default: return "El servicio no está disponible ahora. Conservamos los datos pendientes para reintentarlo."
            }
        }
    }
}
