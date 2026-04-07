// GestureListView.swift
// MagicMotion
//
// Sheet that presents the gesture → game-command mapping for the selected game.
// Each row shows: motion icon | physical description | → | in-game action name.
//
// Presented via .sheet(isPresented:) from ControllerModeView.
// Read-only — no mutations.

import SwiftUI

struct GestureListView: View {

    let profile: GameProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(gestureMappings) { entry in
                        gestureRow(entry)
                    }
                } header: {
                    Label("Controls for \(profile.displayName)", systemImage: "gamecontroller")
                } footer: {
                    Text("These body movements are detected by the iPad camera and sent to the game via your wrist band.")
                        .font(.caption)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Gesture Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Row

    private func gestureRow(_ entry: GestureEntry) -> some View {
        HStack(spacing: 14) {
            Image(systemName: entry.intent.symbolName)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 30, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.intent.motionDescription)
                    .font(.body)
                Text(entry.intent.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(entry.command.gameActionName)
                    .font(.subheadline.bold())
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Data model

    private struct GestureEntry: Identifiable {
        let id = UUID()
        let intent: AppIntent
        let command: GameCommand
    }

    private var gestureMappings: [GestureEntry] {
        profile.mapping
            .compactMap { key, command -> GestureEntry? in
                guard let motionKey = MotionEventKey(rawValue: key),
                      let intent = AppIntent.from(motionKey)
                else { return nil }
                return GestureEntry(intent: intent, command: command)
            }
            .sorted { $0.intent.sortOrder < $1.intent.sortOrder }
    }
}
