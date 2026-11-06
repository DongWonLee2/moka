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

    // 글자는 칸 안 상태로 들고 바뀔 때만 알린다(직접 입력 분 칸과 같은 방식). 바깥 값을 바로 읽는 Binding이면
    // 노치 패널에서 칸이 포커스를 잃은 뒤 글자가 안 보였다(2026-11-06 사람 확인).
    @State private var done = ""
    @State private var next = ""
    @Environment(\.panelPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            label("어디까지 했어요?")
            TextField("", text: $done, prompt: donePlaceholder.map(placeholder))
                .notchField(focused: focus.wrappedValue == .done)
                .focused(focus, equals: .done)
                .onSubmit(moveToNext)
                // 노치 패널에서는 기본 키 순서로 Tab이 다음 칸에 가지 않는다(2026-11-05 사람 확인).
                .onKeyPress(.tab) {
                    moveToNext()
                    return .handled
                }
            label("다음엔 뭐부터 할까요?")
                .padding(.top, 8)
            TextField("", text: $next, prompt: placeholder("비워 둬도 돼요"))
                .notchField(focused: focus.wrappedValue == .next)
                .focused(focus, equals: .next)
                .onSubmit(onSubmitNext)
        }
        .onAppear {
            done = draft.done
            next = draft.next
        }
        .onChange(of: draft) { _, newValue in
            if newValue.done != done { done = newValue.done }
            if newValue.next != next { next = newValue.next }
        }
        .onChange(of: done) { _, newValue in
            if newValue != draft.done { onEdit(NotesDraft(done: newValue, next: next)) }
        }
        .onChange(of: next) { _, newValue in
            if newValue != draft.next { onEdit(NotesDraft(done: done, next: newValue)) }
        }
    }

    /// 첫 칸이 편집을 마무리한 다음 차례에 옮긴다. Enter 처리 도중 바로 옮기면 첫 칸이 글자를 다시 그리지 못했다
    /// (2026-11-06 사람 확인, 클릭으로 옮길 때는 보임).
    private func moveToNext() {
        Task { @MainActor in focus.wrappedValue = .next }
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
