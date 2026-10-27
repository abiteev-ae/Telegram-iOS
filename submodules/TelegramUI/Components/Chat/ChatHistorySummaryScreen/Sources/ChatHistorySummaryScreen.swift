import Foundation
import UIKit
import SwiftSignalKit
import Display
import TelegramCore
import TelegramPresentationData
import ComponentFlow
import AccountContext
import ViewControllerComponent
import MultilineTextComponent
import ResizableSheetComponent
import ListSectionComponent
import ListActionItemComponent
import GlassBarButtonComponent
import BundleIconComponent
import ItemListUI

private final class ChatHistorySummaryContentComponent: Component {
    typealias EnvironmentType = ViewControllerComponentContainer.Environment

    let context: AccountContext
    let peerTitle: String
    let summaryState: ChatHistorySummaryState
    let retry: () -> Void
    let openMessage: (EngineMessage.Id) -> Void

    init(
        context: AccountContext,
        peerTitle: String,
        summaryState: ChatHistorySummaryState,
        retry: @escaping () -> Void,
        openMessage: @escaping (EngineMessage.Id) -> Void
    ) {
        self.context = context
        self.peerTitle = peerTitle
        self.summaryState = summaryState
        self.retry = retry
        self.openMessage = openMessage
    }

    static func ==(lhs: ChatHistorySummaryContentComponent, rhs: ChatHistorySummaryContentComponent) -> Bool {
        if lhs.context !== rhs.context {
            return false
        }
        if lhs.peerTitle != rhs.peerTitle {
            return false
        }
        if lhs.summaryState != rhs.summaryState {
            return false
        }
        return true
    }

    final class View: UIView {
        private var sectionViews: [AnyHashable: ComponentView<Empty>] = [:]

