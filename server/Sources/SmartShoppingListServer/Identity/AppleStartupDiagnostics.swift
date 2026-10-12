import Logging

enum AppleStartupDiagnostics {
    static func invalidConfiguration(_ logger: Logger?, field: StaticString, rule: StaticString) -> AppleGatewayError {
        let fieldName = String(describing: field)
        logger?.error(
            "Invalid Apple startup configuration: \(fieldName) \(rule)",
            metadata: ["field": .string(fieldName)]
        )
        return .invalidConfiguration
    }
}
