import Foundation
import Security

/// Proves a staged bundle is ours: an Apple Development certificate of the Lite team.
enum BundleSignature {
    /// The team, not the certificate — a leaf is reissued on renewal and on a rename.
    static let requirement = """
        anchor apple generic \
        and certificate leaf[subject.OU] = "SL2WXVL9K2" \
        and certificate 1[field.1.2.840.113635.100.6.2.1] exists
        """

    /// No `notarized`: Lite releases are not notarized, and the chain already proves ownership.
    static func isTrusted(_ bundleURL: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
            let staticCode
        else { return false }
        var parsed: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &parsed) == errSecSuccess,
            let parsed
        else { return false }
        // An unsealed bundle can claim any identity, and a nested helper is where one hides.
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(staticCode, flags, parsed) == errSecSuccess
    }
}
