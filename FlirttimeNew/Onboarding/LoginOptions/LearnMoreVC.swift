import UIKit
import WebKit

class LearnMoreVC: UIViewController {
    var webView: WKWebView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Create WKWebView
        webView = WKWebView(frame: view.bounds)
        view.addSubview(webView)
        
        // Load HTML file
        if let htmlPath = Bundle.main.path(forResource: "email", ofType: "html") {
            let url = URL(fileURLWithPath: htmlPath)
            let request = URLRequest(url: url)
            webView.load(request)
        } else {
            print("HTML file not found")
        }
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        webView.frame = view.bounds
    }
}
