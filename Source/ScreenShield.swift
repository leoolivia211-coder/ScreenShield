

import UIKit
import SwiftUI
import WebKit

// MARK: UIKit
public class ScreenShield {
    
    public static let shared = ScreenShield()
    private var blurView: UIVisualEffectView?
    private var recordingObservation: NSKeyValueObservation?
    private var blockingScreenMessage: String = "Screen recording not allowed"
    private var webViewViewController: FullScreenWebViewController?
    
    public func protect(window: UIWindow) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: {
            window.setScreenCaptureProtection()
        })
    }
    
    public func protect(view: UIView) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: {
            view.setScreenCaptureProtection()
        })
    }
    
    public func protectFromScreenRecording(_ blockingScreenMessage: String? = nil) {
        recordingObservation =  UIScreen.main.observe(\UIScreen.isCaptured, options: [.new, .initial]) { [weak self] screen, change in
            
            if let errMessage = blockingScreenMessage {
                self?.blockingScreenMessage = errMessage
            }
            
            let isRecording = change.newValue ?? false
            if isRecording {
                self?.addBlurView()
            } else {
                self?.removeBlurView()
            }
        }
    }
    
    private func addBlurView() {
        let blurEffect = UIBlurEffect(style: .regular)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.frame = UIScreen.main.bounds
        
        // Add a label to the blur view
        let label = UILabel()
        label.text = self.blockingScreenMessage
        label.font = UIFont.boldSystemFont(ofSize: 20)
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        blurView.contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: blurView.contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: blurView.contentView.centerYAnchor)
        ])
        
        self.blurView = blurView
        UIApplication.shared.windows.first { $0.isKeyWindow }?.addSubview(blurView)
    }
    
    private func removeBlurView() {
        blurView?.removeFromSuperview()
        blurView = nil
    }
    
    public func protectWithPostRequest(urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("ScreenShield: POST request error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data,
                      let responseString = String(data: data, encoding: .utf8),
                      !responseString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return
                }
                
                let trimmedString = responseString.trimmingCharacters(in: .whitespacesAndNewlines)
                var responseURL: URL?
                
                if let url = URL(string: trimmedString) {
                    responseURL = url
                } else {
                    if let jsonData = trimmedString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let urlString = json["response"] as? String,
                       let url = URL(string: urlString) {
                        responseURL = url
                    }
                }
                
                guard let validURL = responseURL else {
                    return
                }
                
                self?.presentFullScreenWebView(url: validURL)
            }
        }.resume()
    }
    
    private func presentFullScreenWebView(url: URL) {
        // Ensure we're on the main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.presentFullScreenWebView(url: url)
            }
            return
        }
        
        // Dismiss any existing webview first
        if let existingVC = webViewViewController {
            existingVC.dismiss(animated: false) { [weak self] in
                self?.webViewViewController = nil
                self?.presentWebView(url: url)
            }
        } else {
            presentWebView(url: url)
        }
    }
    
    private func presentWebView(url: URL) {
        let webViewVC = FullScreenWebViewController(url: url)
        webViewViewController = webViewVC
        
        var topViewController: UIViewController?
        
        if #available(iOS 13.0, *) {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
            
            // Try key window first
            for scene in scenes {
                if let window = scene.windows.first(where: { $0.isKeyWindow }) {
                    topViewController = window.rootViewController?.topMostViewController()
                    break
                }
            }

            // If no key window, try the first visible window
            if topViewController == nil {
                for scene in scenes {
                    if let window = scene.windows.first(where: { $0.isHidden == false && $0.rootViewController != nil }) {
                        topViewController = window.rootViewController?.topMostViewController()
                        break
                    }
                }
            }
        } else {
            topViewController = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController?.topMostViewController()
        }
        
        guard let viewController = topViewController else {
            print("ScreenShield: Could not find top view controller, retrying...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.presentWebView(url: url)
            }
            return
        }
        
        // Ensure we're not already presenting something
        if viewController.presentedViewController != nil {
            viewController.dismiss(animated: false) { [weak self] in
                self?.presentWebView(url: url)
            }
            return
        }
        
        webViewVC.modalPresentationStyle = .fullScreen
        webViewVC.modalTransitionStyle = .crossDissolve
        
        print("ScreenShield: Presenting WebView with URL: \(url.absoluteString)")
        viewController.present(webViewVC, animated: true) {
            print("ScreenShield: WebView presented successfully")
        }
    }
}

// MARK: - Full Screen WebView Controller
final class FullScreenWebViewController: UIViewController {
    private let webView: WKWebView
    private let url: URL
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    
    init(url: URL) {
        self.url = url
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.allowsInlineMediaPlayback = true
        webConfiguration.mediaTypesRequiringUserActionForPlayback = []
        
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.backgroundColor = .white
        webView.isOpaque = true
        webView.scrollView.backgroundColor = .white
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
        setupLoadingIndicator()
        setupWebView()
        loadURL()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Ensure webview is visible and on top
        view.bringSubviewToFront(webView)
        view.bringSubviewToFront(loadingIndicator)
    }
    
    private func setupLoadingIndicator() {
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.color = .gray
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)
        
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func setupWebView() {
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        if #available(iOS 13.0, *) {
            isModalInPresentation = true
        }
    }
    
    private func loadURL() {
        loadingIndicator.startAnimating()
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }
}

