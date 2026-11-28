import UIKit

/// The address bar: no pill at rest, like desktop Derp; it fills in with an
/// accent ring while you type. A quiet search glyph marks it, or the mask in
/// private tabs.
final class AddressField: UITextField {
    private let glyph = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        placeholder = "Search or enter address"
        font = .systemFont(ofSize: 16)
        keyboardType = .webSearch
        returnKeyType = .go
        autocapitalizationType = .none
        autocorrectionType = .no
        smartQuotesType = .no
        smartDashesType = .no
        spellCheckingType = .no
        clearButtonMode = .whileEditing
        textContentType = .URL
        accessibilityLabel = "Address bar"
        glyph.contentMode = .center
        let holder = UIView(frame: CGRect(x: 0, y: 0, width: 38, height: 42))
        glyph.frame = CGRect(x: 12, y: 12, width: 18, height: 18)
        holder.addSubview(glyph)
        leftView = holder
        leftViewMode = .always
        layer.cornerRadius = 21
        layer.cornerCurve = .continuous
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError() }

    func paint(_ palette: Palette, private isPrivate: Bool) {
        textColor = palette.text
        tintColor = palette.accent
        attributedPlaceholder = NSAttributedString(string: placeholder ?? "", attributes: [.foregroundColor: palette.dim])
        glyph.image = Icon.named(isPrivate ? "mask" : "search")
        glyph.tintColor = isPrivate ? palette.accent : palette.dim
        backgroundColor = isFirstResponder ? palette.fieldFocus : .clear
        layer.borderWidth = isFirstResponder ? 1.5 : 0
        layer.borderColor = palette.accent.cgColor
        keyboardAppearance = palette.dark ? .dark : .light
    }

    override func clearButtonRect(forBounds bounds: CGRect) -> CGRect {
        super.clearButtonRect(forBounds: bounds).offsetBy(dx: -6, dy: 0)
    }

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        super.textRect(forBounds: bounds).inset(by: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 10))
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect { textRect(forBounds: bounds) }
}

/// The hairline between the page and the toolbar, with desktop Derp's
/// loading shimmer: a short lime-teal-blue streak sweeping along it while a
/// page loads. The hairline is on the page's side.
final class ProgressLine: UIView {
    private let hairline = CALayer()
    private let streak = CAGradientLayer()
    var lineAtTop = true { didSet { setNeedsLayout() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(hairline)
        layer.addSublayer(streak)
        streak.startPoint = CGPoint(x: 0, y: 0.5)
        streak.endPoint = CGPoint(x: 1, y: 0.5)
        streak.opacity = 0
        isUserInteractionEnabled = false
        accessibilityIdentifier = "progress"
        paintStreak()
    }

    required init?(coder: NSCoder) { fatalError() }

    func colors(line: UIColor, background: UIColor) {
        hairline.backgroundColor = line.cgColor
        backgroundColor = background
    }

    /// Rainbow mode (Just for fun): the streak is a rainbow.
    var rainbow = false {
        didSet { if rainbow != oldValue { paintStreak() } }
    }

    private func paintStreak() {
        func c(_ hex: String) -> CGColor { UIColor(hex: hex).cgColor }
        if rainbow {
            streak.colors = ["#00FF5E5E", "#FFFF5E5E", "#FFFFB84D", "#FFFFE14D", "#FF6EE36E", "#FF4DC3FF", "#FF8A7DFF", "#FFE66EFF", "#00E66EFF"].map(c)
            streak.locations = [0, 0.12, 0.25, 0.38, 0.5, 0.62, 0.75, 0.88, 1]
        } else {
            streak.colors = ["#00C6F57E", "#FF72E4A2", "#FF2FD6BE", "#FF2F9ED7", "#002F6FEB"].map(c)
            streak.locations = [0, 0.25, 0.45, 0.75, 1]
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let line = 1 / max(UIScreen.main.scale, 1) * 2
        hairline.frame = CGRect(x: 0, y: lineAtTop ? 0 : bounds.height - line / 2, width: bounds.width, height: line / 2)
        let still = !Gag.motion
        streak.frame = CGRect(x: 0, y: 0, width: still ? bounds.width : bounds.width * 0.35, height: bounds.height)
        streak.cornerRadius = bounds.height / 2
        if busy { animate() }
    }

    var busy = false {
        didSet {
            guard busy != oldValue else { return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.45)
            streak.opacity = busy ? 1 : 0
            CATransaction.commit()
            if busy { animate() } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                    if self?.busy == false { self?.streak.removeAnimation(forKey: "sweep") }
                }
            }
        }
    }

