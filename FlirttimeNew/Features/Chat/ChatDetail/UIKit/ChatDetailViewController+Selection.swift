import UIKit

// MARK: - Selection Mode UI

extension ChatDetailViewController {

    func updateSelectionUI(_ state: MessageSelectionState) {
        let isEnteringSelection = !wasInSelectionMode && state.isSelectionMode
        let isExitingSelection = wasInSelectionMode && !state.isSelectionMode

        if isEnteringSelection {
            previousSelectedIds = state.selectedMessageIds
            wasInSelectionMode = true
            showSelectionBars(count: state.selectedMessageIds.count)
            dataSource?.reconfigureAllForSelection(
                isInSelectionMode: true,
                selectedMessageIds: state.selectedMessageIds
            )
        } else if isExitingSelection {
            previousSelectedIds = []
            wasInSelectionMode = false
            hideSelectionBars()
            dataSource?.reconfigureAllForSelection(
                isInSelectionMode: false,
                selectedMessageIds: []
            )
        } else if state.isSelectionMode {
            let changedIds = previousSelectedIds.symmetricDifference(state.selectedMessageIds)
            previousSelectedIds = state.selectedMessageIds
            selectionHeaderView?.configure(count: state.selectedMessageIds.count)
            if !changedIds.isEmpty {
                dataSource?.reconfigureForSelectionToggle(
                    changedIds: changedIds,
                    selectedMessageIds: state.selectedMessageIds
                )
            }
            updateSelectionActionBar()
        }
    }

    func updateSelectionActionBar() {
        let hasSelection = viewModel.selection.hasSelection
        let canDelForAll = hasSelection && viewModel.canDeleteForEveryoneSelected()
        let canForward = hasSelection && !isSelectionOnlyPolls()
        selectionActionView?.configure(hasSelection: hasSelection, canDeleteForEveryone: canDelForAll, canForward: canForward, isChannel: isChannel)
    }

    private func isSelectionOnlyPolls() -> Bool {
        let ids = viewModel.selection.selectedMessageIds
        guard !ids.isEmpty else { return false }
        return ids.allSatisfy { id in
            guard let msg = viewModel.messages.first(where: { $0.stableId == id }) else { return false }
            return isPollMessage(msg)
        }
    }

    func showSelectionBars(count: Int) {
        if selectionHeaderView == nil {
            let header = ChatSelectionHeaderBar()
            header.configure(count: count)
            header.onCancel = { [weak self] in self?.viewModel.exitSelectionMode() }
            header.onSelectAll = { [weak self] in
                guard let self else { return }
                // Use stableId so selection matches long-press / tap toggle + forward/delete resolve.
                let allIds = self.viewModel.messages.map(\.stableId).filter { !$0.isEmpty }
                self.viewModel.selection.selectAll(from: allIds)
            }
            view.addSubview(header)
            if let navBar = navBar {
                NSLayoutConstraint.activate([
                    header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                    header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    header.bottomAnchor.constraint(equalTo: navBar.bottomAnchor),
                ])
            } else {
                NSLayoutConstraint.activate([
                    header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                    header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                ])
            }
            selectionHeaderView = header
            header.alpha = 0
            UIView.animate(withDuration: 0.2) { header.alpha = 1 }
        } else {
            selectionHeaderView?.configure(count: count)
        }

        if selectionActionView == nil {
            let hasSelection = viewModel.selection.hasSelection
            let canDelForAll = hasSelection && viewModel.canDeleteForEveryoneSelected()
            let canForward = hasSelection && !isSelectionOnlyPolls()
            let actionBar = ChatSelectionActionBar()
            actionBar.configure(hasSelection: hasSelection, canDeleteForEveryone: canDelForAll, canForward: canForward, isChannel: isChannel)
            actionBar.onDeleteForMe = { [weak self] in
                guard let self, self.viewModel.selection.hasSelection else { return }
                self.viewModel.deleteSelectedMessages(forEveryone: false)
            }
            actionBar.onDeleteForEveryone = { [weak self] in
                guard let self, self.viewModel.selection.hasSelection else { return }
                self.viewModel.deleteSelectedMessages(forEveryone: true)
            }
            view.addSubview(actionBar)
            NSLayoutConstraint.activate([
                actionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                actionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                actionBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            selectionActionView = actionBar

            actionBar.transform = CGAffineTransform(translationX: 0, y: 80)
            UIView.animate(withDuration: 0.22) { actionBar.transform = .identity }
        }

        inputContainer.isHidden = true
    }

    func hideSelectionBars() {
        selectionHeaderView?.removeFromSuperview()
        selectionHeaderView = nil

        if let actionBar = selectionActionView {
            selectionActionView = nil
            UIView.animate(withDuration: 0.18, animations: {
                actionBar.transform = CGAffineTransform(translationX: 0, y: 80)
            }) { _ in
                actionBar.removeFromSuperview()
            }
        }

        inputContainer.isHidden = false
    }
}
