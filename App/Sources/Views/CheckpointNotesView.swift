import MokaCore
import SwiftUI

struct NotesDraft: Equatable {
    var done = ""
    var next = ""
}

/// 도는 중 미루기·바꾸기와 두 줄 입력(R-105·R-106).
struct NotesInput {
    var pending: PendingAction?
    var draft = NotesDraft()
    var elapsedMinutes = 0
    var onBegin: (PendingAction) -> Void = { _ in }
    var onEdit: (NotesDraft) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    var onSkipWriting: () -> Void = {}
    var onCancel: () -> Void = {}
    var takeFocusRequest: () -> Bool = { false }
}

struct CheckpointNotesView: View {
    let title: String
    let input: NotesInput

    @FocusState private var focus: NotesFields.Field?
    @Environment(\.panelPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TitleText(title: title, lineLimit: 1)
                Text(NotchStatus.elapsed(minutes: input.elapsedMinutes))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(palette.muted)
                    .fixedSize()
            }
            NotesFields(draft: input.draft, onEdit: input.onEdit, focus: $focus, onSubmitNext: input.onSubmit)
                .padding(.top, 8)
            HStack(spacing: 6) {
                Button(action: input.onCancel) { ButtonLabel(text: "돌아가기", shortcut: "esc") }
                    .buttonStyle(NotchButtonStyle(kind: .ghost))
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                Button("안 적기", action: input.onSkipWriting)
                    .buttonStyle(NotchButtonStyle(kind: .ghost))
                Button(action: input.onSubmit) { ButtonLabel(text: "등록", shortcut: "↵") }
                    .buttonStyle(NotchButtonStyle(kind: .primary))
            }
            .padding(.top, 10)
        }
        .onAppear {
            // 나타나는 순간에는 칸이 아직 붙지 않아 포커스 요청이 버려진다. 다음 차례로 미룬다.
            if input.takeFocusRequest() { Task { @MainActor in focus = .done } }
        }
    }
}

struct NotesFields: View {
    enum Field { case done, next }

    let draft: NotesDraft
    let onEdit: (NotesDraft) -> Void
    var donePlaceholder: String?
    let focus: FocusState<Field?>.Binding
    let onSubmitNext: () -> Void

    @Environment(\.panelPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            label("어디까지 했어요?")
            TextField("", text: doneText, prompt: donePlaceholder.map(placeholder))
                .notchField(focused: focus.wrappedValue == .done)
                .focused(focus, equals: .done)
                .onSubmit { focus.wrappedValue = .next }
                // 노치 패널에서는 기본 키 순서로 Tab이 다음 칸에 가지 않는다(2026-11-05 사람 확인).
                .onKeyPress(.tab) {
                    focus.wrappedValue = .next
                    return .handled
                }
            label("다음엔 뭐부터 할까요?")
                .padding(.top, 8)
            TextField("", text: nextText, prompt: placeholder("비워 둬도 돼요"))
                .notchField(focused: focus.wrappedValue == .next)
                .focused(focus, equals: .next)
                .onSubmit(onSubmitNext)
        }
    }

    private var doneText: Binding<String> {
        Binding(get: { draft.done }, set: { onEdit(NotesDraft(done: $0, next: draft.next)) })
    }

    private var nextText: Binding<String> {
        Binding(get: { draft.next }, set: { onEdit(NotesDraft(done: draft.done, next: $0)) })
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(palette.muted)
            .padding(.bottom, 3)
    }

    private func placeholder(_ text: String) -> Text {
        Text(text).foregroundStyle(palette.placeholder)
    }
}
