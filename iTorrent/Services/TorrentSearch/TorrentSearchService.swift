//
//  TorrentSearchService.swift
//  iTorrent
//
//  Created by iTorrent Enhanced
//

import Foundation

// MARK: - TorrentSearchService

final class TorrentSearchService {

    // MARK: - Errors

    enum SearchError: Error, LocalizedError {
        case allSourcesFailed
        case noResults
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .allSourcesFailed: return "All torrent search sources failed."
            case .noResults:       return "No results found for the given query."
            case .invalidURL:      return "Could not construct a valid search URL."
            }
        }
    }

    // MARK: - Singleton

    static let shared = TorrentSearchService()
    private init() {}

    // MARK: - Constants

    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"

    // MARK: - Public API

    /// Search both 1337x.to and The Pirate Bay concurrently, merging and deduplicating results.
    /// - Parameter query: The search term.
    /// - Returns: Combined `[TorrentResult]` sorted by seeders descending.
    func search(query: String, category: SearchCategory = .all) async throws -> [TorrentResult] {
        async let leet   = search1337x(query: query, category: category)
        async let pirate = searchPirateBay(query: query, category: category)

        var leetResults:   [TorrentResult] = []
        var pirateResults: [TorrentResult] = []
        var leetError:     Error?
        var pirateError:   Error?

        do    { leetResults   = try await leet   } catch { leetError   = error }
        do    { pirateResults = try await pirate  } catch { pirateError = error }

        if leetError != nil && pirateError != nil {
            throw SearchError.allSourcesFailed
        }

        let combined = deduplicated(leetResults + pirateResults)
        return combined.sorted { $0.seeders > $1.seeders }
    }

    // MARK: - 1337x.to

    private func search1337x(query: String, category: SearchCategory) async throws -> [TorrentResult] {
        let encoded = query
            .replacingOccurrences(of: " ", with: "+")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query

        let urlString: String
        if let catPath = category.leetPath {
            urlString = "https://www.1337x.to/category-search/\(encoded)/\(catPath)/1/"
        } else {
            urlString = "https://www.1337x.to/search/\(encoded)/1/"
        }

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        let html = try await fetchString(url: url)
        let rows = parse1337xRows(html: html)

        // Fetch detail pages (max 10) concurrently with limited concurrency
        let topRows = Array(rows.prefix(10))
        let results = try await fetchDetailPages(rows: topRows)
        return results
    }

    // MARK: - Row model (intermediate parse result)

    private struct LeetRow {
        let title: String
        let detailPath: String   // e.g. "/torrent/1234567/name/"
        let seeders: Int
        let leechers: Int
        let size: String
    }

    /// Parse the 1337x search-results HTML into lightweight row models.
    private func parse1337xRows(html: String) -> [LeetRow] {
        var rows: [LeetRow] = []

        // Each result row starts with <tr> and ends with </tr>.
        // We split on <tr> and process each chunk that looks like a result row.
        let chunks = html.components(separatedBy: "<tr")
        for chunk in chunks.dropFirst() {  // first chunk is content before the first <tr>
            guard chunk.contains("coll-1 name") else { continue }

            // --- Title + detail path ---
            // The title link is the SECOND <a> inside the .coll-1 cell.
            // Pattern: href="/torrent/NNNN/slug/">Title</a>
            guard let titleAndPath = extractTitleAndPath(from: chunk) else { continue }

            // --- Seeders ---
            let seeders  = extractCellInt(from: chunk, cssClass: "coll-2")

            // --- Leechers ---
            let leechers = extractCellInt(from: chunk, cssClass: "coll-3")

            // --- Size ---
            // The size cell contains the human-readable size followed by a <span> unit.
            // e.g. "1.2 GB<span class=\"seeds\">...</span>"
            let size = extractSize(from: chunk)

            rows.append(LeetRow(
                title: titleAndPath.title,
                detailPath: titleAndPath.path,
                seeders: seeders,
                leechers: leechers,
                size: size
            ))
        }
        return rows
    }

    /// Extracts the title text and href path from the second anchor inside the name cell.
    private func extractTitleAndPath(from chunk: String) -> (title: String, path: String)? {
        // Find the td containing class "coll-1 name"
        guard let cellStart = chunk.range(of: "coll-1 name") else { return nil }
        let cellChunk = String(chunk[cellStart.lowerBound...])

        // Collect all href="/torrent/..." links in this cell
        var searchRange = cellChunk.startIndex..<cellChunk.endIndex
        var hrefs: [(path: String, label: String)] = []

        while let hrefRange = cellChunk.range(of: "href=\"/torrent/", range: searchRange) {
            // Move past href="
            let pathStart = cellChunk.index(hrefRange.upperBound, offsetBy: 0)
            guard let pathEnd = cellChunk.range(of: "\"", range: pathStart..<cellChunk.endIndex) else { break }
            let path = "/torrent/" + String(cellChunk[pathStart..<pathEnd.lowerBound])

            // Now get the anchor label (text between > and </a>)
            guard let gtRange  = cellChunk.range(of: ">",   range: pathEnd.upperBound..<cellChunk.endIndex),
                  let endRange = cellChunk.range(of: "</a>", range: gtRange.upperBound..<cellChunk.endIndex)
            else { break }

            let rawLabel = String(cellChunk[gtRange.upperBound..<endRange.lowerBound])
            let label = stripTags(rawLabel).trimmingCharacters(in: .whitespacesAndNewlines)

            hrefs.append((path: path, label: label))
            searchRange = endRange.upperBound..<cellChunk.endIndex
        }

        // The second anchor is the title link; fall back to the first if only one exists
        if hrefs.count >= 2 {
            return (title: hrefs[1].label, path: hrefs[1].path)
        } else if let first = hrefs.first {
            return (title: first.label, path: first.path)
        }
        return nil
    }

    /// Extracts an integer from the first occurrence of a <td class="<cssClass>...">N</td> pattern.
    private func extractCellInt(from chunk: String, cssClass: String) -> Int {
        guard let classRange = chunk.range(of: cssClass) else { return 0 }
        let after = String(chunk[classRange.upperBound...])
        guard let gt   = after.range(of: ">"),
              let lt   = after.range(of: "<", range: gt.upperBound..<after.endIndex)
        else { return 0 }
        return Int(after[gt.upperBound..<lt.lowerBound].trimmingCharacters(in: .whitespaces)) ?? 0
    }

    /// Extracts the human-readable size from the "coll-4 size" cell,
    /// stripping the trailing <span> unit tag.
    private func extractSize(from chunk: String) -> String {
        guard let classRange = chunk.range(of: "coll-4 size") else { return "" }
        let after = String(chunk[classRange.upperBound...])
        guard let gt = after.range(of: ">") else { return "" }
        let content = String(after[gt.upperBound...])
        // Content looks like: "1.2 GB<span ...>"
        let raw: String
        if let spanRange = content.range(of: "<span") {
            raw = String(content[content.startIndex..<spanRange.lowerBound])
        } else if let ltRange = content.range(of: "<") {
            raw = String(content[content.startIndex..<ltRange.lowerBound])
        } else {
            raw = content
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Detail page fetching (concurrent, max 5 at a time)

    private func fetchDetailPages(rows: [LeetRow]) async throws -> [TorrentResult] {
        var results: [TorrentResult] = []

        try await withThrowingTaskGroup(of: TorrentResult?.self) { group in
            var active = 0
            var index  = 0

            // Seed up to 5 initial tasks
            while index < rows.count && active < 5 {
                let row = rows[index]
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    return try await self.fetchMagnetAndBuild(row: row)
                }
                active += 1
                index  += 1
            }

            // Collect results and keep refilling the pool
            for try await result in group {
                if let result { results.append(result) }
                active -= 1

                if index < rows.count {
                    let row = rows[index]
                    group.addTask { [weak self] in
                        guard let self else { return nil }
                        return try await self.fetchMagnetAndBuild(row: row)
                    }
                    active += 1
                    index  += 1
                }
            }
        }

        return results
    }

    /// Fetches a 1337x detail page and extracts the magnet link.
    private func fetchMagnetAndBuild(row: LeetRow) async throws -> TorrentResult? {
        guard let url = URL(string: "https://www.1337x.to\(row.detailPath)") else { return nil }

        let html: String
        do {
            html = try await fetchString(url: url)
        } catch {
            // If the detail page fails, skip this result rather than killing the whole batch
            return nil
        }

        guard let magnet = extractMagnet(from: html) else { return nil }

        return TorrentResult(
            title: row.title,
            size: row.size,
            seeders: row.seeders,
            leechers: row.leechers,
            magnetLink: magnet
        )
    }

    /// Finds the first `magnet:?xt=urn:btih:...` link in an HTML page.
    private func extractMagnet(from html: String) -> String? {
        guard let magnetStart = html.range(of: "magnet:?xt=urn:btih:") else { return nil }
        let tail = String(html[magnetStart.lowerBound...])
        // Magnet links end at a quote or whitespace
        let terminators = CharacterSet(charactersIn: "\"' \t\n\r>")
        if let end = tail.unicodeScalars.firstIndex(where: { terminators.contains($0) }) {
            let stringIndex = String.Index(end, within: tail)!
            return String(tail[tail.startIndex..<stringIndex])
        }
        return tail
    }

    // MARK: - The Pirate Bay

    private func searchPirateBay(query: String, category: SearchCategory) async throws -> [TorrentResult] {
        let encoded = query
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

        var urlString = "https://apibay.org/q.php?q=\(encoded)"
        if let cat = category.pirateBayCat {
            urlString += "&cat=\(cat)"
        }

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        let data = try await fetchData(url: url)
        return try parsePirateBayJSON(data: data)
    }

    private func parsePirateBayJSON(data: Data) throws -> [TorrentResult] {
        // Manual JSON parsing to avoid any third-party dependency
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        // A result array containing a single object with id "0" means "no results"
        if json.count == 1, let first = json.first, (first["id"] as? String) == "0" {
            return []
        }

        let trackers = [
            "udp%3A%2F%2Ftracker.opentrackr.org%3A1337",
            "udp%3A%2F%2Fopen.tracker.cl%3A1337",
            "udp%3A%2F%2Ftracker.openbittorrent.com%3A6969"
        ].joined(separator: "&tr=")

        return json.compactMap { item -> TorrentResult? in
            guard
                let name     = item["name"]      as? String,
                let infoHash = item["info_hash"]  as? String,
                !infoHash.isEmpty
            else { return nil }

            let seeders  = Int(item["seeders"]  as? String ?? "") ?? 0
            let leechers = Int(item["leechers"] as? String ?? "") ?? 0
            let rawSize  = Int64(item["size"] as? String ?? "") ?? 0
            let size     = formatBytes(rawSize)

            let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
            let magnet = "magnet:?xt=urn:btih:\(infoHash)&dn=\(encodedName)&tr=\(trackers)"

            return TorrentResult(
                title: name,
                size: size,
                seeders: seeders,
                leechers: leechers,
                magnetLink: magnet
            )
        }
    }

    // MARK: - Deduplication

    /// Removes results with near-identical titles (case-insensitive prefix match of 80% characters).
    private func deduplicated(_ results: [TorrentResult]) -> [TorrentResult] {
        var seen: [String] = []
        return results.filter { result in
            let key = result.title.lowercased()
            // Check whether any already-seen title is very similar
            let isDuplicate = seen.contains { existing in
                similarity(key, existing) > 0.85
            }
            if !isDuplicate {
                seen.append(key)
                return true
            }
            return false
        }
    }

    /// Jaccard similarity on bigrams of two strings.
    private func similarity(_ a: String, _ b: String) -> Double {
        let bigramsA = bigrams(a)
        let bigramsB = bigrams(b)
        guard !bigramsA.isEmpty || !bigramsB.isEmpty else { return 1.0 }
        let intersection = bigramsA.intersection(bigramsB).count
        let union        = bigramsA.union(bigramsB).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private func bigrams(_ s: String) -> Set<String> {
        let chars = Array(s)
        guard chars.count >= 2 else { return [] }
        return Set((0..<chars.count - 1).map { String([chars[$0], chars[$0 + 1]]) })
    }

    // MARK: - Networking helpers

    private func fetchString(url: URL) async throws -> String {
        let data = try await fetchData(url: url)
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    private func fetchData(url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                         forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    // MARK: - Utility helpers

    /// Strips all HTML tags from a string.
    private func stripTags(_ input: String) -> String {
        var result = ""
        var insideTag = false
        for char in input {
            if char == "<" { insideTag = true; continue }
            if char == ">" { insideTag = false; continue }
            if !insideTag { result.append(char) }
        }
        return result
    }

    /// Converts a byte count to a human-readable string.
    private func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "Unknown" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        let formatted = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(formatted) \(units[unitIndex])"
    }
}
