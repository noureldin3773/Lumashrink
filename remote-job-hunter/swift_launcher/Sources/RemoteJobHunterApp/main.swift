import SwiftUI
import Foundation
import AppKit

@MainActor
final class AppModel: ObservableObject {
    enum InputMode: String, CaseIterable, Identifiable {
        case linkOnly = "Link only"
        case linkWithDescription = "Link + pasted job description"
        case jdOnly = "JD Only mode"
        var id: String { rawValue }
    }
    enum DuplicateAction: String, CaseIterable, Identifiable {
        case cancel = "Cancel"
        case openExisting = "Open Existing Folder"
        case regenerate = "Regenerate"
        var id: String { rawValue }
        var backendValue: String {
            switch self {
            case .cancel: return "cancel"
            case .openExisting: return "open_existing"
            case .regenerate: return "regenerate"
            }
        }
    }

    @Published var link = ""
    @Published var company = ""
    @Published var title = ""
    @Published var source = ""
    @Published var location = ""
    @Published var salary = ""
    @Published var description = ""
    @Published var postedDate = "Unknown"
    @Published var jobAgeDays = "Unknown"
    @Published var useAI = true
    @Published var forceRegenerate = false
    @Published var skipExisting = true
    @Published var updateGoogleSheet = true
    @Published var generateCV = true
    @Published var generateCover = true
    @Published var generateApplyPackage = true
    @Published var inputMode: InputMode = .linkOnly
    @Published var duplicateAction: DuplicateAction = .openExisting
    @Published var status = "Ready"
    @Published var logs: [String] = []
    @Published var lastGeneratedFolder: String = ""
    @Published var lastCVPath: String = ""
    @Published var lastCoverPath: String = ""
    @Published var lastApplyPackagePath: String = ""
    @Published var lastCVPDFPath: String = ""
    @Published var aiUsageReason: String = ""
    @Published var cvStatus: String = "-"
    @Published var coverStatus: String = "-"
    @Published var sheetStatus: String = "-"
    @Published var applyPackageStatus: String = "-"

    private let projectDir: String
    private let pythonPath: String

    init() {
        let cwd = FileManager.default.currentDirectoryPath
        let resolvedProjectDir: String
        if FileManager.default.fileExists(atPath: "\(cwd)/src/desktop_actions.py") {
            resolvedProjectDir = cwd
        } else if FileManager.default.fileExists(atPath: "\(cwd)/../src/desktop_actions.py") {
            resolvedProjectDir = URL(fileURLWithPath: cwd).deletingLastPathComponent().path
        } else {
            resolvedProjectDir = cwd
        }
        self.projectDir = resolvedProjectDir
        self.pythonPath = FileManager.default.fileExists(atPath: "\(resolvedProjectDir)/venv/bin/python")
            ? "\(resolvedProjectDir)/venv/bin/python"
            : "/usr/bin/python3"
    }

