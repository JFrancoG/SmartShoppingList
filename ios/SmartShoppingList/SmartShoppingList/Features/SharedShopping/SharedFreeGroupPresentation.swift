import Foundation

enum SharedFreeGroupPresentation {
    case loading
    case unavailable
    case empty
    case single(SharedGroup)
    case multiple(
        selected: SharedGroup?,
        premiumActive: Bool,
        transitionEnd: Date?,
        nextChange: Date?,
        alternatives: [SharedGroup]
    )
}

extension SharedShoppingViewModel {
    /// Presentation only: server capabilities remain the authority for every action.
    func freeGroupPresentation(at date: Date) -> SharedFreeGroupPresentation {
        guard hasLoaded else { return .loading }
        guard sessionIsVerified, groupsAreVerified, let access = membershipAccess else { return .unavailable }
        guard let first = groups.first else { return .empty }
        guard groups.count > 1 else { return .single(first) }
        return .multiple(
            selected: groups.first { $0.id == access.freeGroupId },
            premiumActive: access.premiumActive,
            transitionEnd: !access.premiumActive ? access.transitionEndsAt.flatMap { $0 > date ? $0 : nil } : nil,
            nextChange: !access.canChangeFreeGroup
                ? access.freeGroupChangeAvailableAt.flatMap { $0 > date ? $0 : nil } : nil,
            alternatives: groups.filter { $0.id != access.freeGroupId }
        )
    }
}
