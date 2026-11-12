import AppKit
import MokaCore
import SwiftUI

struct ProviderRow: Equatable {
    let id: ProviderID
    let displayName: String
    let isOpen: Bool
    let closedNote: String?
}

struct MicrosoftFieldInput: Equatable {
    let savedEndpoint: String?
    let savedDeployment: String?
    let showsKeyResetNotice: Bool
    let keyCleared: Bool
}

struct DecisionFieldInput {
    var providers: [ProviderRow] = []
    var selected: ProviderID? = .typesafe
    var issueURL: URL?
    var host: String?
    var provisional = false
    var offNote: String?
    var microsoft: MicrosoftFieldInput?
    var keyState: KeyFieldState = .noKey
    var canRetry = false
    var failure: ProviderAction?
    var onSelect: (ProviderID) -> Void = { _ in }
    var onSaveMicrosoft: (String, String) -> EndpointRejection? = { _, _ in nil }
    var onSaveKey: (String) -> Void = { _ in }
    var onDeleteKey: () -> Void = {}
    var onRetry: () -> Void = {}

    var selectedName: String? {
        providers.first { $0.id == selected }?.displayName
    }
}

struct DecisionFieldStart {
    var listOpen = false
    var endpoint: String?
    var deployment: String?
    var rejection: EndpointRejection?
}

enum DecisionFieldText {
    static let providerLabel = "공급자"
    static let choosePlaceholder = "골라 주세요"
    static let switchNotice = "공급자를 바꾸면 할 일을 모두 새 판단 모델에 다시 물어요. 그동안은 마감이 가까운 순으로 떠요."
    static let closedNote = "아직 연결을 확인하는 중이라 고를 수 없어요."
    static let destinationPrefix = "할 일 제목이 가는 곳: "
    static let provisionalNotice = "이 판단 모델은 순서를 정하는 기준값을 아직 맞추는 중이에요. 순서가 조금 다를 수 있어요."
    static let selectFailed = "공급자를 바꾸지 못했어요. 다시 해 주세요."
    static let saveMicrosoftFailed = "주소를 저장하지 못했어요. 다시 해 주세요."
    static let microsoftHeading = "Azure 배포"
    static let endpointLabel = "리소스 주소"
    static let deploymentLabel = "배포 이름"
    static let endpointPlaceholder = "https://로 시작하는 Azure 리소스 주소"
    static let deploymentPlaceholder = "Azure에서 만든 배포 이름"
    static let saveMicrosoftButton = "주소 저장"
    static let keyResetNotice = "주소를 바꾸면 저장된 키를 지워요. 키를 다시 넣어 주세요."
    static let keyCleared = "주소가 바뀌어서 키를 지웠어요. 이 주소에서 쓸 키를 다시 넣어 주세요."

    static func title(_ providerName: String?) -> String {
        guard let providerName else { return "판단 모델 키" }
        return "판단 모델 키 (\(providerName))"
    }

    static func issueLink(_ displayName: String) -> String {
        let company = displayName.split(separator: " ").first.map(String.init) ?? displayName
        return "\(company)에서 키 받기"
    }

    static func rejection(_ rejection: EndpointRejection) -> String {
        switch rejection {
        case .scheme: "https로 시작하는 주소만 받아요. 내 컴퓨터 주소(localhost)는 http도 돼요."
        case .userInfo: "주소에 아이디나 비밀번호를 넣지 말아 주세요."
        case .query, .fragment: "주소 뒤의 ?나 # 부분은 빼 주세요."
        case .path: "리소스 주소까지만 넣어 주세요. 뒤의 경로는 앱이 붙여요."
        case .unparseable, .emptyHost: "주소를 읽지 못했어요. https://로 시작하는지 봐 주세요."
        }
    }

    static func offNote(_ reason: DecisionSelection.OffReason) -> String {
        switch reason {
        case .needsEndpoint, .needsDeployment: "주소와 배포 이름을 넣기 전에는 판단 모델에 묻지 않아요. 할 일은 마감이 가까운 순으로 떠요."
        case .closedProvider: "이 판단 모델은 아직 연결을 확인하는 중이라 묻지 않아요. 할 일은 마감이 가까운 순으로 떠요."
        case .unknownProvider: "고른 판단 모델을 찾지 못했어요. 공급자를 다시 골라 주세요."
        }
    }
}

