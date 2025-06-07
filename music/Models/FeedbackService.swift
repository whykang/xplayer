import SwiftUI
import UIKit

class FeedbackService {
    static let shared = FeedbackService()
    
    enum FeedbackStatus {
        case idle
        case submitting
        case success
        case failure(String)
    }
    
    // 用于保存上次成功提交反馈的时间的UserDefaults键
    private let lastFeedbackTimeKey = "lastFeedbackSubmissionTime"
    // 设置提交反馈的最小间隔时间为3天
    private let minimumFeedbackInterval: TimeInterval = 3 * 24 * 60 * 60 // 3天的秒数
    
    // 检查是否可以提交反馈
    func canSubmitFeedback() -> Bool {
        if let lastSubmissionTime = UserDefaults.standard.object(forKey: lastFeedbackTimeKey) as? Date {
            let timeElapsed = Date().timeIntervalSince(lastSubmissionTime)
            return timeElapsed >= minimumFeedbackInterval
        }
        return true // 如果没有提交记录，允许提交
    }
    
    // 获取最近一次提交反馈的时间
    func getLastFeedbackTime() -> Date? {
        return UserDefaults.standard.object(forKey: lastFeedbackTimeKey) as? Date
    }
    
    // 获取下次可提交反馈的时间
    func getNextFeedbackTime() -> Date? {
        guard let lastTime = getLastFeedbackTime() else { return nil }
        return lastTime.addingTimeInterval(minimumFeedbackInterval)
    }
    
    // 记录反馈提交时间
    private func recordFeedbackSubmission() {
        UserDefaults.standard.set(Date(), forKey: lastFeedbackTimeKey)
    }
    
    // 获取设备信息
    func getDeviceInfo() -> String {
        let device = UIDevice.current
        let systemName = device.systemName
        let systemVersion = device.systemVersion
        let deviceModel = deviceModelName()
        
        return "设备型号: \(deviceModel)\n系统: \(systemName) \(systemVersion)"
    }
    
    // 获取更具体的设备型号信息
    private func deviceModelName() -> String {
        #if targetEnvironment(simulator)
        return "Simulator"
        #else
        var size: size_t = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let identifier = String(cString: machine)
        
        // 常见的iPhone设备标识符映射
        let modelMap: [String: String] = [
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max"
        ]
        
        if let model = modelMap[identifier] {
            return model
        } else {
            // 如果找不到对应的具体型号，则返回原始标识符
            return identifier
        }
        #endif
    }
    
    func submitFeedback(content: String, image: UIImage?, completion: @escaping (FeedbackStatus) -> Void) {
        // 检查提交频率
        if !canSubmitFeedback() {
            let nextTime = getNextFeedbackTime()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            let nextTimeStr = nextTime != nil ? formatter.string(from: nextTime!) : "未知时间"
            completion(.failure("提交频率过高，请在\(nextTimeStr)之后再试"))
            return
        }
        //需要自己实现
        let url = URL(string: "")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // 文本内容
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"content\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(content)\r\n".data(using: .utf8)!)

        // 图片上传（如果有）
        if let image = image,
           let imageData = image.jpegData(compressionQuality: 0.8) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"image\"; filename=\"feedback.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        // 发送请求
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error.localizedDescription))
                    return
                }
                
                // 服务器返回确认
                if let data = data {
                    // 打印原始响应用于调试
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("原始服务器响应: \(responseString)")
                    }
                    
                    do {
                        if let result = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                            print("反馈提交结果：\(result)")
                            
                            if let status = result["status"] as? String {
                                if status == "success" {
                                    // 记录成功提交的时间
                                    self.recordFeedbackSubmission()
                                    completion(.success)
                                    return
                                } else if let message = result["message"] as? String {
                                    // 尝试解码Unicode转义序列
                                    if let decodedMessage = self.decodeUnicodeEscapes(message) {
                                        completion(.failure(decodedMessage))
                                    } else {
                                        completion(.failure(message))
                                    }
                                    return
                                }
                            }
                        }
                        
                        // 服务器返回不是预期的JSON格式，暂时默认为成功
                        // 记录成功提交的时间
                        self.recordFeedbackSubmission()
                        completion(.success)
                    } catch {
                        completion(.failure("解析服务器响应失败"))
                    }
                } else {
                    completion(.failure("服务器无响应"))
                }
            }
        }.resume()
    }
    
    // 解码Unicode转义序列
    private func decodeUnicodeEscapes(_ input: String) -> String? {
        let pattern = "\\\\u([0-9a-fA-F]{4})"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        var result = input
        let matches = regex.matches(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count))
        
        for match in matches.reversed() {
            if let range = Range(match.range(at: 1), in: input) {
                let hexString = String(input[range])
                if let scalar = UInt32(hexString, radix: 16),
                   let unicodeScalar = Unicode.Scalar(scalar) {
                    let char = String(unicodeScalar)
                    let fullRange = Range(match.range, in: input)!
                    result = result.replacingOccurrences(of: input[fullRange], with: char)
                }
            }
        }
        
        return result
    }
} 
