import AppKit
import DigUpKit
import Foundation
import JavaScriptCore

/// Fast zero-overhead launcher reflexes: Web URLs, Math evaluation, System commands, Terminal, and Google Antigravity Gemini.
enum QuickActions {
    private static let jsContext = JSContext()

    private static let fileExtensions: Set<String> = [
        "md", "txt", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "py", "js", "ts", "tsx", "jsx", "json", "yaml", "yml", "sh", "bash", "zsh",
        "swift", "c", "cpp", "h", "m", "rs", "go", "rb", "java", "kt", "html", "css", "scss",
        "png", "jpg", "jpeg", "gif", "svg", "webp", "mp4", "mov", "mp3", "wav", "m4a",
        "zip", "tar", "gz", "app", "dmg", "pkg", "iso", "csv", "sql", "sqlite", "db", "log", "env", "xml", "toml", "lock"
    ]

    private static let webTLDs: Set<String> = [
        "com", "org", "net", "edu", "gov", "mil", "int",
        "dev", "io", "ai", "co", "app", "tech", "me", "xyz", "info", "biz",
        "cloud", "online", "site", "store", "live", "space", "shop", "top", "club",
        "tr", "de", "uk", "fr", "ru", "jp", "ca", "au", "br", "in", "it", "es", "nl", "se", "no", "fi", "dk", "ch", "at", "be"
    ]

    /// Detects if `text` is a Web URL, domain name, or localhost.
    /// Excludes filenames with common extensions (e.g. readme.md, main.py).
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

        if trimmed.hasPrefix("www.") {
            return URL(string: "https://" + trimmed)
        }
        
        // Extract host to check TLD
        let host = trimmed.components(separatedBy: "/").first?.components(separatedBy: ":").first ?? ""
        let parts = host.components(separatedBy: ".")
        guard parts.count >= 2, let tld = parts.last?.lowercased() else { return nil }
        
        // If it's a known file extension, it's NOT a web URL (e.g. readme.md, main.py)
        if fileExtensions.contains(tld) { return nil }
        
        // Must be a recognized web TLD
        if webTLDs.contains(tld) {
            return URL(string: "https://" + trimmed)
        }
        
        return nil
    }

    /// Evaluates simple arithmetic expressions safely via JavaScriptCore (never crashes on partial/syntax errors).
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
        
        guard let ctx = jsContext else { return nil }
        ctx.exception = nil
        let jsVal = ctx.evaluateScript(sanitized)
        guard ctx.exception == nil, let num = jsVal?.toNumber()?.doubleValue, num.isFinite else { return nil }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        guard let formatted = formatter.string(from: NSNumber(value: num)) else { return nil }
        
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
        case "empty trash":
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
            return (prompt, "Ask Gemini 3.8 Flash: “\(prompt)”")
        }
        if trimmed.lowercased().hasPrefix("ai:") {
            let prompt = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
            guard !prompt.isEmpty else { return nil }
            return (prompt, "Ask Gemini 3.8 Flash: “\(prompt)”")
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

    /// Synchronous query to Google Antigravity Gemini 3.8 Flash via agy CLI.
    nonisolated static func queryGemini(_ prompt: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/Users/salimonurcetin/.local/bin/agy")
        task.arguments = ["-p", prompt]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (output?.isEmpty == false) ? output : nil
        } catch {
            return nil
        }
    }

    /// Queries Google Antigravity Gemini 3.8 Flash asynchronously and copies answer to clipboard.
    static func openAIQuery(_ prompt: String, onAnswer: @escaping @Sendable @MainActor (String) -> Void) {
        Task { @MainActor in
            let answer = await Task.detached(priority: .userInitiated) {
                queryGemini(prompt)
            }.value
            if let answer {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(answer, forType: .string)
                onAnswer(answer)
            } else {
                let encoded = prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? prompt
                if let url = URL(string: "https://antigravity.utkuk.dev/?q=\(encoded)") {
                    NSWorkspace.shared.open(url)
                }
            }
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
                folder: "Google Antigravity · Gemini 3.8 Flash",
                excerpt: "Ask Gemini 3.8 Flash: “\(prompt)”",
                info: ["action": "ai", "prompt": prompt]
            )
            actions.append(row)
            return actions
        }

        // 3. System Commands (lock, sleep, dark mode, ip, empty trash...)
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
