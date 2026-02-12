import UIKit

class MainViewController: UIViewController {

    private let titleLabel = UILabel()
    private let instructionsLabel = UILabel()
    private let stepsLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
    }

    private func setupUI() {
        titleLabel.text = "Better Keyboard"
        titleLabel.font = .systemFont(ofSize: 32, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        instructionsLabel.text = "To enable the circular keyboard:"
        instructionsLabel.font = .systemFont(ofSize: 18, weight: .medium)
        instructionsLabel.textAlignment = .center
        instructionsLabel.translatesAutoresizingMaskIntoConstraints = false

        let steps = """
        1. Open Settings
        2. Go to General → Keyboard → Keyboards
        3. Tap "Add New Keyboard..."
        4. Select "Better Keyboard"
        5. Switch to it in any text field using the globe key
        """
        stepsLabel.text = steps
        stepsLabel.font = .systemFont(ofSize: 16)
        stepsLabel.numberOfLines = 0
        stepsLabel.textColor = .secondaryLabel
        stepsLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(instructionsLabel)
        view.addSubview(stepsLabel)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),

            instructionsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionsLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 40),

            stepsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            stepsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            stepsLabel.topAnchor.constraint(equalTo: instructionsLabel.bottomAnchor, constant: 20),
        ])
    }
}
