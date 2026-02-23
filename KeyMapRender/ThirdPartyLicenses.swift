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
        guard
            let licensesDir = Bundle.main.url(
                forResource: "licenses",
                withExtension: nil,
                subdirectory: "python_deps/hidapi-0.15.0.dist-info"
            )
        else {
            return nil
        }

        let files = [
            "LICENSE.txt",
            "LICENSE-bsd.txt",
            "LICENSE-gpl3.txt",
            "LICENSE-orig.txt"
        ]

        var body: [String] = []
        body.append("## hidapi (cython-hidapi 0.15.0)")

        for file in files {
            let fileURL = licensesDir.appendingPathComponent(file)
            guard let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }
            body.append("### \(file)")
            body.append(text)
        }

        return body.isEmpty ? nil : body.joined(separator: "\n\n")
    }
}

