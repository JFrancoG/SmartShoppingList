import Foundation

enum SharedErrorMessage {
    static func message(for error: any Error) -> LocalizedStringResource {
        guard let error = error as? SharedAPIError else {
            return "The operation could not be completed. Pending data is kept; try again."
        }
        switch error {
        case .configuration:
            return "The group connection is not configured yet. You can prepare your draft manually."
        case .invalidInvitation:
            return "This invitation link is not valid for this app."
        case .requestTooLarge:
            return "The submission is too large. Review the draft before confirming it."
        case .transport, .invalidResponse:
            return "The result could not be confirmed. The original submission is kept so you can retry without duplicating products."
        case .server(_, let code, _, _):
            switch code {
            case "invalid_session": return "Your session has expired or been revoked. Sign in again with the same Apple Account."
            case "invalid_apple_credentials", "challenge_expired", "challenge_consumed":
                return "This sign-in attempt is no longer valid. Start signing in with Apple again."
            case "already_in_group": return "Your account already belongs to a group. Refresh to check its status."
            case "invitation_expired": return "The invitation has expired. Ask for a new link."
            case "invitation_revoked": return "The invitation has been revoked. Ask for a new link."
            case "invitation_consumed": return "Someone else has already used this invitation. Ask for a new link."
            case "not_found": return "The resource is unavailable or you do not have access. Refresh and try again."
            case "creator_required": return "Only the person who created the group can manage invitations."
            case "idempotency_key_reused", "item_conflict":
                return "The submission has a conflict. Refresh and review the data before confirming again."
            case "invalid_request", "body_too_large": return "Review the form data before submitting it again."
            case "rate_limited": return "Too many attempts. Wait a moment before retrying."
            default: return "The service is currently unavailable. Pending data is kept so you can retry."
            }
        }
    }
}