/// 기본 탭 아래 판단 모델 칸(006 시안 1~10번). 공급자 고르기, 바꾸기 안내, Microsoft 칸, 가는 곳, 잠정값 안내,
/// 발급 링크, 키 칸 순이다. 바꾸기 전에 확인 창을 띄우지 않는다(R-622).
struct DecisionFieldBox: View {
    let input: DecisionFieldInput
    @State private var isListOpen: Bool
    private let start: DecisionFieldStart

    init(input: DecisionFieldInput, start: DecisionFieldStart = DecisionFieldStart()) {
        self.input = input
        self.start = start
        _isListOpen = State(initialValue: start.listOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(DecisionFieldText.title(input.selectedName))
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.bottom, 6)
            HStack(spacing: 8) {
                Text(DecisionFieldText.providerLabel)
                    .font(.system(size: 12))
                    .frame(width: 64, alignment: .leading)
                ProviderPopButton(title: input.selectedName ?? DecisionFieldText.choosePlaceholder) {
                    isListOpen.toggle()
                }
            }
            .padding(.bottom, 6)
            if isListOpen {
                ProviderList(rows: input.providers, selected: input.selected) { id in
                    isListOpen = false
                    input.onSelect(id)
                }
                .padding(.leading, 72)
            }
            FieldNote(text: DecisionFieldText.switchNotice)
                .padding(.leading, 72)
                .padding(.bottom, 6)
            if input.failure == .select {
                FieldNote(text: DecisionFieldText.selectFailed, isWarning: true)
                    .padding(.leading, 72)
                    .padding(.bottom, 6)
            }
            if let microsoft = input.microsoft {
                MicrosoftFields(
                    input: microsoft, offNote: input.offNote, saveFailed: input.failure == .saveMicrosoft,
                    start: start, onSave: input.onSaveMicrosoft)
            } else if let offNote = input.offNote {
                FieldNote(text: offNote).padding(.bottom, 6)
            }
            if let host = input.host {
                (Text(DecisionFieldText.destinationPrefix) + Text(host).fontWeight(.semibold))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }
            if input.provisional {
                ProvisionalNote().padding(.bottom, 6)
            }
            if input.microsoft?.keyCleared == true {
                FieldNote(text: DecisionFieldText.keyCleared, isWarning: true).padding(.bottom, 6)
            }
            if let issueURL = input.issueURL, let name = input.selectedName {
                Button(DecisionFieldText.issueLink(name)) { NSWorkspace.shared.open(issueURL) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .underline()
                    .foregroundStyle(MokaColors.mocha)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
            }
            if input.selected != nil {
                KeyFieldBox(
                    state: input.keyState, canRetry: input.canRetry, onSave: input.onSaveKey,
                    onDelete: input.onDeleteKey, onRetry: input.onRetry,
                    showsIntro: input.microsoft?.keyCleared != true)
            }
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(hex: 0x806E5F, opacity: 0.22))
                .frame(height: 1)
        }
        .padding(.top, 12)
    }
}

