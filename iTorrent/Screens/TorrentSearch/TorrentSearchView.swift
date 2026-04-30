//
//  TorrentSearchView.swift
//  iTorrent
//

import MvvmFoundation
import SwiftUI

struct TorrentSearchView<VM: TorrentSearchViewModel>: MvvmSwiftUIViewProtocol {
    @ObservedObject var viewModel: VM

    var title: String = "Search"

    init(viewModel: VM) {
        self.viewModel = viewModel
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                errorView(message: error)
            } else if !viewModel.hasSearched {
                placeholderView
            } else if viewModel.results.isEmpty {
                emptyView
            } else {
                resultsList
            }
        }
        .searchable(text: $viewModel.searchQuery, prompt: "Search torrents…")
        .navigationTitle("Search")
    }

    // MARK: - Subviews

    private var resultsList: some View {
        List(viewModel.results, id: \.magnetLink) { result in
            Button {
                viewModel.triggerMagnetDownload(for: result)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 12) {
                        Text(result.size)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Label("\(result.seeders)", systemImage: "arrow.up")
                            .font(.caption)
                            .foregroundStyle(.green)

                        Label("\(result.leechers)", systemImage: "arrow.down")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.plain)
    }

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Search Torrents")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Enter a query above to find torrents")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Results")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Try a different search term")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Search Failed")
                .font(.title2)
                .fontWeight(.semibold)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
