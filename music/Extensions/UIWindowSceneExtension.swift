import UIKit

extension UIWindowScene {
    var keyWindow: UIWindow? {
        // iOS 15及以上推荐这种方式
        return windows.first(where: { $0.isKeyWindow })
    }
}

// 便捷函数获取根视图控制器
func getRootViewController() -> UIViewController? {
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
       let rootViewController = windowScene.keyWindow?.rootViewController {
        return rootViewController
    }
    return nil
} 