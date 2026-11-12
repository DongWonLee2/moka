import AppKit
import MokaCore
import SwiftUI

struct OnboardingValues: Equatable {
    var context: NewContext?
    var quantumMin: Int
    var extendMin: Int
    var dayStart: DayStart
}

struct OnboardingKeyInput {
    let hasKey: Bool
    let onSave: (String) -> Bool
    let issueURL: URL?
    let host: String
}

enum OnboardingKeyText {
    static let title = "판단 모델 키가 있나요?"
    static let message = "TypeSafe에서 받은 키를 붙여 넣으면 판단 모델이 할 일 순서를 정해요. 키가 없으면 마감이 가까운 순으로 떠요."
    static let issueLink = DecisionFieldText.issueLink("TypeSafe Jev")
    static let otherProviders = "다른 판단 모델은 시작한 뒤 설정에서 고를 수 있어요."
    static let fieldLabel = "키"
    static let placeholder = "키를 붙여 넣어 주세요"
    static let saveFailed = "키를 저장하지 못했어요. 다시 해 주세요."
    static let saved = "저장되어 있어요"
}

/// 키 단계에서 붙여 넣는 글자와 저장 실패 표시(R-624·R-625). 창은 AppState를 관찰하지 않으므로 실패는 뷰가 든다.
struct OnboardingKeyDraft: Equatable {
    var text = ""
    var saveFailed = false

    func canGoNext(hasKey: Bool) -> Bool {
        hasKey || KeyFieldState.canSave(text)
    }

    mutating func submit(hasKey: Bool, onSave: (String) -> Bool) -> Bool {
        if hasKey { return true }
        guard KeyFieldState.canSave(text) else { return false }
        guard onSave(text) else {
            saveFailed = true
            return false
        }
        saveFailed = false
        text = ""
        return true
    }
}

/// 첫 실행 온보딩(R-116, spec 006 R-624). `keyStep`이 있으면 키, 일정, 기본값 세 단계이고 없으면 일정, 기본값 두 단계다.
/// 일정·기본값 저장은 마지막 "시작하기"에서 한꺼번에 하고, 키는 키 단계 "다음"에서 따로 저장한다. 값과 콜백만 받는다(ADR-0009).
struct OnboardingView: View {
    private enum Page {
        case key
        case context
        case defaults
    }

    let today: LocalDay
    let calendar: Calendar
    let keyStep: OnboardingKeyInput?
    let onFinish: (OnboardingValues) -> Void

    @State private var step: Int
    @State private var keyDraft: OnboardingKeyDraft
    @FocusState private var isKeyFocused: Bool
    @State private var name = ""
    @State private var date: LocalDay
    @State private var impact: ContextImpact = .normal
    @State private var includesContext = false
    @State private var isPickingDate = false
    @State private var quantumText: String
    @State private var extendText: String
    @State private var dayStart: Date
    @FocusState private var isNameFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    init(
        today: LocalDay, calendar: Calendar, initialQuantum: Int, initialExtend: Int, initialDayStart: DayStart,
        initialStep: Int = 1, keyStep: OnboardingKeyInput? = nil,
        initialKeyDraft: OnboardingKeyDraft = OnboardingKeyDraft(), onFinish: @escaping (OnboardingValues) -> Void
    ) {
        self.today = today
        self.calendar = calendar
        self.keyStep = keyStep
        self.onFinish = onFinish
        _step = State(initialValue: initialStep)
        _keyDraft = State(initialValue: initialKeyDraft)
        _date = State(initialValue: today)
        _quantumText = State(initialValue: String(initialQuantum))
        _extendText = State(initialValue: String(initialExtend))
        _dayStart = State(initialValue: initialDayStart.date(calendar: calendar))
    }

    private var hasName: Bool { MokaContext.normalizedName(name) != nil }
    private var quantumMin: Int? { QuantumChip.parseCustom(quantumText) }
    private var extendMin: Int? { QuantumChip.parseCustom(extendText) }

