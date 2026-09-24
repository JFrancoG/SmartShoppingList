@testable import SmartShoppingListServer
import Testing

struct DatabaseTLSConfigurationTests {
    @Test(arguments: [
        "",
        " \n\t",
        "not a certificate",
        "-----BEGIN CERTIFICATE-----\ninvalid\n-----END CERTIFICATE-----",
        "-----BEGIN CERTIFICATE-----\nMIIB"
    ])
    func `rejects a configured invalid CA instead of falling back to local TLS`(certificatePEM: String) {
        #expect(throws: AppConfigurationError.invalidDatabaseCACertificatePEM) {
            _ = try DatabaseTLSConfiguration.make(caCertificatePEM: certificatePEM)
        }
    }
}