    private func animate() {
        guard Gag.motion, bounds.width > 0 else { return }
        streak.removeAnimation(forKey: "sweep")
        let length = bounds.width * 0.35
        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -length / 2
        sweep.toValue = bounds.width * 1.05 + length / 2
        sweep.duration = 1.15
        sweep.repeatCount = .infinity
        sweep.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.55, 1)
        streak.add(sweep, forKey: "sweep")
    }
}

/// The tabs button (narrow windows): how many tabs, in a rounded square.
final class TabsButton: UIButton {
    private let count = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        count.font = .systemFont(ofSize: 11, weight: .semibold)
        count.textAlignment = .center
        count.layer.borderWidth = 1.5
        count.layer.cornerRadius = 5
        count.translatesAutoresizingMaskIntoConstraints = false
        count.isUserInteractionEnabled = false
        addSubview(count)
        NSLayoutConstraint.activate([
            count.centerXAnchor.constraint(equalTo: centerXAnchor),
            count.centerYAnchor.constraint(equalTo: centerYAnchor),
            count.widthAnchor.constraint(equalToConstant: 21),
            count.heightAnchor.constraint(equalToConstant: 21),
        ])
        accessibilityLabel = "Tabs"
    }

    required init?(coder: NSCoder) { fatalError() }

    func paint(count n: Int, palette: Palette) {
        count.text = n > 99 ? ":D" : String(n)
        count.textColor = palette.icon
        count.layer.borderColor = palette.icon.cgColor
        accessibilityValue = "\(n)"
    }
}

/// Your dork, round, in the toolbar or the tab strip.
final class AvatarButton: UIButton {
    let face = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        face.contentMode = .scaleAspectFill
        face.clipsToBounds = true
        face.layer.cornerRadius = 14
        face.isUserInteractionEnabled = false
        face.translatesAutoresizingMaskIntoConstraints = false
        addSubview(face)
        NSLayoutConstraint.activate([
            face.centerXAnchor.constraint(equalTo: centerXAnchor),
            face.centerYAnchor.constraint(equalTo: centerYAnchor),
            face.widthAnchor.constraint(equalToConstant: 28),
            face.heightAnchor.constraint(equalToConstant: 28),
        ])
        accessibilityLabel = "Your dork"
    }

    required init?(coder: NSCoder) { fatalError() }

    func paint(_ picture: UIImage?, palette: Palette) {
        face.image = picture
    }
}

