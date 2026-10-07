//
//  TodoListView.swift
//  boringNotch
//
//  Tools: to-do tab. Type a task, press Return, tick them off.
//

import Defaults
import SwiftUI

struct TodoListView: View {
    @ObservedObject var manager = TodoManager.shared
    @State private var newText = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("To-dos")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if manager.remainingCount > 0 {
                    Text("\(manager.remainingCount) left")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                }
            }

            HStack(spacing: 6) {
                TextField("Add a task, press Return", text: $newText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(6)
                    .background {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.08))
                    }
                    .foregroundStyle(.white)
                    .onSubmit {
                        manager.add(newText)
                        newText = ""
                    }

                Button {
                    manager.add(newText)
                    newText = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if manager.items.isEmpty {
                Text("Nothing here yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(manager.items) { item in
                            row(item)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ item: TodoItem) -> some View {
        Button {
            manager.toggle(item)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(item.isDone ? Color.green : Color.gray)

                Text(item.text)
                    .font(.system(size: 11))
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? .gray : .white)
                    .lineLimit(2)

                Spacer()
            }
            .padding(7)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.06))
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove") {
                manager.remove(item)
            }
        }
    }
}
