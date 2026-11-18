//
//  FilmPickerView.swift
//  Reciprocity Failure Calculator
//

import SwiftUI

struct FilmPickerView: View {
    @Environment(FilmStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedFilmID: String
    @State private var query = ""
    @State private var showingAdd = false
    @State private var saveError: String?

    var body: some View {
        List {
            ForEach(store.grouped(matching: query), id: \.brand) { group in
                Section(group.brand) {
                    ForEach(group.films) { film in
                        Button {
                            selectedFilmID = film.id
                            dismiss()
                        } label: {
                            HStack {
                                FilmRow(film: film)
                                Spacer()
                                if film.id == selectedFilmID {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if film.isCustom {
                                Button("Delete", role: .destructive) { delete(film) }
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if !query.isEmpty, store.grouped(matching: query).isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: "Film or ISO")
        .navigationTitle("Films")
        .toolbar {
            Button("Add film", systemImage: "plus") { showingAdd = true }
        }
        .sheet(isPresented: $showingAdd) {
            AddFilmView { film in
                selectedFilmID = film.id
            }
        }
        .alert("Couldn't save", isPresented: .constant(saveError != nil)) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func delete(_ film: Film) {
        do {
            try store.deleteCustom(id: film.id)
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        FilmPickerView(selectedFilmID: .constant("Ilford|HP5+"))
    }
    .environment(FilmStore())
}