/// A tab in the tab strip. The one in front is desktop Derp's folder tab: the
/// toolbar's color, outlined by a hairline whose feet curve out into the
/// strip's bottom line (Derp for Android's FolderTab draws the same).
final class FolderTab: UIControl {
    static let foot: CGFloat = 10
    private let lip: CGFloat = 6
    var front = false { didSet { setNeedsDisplay() } }
    var fill = UIColor.white
    var edge = UIColor.gray
    let icon = UIImageView()
    let label = UILabel()
    let close = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        icon.contentMode = .scaleAspectFit
        label.font = .systemFont(ofSize: 14)
        close.setImage(Icon.named("close"), for: .normal)
        close.accessibilityLabel = "Close tab"
        for view in [icon, label, close] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let r = FolderTab.foot
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: r + 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 3),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            close.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 2),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(r + 2)),
            close.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 28),
            close.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func outline(_ w: CGFloat, _ bottom: CGFloat) -> UIBezierPath {
        let r = FolderTab.foot
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: bottom))
        path.addArc(withCenter: CGPoint(x: 0, y: bottom - r), radius: r, startAngle: .pi / 2, endAngle: 0, clockwise: false)
        path.addLine(to: CGPoint(x: r, y: lip + r))
        path.addArc(withCenter: CGPoint(x: 2 * r, y: lip + r), radius: r, startAngle: .pi, endAngle: 1.5 * .pi, clockwise: true)
        path.addLine(to: CGPoint(x: w - 2 * r, y: lip))
        path.addArc(withCenter: CGPoint(x: w - 2 * r, y: lip + r), radius: r, startAngle: 1.5 * .pi, endAngle: 2 * .pi, clockwise: true)
        path.addLine(to: CGPoint(x: w - r, y: bottom - r))
        path.addArc(withCenter: CGPoint(x: w, y: bottom - r), radius: r, startAngle: .pi, endAngle: .pi / 2, clockwise: false)
        return path
    }

    override func draw(_ rect: CGRect) {
        let hair = 1 / max(UIScreen.main.scale, 1)
        if front {
            let shape = outline(bounds.width, bounds.height)
            shape.close()
            fill.setFill()
            shape.fill()
            let line = outline(bounds.width, bounds.height - hair / 2)
            line.lineWidth = hair
            edge.setStroke()
            line.stroke()
        } else if isHighlighted {
            edge.withAlphaComponent(0.4).setFill()
            UIBezierPath(roundedRect: bounds.insetBy(dx: FolderTab.foot, dy: 0).inset(by: UIEdgeInsets(top: lip, left: 0, bottom: 5, right: 0)), cornerRadius: 8).fill()
        }
    }

    override var isHighlighted: Bool { didSet { setNeedsDisplay() } }
}

