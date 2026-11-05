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

    private enum Field { case done, next }

    @FocusState private var focus: Field?
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
            label("어디까지 했어요?")
            TextField("", text: doneText)
                .notchField(focused: focus == .done)
                .focused($focus, equals: .done)
                .onSubmit { focus = .next }
            label("다음엔 뭐부터 할까요?")
            TextField("", text: nextText, prompt: placeholder("비워 둬도 돼요"))
                .notchField(focused: focus == .next)
                .focused($focus, equals: .next)
                .onSubmit(input.onSubmit)
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

    private var doneText: Binding<String> {
        Binding(
            get: { input.draft.done },
            set: { input.onEdit(NotesDraft(done: $0, next: input.draft.next)) })
    }

    private var nextText: Binding<String> {
        Binding(
            get: { input.draft.next },
            set: { input.onEdit(NotesDraft(done: input.draft.done, next: $0)) })
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(palette.muted)
            .padding(.top, 8)
            .padding(.bottom, 3)
    }

    private func placeholder(_ text: String) -> Text {
        Text(text).foregroundStyle(palette.placeholder)
    }
}
