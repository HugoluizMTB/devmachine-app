import XCTest
@testable import DevmachineCore

final class MachineReportsTests: XCTestCase {
    func testResolveSaysWhichAddressesWorkAndWhyOthersWereSkipped() throws {
        let json = #"""
        {"machine":"main","addresses":[
          {"address":"100.64.0.10","source":"tailscale:main","package":"tailscale"},
          {"address":"203.0.113.10","source":"203.0.113.10","package":""}],
         "dropped":[{"source":"main.example.com","reason":"no such host"}]}
        """#
        let report = try XCTUnwrap(MachineAddresses.parse(json))
        XCTAssertEqual(report.machine, "main")
        XCTAssertEqual(report.addresses.map(\.address), ["100.64.0.10", "203.0.113.10"])
        XCTAssertEqual(report.addresses.map(\.isTailnet), [true, false])
        XCTAssertEqual(report.addresses[0].package, "tailscale")
        XCTAssertEqual(report.dropped, [MachineAddresses.Dropped(source: "main.example.com", reason: "no such host")])
    }

    func testResolveWithNullListsReadsAsEmpty() throws {
        let report = try XCTUnwrap(MachineAddresses.parse(#"{"machine":"lab","addresses":[],"dropped":null}"#))
        XCTAssertTrue(report.addresses.isEmpty)
        XCTAssertTrue(report.dropped.isEmpty)
        XCTAssertNil(MachineAddresses.parse("not json"))
    }

    func testPasswordLoginSaysWhoCanLogInWithAPassword() throws {
        let json = #"""
        {"machine":"studio","default":false,"drop_in":true,
         "accounts":[{"user":"alice","password_login":true},{"user":"bob","password_login":false}],
         "keep":["alice"]}
        """#
        let report = try XCTUnwrap(MachinePasswordLogin.parse(json))
        XCTAssertFalse(report.allowedByDefault)
        XCTAssertTrue(report.dropIn)
        XCTAssertEqual(report.accounts.map(\.user), ["alice", "bob"])
        XCTAssertEqual(report.accounts.map(\.allowed), [true, false])
        XCTAssertEqual(report.keep, ["alice"])
        XCTAssertEqual(report.summary, "Off, except for alice")
        XCTAssertNil(MachinePasswordLogin.parse("not json"))
    }

    func testPasswordLoginSummaryForEachState() throws {
        let off = try XCTUnwrap(MachinePasswordLogin.parse(#"{"machine":"m","default":false,"drop_in":true,"accounts":[],"keep":[]}"#))
        XCTAssertEqual(off.summary, "Off for every account")
        let on = try XCTUnwrap(MachinePasswordLogin.parse(#"{"machine":"m","default":true,"drop_in":false,"accounts":null,"keep":null}"#))
        XCTAssertEqual(on.summary, "On (the system's own setting)")
        XCTAssertTrue(on.accounts.isEmpty)
    }

    func testPasswordLoginArguments() {
        XCTAssertEqual(MachinePasswordLogin.arguments(machine: "studio"),
                       ["--format", "json", "machines", "password-login", "studio"])
        XCTAssertEqual(PasswordLoginChange.off.arguments(machine: "studio"),
                       ["machines", "password-login", "studio", "--off", "--yes"])
        XCTAssertEqual(PasswordLoginChange.keep(["alice", "bob"]).arguments(machine: "studio"),
                       ["machines", "password-login", "studio", "--keep", "alice,bob", "--yes"])
        XCTAssertEqual(PasswordLoginChange.on.arguments(machine: "studio"),
                       ["machines", "password-login", "studio", "--on", "--yes"])
        XCTAssertEqual(PasswordLoginChange.keep([]).arguments(machine: "studio"),
                       ["machines", "password-login", "studio", "--off", "--yes"])
    }

    func testResolveArgumentsNameTheMachine() {
        XCTAssertEqual(MachineAddresses.arguments(machine: "main"), ["--format", "json", "resolve", "--machine", "main"])
    }

    func testCredentialsListsWhatIsMissingWithItsFix() throws {
        let json = #"""
        {"credentials":[
          {"key":"claude","name":"claude","kind":"file","package":"claude-code","place":"~/.claude","status":"present"},
          {"key":"acme/gh","name":"gh","kind":"manual","package":"dev","workspace":"acme","place":"~/.config/gh",
           "status":"missing","fix":"devmachine login gh --workspace acme"},
          {"key":"sentry","name":"sentry","kind":"secret","package":"sentry","status":"unknown",
           "fix":"devmachine secrets set sentry, then devmachine credentials push"}]}
        """#
        let report = try XCTUnwrap(MachineCredentials.parse(json))
        XCTAssertEqual(report.credentials.count, 3)
        XCTAssertEqual(report.missing.map(\.key), ["acme/gh"])
        XCTAssertEqual(report.unknown.map(\.key), ["sentry"])
        XCTAssertEqual(report.missing.first?.fix, "devmachine login gh --workspace acme")
        XCTAssertEqual(report.missing.first?.workspace, "acme")
    }

    func testCredentialsArgumentsNameTheMachine() {
        XCTAssertEqual(
            MachineCredentials.arguments(machine: "main"),
            ["--format", "json", "credentials", "list", "--machine", "main"])
        XCTAssertNil(MachineCredentials.parse("{}"))
    }

    func testLocalMachineCommandsNameTheLimaMachine() {
        XCTAssertEqual(LocalMachineCommand.start.arguments(machine: "lab"), ["machines", "start", "lab"])
        XCTAssertEqual(LocalMachineCommand.stop.arguments(machine: "lab"), ["machines", "stop", "lab"])
        XCTAssertEqual(
            LocalMachineCommand.delete.arguments(machine: "lab"), ["machines", "delete-local", "lab", "--yes"])
        XCTAssertEqual(LocalMachineCommand.start.title(machine: "lab"), "Start lab")
        XCTAssertEqual(LocalMachineCommand.delete.title(machine: "lab"), "Delete the VM lab")
    }
}