    private var pages: [Page] { keyStep == nil ? [.context, .defaults] : [.key, .context, .defaults] }
    private var page: Page { pages[step - 1] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepBar(step: step, total: pages.count)
            switch page {
            case .key:
                if let keyStep { keyStepView(keyStep) }
            case .context:
                contextStep
            case .defaults:
                defaultsStep
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(width: 400, alignment: .leading)
    }

    private func keyStepView(_ input: OnboardingKeyInput) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            heading(OnboardingKeyText.title, OnboardingKeyText.message)
            if let issueURL = input.issueURL, !input.hasKey {
                Button(OnboardingKeyText.issueLink) { NSWorkspace.shared.open(issueURL) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .underline()
                    .foregroundStyle(MokaColors.mocha)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(DecisionFieldText.destinationPrefix) + Text(input.host).fontWeight(.semibold)
                Text(OnboardingKeyText.otherProviders)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 10)
            if input.hasKey {
                Text(OnboardingKeyText.saved)
                    .font(.system(size: 12.5))
            } else {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow {
                        label(OnboardingKeyText.fieldLabel, width: 52)
                        SecureField(OnboardingKeyText.placeholder, text: $keyDraft.text)
                            .textFieldStyle(.roundedBorder)
                            .focused($isKeyFocused)
                            .accessibilityLabel(OnboardingKeyText.fieldLabel)
                    }
                }
                if keyDraft.saveFailed {
                    Text(OnboardingKeyText.saveFailed)
                        .font(.system(size: 11))
                        .foregroundStyle(MokaColors.danger)
                        .padding(.top, 5)
                }
            }
            HStack(spacing: 6) {
                Spacer()
                if !input.hasKey {
                    SheetButton(title: "건너뛰기", kind: .normal) { step += 1 }
                }
                SheetButton(title: "다음", kind: .primary) {
                    if keyDraft.submit(hasKey: input.hasKey, onSave: input.onSave) { step += 1 }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!keyDraft.canGoNext(hasKey: input.hasKey))
            }
            .padding(.top, 14)
        }
        .onAppear { isKeyFocused = !input.hasKey }
    }

    private var contextStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("다가오는 시험이나 제출이 있나요?", "하나만 넣어 두면 돼요. 나머지는 설정의 일정 탭에서 추가할 수 있어요.")
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    label("이름", width: 52)
                    TextField("예: 중간고사", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNameFocused)
                        .accessibilityLabel("이름")
                }
                GridRow {
                    label("날짜", width: 52)
                    PillButton(title: ContextText.formDate(date), isMuted: false) { isPickingDate = true }
                        .accessibilityLabel("날짜")
                        .accessibilityValue(ContextText.formDate(date))
                        .popover(isPresented: $isPickingDate, arrowEdge: .bottom) {
                            MokaCalendar(
                                selected: date, today: today, calendar: calendar, allowsClear: false,
                                onPick: { day in
                                    if let day { date = day }
                                    isPickingDate = false
                                })
                        }
                }
                GridRow {
                    label("중요도", width: 52)
                    ChoiceChips(
                        label: "중요도", items: ContextImpact.allCases.map { ($0, ContextText.impact($0)) },
                        selection: $impact)
                }
            }
            HStack(spacing: 6) {
                Spacer()
                SheetButton(title: "건너뛰기", kind: .normal) {
                    includesContext = false
                    step += 1
                }
                SheetButton(title: "다음", kind: .primary) {
                    includesContext = true
                    step += 1
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasName)
            }
            .padding(.top, 14)
        }
        .onAppear { isNameFocused = true }
    }

    private var defaultsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("이대로 시작할까요?", "언제든 설정에서 바꿀 수 있어요.")
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                minutesRow("기본 작업 시간", text: $quantumText)
                minutesRow("추가 시간", text: $extendText)
                GridRow {
                    label("하루 시작 시각", width: 110)
                    TimeField(date: $dayStart, locale: BasicTabView.twentyFourHour)
                        .accessibilityLabel("하루 시작 시각")
                        .frame(width: 70)
                }
            }
            if let issue = [quantumText, extendText].lazy.compactMap({ QuantumChip.customIssueMessage(customText: $0) })
                .first
            {
                Text(issue)
                    .font(.system(size: 11))
                    .foregroundStyle(MokaColors.danger)
                    .padding(.top, 6)
            }
            HStack(spacing: 6) {
                SheetButton(title: "이전", kind: .normal) { step -= 1 }
                Spacer()
                SheetButton(title: "시작하기", kind: .primary, action: finish)
                    .keyboardShortcut(.defaultAction)
                    .disabled(quantumMin == nil || extendMin == nil)
            }
            .padding(.top, 14)
        }
    }

    private func finish() {
        guard let quantumMin, let extendMin else { return }
        onFinish(
            OnboardingValues(
                context: includesContext ? NewContext(name: name, date: date, impact: impact) : nil,
                quantumMin: quantumMin, extendMin: extendMin, dayStart: DayStart(date: dayStart, calendar: calendar)))
    }

    private func heading(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private func label(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
    }

    private func minutesRow(_ title: String, text: Binding<String>) -> some View {
        GridRow {
            label(title, width: 110)
            HStack(spacing: 4) {
                TextField("", text: text)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .accessibilityLabel(title)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                Text("분")
                    .font(.system(size: 12))
            }
        }
    }
}

private struct StepBar: View {
    let step: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index <= step ? MokaColors.mocha : Color(hex: 0x806E5F, opacity: 0.3))
                    .frame(width: 18, height: 4)
            }
            Text("\(step)/\(total)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(step)/\(total)단계")
    }
}