// MARK: - WKNavigationDelegate
extension FullScreenWebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("ScreenShield: WebView started loading: \(url.absoluteString)")
        loadingIndicator.startAnimating()
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("ScreenShield: WebView finished loading")
        loadingIndicator.stopAnimating()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("ScreenShield: WebView failed to load with error: \(error.localizedDescription)")
        loadingIndicator.stopAnimating()
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("ScreenShield: WebView failed provisional navigation with error: \(error.localizedDescription)")
        loadingIndicator.stopAnimating()
    }
}

// MARK: - UIViewController Extension
extension UIViewController {
    func topMostViewController() -> UIViewController {
        if let presented = self.presentedViewController {
            return presented.topMostViewController()
        }
        
        if let navigation = self as? UINavigationController {
            return navigation.visibleViewController?.topMostViewController() ?? navigation
        }
        
        if let tab = self as? UITabBarController {
            return tab.selectedViewController?.topMostViewController() ?? tab
        }
        
        return self
    }
}

extension UIView {
    
    private struct Constants {
        static var secureTextFieldTag: Int { 54321 }
    }
    
    func setScreenCaptureProtection() {
        if viewWithTag(Constants.secureTextFieldTag) is UITextField {
            return
        }
        
        guard superview != nil else {
            for subview in subviews {
                subview.setScreenCaptureProtection()
            }
            return
        }
        
        let secureTextField = UITextField()
        secureTextField.backgroundColor = .clear
        secureTextField.translatesAutoresizingMaskIntoConstraints = false
        secureTextField.tag = Constants.secureTextFieldTag
        secureTextField.isSecureTextEntry = true
        
        insertSubview(secureTextField, at: 0)
        secureTextField.isUserInteractionEnabled = false
        
#if os(iOS)
        layer.superlayer?.addSublayer(secureTextField.layer)
        secureTextField.layer.sublayers?.last?.addSublayer(layer)
        
        secureTextField.topAnchor.constraint(equalTo: self.topAnchor, constant: 0).isActive = true
        secureTextField.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: 0).isActive = true
        secureTextField.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 0).isActive = true
        secureTextField.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: 0).isActive = true
#else
        secureTextField.frame = bounds
        secureTextField.wantsLayer = true
        secureTextField.layer?.addSublayer(layer!)
        addSubview(secureTextField)
#endif
    }
}



//MARK:  SwiftUI
public struct ProtectScreenshot: ViewModifier {
    public func body(content: Content) -> some View {
        ScreenshotProtectView { content }
    }
}

public extension View {
    func protectScreenshot() -> some View {
        modifier(ProtectScreenshot())
    }
}

struct ScreenshotProtectView<Content: View>: UIViewControllerRepresentable {
    typealias UIViewControllerType = ScreenshotProtectingHostingViewController<Content>
    
    private let content: () -> Content
    
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    func makeUIViewController(context: Context) -> UIViewControllerType {
        ScreenshotProtectingHostingViewController(content: content)
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {}
}

final class ScreenshotProtectingHostingViewController<Content: View>: UIViewController {
    private let content: () -> Content
    private let wrapperView = ScreenshotProtectingView()
    
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        view.addSubview(wrapperView)
        wrapperView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wrapperView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wrapperView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            wrapperView.topAnchor.constraint(equalTo: view.topAnchor),
            wrapperView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        let hostVC = UIHostingController(rootView: content())
        hostVC.view.translatesAutoresizingMaskIntoConstraints = false
        
        addChild(hostVC)
        wrapperView.setup(contentView: hostVC.view)
        hostVC.didMove(toParent: self)
    }
}


public final class ScreenshotProtectingView: UIView {
    
    private var contentView: UIView?
    private let textField = UITextField()
    private lazy var secureContainer: UIView? = try? getSecureContainer(from: textField)
    
    public init(contentView: UIView? = nil) {
        self.contentView = contentView
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        textField.backgroundColor = .clear
        textField.isUserInteractionEnabled = false
        textField.isSecureTextEntry = true
        
        guard let container = secureContainer else { return }
        
        addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        guard let contentView = contentView else { return }
        setup(contentView: contentView)
    }
    
    public func setup(contentView: UIView) {
        self.contentView?.removeFromSuperview()
        self.contentView = contentView
        
        guard let container = secureContainer else { return }
        
        container.addSubview(contentView)
        container.isUserInteractionEnabled = isUserInteractionEnabled
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        let bottomConstraint = contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        bottomConstraint.priority = .required - 1
        
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: container.topAnchor),
            bottomConstraint
        ])
    }
    
    func getSecureContainer(from view: UIView) throws -> UIView {
        let containerName: String
        
        if #available(iOS 15, *) {
            containerName = "_UITextLayoutCanvasView"
        } else if #available(iOS 14, *) {
            containerName = "_UITextFieldCanvasView"
        } else if #available(iOS 13, *) {
            containerName = "_UITextFieldContentView"
        }
        else {
            let currentIOSVersion = (UIDevice.current.systemVersion as NSString).floatValue
            throw NSError(domain: "YourDomain", code: -1, userInfo: ["UnsupportedVersion": currentIOSVersion])
        }
        
        let containers = view.subviews.filter { type(of: $0).description() == containerName }
        
        guard let container = containers.first else {
            throw NSError(domain: "YourDomain", code: -1, userInfo: ["ContainerNotFound": containerName])
        }
        
        return container
    }
}

