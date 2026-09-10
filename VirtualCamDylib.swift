import UIKit
import AVFoundation
import Foundation
import ObjectiveC
import CoreMedia
import UniformTypeIdentifiers

// 外部引用Obj‑C代理类
@_silgen_name("VirtualCamProxyDelegate_alloc")
func VirtualCamProxyDelegate_alloc(_ orig: AnyObject) -> AnyObject

var g_virtualVideoName: String? = nil
var g_videoPlayer: AVPlayer?
var g_videoOutput: AVPlayerItemVideoOutput?
var g_displayLink: CADisplayLink?
private var loopObserver: NSObjectProtocol?
private var kProxyDelegateKey: UInt8 = 0

var g_floatBtn: VirtualCamFloatButton?
var g_controlWindow: VirtualCamControlWindow?

@_cdecl("constructor")
func constructor() {
    print("[VirtualCamDylib] dylib loaded")
    swizzleCaptureVideoDataOutput()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
        setupFloatButton()
        addTwoFingerLongPressGesture()
        showBootToast()
    }
}

// MARK: 悬浮拖拽小球
class VirtualCamFloatButton: UIView {
    private let btnSize: CGFloat = 44
    private var startPoint: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: CGRect(x:20, y:250, width: btnSize, height: btnSize))
        backgroundColor = UIColor.systemBlue.withAlphaComponent(0.75)
        layer.cornerRadius = btnSize/2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 6

        let tap = UITapGestureRecognizer(target:self, action:#selector(tapSelf))
        addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target:self, action:#selector(panHandle(_:)))
        addGestureRecognizer(pan)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    @objc func tapSelf() {
        g_controlWindow?.toggle()
    }

    @objc func panHandle(_ gesture:UIPanGestureRecognizer) {
        let trans = gesture.translation(in:self.superview)
        switch gesture.state {
        case .began:
            startPoint = self.center
        case .changed:
            self.center = CGPoint(x: startPoint.x + trans.x, y: startPoint.y + trans.y)
        case .ended, .cancelled:
            guard let sup = self.superview else { return }
            let midX = sup.bounds.midX
            var targetX: CGFloat
            if self.center.x < midX {
                targetX = btnSize/2 + 8
            } else {
                targetX = sup.bounds.width - btnSize/2 - 8
            }
            UIView.animate(withDuration:0.22) {
                self.center.x = targetX
            }
        default: break
        }
    }
}

func setupFloatButton() {
    DispatchQueue.main.async {
        guard let winScene = UIApplication.shared.connectedScenes
                .filter({$0.activationState == .foregroundActive})
                .compactMap({$0 as? UIWindowScene}).first,
              let topWin = winScene.windows.first else { return }
        if g_floatBtn == nil {
            g_floatBtn = VirtualCamFloatButton()
            topWin.addSubview(g_floatBtn!)
        }
    }
}

// MARK: 双指长按唤起面板
func addTwoFingerLongPressGesture() {
    DispatchQueue.main.async {
        guard let winScene = UIApplication.shared.connectedScenes
                .filter({$0.activationState == .foregroundActive})
                .compactMap({$0 as? UIWindowScene}).first,
              let topWin = winScene.windows.first else { return }
        let longPress = UILongPressGestureRecognizer(target: nil, action:#selector(handleTwoFingerLong(_:)))
        longPress.minimumNumberOfTouches = 2
        longPress.minimumPressDuration = 0.6
        longPress.allowableMovement = 35
        topWin.addGestureRecognizer(longPress)
    }
}
@objc func handleTwoFingerLong(_ gesture:UILongPressGestureRecognizer) {
    guard gesture.state == .began else { return }
    g_controlWindow?.toggle()
}

// MARK: 启动提示弹窗
func showBootToast() {
    DispatchQueue.main.async {
        guard let rootVC = UIApplication.shared.connectedScenes
                .filter({ $0.activationState == .foregroundActive })
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first?.rootViewController else { return }
        let alert = UIAlertController(title:"虚拟摄像头已加载",
                                      message:"点击悬浮球 / 双指长按唤出控制面板，支持相册选择MP4",
                                      preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"确定", style:.default))
        rootVC.present(alert, animated:true)
    }
}

