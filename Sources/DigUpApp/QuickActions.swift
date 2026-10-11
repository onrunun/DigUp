import AppKit
import DigUpKit
import Foundation

/// Fast zero-overhead launcher reflexes: Web URLs, Math evaluation, System commands, Terminal, and AI queries.
enum QuickActions {
    /// Detects if `text` is a Web URL, domain name, or localhost.
    static func detectURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        
        if trimmed.hasPrefix("localhost:") || trimmed.hasPrefix("localhost/") || trimmed == "localhost" {
            return URL(string: "http://" + trimmed)
        }
        
        if trimmed.hasPrefix("127.0.0.1:") || trimmed.hasPrefix("127.0.0.1/") || trimmed == "127.0.0.1" {
            return URL(string: "http://" + trimmed)
        }
        
        // Standard domain with 2+ letter TLD (e.g. sahibinden.com, github.com, utkuk.dev, apple.com/tr)
        let domainPattern = #"^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*\.[a-zA-Z]{2,}(:\d+)?(/.*)?$"#
        if trimmed.range(of: domainPattern, options: .regularExpression) != nil {
            return URL(string: "https://" + trimmed)
        }
        
        return nil
    }

    /// Evaluates simple arithmetic expressions safely via NSExpression.
    static func detectMath(_ text: String) -> (expr: String, result: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }
        
        // Must contain an operator
        let operators = "+-*/%^"
        guard trimmed.contains(where: { operators.contains($0) }) else { return nil }
        
        // Allowed characters only
        let allowed = CharacterSet(charactersIn: "0123456789+-*/.%^() ")
        guard CharacterSet(charactersIn: trimmed).isSubset(of: allowed) else { return nil }
        
        // Replace power operator if present
        let sanitized = trimmed.replacingOccurrences(of: "^", with: "**")
        
        let expr = NSExpression(format: sanitized)
        guard let num = expr.expressionValue(with: nil, context: nil) as? NSNumber else { return nil }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        guard let formatted = formatter.string(from: num) else { return nil }
        
        return (trimmed, formatted)
    }

    /// Primary local IPv4 network address in < 1ms.
    static func getLocalIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            if addr.sa_family == UInt8(AF_INET), (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let name = String(cString: ptr.pointee.ifa_name)
                    let ip = hostname.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                    if name.hasPrefix("en") || name.hasPrefix("utun") {
                        return "\(ip) (\(name))"
                    }
                }
            }
        }
        return nil
    }

    /// System command actions.
    static func detectSystemCommand(_ text: String) -> (name: String, cmd: String, symbol: String, folder: String)? {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lower {
        case "lock", "lock screen":
            return ("Lock Screen", "lock", "lock.fill", "System · Lock your Mac immediately")
        case "sleep":
            return ("Sleep Mac", "sleep", "moon.fill", "System · Put Mac to sleep")
        case "restart", "reboot":
            return ("Restart Mac…", "restart", "arrow.clockwise.circle.fill", "System · Restart computer")
        case "shutdown", "shut down":
            return ("Shut Down Mac…", "shutdown", "power.circle.fill", "System · Shut down computer")
        case "dark mode", "toggle dark mode":
            return ("Toggle Dark Mode", "darkmode", "circle.lefthalf.filled", "Appearance · Toggle Light / Dark mode")
        case "trash", "empty trash":
            return ("Empty Trash", "trash", "trash.fill", "Finder · Empty Trash items")
        case "ip", "my ip", "local ip":
            if let ip = getLocalIP() {
                return ("Local IP: \(ip)", "ip:\(ip)", "network", "Network · Press Return or ⌘C to copy")
            }
            return nil
        default:
            return nil
        }
    }

    /// Terminal command runner when prefixed with `>` or `$`.
    static func detectTerminalCommand(_ text: String) -> (cmd: String, display: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(">") {
            let cmd = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            guard !cmd.isEmpty else { return nil }
            return (cmd, "Run in Terminal: “\(cmd)”")
        }
        if trimmed.hasPrefix("$") {
            let cmd = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            guard !cmd.isEmpty else { return nil }
            return (cmd, "Run in Terminal: “\(cmd)”")
        }
        return nil
    }

    /// AI Query when prefixed with `?` or `ai:`.
    static func detectAIQuery(_ text: String) -> (prompt: String, display: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("?") {
            let prompt = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            guard !prompt.isEmpty else { return nil }
            return (prompt, "Ask AI: “\(prompt)”")
        }
        if trimmed.lowercased().hasPrefix("ai:") {
            let prompt = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
            guard !prompt.isEmpty else { return nil }
            return (prompt, "Ask AI: “\(prompt)”")
        }
        return nil
    }

    /// Executes system commands safely.
    static func executeSystemCommand(_ cmd: String) {
        if cmd.hasPrefix("ip:") {
            let raw = cmd.dropFirst(3)
            let ip = raw.components(separatedBy: " ").first ?? String(raw)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(ip), forType: .string)
            return
        }
        switch cmd {
        case "lock":
            let script = "tell application \"System Events\" to key code 12 using {control down, command down}"
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        case "sleep":
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            task.arguments = ["sleepnow"]
            try? task.run()
        case "restart":
            let script = "tell application \"System Events\" to restart"
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        case "shutdown":
            let script = "tell application \"System Events\" to shut down"
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        case "darkmode":
            let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        case "trash":
            let script = "tell application \"Finder\" to empty trash"
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        default:
            break
        }
    }

    /// Runs command in macOS Terminal.
    static func runInTerminal(_ cmd: String) {
        let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell"
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }

    /// Opens AI prompt in browser.
    static func openAIQuery(_ prompt: String) {
        let encoded = prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? prompt
        if let url = URL(string: "https://www.perplexity.ai/search?q=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Generates quick actions for a query and current hits.
    static func generate(for query: String, hits: [SearchHit]) -> [ResultRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        var actions: [ResultRow] = []

        // 1. Terminal runner (> or $)
        if let (cmd, display) = detectTerminalCommand(trimmed) {
            let row = ResultRow(
                action: "action:terminal:\(cmd)",
                url: URL(string: "terminal://run") ?? URL(fileURLWithPath: "/"),
                name: display,
                folder: "Terminal · /bin/zsh",
                excerpt: "Run command “\(cmd)” in Terminal",
                info: ["action": "terminal", "command": cmd]
            )
            actions.append(row)
            return actions
        }

        // 2. AI query (? or ai:)
        if let (prompt, display) = detectAIQuery(trimmed) {
            let row = ResultRow(
                action: "action:ai:\(prompt)",
                url: URL(string: "ai://ask") ?? URL(fileURLWithPath: "/"),
                name: display,
                folder: "AI Assistant · Perplexity AI",
                excerpt: "Ask AI: “\(prompt)”",
                info: ["action": "ai", "prompt": prompt]
            )
            actions.append(row)
            return actions
        }

        // 3. System Commands (lock, sleep, dark mode, ip...)
        if let (name, cmd, symbol, folder) = detectSystemCommand(trimmed) {
            let row = ResultRow(
                action: "action:sys:\(cmd)",
                url: URL(string: "sys://\(cmd)") ?? URL(fileURLWithPath: "/"),
                name: name,
                folder: folder,
                excerpt: folder,
                info: ["action": "sys", "command": cmd, "symbol": symbol]
            )
            actions.append(row)
        }
        
        // 4. Math calculation
        if let (expr, result) = detectMath(trimmed) {
            let row = ResultRow(
                action: "action:calc:\(result)",
                url: URL(string: "calc://\(result)") ?? URL(fileURLWithPath: "/"),
                name: "= \(result)",
                folder: "Calculator · \(expr)",
                excerpt: "\(expr) = \(result)",
                info: ["action": "calc", "result": result]
            )
            actions.append(row)
        }
        
        // 5. Direct Web URL / Domain
        if let url = detectURL(trimmed) {
            let host = url.host ?? trimmed
            let row = ResultRow(
                action: "action:url:\(url.absoluteString)",
                url: url,
                name: "Open \(host) in Browser",
                folder: "Web · \(url.absoluteString)",
                excerpt: "Open \(url.absoluteString) in your default browser",
                info: ["action": "url", "url": url.absoluteString]
            )
            actions.append(row)
        }
        
        // 6. Web Search fallback when query has no strong local hits or user typed a search phrase
        let strongHits = Searcher.strongCount(hits)
        let isSearchCandidate = trimmed.count >= 2 && !actions.contains { $0.info["action"] == "url" }
        if strongHits == 0 && isSearchCandidate {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            if let googleURL = URL(string: "https://www.google.com/search?q=\(encoded)") {
                let row = ResultRow(
                    action: "action:web:\(trimmed)",
                    url: googleURL,
                    name: "Search Google for “\(trimmed)”",
                    folder: "Web Search · google.com",
                    excerpt: "Search for “\(trimmed)” on Google",
                    info: ["action": "web", "query": trimmed]
                )
                actions.append(row)
            }
        }
        
        return actions
    }
}