    func extractFromLink() {
        if inputMode == .jdOnly {
            extractFromJD()
            return
        }

        guard !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setStatus("Please paste a job link first.")
            return
        }
        runBridge(args: ["extract", "--url", link]) { result in
            guard let result else { return }
            if let t = result["title"] { self.title = t }
            if let c = result["company"] { self.company = c }
            if let l = result["location"] { self.location = l }
            if let s = result["salary"] { self.salary = s }
            if let p = result["posted_date"] { self.postedDate = p }
            if let a = result["job_age_days"] { self.jobAgeDays = a }
            if self.inputMode == .linkOnly, let d = result["description"] { self.description = d }
            let needsManual = (result["needs_manual_description"] ?? "").lowercased() == "true"
            self.setStatus(needsManual ? "Partial extraction. Please paste description manually." : "Extraction complete.")
        }
    }

    private func extractFromJD() {
        let jd = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !jd.isEmpty else {
            setStatus("Please paste job description first.")
            return
        }
        runBridge(args: ["extract_jd", "--jd-text", jd]) { result in
            guard let result else { return }
            if let t = result["title"], !t.isEmpty { self.title = t }
            if let c = result["company"], !c.isEmpty { self.company = c }
            if let l = result["location"], !l.isEmpty { self.location = l }
            if let s = result["salary"], !s.isEmpty { self.salary = s }
            if let p = result["posted_date"], !p.isEmpty { self.postedDate = p }
            if let a = result["job_age_days"], !a.isEmpty { self.jobAgeDays = a }
            self.source = "Manual JD"
            if self.company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || self.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.setStatus("Please fill missing Company/Title manually.")
            } else {
                self.setStatus("JD extraction complete.")
            }
        }
    }

    func generateApplication() {
        if inputMode != .jdOnly {
            guard !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                setStatus("Job link is required.")
                return
            }
        }
        let restrictedSource = Self.isRestrictedSource(link)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if inputMode == .linkWithDescription && trimmedDescription.isEmpty {
            setStatus("Please paste the job description in this mode.")
            return
        }
        if restrictedSource && trimmedDescription.isEmpty {
            setStatus("LinkedIn/Indeed/Glassdoor detected. Please paste job description manually.")
            return
        }
        if isOlderThan15Days() && !forceRegenerate {
            setStatus("This job is older than 15 days.")
            return
        }

        let payload: [String: Any] = [
            "company": company.isEmpty ? "Unknown Company" : company,
            "title": title.isEmpty ? "Product Designer" : title,
            "link": link,
            "source": source.isEmpty ? (inputMode == .jdOnly ? "Manual JD" : "Direct Link") : source,
            "location": location,
            "salary": salary,
            "description": trimmedDescription,
            "posted_date": postedDate,
            "job_age_days": jobAgeDays,
            "force_ai": useAI,
            "force_regenerate": forceRegenerate,
            "skip_existing": skipExisting,
            "update_google_sheet": updateGoogleSheet,
            "generate_cv": generateCV,
            "generate_cover": generateCover,
            "generate_apply_package": generateApplyPackage,
            "duplicate_action": duplicateAction.backendValue,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            setStatus("Failed to serialize request.")
            return
        }
        runBridge(args: ["generate", "--job-json", json]) { result in
            self.setStatus("Application generation finished.")
            if let folder = result?["application_folder"], !folder.isEmpty {
                self.lastGeneratedFolder = folder
                self.log("Application folder: \(folder)")
            }
            self.lastCVPath = result?["cv_file_path"] ?? ""
            self.lastCoverPath = result?["cover_file_path"] ?? ""
            self.lastApplyPackagePath = result?["apply_package_path"] ?? ""
            self.lastCVPDFPath = self.lastCVPath.replacingOccurrences(of: ".docx", with: ".pdf")
            self.aiUsageReason = result?["ai_usage_reason"] ?? ""
            self.cvStatus = result?["cv_status"] ?? "-"
            self.coverStatus = result?["cover_status"] ?? "-"
            self.sheetStatus = result?["sheet_status"] ?? "-"
            self.applyPackageStatus = result?["apply_package_status"] ?? "-"
            if (result?["duplicate"] ?? "false").lowercased() == "true" {
                let action = result?["action"] ?? ""
                self.setStatus("Duplicate detected (\(action)).")
                if action == "open_existing", let folder = result?["application_folder"], !folder.isEmpty {
                    NSWorkspace.shared.open(URL(fileURLWithPath: folder, isDirectory: true))
                }
            }
        }
    }

    func extractAndGenerateApplication() {
        if inputMode == .jdOnly {
            let jd = description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !jd.isEmpty else {
                setStatus("Please paste job description first.")
                return
            }
            runBridge(args: ["extract_jd", "--jd-text", jd]) { result in
                if let t = result?["title"], !t.isEmpty { self.title = t }
                if let c = result?["company"], !c.isEmpty { self.company = c }
                if let l = result?["location"], !l.isEmpty { self.location = l }
                if let s = result?["salary"], !s.isEmpty { self.salary = s }
                if let p = result?["posted_date"], !p.isEmpty { self.postedDate = p }
                if let a = result?["job_age_days"], !a.isEmpty { self.jobAgeDays = a }
                self.source = "Manual JD"
                self.generateApplication()
            }
            return
        }

        guard !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setStatus("Please paste a job link first.")
            return
        }
        runBridge(args: ["extract", "--url", link]) { result in
            if let t = result?["title"] { self.title = t }
            if let c = result?["company"] { self.company = c }
            if let l = result?["location"] { self.location = l }
            if let s = result?["salary"] { self.salary = s }
            if let p = result?["posted_date"] { self.postedDate = p }
            if let a = result?["job_age_days"] { self.jobAgeDays = a }
            if self.inputMode == .linkOnly, let d = result?["description"] { self.description = d }
            self.generateApplication()
        }
    }

    func isOlderThan15Days() -> Bool {
        guard let value = Int(jobAgeDays.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return value > 15
    }

    static func isRestrictedSource(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return false }
        return host.contains("linkedin.com") || host.contains("indeed.com") || host.contains("glassdoor.com")
    }

    func runFullSearch() {
        runBridge(args: ["full_search"]) { _ in
            self.setStatus("Full job search completed.")
        }
    }

    func scrapeAllSites() {
        runBridge(args: ["scrape_all"]) { _ in
            self.setStatus("Scrape all sites completed.")
        }
    }

    func openSheet() {
        runBridge(args: ["sheet_url"]) { result in
            guard let urlText = result?["url"], let url = URL(string: urlText), !urlText.isEmpty else {
                self.setStatus("GOOGLE_SHEET_ID is missing in .env")
                return
            }
            NSWorkspace.shared.open(url)
            self.setStatus("Opened Google Sheet.")
        }
    }

    func openApplicationsFolder() {
        let folder = URL(fileURLWithPath: "\(projectDir)/outputs/applications", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
        setStatus("Opened applications folder.")
    }

    func openLastGeneratedFolder() {
        let trimmed = lastGeneratedFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setStatus("No generated folder available yet.")
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: trimmed, isDirectory: true))
        setStatus("Opened generated folder.")
    }

    func openCV() {
        guard !lastCVPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: lastCVPath))
    }

    func openCVPDF() {
        guard !lastCVPDFPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: lastCVPDFPath))
    }

    func openCoverLetter() {
        guard !lastCoverPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: lastCoverPath))
    }

    func openApplyPackage() {
        guard !lastApplyPackagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: lastApplyPackagePath))
    }

    func copyApplyPackage() {
        let path = lastApplyPackagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            setStatus("Could not read apply package.")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        setStatus("Apply package copied.")
    }

    func markCVApproved() {
        markStatusAction(action: "mark_cv_approved")
    }

    func markCoverApproved() {
        markStatusAction(action: "mark_cover_approved")
    }

    func markApplied() {
        markStatusAction(action: "mark_applied")
    }

    private func markStatusAction(action: String) {
        let payload: [String: Any] = [
            "company": company,
            "title": title,
            "link": link,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            setStatus("Failed to build status update payload.")
            return
        }
        runBridge(args: [action, "--job-json", json]) { result in
            let ok = (result?["ok"] ?? "false").lowercased() == "true"
            self.setStatus(ok ? "Google Sheet status updated." : "Could not update sheet status.")
        }
    }

    private func runBridge(args: [String], onSuccess: @escaping ([String: String]?) -> Void) {
        setStatus("Working...")
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.currentDirectoryURL = URL(fileURLWithPath: self.projectDir)
            process.environment = {
                var env = ProcessInfo.processInfo.environment
                let existing = env["PYTHONPATH"] ?? ""
                env["PYTHONPATH"] = existing.isEmpty ? self.projectDir : "\(self.projectDir):\(existing)"
                env["PYTHONWARNINGS"] = "ignore"
                return env
            }()
            process.executableURL = URL(fileURLWithPath: self.pythonPath)
            process.arguments = ["-m", "src.desktop_actions"] + args
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            do {
                try process.run()
                process.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    self.handleBridgeOutput(text, onSuccess: onSuccess)
                }
            } catch {
                DispatchQueue.main.async {
                    self.setStatus("Failed to run backend: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handleBridgeOutput(_ text: String, onSuccess: @escaping ([String: String]?) -> Void) {
        let lines = text.split(separator: "\n").map(String.init)
        guard let jsonLine = lines.reversed().first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("{") && $0.trimmingCharacters(in: .whitespaces).hasSuffix("}") }),
              let data = jsonLine.data(using: .utf8) else {
            self.setStatus("Unexpected backend output.")
            lines.filter(Self.isUsefulLogLine).forEach { self.log($0) }
            return
        }

        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.setStatus("Failed to parse backend response.")
                lines.filter(Self.isUsefulLogLine).forEach { self.log($0) }
                return
            }
            let ok = (obj["ok"] as? Bool) ?? false
            if ok {
                let rawResult = obj["result"] as? [String: Any]
                let stringResult = rawResult?.reduce(into: [String: String](), { acc, item in
                    acc[item.key] = String(describing: item.value)
                })
                onSuccess(stringResult)
            } else {
                let errorType = String(describing: obj["error_type"] ?? "Error")
                let errorMessage = String(describing: obj["error_message"] ?? "Unknown error")
                self.setStatus("\(errorType): \(errorMessage)")
            }
            lines.filter(Self.isUsefulLogLine).forEach { self.log($0) }
        } catch {
            self.setStatus("Failed to parse backend response.")
            lines.filter(Self.isUsefulLogLine).forEach { self.log($0) }
        }
    }

    private func setStatus(_ message: String) {
        status = message
        log(message)
    }

    private func log(_ message: String) {
        logs.append(message)
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
    }

    private static func isUsefulLogLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") { return false }

        let lowered = trimmed.lowercased()
        let states = [
            "fetching job",
            "extracting from pasted jd",
            "scoring job",
            "calculating fit score",
            "generating cv",
            "generating cover letter",
            "generating apply package",
            "updating google sheets",
            "done",
            "error:"
        ]
        if states.contains(where: { lowered.contains($0) }) { return true }
        if lowered.contains("application folder:") { return true }
        if lowered.contains("older than 15 days") { return true }
        return false
    }
}