// MARK: 控制面板窗口
class VirtualCamControlWindow: UIWindow {
    private let panel = VirtualCamControlPanel()
    override init(frame: CGRect) {
        super.init(frame:frame)
        if let scene = UIApplication.shared.connectedScenes
            .filter({$0.activationState == .foregroundActive})
            .compactMap({$0 as? UIWindowScene}).first {
            self.windowScene = scene
        }
        rootViewController = UIViewController()
        rootViewController?.view.backgroundColor = .clear
        isHidden = true
        addSubview(panel)
        panel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo:centerXAnchor),
            panel.centerYAnchor.constraint(equalTo:centerYAnchor),
            panel.widthAnchor.constraint(equalToConstant:330),
            panel.heightAnchor.constraint(equalToConstant:480)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    func show(){ isHidden=false; panel.updateUI() }
    func hide(){ isHidden=true }
    func toggle(){ isHidden ? show() : hide() }
}

class VirtualCamControlPanel: UIView {
    private let titleLabel = UILabel()
    private let closeBtn = UIButton(type:.system)
    private let tableView = UITableView()

    override init(frame:CGRect) {
        super.init(frame:frame)
        setupUI()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    private func setupUI() {
        backgroundColor = UIColor.systemBackground.withAlphaComponent(0.96)
        layer.cornerRadius = 18
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 12

        titleLabel.text = "虚拟摄像头控制"
        titleLabel.font = UIFont.boldSystemFont(ofSize:18)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        closeBtn.setTitle("关闭", for:.normal)
        closeBtn.addTarget(self, action:#selector(onClose), for:.touchUpInside)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeBtn)

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier:"Cell")
        tableView.separatorStyle = .singleLine
        tableView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tableView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo:topAnchor,constant:18),
            titleLabel.centerXAnchor.constraint(equalTo:centerXAnchor),

            closeBtn.topAnchor.constraint(equalTo:topAnchor,constant:18),
            closeBtn.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-18),

            tableView.topAnchor.constraint(equalTo:titleLabel.bottomAnchor,constant:18),
            tableView.leadingAnchor.constraint(equalTo:leadingAnchor,constant:12),
            tableView.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-12),
            tableView.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-12)
        ])
    }
    @objc private func onClose() {
        g_controlWindow?.hide()
    }
    func updateUI() {
        tableView.reloadData()
    }
}

extension VirtualCamControlPanel: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 7
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier:"Cell", for:indexPath)
        switch indexPath.row {
        case 0:
            cell.textLabel?.text = "🔴 禁用虚拟摄像头"
            cell.textLabel?.textColor = .systemRed
            cell.accessoryType = (g_virtualVideoName == nil) ? .checkmark : .none
        case 1:
            cell.textLabel?.text = "📁 从相册选择MP4"
            cell.textLabel?.textColor = .systemBlue
            cell.accessoryType = .none
        case 2:
            cell.textLabel?.text = "▶ 相册选中视频.mp4"
            cell.accessoryType = (g_virtualVideoName == "user_video") ? .checkmark : .none
        case 3,4,5,6:
            let idx = indexPath.row - 2
            let name = "video\(idx)"
            cell.textLabel?.text = "▶ \(name).mp4"
            cell.accessoryType = (g_virtualVideoName == name) ? .checkmark : .none
        default: break
        }
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at:indexPath, animated:true)
        switch indexPath.row {
        case 0:
            disableVirtualCam()
            updateUI()
        case 1:
            g_controlWindow?.hide()
            openVideoPicker()
            return
        case 2:
            enableVirtualCam(videoName: "user_video")
        case 3,4,5,6:
            let idx = indexPath.row - 2
            enableVirtualCam(videoName: "video\(idx)")
        default: break
        }
        updateUI()
        g_controlWindow?.hide()
    }
}

// MARK: UIImagePicker 相册选视频
class VideoPickerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    static let shared = VideoPickerDelegate()
    private override init(){}

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated:true)
        guard let videoUrl = info[.mediaURL] as? URL else {
            print("[VirtualCam] 获取相册视频URL失败")
            return
        }
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destUrl = docDir.appendingPathComponent("user_video.mp4")
        try? FileManager.default.removeItem(at: destUrl)
        do {
            try FileManager.default.copyItem(at: videoUrl, to: destUrl)
            print("[VirtualCam] 相册视频保存成功 user_video.mp4")
            DispatchQueue.main.async {
                enableVirtualCam(videoName:"user_video")
            }
        } catch {
            print("[VirtualCam] 复制视频失败: \(error)")
        }
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated:true)
    }
}

func openVideoPicker() {
    DispatchQueue.main.async {
        guard let rootVC = UIApplication.shared.connectedScenes
                .filter({ $0.activationState == .foregroundActive })
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first?.rootViewController else { return }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = [kUTTypeMovie as String]
        picker.delegate = VideoPickerDelegate.shared
        rootVC.present(picker, animated:true)
    }
}

