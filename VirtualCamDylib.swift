import UIKit
import AVFoundation
import Foundation
import ObjectiveC
import CoreMedia

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
    print("[VirtualCamDylib] ✅ dylib constructor RUNNED! dylib loaded")
    swizzleCaptureVideoDataOutput()
    print("[VirtualCamDylib] ✅ swizzle done")

    // 延长延迟到2秒，适配抖音复杂启动流程
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        print("[VirtualCamDylib] ✅ start setup float button")
        setupFloatButton()
        showBootToast()
        print("[VirtualCamDylib] ✅ UI init finished")
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
        print("[VirtualCamDylib] ✅ FloatButton created")
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
                .compactMap({$0 as? UIWindowScene}).first else {
            print("[VirtualCamDylib] ❌ Cannot get foreground window scene")
            return
        }
        guard let topWin = winScene.windows.first else {
            print("[VirtualCamDylib] ❌ Cannot get top window")
            return
        }
        if g_floatBtn == nil {
            g_floatBtn = VirtualCamFloatButton()
            topWin.addSubview(g_floatBtn!)
            print("[VirtualCamDylib] ✅ FloatButton added to top window")
        } else {
            print("[VirtualCamDylib] ⚠️ FloatButton already exists")
        }
    }
}

// MARK: 启动提示弹窗
func showBootToast() {
    DispatchQueue.main.async {
        guard let rootVC = UIApplication.shared.connectedScenes
                .filter({ $0.activationState == .foregroundActive })
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first?.rootViewController else {
            print("[VirtualCamDylib] ❌ Cannot get rootVC for alert")
            return
        }
        let alert = UIAlertController(title:"虚拟摄像头已加载",
                                      message:"点击悬浮球唤出控制面板，切换本地MP4视频",
                                      preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"确定", style:.default))
        rootVC.present(alert, animated:true)
        print("[VirtualCamDylib] ✅ Boot alert presented")
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
            panel.heightAnchor.constraint(equalToConstant:420)
        ])
        print("[VirtualCamDylib] ✅ ControlWindow created")
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
        print("[VirtualCamDylib] ✅ ControlPanel UI setup")
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
        return 6
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier:"Cell", for:indexPath)
        switch indexPath.row {
        case 0:
            cell.textLabel?.text = "🔴 禁用虚拟摄像头"
            cell.textLabel?.textColor = .systemRed
            cell.accessoryType = (g_virtualVideoName == nil) ? .checkmark : .none
        case 1:
            cell.textLabel?.text = "▶ video1.mp4"
            cell.accessoryType = (g_virtualVideoName == "video1") ? .checkmark : .none
        case 2:
            cell.textLabel?.text = "▶ video2.mp4"
            cell.accessoryType = (g_virtualVideoName == "video2") ? .checkmark : .none
        case 3:
            cell.textLabel?.text = "▶ video3.mp4"
            cell.accessoryType = (g_virtualVideoName == "video3") ? .checkmark : .none
        case 4:
            cell.textLabel?.text = "▶ video4.mp4"
            cell.accessoryType = (g_virtualVideoName == "video4") ? .checkmark : .none
        case 5:
            cell.textLabel?.text = "▶ video5.mp4"
            cell.accessoryType = (g_virtualVideoName == "video5") ? .checkmark : .none
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
            enableVirtualCam(videoName: "video1")
        case 2:
            enableVirtualCam(videoName: "video2")
        case 3:
            enableVirtualCam(videoName: "video3")
        case 4:
            enableVirtualCam(videoName: "video4")
        case 5:
            enableVirtualCam(videoName: "video5")
        default: break
        }
        updateUI()
        g_controlWindow?.hide()
    }
}

// MARK: AVCaptureVideoDataOutput Swizzle
func swizzleCaptureVideoDataOutput() {
    let originalSel = #selector(AVCaptureVideoDataOutput.setSampleBufferDelegate(_:queue:))
    let swizzledSel = #selector(AVCaptureVideoDataOutput.trollfools_setSampleBufferDelegate(_:queue:))
    guard let originalMethod = class_getInstanceMethod(AVCaptureVideoDataOutput.self, originalSel),
          let swizzledMethod = class_getInstanceMethod(AVCaptureVideoDataOutput.self, swizzledSel) else {
        print("[VirtualCamDylib] ❌ swizzle failed")
        return
    }
    method_exchangeImplementations(originalMethod, swizzledMethod)
    print("[VirtualCamDylib] ✅ swizzle AVCaptureVideoDataOutput done")
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
            let alert = UIAlertController(title:"错误", message:"找不到 \(videoName).mp4，请放到App文档目录", preferredStyle:.alert)
            alert.addAction(UIAlertAction(title:"确定", style:.default))
            rootVC.present(alert, animated:true)
        }
        print("[VirtualCamDylib] ❌ Video file not found: \(videoName).mp4")
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
    print("[VirtualCamDylib] ✅ Enabled video：\(videoName)")
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
    print("[VirtualCamDylib] ✅ Virtual cam disabled")
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