        override init(frame: CGRect) {
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func textComponent(
            _ text: String,
            font: UIFont,
            color: UIColor,
            maximumNumberOfLines: Int = 0
        ) -> AnyComponent<Empty> {
            return AnyComponent(MultilineTextComponent(
                text: .plain(NSAttributedString(string: text, font: font, textColor: color)),
                maximumNumberOfLines: maximumNumberOfLines
            ))
        }

        private func bodyItem(
            id: AnyHashable,
            text: String,
            theme: PresentationTheme,
            fontSize: CGFloat
        ) -> AnyComponentWithIdentity<Empty> {
            return AnyComponentWithIdentity(id: id, component: AnyComponent(ListActionItemComponent(
                theme: theme,
                style: .glass,
                title: self.textComponent(
                    text,
                    font: Font.regular(fontSize),
                    color: theme.list.itemPrimaryTextColor
                ),
                contentInsets: UIEdgeInsets(top: 14.0, left: 0.0, bottom: 14.0, right: 0.0),
                accessory: nil,
                action: nil,
                highlighting: .disabled
            )))
        }

        private func actionItem(
            id: AnyHashable,
            title: String,
            theme: PresentationTheme,
            fontSize: CGFloat,
            action: @escaping () -> Void
        ) -> AnyComponentWithIdentity<Empty> {
            return AnyComponentWithIdentity(id: id, component: AnyComponent(ListActionItemComponent(
                theme: theme,
                style: .glass,
                title: self.textComponent(
                    title,
                    font: Font.regular(fontSize),
                    color: theme.list.itemAccentColor,
                    maximumNumberOfLines: 1
                ),
                accessory: .arrow,
                action: { _ in
                    action()
                }
            )))
        }

        func update(
            component: ChatHistorySummaryContentComponent,
            availableSize: CGSize,
            state: EmptyComponentState,
            environment: Environment<ViewControllerComponentContainer.Environment>,
            transition: ComponentTransition
        ) -> CGSize {
            let environmentValue = environment[ViewControllerComponentContainer.Environment.self].value
            let presentationData = component.context.sharedContext.currentPresentationData.with { $0 }
            let theme = environmentValue.theme.withModalBlocksBackground()
            let fontSize = presentationData.listsFontSize.baseDisplaySize
            let headerFontSize = presentationData.listsFontSize.itemListBaseHeaderFontSize
            let leftInset = 16.0 + environmentValue.safeInsets.left
            let rightInset = 16.0 + environmentValue.safeInsets.right
            let sectionWidth = max(1.0, availableSize.width - leftInset - rightInset)

            var sectionComponents: [(AnyHashable, ListSectionComponent)] = []

            let makeHeader: (String) -> AnyComponent<Empty> = { title in
                return self.textComponent(
                    title,
                    font: Font.regular(headerFontSize),
                    color: theme.list.freeTextColor,
                    maximumNumberOfLines: 1
                )
            }

            switch component.summaryState {
            case .idle, .loading:
                sectionComponents.append((
                    "loading",
                    ListSectionComponent(
                        theme: theme,
                        style: .glass,
                        header: makeHeader(component.peerTitle),
                        footer: nil,
                        items: [
                            AnyComponentWithIdentity(id: "loading", component: AnyComponent(ListActionItemComponent(
                                theme: theme,
                                style: .glass,
                                title: self.textComponent(
                                    environmentValue.strings.ChatList_HistorySummary_Loading,
                                    font: Font.regular(fontSize),
                                    color: theme.list.itemSecondaryTextColor
                                ),
                                accessory: .activity,
                                action: nil,
                                highlighting: .disabled
                            )))
                        ]
                    )
                ))
            case let .ready(_, summary):
                let overviewTitle = "\(component.peerTitle) · \(summary.coveredMessageCount)"
                sectionComponents.append((
                    "overview",
                    ListSectionComponent(
                        theme: theme,
                        style: .glass,
                        header: makeHeader(environmentValue.strings.ChatList_HistorySummary_Overview),
                        footer: self.textComponent(
                            environmentValue.strings.ChatList_HistorySummary_DemoNotice,
                            font: Font.regular(13.0),
                            color: theme.list.freeTextColor
                        ),
                        items: [
                            AnyComponentWithIdentity(id: "overview", component: AnyComponent(ListActionItemComponent(
                                theme: theme,
                                style: .glass,
                                title: AnyComponent(VStack([
                                    AnyComponentWithIdentity(id: "peer", component: self.textComponent(
                                        overviewTitle,
                                        font: Font.semibold(fontSize),
                                        color: theme.list.itemPrimaryTextColor,
                                        maximumNumberOfLines: 1
                                    )),
                                    AnyComponentWithIdentity(id: "text", component: self.textComponent(
                                        summary.overview,
                                        font: Font.regular(fontSize),
                                        color: theme.list.itemPrimaryTextColor
                                    ))
                                ], alignment: .left, spacing: 7.0)),
                                contentInsets: UIEdgeInsets(top: 14.0, left: 0.0, bottom: 14.0, right: 0.0),
                                accessory: nil,
                                action: nil,
                                highlighting: .disabled
                            )))
                        ]
                    )
                ))

                for (index, summarySection) in summary.sections.enumerated() {
                    let title: String
                    switch summarySection.kind {
                    case .keyPoints:
                        title = environmentValue.strings.ChatList_HistorySummary_KeyPoints
                    case .decisions:
                        title = environmentValue.strings.ChatList_HistorySummary_Decisions
                    case .actionItems:
                        title = environmentValue.strings.ChatList_HistorySummary_ActionItems
                    }

                    var items: [AnyComponentWithIdentity<Empty>] = [
                        self.bodyItem(
                            id: "body",
                            text: summarySection.text,
                            theme: theme,
                            fontSize: fontSize
                        )
                    ]
                    if let citation = summarySection.citation {
                        items.append(self.actionItem(
                            id: "citation",
                            title: citation.title,
                            theme: theme,
                            fontSize: fontSize,
                            action: {
                                component.openMessage(citation.messageId)
                            }
                        ))
                    }

                    sectionComponents.append((
                        "section-\(index)",
                        ListSectionComponent(
                            theme: theme,
                            style: .glass,
                            header: makeHeader(title),
                            footer: nil,
                            items: items
                        )
                    ))
                }
            case .empty:
                sectionComponents.append((
                    "empty",
                    ListSectionComponent(
                        theme: theme,
                        style: .glass,
                        header: makeHeader(component.peerTitle),
                        footer: nil,
                        items: [
                            self.bodyItem(
                                id: "empty",
                                text: environmentValue.strings.ChatList_HistorySummary_Empty,
                                theme: theme,
                                fontSize: fontSize
                            )
                        ]
                    )
                ))
            case .failed:
                sectionComponents.append((
                    "error",
                    ListSectionComponent(
                        theme: theme,
                        style: .glass,
                        header: makeHeader(component.peerTitle),
                        footer: nil,
                        items: [
                            self.bodyItem(
                                id: "error",
                                text: environmentValue.strings.ChatList_HistorySummary_Error,
                                theme: theme,
                                fontSize: fontSize
                            ),
                            self.actionItem(
                                id: "retry",
                                title: environmentValue.strings.ChatList_HistorySummary_Retry,
                                theme: theme,
                                fontSize: fontSize,
                                action: component.retry
                            )
                        ]
                    )
                ))
            }

            var validIds = Set<AnyHashable>()
            var contentHeight: CGFloat = 76.0 + 15.0
            for (id, sectionComponent) in sectionComponents {
                validIds.insert(id)
                let sectionView: ComponentView<Empty>
                if let current = self.sectionViews[id] {
                    sectionView = current
                } else {
                    sectionView = ComponentView()
                    self.sectionViews[id] = sectionView
                }
                sectionView.parentState = state
                let sectionSize = sectionView.update(
                    transition: transition,
                    component: AnyComponent(sectionComponent),
                    environment: {},
                    containerSize: CGSize(width: sectionWidth, height: 100000.0)
                )
                if let view = sectionView.view {
                    if view.superview == nil {
                        self.addSubview(view)
                    }
                    transition.setFrame(
                        view: view,
                        frame: CGRect(x: leftInset, y: contentHeight, width: sectionSize.width, height: sectionSize.height)
                    )
                }
                contentHeight += sectionSize.height + 20.0
            }

            let removedIds = self.sectionViews.keys.filter { !validIds.contains($0) }
            for id in removedIds {
                self.sectionViews[id]?.view?.removeFromSuperview()
                self.sectionViews.removeValue(forKey: id)
            }

            contentHeight += max(20.0, environmentValue.safeInsets.bottom)
            return CGSize(width: availableSize.width, height: contentHeight)
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(
        view: View,
        availableSize: CGSize,
        state: EmptyComponentState,
        environment: Environment<ViewControllerComponentContainer.Environment>,
        transition: ComponentTransition
    ) -> CGSize {
        return view.update(
            component: self,
            availableSize: availableSize,
            state: state,
            environment: environment,
            transition: transition
        )
    }
}

private final class ChatHistorySummarySheetComponent: Component {
    typealias EnvironmentType = ViewControllerComponentContainer.Environment

    let context: AccountContext
    let peerTitle: String
    let request: ChatHistorySummaryRequest
    let provider: any ChatHistorySummaryProviding
    let openMessage: (EngineMessage.Id) -> Void

    init(
        context: AccountContext,
        peerTitle: String,
        request: ChatHistorySummaryRequest,
        provider: any ChatHistorySummaryProviding,
        openMessage: @escaping (EngineMessage.Id) -> Void
    ) {
        self.context = context
        self.peerTitle = peerTitle
        self.request = request
        self.provider = provider
        self.openMessage = openMessage
    }

    static func ==(lhs: ChatHistorySummarySheetComponent, rhs: ChatHistorySummarySheetComponent) -> Bool {
        if lhs.context !== rhs.context {
            return false
        }
        if lhs.peerTitle != rhs.peerTitle || lhs.request != rhs.request {
            return false
        }
        if (lhs.provider as AnyObject) !== (rhs.provider as AnyObject) {
            return false
        }
        return true
    }

    final class View: UIView {
        private let sheet = ComponentView<(ViewControllerComponentContainer.Environment, ResizableSheetComponentEnvironment)>()
        private let animateOut = ActionSlot<Action<Void>>()
        private let requestDisposable = MetaDisposable()

        private var component: ChatHistorySummarySheetComponent?
        private weak var state: EmptyComponentState?
        private var summaryState: ChatHistorySummaryState = .idle
        private var nextRequestId: Int64 = 0
        private var isDismissing = false

        override init(frame: CGRect) {
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            self.requestDisposable.dispose()
        }

        private func requestSummary(notify: Bool = true) {
            guard let component = self.component else {
                return
            }

            self.nextRequestId += 1
            let requestId = self.nextRequestId
            self.summaryState = reduceChatHistorySummaryState(
                state: self.summaryState,
                event: .start(requestId: requestId)
            )
            // Never call state.updated while already inside ComponentHostView.update —
            // that re-enters with isUpdating == true and traps.
            if notify {
                self.state?.updated(transition: .easeInOut(duration: 0.2))
            }

            self.requestDisposable.set((
                component.provider.summary(request: component.request)
                |> deliverOnMainQueue
            ).start(next: { [weak self] summary in
                guard let self else {
                    return
                }
                self.summaryState = reduceChatHistorySummaryState(
                    state: self.summaryState,
                    event: .result(requestId: requestId, summary: summary)
                )
                self.state?.updated(transition: .spring(duration: 0.35))
            }, error: { [weak self] error in
                guard let self else {
                    return
                }
                self.summaryState = reduceChatHistorySummaryState(
                    state: self.summaryState,
                    event: .failure(requestId: requestId, error: error)
                )
                self.state?.updated(transition: .easeInOut(duration: 0.2))
            }))
        }

        func update(
            component: ChatHistorySummarySheetComponent,
            availableSize: CGSize,
            state: EmptyComponentState,
            environment: Environment<ViewControllerComponentContainer.Environment>,
            transition: ComponentTransition
        ) -> CGSize {
            let environmentValue = environment[ViewControllerComponentContainer.Environment.self].value
            let controller = environmentValue.controller
            let theme = environmentValue.theme.withModalBlocksBackground()

            let previousProvider = self.component.map { $0.provider as AnyObject }
            let shouldStart = self.component == nil
                || self.component?.request != component.request
                || previousProvider !== (component.provider as AnyObject)
            self.component = component
            self.state = state
            if shouldStart {
                self.summaryState = .idle
                self.requestSummary(notify: false)
            }

            let dismiss: (Bool) -> Void = { [weak self] animated in
                guard let self, !self.isDismissing else {
                    return
                }
                self.isDismissing = true
                self.requestDisposable.set(nil)

                let performDismiss: () -> Void = {
                    if let controller = controller() as? ChatHistorySummaryScreen {
                        controller.completePendingDismiss()
                        controller.dismiss(animated: false)
                    }
                }
                if animated {
                    self.animateOut.invoke(Action { _ in
                        performDismiss()
                    })
                } else {
                    performDismiss()
                }
            }

            let sheetSize = self.sheet.update(
                transition: transition,
                component: AnyComponent(ResizableSheetComponent<ViewControllerComponentContainer.Environment>(
                    content: AnyComponent(ChatHistorySummaryContentComponent(
                        context: component.context,
                        peerTitle: component.peerTitle,
                        summaryState: self.summaryState,
                        retry: { [weak self] in
                            self?.requestSummary()
                        },
                        openMessage: { messageId in
                            dismiss(true)
                            component.openMessage(messageId)
                        }
                    )),
                    titleItem: AnyComponent(MultilineTextComponent(
                        text: .plain(NSAttributedString(
                            string: environmentValue.strings.ChatList_HistorySummary_Title,
                            font: Font.semibold(17.0),
                            textColor: theme.list.itemPrimaryTextColor
                        )),
                        maximumNumberOfLines: 1
                    )),
                    leftItem: AnyComponent(GlassBarButtonComponent(
                        size: CGSize(width: 44.0, height: 44.0),
                        backgroundColor: nil,
                        isDark: theme.overallDarkAppearance,
                        state: .glass,
                        component: AnyComponentWithIdentity(id: "close", component: AnyComponent(
                            BundleIconComponent(
                                name: "Navigation/Close",
                                tintColor: theme.chat.inputPanel.panelControlColor
                            )
                        )),
                        action: { _ in
                            dismiss(true)
                        }
                    )),
                    backgroundColor: .color(theme.list.modalBlocksBackgroundColor),
                    animateOut: self.animateOut
                )),
                environment: {
                    environmentValue
                    ResizableSheetComponentEnvironment(
                        theme: theme,
                        statusBarHeight: environmentValue.statusBarHeight,
                        safeInsets: environmentValue.safeInsets,
                        inputHeight: 0.0,
                        metrics: environmentValue.metrics,
                        deviceMetrics: environmentValue.deviceMetrics,
                        isDisplaying: environmentValue.isVisible,
                        isCentered: environmentValue.presentsFloatingPanels,
                        screenSize: availableSize,
                        regularMetricsSize: nil,
                        dismiss: { animated in
                            dismiss(animated)
                        }
                    )
                },
                forceUpdate: true,
                containerSize: availableSize
            )
            self.sheet.parentState = state
            if let sheetView = self.sheet.view {
                if sheetView.superview == nil {
                    self.addSubview(sheetView)
                }
                transition.setFrame(view: sheetView, frame: CGRect(origin: .zero, size: sheetSize))
            }

            return availableSize
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(
        view: View,
        availableSize: CGSize,
        state: EmptyComponentState,
        environment: Environment<ViewControllerComponentContainer.Environment>,
        transition: ComponentTransition
    ) -> CGSize {
        return view.update(
            component: self,
            availableSize: availableSize,
            state: state,
            environment: environment,
            transition: transition
        )
    }
}

public final class ChatHistorySummaryScreen: ViewControllerComponentContainer {
    private var isDismissed = false
    private var dismissCompletion: (() -> Void)?

    public init(
        context: AccountContext,
        peerTitle: String,
        request: ChatHistorySummaryRequest,
        provider: any ChatHistorySummaryProviding,
        openMessage: @escaping (EngineMessage.Id) -> Void
    ) {
        super.init(
            context: context,
            component: ChatHistorySummarySheetComponent(
                context: context,
                peerTitle: peerTitle,
                request: request,
                provider: provider,
                openMessage: openMessage
            ),
            navigationBarAppearance: .none
        )

        self.statusBar.statusBarStyle = .Ignore
        self.navigationPresentation = .flatModal
        self.blocksBackgroundWhenInOverlay = true
    }

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate func completePendingDismiss() {
        let dismissCompletion = self.dismissCompletion
        self.dismissCompletion = nil
        dismissCompletion?()
    }

    public func dismissAnimated() {
        if let view = self.node.hostView.findTaggedView(
            tag: ResizableSheetComponent<ViewControllerComponentContainer.Environment>.View.Tag()
        ) as? ResizableSheetComponent<ViewControllerComponentContainer.Environment>.View {
            view.dismissAnimated()
        }
    }

    override public func dismiss(completion: (() -> Void)? = nil) {
        if !self.isDismissed {
            self.isDismissed = true
            self.dismissCompletion = completion
            if let view = self.node.hostView.findTaggedView(
                tag: ResizableSheetComponent<ViewControllerComponentContainer.Environment>.View.Tag()
            ) as? ResizableSheetComponent<ViewControllerComponentContainer.Environment>.View {
                view.dismissAnimated()
            } else {
                self.completePendingDismiss()
                self.dismiss(animated: false)
            }
        }
    }
}