/// The tab strip (wide windows): your tabs and a new tab button, and your
/// dork in the corner.
final class TabStrip: UIView {
    private let scroll = UIScrollView()
    private let line = UIView()
    private let newTab = UIButton(type: .system)
    private var tabViews: [FolderTab] = []
    private var shown = ""
    var avatar: AvatarButton? {
        didSet {
            guard let avatar else { return }
            avatar.translatesAutoresizingMaskIntoConstraints = false
            addSubview(avatar)
            NSLayoutConstraint.activate([
                avatar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                avatar.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1),
                avatar.widthAnchor.constraint(equalToConstant: 44),
                avatar.heightAnchor.constraint(equalToConstant: 44),
            ])
        }
    }
    var onSelect: ((Tab) -> Void)?
    var onClose: ((Tab, UIView) -> Void)?
    var onNew: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = false
        addSubview(line)
        addSubview(scroll)
        newTab.setImage(Icon.named("plus"), for: .normal)
        newTab.accessibilityLabel = "Open a new tab"
        newTab.addAction(UIAction { [weak self] _ in self?.onNew?() }, for: .touchUpInside)
        scroll.addSubview(newTab)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let hair = 1 / max(UIScreen.main.scale, 1)
        line.frame = CGRect(x: -100, y: bounds.height - hair, width: bounds.width + 200, height: hair)
        scroll.frame = CGRect(x: 6, y: 0, width: bounds.width - 6 - 52, height: bounds.height)
        place()
    }

    private func place() {
        let foot = FolderTab.foot
        let count = max(1, tabViews.count)
        // Tabs share the room up to desktop's tab width; past that the strip scrolls.
        let room = scroll.bounds.width - 40
        let body = min(232, max(112, room / CGFloat(count) - foot))
        var x: CGFloat = 0
        for view in tabViews {
            view.frame = CGRect(x: x, y: 0, width: body + 2 * foot, height: bounds.height)
            x += body + foot
        }
        newTab.frame = CGRect(x: x + foot + 2, y: (bounds.height - 34) / 2 + 3, width: 34, height: 34)
        scroll.contentSize = CGSize(width: newTab.frame.maxX + 6, height: bounds.height)
        if let front = tabViews.first(where: \.front) {
            scroll.bringSubviewToFront(front)
            scroll.scrollRectToVisible(front.frame.insetBy(dx: -8, dy: 0), animated: false)
        }
    }

    /// Rebuilt when a tab's title, address or place changes.
    func fill(_ window: BrowserViewController) {
        guard !isHidden else { return }
        let palette = window.palette
        let browser = window.browser
        let key = browser.tabs.map { "\(ObjectIdentifier($0)) \($0.isPrivate) \($0 === browser.current) \($0.asleep) \(window.tabTitle($0))" }.joined(separator: "\n")
            + palette.toolbar.hex + palette.text.hex + palette.accent.hex
        backgroundColor = palette.frame
        line.backgroundColor = palette.line
        newTab.tintColor = palette.icon
        guard key != shown else { return }
        shown = key
        tabViews.forEach { $0.removeFromSuperview() }
        tabViews = browser.tabs.map { tab in
            let view = FolderTab()
            let selected = tab === browser.current
            view.front = selected
            view.fill = palette.toolbar
            view.edge = palette.line
            let (image, tint) = window.icon(tab)
            view.icon.image = image
            view.icon.tintColor = tint
            view.label.text = window.tabTitle(tab)
            view.label.textColor = selected ? palette.text : palette.dim
            view.label.font = selected ? .medium(14) : .systemFont(ofSize: 14)
            view.close.isHidden = !selected
            view.close.tintColor = palette.icon
            view.alpha = tab.asleep ? 0.55 : 1
            view.accessibilityLabel = window.tabTitle(tab)
            view.accessibilityTraits = selected ? [.button, .selected] : .button
            view.isAccessibilityElement = true
            view.addAction(UIAction { [weak self] _ in self?.onSelect?(tab) }, for: .touchUpInside)
            view.close.addAction(UIAction { [weak self, weak view] _ in
                guard let view else { return }
                self?.onClose?(tab, view.close)
            }, for: .touchUpInside)
            scroll.addSubview(view)
            return view
        }
        place()
    }
}