// MARK: AVCaptureVideoDataOutput Swizzle
func swizzleCaptureVideoDataOutput() {
    let originalSel = #selector(AVCaptureVideoDataOutput.setSampleBufferDelegate(_:queue:))
    let swizzledSel = #selector(AVCaptureVideoDataOutput.trollfools_setSampleBufferDelegate(_:queue:))
    guard let originalMethod = class_getInstanceMethod(AVCaptureVideoDataOutput.self, originalSel),
          let swizzledMethod = class_getInstanceMethod(AVCaptureVideoDataOutput.self, swizzledSel) else {
        print("[VirtualCamDylib] swizzle failed")
        return
    }
    method_exchangeImplementations(originalMethod, swizzledMethod)
}

extension AVCaptureVideoDataOutput {
    @objc func trollfools_setSampleBufferDelegate(_ delegate: AVCaptureVideoDataOutputSampleBufferDelegate?, queue: DispatchQueue?) {
        self.trollfools_setSampleBufferDelegate(delegate, queue: queue)
        guard let originalDel = delegate else {
            objc_setAssociatedObject(self, &kProxyDelegateKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return
        }
        let proxy = VirtualCamProxyDelegate_alloc(originalDel as AnyObject)
        objc_setAssociatedObject(self, &kProxyDelegateKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        self.setSampleBufferDelegate(proxy as? AVCaptureVideoDataOutputSampleBufferDelegate, queue: queue)
    }
}

// MARK: 视频播放逻辑
func enableVirtualCam(videoName: String) {
    disableVirtualCam()
    let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let videoURL = docDir.appendingPathComponent("\(videoName).mp4")
    guard FileManager.default.fileExists(atPath: videoURL.path) else {
        DispatchQueue.main.async {
            guard let rootVC = UIApplication.shared.connectedScenes
                    .filter({ $0.activationState == .foregroundActive })
                    .compactMap({ $0 as? UIWindowScene })
                    .first?.windows.first?.rootViewController else { return }
            let alert = UIAlertController(title:"错误", message:"找不到 \(videoName).mp4", preferredStyle:.alert)
            alert.addAction(UIAlertAction(title:"确定", style:.default))
            rootVC.present(alert, animated:true)
        }
        return
    }
    g_virtualVideoName = videoName
    let playerItem = AVPlayerItem(url: videoURL)
    g_videoPlayer = AVPlayer(playerItem: playerItem)
    let pixelAttr: [String:Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    g_videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelAttr)
    playerItem.add(g_videoOutput!)
    loopObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { _ in
        g_videoPlayer?.seek(to: .zero)
        g_videoPlayer?.play()
    }
    g_videoPlayer?.play()
    print("[VirtualCamDylib] 启用视频：\(videoName)")
}

func disableVirtualCam() {
    g_virtualVideoName = nil
    g_videoPlayer?.pause()
    g_videoPlayer = nil
    g_videoOutput = nil
    g_displayLink?.invalidate()
    g_displayLink = nil
    if let obs = loopObserver {
        NotificationCenter.default.removeObserver(obs)
        loopObserver = nil
    }
    print("[VirtualCamDylib] 虚拟摄像头关闭")
}

func getVirtualSampleBuffer() -> CMSampleBuffer? {
    guard let output = g_videoOutput else { return nil }
    let time = CMTimeMakeWithSeconds(CACurrentMediaTime(), preferredTimescale: 600)
    guard let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return nil }

    var formatDesc: CMFormatDescription?
    let mediaType: FourCharCode = 0x76696465
    let status = CMFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        mediaType: mediaType,
        mediaSubType: CVPixelBufferGetPixelFormatType(pixelBuffer),
        extensions: nil,
        formatDescriptionOut: &formatDesc
    )
    guard status == noErr, let desc = formatDesc else { return nil }

    let timing = CMSampleTimingInfo(
        duration: CMTimeMake(value: 1, timescale: 30),
        presentationTimeStamp: time,
        decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    var timingInfo = timing
    let bufStatus = CMSampleBufferCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        dataReady: true,
        makeDataReadyCallback: nil,
        refcon: nil,
        formatDescription: desc,
        sampleTiming: &timingInfo,
        sampleBufferOut: &sampleBuffer
    )
    guard bufStatus == noErr, let sb = sampleBuffer else { return nil }
    return sb
}

// C接口给ObjC调用
@_cdecl("GetGlobalVirtualSampleBuffer")
func GetGlobalVirtualSampleBuffer() -> CMSampleBuffer? {
    guard g_virtualVideoName != nil, let buf = getVirtualSampleBuffer() else {
        return nil
    }
    return buf
}
