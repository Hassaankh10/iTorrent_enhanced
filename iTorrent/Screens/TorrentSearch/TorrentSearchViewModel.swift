//
//  TorrentSearchViewModel.swift
//  iTorrent
//

import Combine
import Foundation
import LibTorrent
import MvvmFoundation

class TorrentSearchViewModel: BaseViewModel, ObservableObject {
    @Published var searchQuery: String = ""
    @Published var results: [TorrentResult] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var hasSearched: Bool = false

    required init() {
        super.init()
        binding()
    }

    private var searchTask: Task<Void, Never>?
}

private extension TorrentSearchViewModel {
    func binding() {
        disposeBag.bind {
            $searchQuery
                .throttle(for: 0.5, scheduler: DispatchQueue.global(qos: .userInitiated), latest: true)
                .sink { [unowned self] query in
                    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        DispatchQueue.main.async { [self] in
                            results = []
                            errorMessage = nil
                            isLoading = false
                        }
                        return
                    }
                    performSearch(query: trimmed)
                }
        }
    }

    func performSearch(query: String) {
        searchTask?.cancel()

        DispatchQueue.main.async { [self] in
            isLoading = true
            errorMessage = nil
        }

        searchTask = Task {
            do {
                let found = try await TorrentSearchService.shared.search(query: query)
                guard !Task.isCancelled else { return }
                await MainActor.run { [self] in
                    results = found
                    isLoading = false
                    hasSearched = true
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [self] in
                    errorMessage = error.localizedDescription
                    isLoading = false
                    hasSearched = true
                }
            }
        }
    }
}

extension TorrentSearchViewModel {
    func triggerMagnetDownload(for result: TorrentResult) {
        guard let url = URL(string: result.magnetLink),
              let magnet = MagnetURI(with: url)
        else {
            alert(title: %"common.error", message: "Invalid magnet link", actions: [
                .init(title: %"common.close", style: .cancel, isPrimary: true)
            ])
            return
        }

        TorrentService.shared.addTorrent(by: magnet)

        alert(title: "Added", message: result.title, actions: [
            .init(title: %"common.close", style: .cancel, isPrimary: true)
        ])
    }
}