/// The tabs view (narrow windows): like desktop's tabs, the one in front is a
/// card the toolbar's color, the rest sit flat.
final class TabsPanel: UIView {
    private let header = UIStackView()
    private let titleLabel = UILabel()
    private let list = UIStackView()
    private let scroll = UIScrollView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "tabs panel"
        titleLabel.text = "Tabs"
        titleLabel.font = .medium(22)
        header.axis = .horizontal
        header.alignment = .center
        header.addArrangedSubview(titleLabel)
        list.axis = .vertical
        list.spacing = 4
        for view in [header, scroll] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        list.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(list)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 22),
            header.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -10),
            header.heightAnchor.constraint(equalToConstant: 48),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
            scroll.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            list.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            list.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            list.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 10),
            list.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private var built = false

    func fill(_ window: BrowserViewController) {
        let base = Palette.of(dark: window.dark, private: false)
        let browser = window.browser
        backgroundColor = base.frame
        titleLabel.textColor = base.text
        if !built {
            built = true
            for (icon, label, isPrivate) in [("mask", "New private tab", true), ("plus", "Open a new tab", false)] {
                let button = window.iconButton(icon, label) { [weak window] in
                    window?.closeTabs()
                    window?.browser.newTab(nil, private: isPrivate)
                }
                button.tintColor = base.icon
                button.widthAnchor.constraint(equalToConstant: 44).isActive = true
                header.addArrangedSubview(button)
            }
        }
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for tab in browser.tabs {
            let selected = tab === browser.current
            let card = UIControl()
            card.backgroundColor = selected ? base.toolbar : .clear
            card.layer.cornerRadius = 12
            card.layer.cornerCurve = .continuous
            card.layer.borderWidth = selected ? 1 / UIScreen.main.scale : 0
            card.layer.borderColor = base.line.cgColor
            card.alpha = tab.asleep ? 0.55 : 1
            card.accessibilityLabel = window.tabTitle(tab)
            card.addAction(UIAction { [weak window] _ in
                window?.browser.select(tab)
                window?.closeTabs()
            }, for: .touchUpInside)
            let (image, tint) = window.icon(tab)
            let icon = UIImageView(image: image)
            icon.tintColor = tint
            icon.contentMode = .scaleAspectFit
            let title = UILabel()
            title.text = window.tabTitle(tab)
            title.font = selected ? .medium(15) : .systemFont(ofSize: 15)
            title.textColor = base.text
            let sub = UILabel()
            let place = browser.display(tab)
            sub.text = [tab.isPrivate ? "Private" : nil, place.isEmpty ? nil : place].compactMap { $0 }.joined(separator: " · ").ifEmpty("Derp")
            sub.font = .systemFont(ofSize: 13)
            sub.textColor = base.dim
            let words = UIStackView(arrangedSubviews: [title, sub])
            words.axis = .vertical
            words.isUserInteractionEnabled = false
            let close = window.iconButton("close", "Close tab") {}
            close.tintColor = base.icon
            close.addAction(UIAction { [weak window, weak close] _ in
                if let close { window?.ghost(from: close) }
                window?.browser.close(tab)
            }, for: .touchUpInside)
            for view in [icon, words, close] as [UIView] {
                view.translatesAutoresizingMaskIntoConstraints = false
                card.addSubview(view)
            }
            icon.isUserInteractionEnabled = false
            NSLayoutConstraint.activate([
                card.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
                icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
                icon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18),
                icon.heightAnchor.constraint(equalToConstant: 18),
                words.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
                words.centerYAnchor.constraint(equalTo: card.centerYAnchor),
                words.topAnchor.constraint(greaterThanOrEqualTo: card.topAnchor, constant: 10),
                close.leadingAnchor.constraint(equalTo: words.trailingAnchor, constant: 4),
                close.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -4),
                close.centerYAnchor.constraint(equalTo: card.centerYAnchor),
                close.widthAnchor.constraint(equalToConstant: 44),
                close.heightAnchor.constraint(equalToConstant: 44),
            ])
            list.addArrangedSubview(card)
        }
        if let profile = DerpApp.shared.setup.profile { titleLabel.text = "Tabs · \(profile)" }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

/// A short message near the bottom of the window, like Android's toasts.
final class Toast: UILabel {
    static func show(_ text: String, in view: UIView, above bottom: CGFloat, palette: Palette) {
        view.subviews.compactMap { $0 as? Toast }.forEach { $0.removeFromSuperview() }
        let toast = Toast()
        toast.text = text
        toast.numberOfLines = 0
        toast.textAlignment = .center
        toast.font = .medium(14)
        toast.textColor = palette.dark ? UIColor(hex: "#1D1D1F") : .white
        toast.backgroundColor = palette.dark ? UIColor(hex: "#ECECEC") : UIColor(hex: "#1D1D1F")
        toast.layer.cornerRadius = 18
        toast.layer.cornerCurve = .continuous
        toast.clipsToBounds = true
        toast.accessibilityIdentifier = "toast"
        let width = min(view.bounds.width - 48, 420)
        let size = toast.sizeThatFits(CGSize(width: width - 36, height: .greatestFiniteMagnitude))
        let w = min(width, size.width + 36), h = size.height + 18
        toast.frame = CGRect(x: (view.bounds.width - w) / 2, y: view.bounds.height - bottom - h - 16, width: w, height: h)
        toast.alpha = 0
        view.addSubview(toast)
        UIView.animate(withDuration: 0.16) { toast.alpha = 1 }
        UIView.animate(withDuration: 0.3, delay: 2.4, options: [], animations: { toast.alpha = 0 }) { _ in toast.removeFromSuperview() }
    }
}
