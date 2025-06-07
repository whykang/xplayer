import SwiftUI
import PhotosUI

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FeedbackViewModel()
    
    var body: some View {
        NavigationView {
            Group {
                if !viewModel.canAccessFeedback {
                    // 显示提交频率限制信息
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                            .padding(.bottom, 10)
                        
                        Text("提交频率限制")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("您已在近期提交过反馈，为了保证服务质量，请在\(viewModel.nextSubmissionTimeString)之后再次提交。")
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button(action: {
                            dismiss()
                        }) {
                            Text("返回")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .padding(.top, 20)
                        .padding(.horizontal, 40)
                    }
                    .padding()
                } else {
                    // 正常的反馈表单
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // 反馈类型选择
                            VStack(alignment: .leading, spacing: 10) {
                                Text("反馈类型")
                                    .font(.headline)
                                
                                Picker("反馈类型", selection: $viewModel.feedbackType) {
                                    ForEach(FeedbackViewModel.FeedbackType.allCases, id: \.self) { type in
                                        Text(type.description).tag(type)
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())
                            }
                            
                            // 反馈内容输入
                            VStack(alignment: .leading, spacing: 10) {
                                Text("描述")
                                    .font(.headline)
                                
                                ZStack(alignment: .topLeading) {
                                    TextEditor(text: $viewModel.content)
                                        .frame(minHeight: 150)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                    
                                    if viewModel.content.isEmpty {
                                        Text(viewModel.contentPlaceholder)
                                            .foregroundColor(.gray.opacity(0.8))
                                            .padding(.horizontal, 5)
                                            .padding(.top, 8)
                                            .allowsHitTesting(false)
                                    }
                                }
                            }
                            
                            // 联系方式（可选）
                            VStack(alignment: .leading, spacing: 10) {
                                Text("联系方式（可选）")
                                    .font(.headline)
                                
                                TextField("邮箱或其他联系方式", text: $viewModel.contactInfo)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                            
                            // 图片添加
                            VStack(alignment: .leading, spacing: 10) {
                                Text("添加截图（可选）")
                                    .font(.headline)
                                
                                if let selectedImage = viewModel.selectedImage {
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: selectedImage)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 200)
                                            .cornerRadius(8)
                                        
                                        Button(action: {
                                            viewModel.selectedImage = nil
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.title)
                                                .foregroundColor(.white)
                                                .background(Color.black.opacity(0.6))
                                                .clipShape(Circle())
                                        }
                                        .padding(8)
                                    }
                                } else {
                                    Button(action: {
                                        viewModel.showingImagePicker = true
                                    }) {
                                        HStack {
                                            Image(systemName: "photo")
                                            Text("添加图片")
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            
                            // 提交按钮
                            Button(action: {
                                viewModel.showSubmitConfirmation = true
                            }) {
                                HStack {
                                    if viewModel.isSubmitting {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Text("提交反馈")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(viewModel.canSubmit ? Color.blue : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .disabled(!viewModel.canSubmit || viewModel.isSubmitting)
                            .padding(.top, 20)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("反馈与建议")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .alert(isPresented: $viewModel.showingAlert) {
                Alert(
                    title: Text(viewModel.alertTitle),
                    message: Text(viewModel.alertMessage),
                    dismissButton: .default(Text("确定")) {
                        if case .success = viewModel.feedbackStatus {
                            dismiss()
                        }
                    }
                )
            }
            .alert("确认提交", isPresented: $viewModel.showSubmitConfirmation) {
                Button("取消", role: .cancel) { }
                Button("提交") {
                    viewModel.submitFeedback()
                }
            } message: {
                Text("确定要提交这条反馈吗？提交后将在3天内无法再次提交反馈。")
            }
            .sheet(isPresented: $viewModel.showingImagePicker) {
                ImagePicker(selectedImage: $viewModel.selectedImage, sourceType: .photoLibrary)
            }
            // 添加点击手势收起键盘
            .gesture(
                TapGesture()
                    .onEnded { _ in
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
            )
            .onAppear {
                viewModel.checkFeedbackAccess()
            }
        }
    }
}

// 反馈视图模型
class FeedbackViewModel: ObservableObject {
    enum FeedbackType: String, CaseIterable {
        case suggestion = "suggestion"
        case bug = "bug"
        case other = "other"
        
        var description: String {
            switch self {
            case .suggestion: return "功能建议"
            case .bug: return "问题反馈"
            case .other: return "其他"
            }
        }
    }
    
    @Published var feedbackType: FeedbackType = .suggestion
    @Published var content: String = ""
    @Published var contactInfo: String = ""
    @Published var selectedImage: UIImage? = nil
    @Published var showingImagePicker = false
    @Published var showingAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published var isSubmitting = false
    @Published var feedbackStatus: FeedbackService.FeedbackStatus = .idle
    @Published var showSubmitConfirmation = false
    @Published var canAccessFeedback = true
    @Published var nextSubmissionTimeString = ""
    
    var contentPlaceholder: String {
        switch feedbackType {
        case .suggestion:
            return "请描述您希望添加的功能或改进建议..."
        case .bug:
            return "请描述您遇到的问题，以及如何重现这个问题..."
        case .other:
            return "请输入您的反馈内容..."
        }
    }
    
    var canSubmit: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    func checkFeedbackAccess() {
        if !FeedbackService.shared.canSubmitFeedback() {
            canAccessFeedback = false
            
            // 格式化下次可提交的时间
            if let nextTime = FeedbackService.shared.getNextFeedbackTime() {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                nextSubmissionTimeString = formatter.string(from: nextTime)
            } else {
                nextSubmissionTimeString = "3天后"
            }
        } else {
            canAccessFeedback = true
        }
    }
    
    func submitFeedback() {
        guard canSubmit else { return }
        
        isSubmitting = true
        feedbackStatus = .submitting
        
        // 准备提交的内容
        var fullContent = "类型: \(feedbackType.description)\n\n"
        fullContent += "内容: \(content)\n\n"
        
        if !contactInfo.isEmpty {
            fullContent += "联系方式: \(contactInfo)\n\n"
        }
        
        // 添加设备信息
        fullContent += FeedbackService.shared.getDeviceInfo()
        
        // 提交反馈
        FeedbackService.shared.submitFeedback(content: fullContent, image: selectedImage) { [weak self] status in
            guard let self = self else { return }
            
            self.isSubmitting = false
            self.feedbackStatus = status
            
            switch status {
            case .success:
                self.alertTitle = "提交成功"
                self.alertMessage = "感谢您的反馈，我们会认真考虑您的建议。"
            case .failure(let message):
                self.alertTitle = "提交失败"
                self.alertMessage = "反馈提交失败: \(message)"
            default:
                break
            }
            
            self.showingAlert = true
        }
    }
} 