struct GlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.black.opacity(0.18), lineWidth: 1))
    }
}

struct ContentView: View {
    @ObservedObject var vm: AppModel

    private let helperColor = Color(red: 0.8, green: 0.8, blue: 0.8)

    private func fieldStyle(_ field: some View) -> some View {
        field
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.98), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.12), lineWidth: 1))
            .foregroundStyle(Color.black)
    }

    private func labeledField(_ label: String, field: some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.black.opacity(0.72))
            fieldStyle(field)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.97, green: 0.98, blue: 1.0), Color(red: 0.90, green: 0.93, blue: 0.99)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()

            ScrollView {
            VStack(spacing: 14) {
                Text("Remote Job Hunter")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.black)

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Mode", selection: $vm.inputMode) {
                            ForEach(AppModel.InputMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack(spacing: 10) {
                        labeledField(
                            "Job Link",
                            field: TextField(
                                "",
                                text: $vm.link,
                                prompt: Text(vm.inputMode == .jdOnly ? "Optional: paste job link (manual JD works without it)" : "Paste job link (e.g., company careers page URL)")
                                    .foregroundColor(helperColor)
                            )
                        )
                        Button {
                            vm.extractFromLink()
                        } label: {
                            Label("Extract", systemImage: "sparkle.magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                }

                GlassCard {
                    HStack(spacing: 10) {
                        Button {
                            vm.generateApplication()
                        } label: {
                            Label("Generate Application", systemImage: "doc.badge.gearshape")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("g", modifiers: [.command])

                        Button {
                            vm.extractAndGenerateApplication()
                        } label: {
                            Label("Extract & Generate Application", systemImage: "sparkles.rectangle.stack")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("e", modifiers: [.command])

                        Button {
                            vm.runFullSearch()
                        } label: {
                            Label("Run Full Job Search", systemImage: "magnifyingglass.circle")
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("r", modifiers: [.command])

                        Button {
                            vm.scrapeAllSites()
                        } label: {
                            Label("Scrape All Sites", systemImage: "globe")
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("f", modifiers: [.command])

                        Toggle("Use AI", isOn: $vm.useAI)
                            .foregroundStyle(Color.black)
                        Toggle("Force Regenerate", isOn: $vm.forceRegenerate)
                            .foregroundStyle(Color.black)
                        Toggle("Skip Existing", isOn: $vm.skipExisting)
                            .foregroundStyle(Color.black)
                        Spacer()
                        Button {
                            vm.openSheet()
                        } label: {
                            Label("Open Sheet", systemImage: "tablecells")
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                        Button {
                            vm.openApplicationsFolder()
                        } label: {
                            Label("Open Folder", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("o", modifiers: [.command, .shift])

                        if !vm.lastGeneratedFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                vm.openLastGeneratedFolder()
                            } label: {
                                Label("Open Generated Folder", systemImage: "folder.badge.checkmark")
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.return, modifiers: [.command])
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Job Preview & Generation Options")
                            .font(.headline)
                            .foregroundStyle(Color.black)
                        HStack {
                            Text("Posted Date: \(vm.postedDate)")
                            Text("Job Age (days): \(vm.jobAgeDays)")
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.black)
                        if vm.isOlderThan15Days() && !vm.forceRegenerate {
                            Text("This job is older than 15 days.")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        HStack {
                            Picker("Duplicate", selection: $vm.duplicateAction) {
                                ForEach(AppModel.DuplicateAction.allCases) { item in
                                    Text(item.rawValue).tag(item)
                                }
                            }
                            .frame(width: 260)
                            Toggle("Generate CV", isOn: $vm.generateCV)
                            Toggle("Generate Cover Letter", isOn: $vm.generateCover)
                            Toggle("Generate Apply Package", isOn: $vm.generateApplyPackage)
                            Toggle("Update Google Sheet", isOn: $vm.updateGoogleSheet)
                        }
                        if !vm.aiUsageReason.isEmpty {
                            Text("AI usage reason: \(vm.aiUsageReason)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("CV: \(vm.cvStatus)")
                            Text("Cover: \(vm.coverStatus)")
                            Text("Apply Package: \(vm.applyPackageStatus)")
                            Text("Sheet: \(vm.sheetStatus)")
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.black)
                    }
                }

                GlassCard {
                    HStack(spacing: 14) {
                        VStack(spacing: 10) {
                            labeledField("Company", field: TextField("", text: $vm.company, prompt: Text("Company name (e.g., Stripe, Veeva)").foregroundColor(helperColor)))
                            labeledField("Job Title", field: TextField("", text: $vm.title, prompt: Text("Job title (e.g., Senior Product Designer)").foregroundColor(helperColor)))
                            labeledField("Source", field: TextField("", text: $vm.source, prompt: Text("Source (e.g., LinkedIn, RemoteOK, Manual JD)").foregroundColor(helperColor)))
                            labeledField("Location", field: TextField("", text: $vm.location, prompt: Text("Location (e.g., Remote Worldwide, Cairo)").foregroundColor(helperColor)))
                            labeledField("Salary", field: TextField("", text: $vm.salary, prompt: Text("Salary (optional, e.g., $4,000/month)").foregroundColor(helperColor)))
                        }
                        .frame(width: 320)

                        VStack(alignment: .leading, spacing: 8) {
                            Label("Job Description", systemImage: "doc.text").font(.headline).foregroundStyle(Color.black)
                            if AppModel.isRestrictedSource(vm.link) {
                                Text("LinkedIn/Indeed/Glassdoor: paste full job description manually.")
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                            }
                            TextEditor(text: $vm.description)
                                .frame(height: 320)
                                .scrollContentBackground(.hidden)
                                .foregroundStyle(Color.black)
                                .background(Color.white.opacity(0.92))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .topLeading) {
                                    if vm.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text("Paste full job description here (required for JD-only mode).")
                                            .foregroundColor(helperColor)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 12)
                                            .allowsHitTesting(false)
                                    }
                                }
                            HStack {
                                Spacer()
                                Button {
                                    vm.extractAndGenerateApplication()
                                } label: {
                                    Label("Extract & Generate", systemImage: "sparkles.rectangle.stack")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(vm.status, systemImage: "waveform.path.ecg").font(.headline).foregroundStyle(Color(red: 0.02, green: 0.44, blue: 0.23))
                            Spacer()
                            Button("Copy Log") { vm.copyLogToClipboard() }
                                .buttonStyle(.bordered)
                        }
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(vm.logs.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(Color.black)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(minHeight: 220, maxHeight: 300)
                        HStack {
                            Button("Open CV") { vm.openCV() }.buttonStyle(.bordered)
                            Button("Open CV PDF") { vm.openCVPDF() }.buttonStyle(.bordered)
                            Button("Open Cover Letter") { vm.openCoverLetter() }.buttonStyle(.bordered)
                            Button("Open Apply Package") { vm.openApplyPackage() }.buttonStyle(.bordered)
                            Button("Copy Apply Package") { vm.copyApplyPackage() }.buttonStyle(.bordered)
                            Button("Open Application Folder") { vm.openLastGeneratedFolder() }.buttonStyle(.bordered)
                            Button("Open Google Sheet") { vm.openSheet() }.buttonStyle(.bordered)
                            Spacer()
                            Button("Mark CV Approved") { vm.markCVApproved() }.buttonStyle(.borderedProminent)
                            Button("Mark Cover Approved") { vm.markCoverApproved() }.buttonStyle(.borderedProminent)
                            Button("Mark Applied") { vm.markApplied() }.buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding(20)
            }
        }
    }
}

@main
struct RemoteJobHunterApp: App {
    @StateObject private var vm = AppModel()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        if let icon = NSImage(systemSymbolName: "briefcase.fill", accessibilityDescription: "Remote Job Hunter") {
            icon.isTemplate = false
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(vm: vm)
                .frame(minWidth: 980, minHeight: 720)
        }
        .commands {
            CommandMenu("Mode") {
                Button("Link only") {
                    vm.inputMode = .linkOnly
                }
                .keyboardShortcut("l", modifiers: [.command])

                Button("Link + pasted job description") {
                    vm.inputMode = .linkWithDescription
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("JD Only mode") {
                    vm.inputMode = .jdOnly
                }
                .keyboardShortcut("j", modifiers: [.command])
            }
        }
    }
}

extension AppModel {
    @MainActor
    func copyLogToClipboard() {
        let text = logs.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status = "Log copied to clipboard."
        log("Log copied to clipboard.")
    }
}