private struct ProvisionalNote: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(DecisionFieldText.provisionalNotice)
            .font(.system(size: 11))
            .foregroundStyle(colorScheme == .dark ? Color(hex: 0xD9A774) : MokaColors.mocha)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FieldNote: View {
    let text: String
    var isWarning = false

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(isWarning ? AnyShapeStyle(MokaColors.danger) : AnyShapeStyle(.secondary))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ProviderPopButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 12.5))
                Spacer(minLength: 0)
                Text("▾").font(.system(size: 10)).opacity(0.7)
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 170, minHeight: 22)
            .fixedSize()
            .background(
                colorScheme == .dark ? Color(hex: 0x4A423C) : Color.white, in: RoundedRectangle(cornerRadius: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(
                        colorScheme == .dark ? Color.clear : Color(hex: 0x3C2314, opacity: 0.3), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(DecisionFieldText.providerLabel), \(title)")
    }
}

private struct ProviderList: View {
    let rows: [ProviderRow]
    let selected: ProviderID?
    let onPick: (ProviderID) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows, id: \.id) { row in
                let isSelected = row.id == selected
                Button {
                    onPick(row.id)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.displayName).font(.system(size: 12.5))
                        if let note = row.closedNote {
                            Text(note).font(.system(size: 10.5))
                        }
                    }
                    .foregroundStyle(isSelected ? MokaColors.textOnPrimary : Color.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isSelected ? MokaColors.mocha : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                    .opacity(row.isOpen ? 1 : 0.5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!row.isOpen)
            }
        }
        .padding(4)
        .frame(width: 300, alignment: .leading)
        .background(
            colorScheme == .dark ? Color(hex: 0x2B2521) : Color(hex: 0xFBF8F5), in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(
                    colorScheme == .dark ? Color(hex: 0xFFF0E1, opacity: 0.2) : Color(hex: 0x3C2314, opacity: 0.3),
                    lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.25), radius: 9, y: 6)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }
}

/// Microsoft 칸(시안 7~10번). 두 칸의 앞뒤 공백·줄바꿈을 지우고 비거나 저장된 값과 같으면 저장을 끈다(R-623).
private struct MicrosoftFields: View {
    let input: MicrosoftFieldInput
    let offNote: String?
    let saveFailed: Bool
    let onSave: (String, String) -> EndpointRejection?
    @State private var endpoint: String
    @State private var deployment: String
    @State private var rejection: EndpointRejection?

    init(
        input: MicrosoftFieldInput, offNote: String?, saveFailed: Bool, start: DecisionFieldStart,
        onSave: @escaping (String, String) -> EndpointRejection?
    ) {
        self.input = input
        self.offNote = offNote
        self.saveFailed = saveFailed
        self.onSave = onSave
        _endpoint = State(initialValue: start.endpoint ?? input.savedEndpoint ?? "")
        _deployment = State(initialValue: start.deployment ?? input.savedDeployment ?? "")
        _rejection = State(initialValue: start.rejection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(DecisionFieldText.microsoftHeading)
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 4)
                .padding(.bottom, 4)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    label(DecisionFieldText.endpointLabel)
                    TextField(DecisionFieldText.endpointPlaceholder, text: $endpoint)
                        .accessibilityLabel(DecisionFieldText.endpointLabel)
                        .onSubmit(save)
                }
                GridRow {
                    label(DecisionFieldText.deploymentLabel)
                    TextField(DecisionFieldText.deploymentPlaceholder, text: $deployment)
                        .accessibilityLabel(DecisionFieldText.deploymentLabel)
                        .onSubmit(save)
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    HStack {
                        Spacer(minLength: 0)
                        SheetButton(title: DecisionFieldText.saveMicrosoftButton, kind: .primary, action: save)
                            .disabled(!canSave)
                    }
                }
            }
            .padding(.bottom, 6)
            if let rejection {
                FieldNote(text: DecisionFieldText.rejection(rejection), isWarning: true).padding(.bottom, 6)
            } else if saveFailed {
                FieldNote(text: DecisionFieldText.saveMicrosoftFailed, isWarning: true).padding(.bottom, 6)
            } else if let offNote {
                FieldNote(text: offNote).padding(.bottom, 6)
            }
            if input.showsKeyResetNotice {
                FieldNote(text: DecisionFieldText.keyResetNotice).padding(.bottom, 6)
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).frame(width: 64, alignment: .leading)
    }

    private var trimmed: (endpoint: String, deployment: String) {
        (
            endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            deployment.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private var canSave: Bool {
        let values = trimmed
        guard !values.endpoint.isEmpty, !values.deployment.isEmpty else { return false }
        return values.endpoint != input.savedEndpoint || values.deployment != input.savedDeployment
    }

    private func save() {
        guard canSave else { return }
        let values = trimmed
        rejection = onSave(values.endpoint, values.deployment)
    }
}
