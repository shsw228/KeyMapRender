import Foundation

enum ThirdPartyLicenses {
    static func load() -> String {
        var sections: [String] = []
        sections.append("# Third-Party Licenses")
        sections.append("このアプリは以下の外部ライブラリを利用します。")

        if let hidapi = loadHidapiLicenses() {
            sections.append(hidapi)
        } else {
            sections.append("hidapi: ライセンス情報を読み込めませんでした。")
        }

        return sections.joined(separator: "\n\n")
    }

    private static func loadHidapiLicenses() -> String? {
        let files = [
            "LICENSE.txt",
            "LICENSE-bsd.txt",
            "LICENSE-gpl3.txt",
            "LICENSE-orig.txt"
        ]

        var body: [String] = []
        body.append("## hidapi (cython-hidapi 0.15.0)")

        // In app bundles, python wheel resources are flattened into Contents/Resources.
        for file in files {
            guard let fileURL = resolveLicenseFileURL(named: file),
                  let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data, encoding: .utf8)
            else {
                continue
            }
            body.append("### \(file)")
            body.append(text)
        }

        return body.count > 1 ? body.joined(separator: "\n\n") : nil
    }

    private static func resolveLicenseFileURL(named file: String) -> URL? {
        let name = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: file).pathExtension

        if let direct = Bundle.main.url(forResource: name, withExtension: ext) {
            return direct
        }
        if let nested = Bundle.main.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "python_deps/hidapi-0.15.0.dist-info/licenses"
        ) {
            return nested
        }
        if let legacy = Bundle.main.url(
            forResource: file,
            withExtension: nil,
            subdirectory: "python_deps/hidapi-0.15.0.dist-info/licenses"
        ) {
            return legacy
        }
        return nil
    }
}
