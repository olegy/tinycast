import Foundation

@main
struct StatusIconsTest {
    nonisolated(unsafe) static var failures = 0

    static func check(_ description: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }

    static func main() {
        testClassify()
        testParsing()
        testReadings()
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    private static let defaults = DNSStatus.localResolvers(from: DNSStatus.defaultLocalResolvers)

    private static func testClassify() {
        check("loopback v4 alone is local", DNSStatus.classify(resolvers: ["127.0.0.1"], local: defaults) == .local)
        check(
            "loopback v4 and v6 are local",
            DNSStatus.classify(resolvers: ["127.0.0.1", "::1"], local: defaults) == .local)
        check(
            "a router is external",
            DNSStatus.classify(resolvers: ["192.168.1.1"], local: defaults) == .external)
        check(
            "one external among local ones is external",
            DNSStatus.classify(resolvers: ["127.0.0.1", "1.1.1.1"], local: defaults) == .external)
        check("no resolvers is no servers", DNSStatus.classify(resolvers: [], local: defaults) == .noServers)
        let custom = DNSStatus.localResolvers(from: "10.0.0.53")
        check(
            "a custom list decides",
            DNSStatus.classify(resolvers: ["10.0.0.53"], local: custom) == .local
                && DNSStatus.classify(resolvers: ["127.0.0.1"], local: custom) == .external)
        check(
            "an empty list makes everything external",
            DNSStatus.classify(resolvers: ["127.0.0.1"], local: []) == .external)
    }

    private static func testParsing() {
        check("the default is v4 and v6 loopback", defaults == ["127.0.0.1", "::1"])
        check(
            "spaces and stray commas are dropped",
            DNSStatus.localResolvers(from: " 127.0.0.1 ,, ::1, ,") == ["127.0.0.1", "::1"])
        check("an empty field is an empty set", DNSStatus.localResolvers(from: "").isEmpty)
        check("a blank field is an empty set", DNSStatus.localResolvers(from: " , ").isEmpty)
        check(
            "IPv6 is compared case-insensitively",
            DNSStatus.classify(resolvers: ["FD00::53"], local: DNSStatus.localResolvers(from: "fd00::53"))
                == .local
                && DNSStatus.classify(
                    resolvers: ["fd00::53"], local: DNSStatus.localResolvers(from: "FD00::53")) == .local)
    }

    private static func testReadings() {
        let local = DNSStatus.reading(resolvers: ["127.0.0.1"], local: defaults)
        check("local draws a closed lock", local.symbol == "lock.fill" && local.tone == .normal)
        check("local says so", local.summary == "DNS: 127.0.0.1 — local")

        let external = DNSStatus.reading(resolvers: ["192.168.1.1", "1.1.1.1"], local: defaults)
        check(
            "external draws an open lock asking for attention",
            external.symbol == "lock.open.fill" && external.tone == .attention)
        check("external lists every address", external.summary == "DNS: 192.168.1.1, 1.1.1.1 — not local")

        let none = DNSStatus.reading(resolvers: [], local: defaults)
        check("no servers draws a calm open lock", none.symbol == "lock.open.fill" && none.tone == .normal)
        check("no servers says so", none.summary == "DNS: no servers")
    }
}
