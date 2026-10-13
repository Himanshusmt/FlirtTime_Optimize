//
//  FAQViewController.swift
//  FlirttimeNew
//

import UIKit

final class FAQViewController: BaseViewController, Instantiable {

    static var storyboardName: StringConvertible {
        return StoryboardName.settings
    }

    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var faqTableView: UITableView!

    /// `nil` shows every question.
    var category: FAQCategory?

    private lazy var items = FAQCatalog.items(in: category)
    private var expandedIndex: Int?

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.text = category?.title ?? "FAQs"
        faqTableView.rowHeight = UITableView.automaticDimension
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: true)
    }

    @IBAction private func backButtonTapped(_ sender: UIButton) {
        navigationController?.popViewController(animated: true)
    }
}

extension FAQViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: FAQCell.identifier, for: indexPath) as? FAQCell else {
            return UITableViewCell()
        }
        cell.configure(with: items[indexPath.row], isExpanded: expandedIndex == indexPath.row)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let previous = expandedIndex
        expandedIndex = previous == indexPath.row ? nil : indexPath.row
        let changed = [previous, indexPath.row].compactMap { $0 }.map { IndexPath(row: $0, section: 0) }
        tableView.performBatchUpdates {
            for indexPath in Set(changed) {
                (tableView.cellForRow(at: indexPath) as? FAQCell)?
                    .configure(with: items[indexPath.row], isExpanded: expandedIndex == indexPath.row, animated: true)
            }
        }
    }
}
