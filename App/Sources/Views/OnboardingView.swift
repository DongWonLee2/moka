import MokaCore
import SwiftUI

struct OnboardingValues: Equatable {
    var context: NewContext?
    var quantumMin: Int
    var extendMin: Int
    var dayStart: DayStart
}

/// 첫 실행 온보딩 두 단계(시안 11·12번, R-116). 1단계 일정 한 건(건너뛸 수 있음), 2단계 기본값 확인.
/// 저장은 2단계 "시작하기"에서 한꺼번에 한다. 값과 콜백만 받는다(ADR-0009).
struct OnboardingView: View {
    let today: LocalDay
    let calendar: Calendar
    let onFinish: (OnboardingValues) -> Void

    @State private var step: Int
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
        initialStep: Int = 1, onFinish: @escaping (OnboardingValues) -> Void
    ) {
        self.today = today
        self.calendar = calendar
        self.onFinish = onFinish
        _step = State(initialValue: initialStep)
        _date = State(initialValue: today)
        _quantumText = State(initialValue: String(initialQuantum))
        _extendText = State(initialValue: String(initialExtend))
        _dayStart = State(initialValue: initialDayStart.date(calendar: calendar))
    }

    private var hasName: Bool { MokaContext.normalizedName(name) != nil }
    private var quantumMin: Int? { QuantumChip.parseCustom(quantumText) }
    private var extendMin: Int? { QuantumChip.parseCustom(extendText) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepBar(step: step)
            if step == 1 {
                contextStep
            } else {
                defaultsStep
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(width: 400, alignment: .leading)
    }

    private var contextStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("다가오는 시험이나 제출이 있나요?", "하나만 넣어 두면 돼요. 나머지는 설정의 일정 탭에서 더할 수 있어요.")
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
                    step = 2
                }
                SheetButton(title: "다음", kind: .primary) {
                    includesContext = true
                    step = 2
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
            if let issue = QuantumChip.customIssueMessage(customText: quantumMin == nil ? quantumText : extendText) {
                Text(issue)
                    .font(.system(size: 11))
                    .foregroundStyle(MokaColors.danger)
                    .padding(.top, 6)
            }
            HStack(spacing: 6) {
                SheetButton(title: "이전", kind: .normal) { step = 1 }
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

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...2, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index <= step ? MokaColors.mocha : Color(hex: 0x806E5F, opacity: 0.3))
                    .frame(width: 18, height: 4)
            }
            Text("\(step)/2")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(step)/2단계")
    }
}
