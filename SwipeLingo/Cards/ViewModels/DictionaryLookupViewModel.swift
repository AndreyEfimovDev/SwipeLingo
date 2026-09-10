//
//  DictionaryLookupViewModel.swift
//  SwipeLingo
//
//  Created by Andrey Efimov on 10.09.2026.
//

import SwiftUI
import SwiftData
import Translation

// MARK: - DictionaryLookupViewModel

@Observable
final class DictionaryLookupViewModel {

    // MARK: Phase

    enum Phase {
        case loading
        case loaded(DictionaryEntry)
        case error(String)
    }

    // MARK: State

    private(set) var phase: Phase = .loading

    /// Shows a cached entry immediately (called from the View's .task before the network fetch).
    func showCached(_ entry: DictionaryEntry) {
        phase = .loaded(entry)
    }
    let audioService = AudioPlayerService()

    /// Flips true the moment a successful entry is loaded — used for caching trigger.
    private(set) var didLoad = false

    // MARK: Service

    private let service = DictionaryService()


    // MARK: Actions

    func load(word: String) async {
        phase = .loading
        do {
            let entry = try await service.lookup(word: word)
            phase = .loaded(entry)
            didLoad = true
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func toggleAudio(urlString: String) {
        if audioService.isPlaying {
            audioService.stop()
        } else {
            audioService.play(urlString: urlString)
        }
    }

    // MARK: - Card mutation
    //
    // Context and card are passed explicitly — same pattern as SRSService / PileBuilderViewModel.
    // Using do-catch instead of try? so errors are visible in the console.

    /// Keys of examples already added in this session — drives the ✓ indicator in the UI.
    var addedItems: Set<String> = []

    func addDefinition(
        _ definition: DictionaryDefinition,
        to card: Card,
        context: ModelContext,
        translatedExample: String? = nil
    ) {
        var samplesEN   = card.userSampleEN
        var samplesItem = card.userSampleItem
        var changed = false

        let allEN = card.allSampleEN

        if let example = definition.example, !allEN.contains(example) {
            samplesEN.append(example)
            samplesItem.append(translatedExample ?? "")
            changed = true
            log("[+] example: \"\(example.prefix(60))\"")
            if let t = translatedExample { log("    translation: \"\(t.prefix(60))\"") }
        }

        guard changed else {
            log("[+] already present — skipped")
            return
        }

        card.userSampleEN   = samplesEN
        card.userSampleItem = samplesItem
        save(context: context)
        if let example = definition.example { addedItems.insert(example) }
    }

    func addSynonym(_ synonym: String, to card: Card, context: ModelContext) {
        var syns = card.synonyms
        guard !syns.contains(synonym) else {
            log("[+] '\(synonym)' already present — skipped")
            return
        }
        syns.append(synonym)
        card.synonyms = syns
        save(context: context)
        log("[+] synonym: '\(synonym)'")
    }

    private func save(context: ModelContext) {
        context.saveWithErrorHandling()
    }
}


