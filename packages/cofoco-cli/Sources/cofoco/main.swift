import CofocoCLI
import Foundation

@main
struct CofocoMain {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let baseURL: URL
        do {
            if let configured = ProcessInfo.processInfo.environment["COFOCO_SERVICE_URL"] {
                guard let url = URL(string: configured) else { throw ServiceClientError.invalidEndpoint }
                baseURL = url
            } else {
                baseURL = CofocoServiceClient.defaultBaseURL
            }
            let client = try CofocoServiceClient(baseURL: baseURL)
            let cli = CofocoCommandLine(client: client)
            let exitCode = await cli.run(arguments)
            if exitCode != 0 { exit(exitCode) }
        } catch {
            fputs("cofoco: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
