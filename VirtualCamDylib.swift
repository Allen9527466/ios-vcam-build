import UIKit
import AVFoundation
import Foundation
import ObjectiveC

// dylib加载入口
@_cdecl("constructor")
func constructor() {
    print("[VirtualCamDylib] dylib loaded")
    swizzleCaptureVideoDataOutput()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        showVirtualCamAlert()
    }
}

// MARK: 全局状态
var g_virtualVideoName: String? = nil
var g_videoPlayer: AVPlayer?
var g_videoOutput: AVPlayerItemVideoOutput?
var g_displayLink: CADisplayLink?
private var loopObserver: NSObjectProtocol?

// 关联key，用于把代理对象绑定到AVCaptureVideoDataOutput实例
private var kProxyDelegateKey: UInt8 = 0

// MARK: Swizzle AVCaptureVideoDataOutput setSampleBufferDelegate
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
        // 调用原始方法
        self.trollfools_setSampleBufferDelegate(delegate, queue: queue)
        
        guard let originalDel = delegate else {
            objc_setAssociatedObject(self, &kProxyDelegateKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return
        }
        
        // 创建代理包装器，绑定到当前output实例，避免野指针
        let proxy = VirtualCamProxyDelegate()
        proxy.originalDelegate = originalDel
        objc_setAssociatedObject(self, &kProxyDelegateKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        // 把output的delegate指向我们的proxy
        self.setSampleBufferDelegate(proxy, queue: queue)
    }
}

// MARK: 弹窗选择视频
func showVirtualCamAlert() {
    DispatchQueue.main.async {
        guard let rootVC = UIApplication.shared.keyWindow?.rootViewController else {
            print("[VirtualCamDylib] no root vc")
            return
        }
        let alert = UIAlertController(title: "TrollFools虚拟摄像头", message: "仅当前App生效", preferredStyle: .actionSheet)
        
        let videos = ["video1","video2","video3","video4","video5"]
        for name in videos {
            alert.addAction(UIAlertAction(title: name, style: .default, handler: { _ in
                enableVirtualCam(videoName: name)
            }))
        }
        alert.addAction(UIAlertAction(title: "禁用虚拟摄像头", style: .destructive, handler: { _ in
            disableVirtualCam()
        }))
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        rootVC.present(alert, animated: true)
    }
}

// MARK: 启用虚拟摄像头
func enableVirtualCam(videoName: String) {
    disableVirtualCam()
    do {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let videoURL = docDir.appendingPathComponent("\(videoName).mp4")
        
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw NSError(domain: "VirtualCam", code: -1, userInfo: [NSLocalizedDescriptionKey:"找不到 \(videoName).mp4，请放入Documents目录"])
        }
        
        g_virtualVideoName = videoName
        let playerItem = AVPlayerItem(url: videoURL)
        g_videoPlayer = AVPlayer(playerItem: playerItem)
        
        let outputSettings: [String:Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        g_videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        playerItem.add(g_videoOutput!)
        
        // 循环播放通知（修复：保存observer句柄用于移除）
        loopObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { _ in
            g_videoPlayer?.seek(to: .zero)
            g_videoPlayer?.play()
        }
        
        g_videoPlayer?.play()
        print("[VirtualCamDylib] 已启用虚拟视频：\(videoName)")
    } catch {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "错误", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            UIApplication.shared.keyWindow?.rootViewController?.present(alert, animated: true)
        }
    }
}

// MARK: 关闭虚拟摄像头
func disableVirtualCam() {
    g_virtualVideoName = nil
    g_videoPlayer?.pause()
    g_videoPlayer = nil
    g_videoOutput = nil
    g_displayLink?.invalidate()
    g_displayLink = nil
    // 修复：用保存的observer移除通知
    if let obs = loopObserver {
        NotificationCenter.default.removeObserver(obs)
        loopObserver = nil
    }
    print("[VirtualCamDylib] 虚拟摄像头已关闭")
}

// MARK: 获取虚拟帧 SampleBuffer，全部做异常防护
func getVirtualSampleBuffer() -> CMSampleBuffer? {
    do {
        guard let output = g_videoOutput else { return nil }
        let time = CMTimeMakeWithSeconds(CACurrentMediaTime(), preferredTimescale: 600)
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else {
            return nil
        }
        
        var formatDesc: CMFormatDescription?
        let status = CMFormatDescriptionCreate(kCFAllocatorDefault, kCMFormatDescriptionType_Video, pixelBuffer, nil, &formatDesc)
        guard status == noErr, let desc = formatDesc else {
            return nil
        }
        
        let timing = CMSampleTimingInfo(
            duration: CMTimeMake(value: 1, timescale: 30),
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let bufStatus = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, true, nil, nil, desc, timing, &sampleBuffer)
        guard bufStatus == noErr else {
            return nil
        }
        return sampleBuffer
    } catch {
        print("[VirtualCamDylib] getVirtualSampleBuffer exception: \(error)")
        return nil
    }
}

// MARK: 代理包装器，做异常捕获，防止闪退
class VirtualCamProxyDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    weak var originalDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?
    
    func captureOutput(_ output: AVCaptureVideoDataOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        do {
            // 如果开启虚拟摄像头，尝试替换帧；失败则回退原生
            if g_virtualVideoName != nil, let virtualBuf = getVirtualSampleBuffer() {
                originalDelegate?.captureOutput(output, didOutput: virtualBuf, from: connection)
            } else {
                originalDelegate?.captureOutput(output, didOutput: sampleBuffer, from: connection)
            }
        } catch {
            print("[VirtualCamDylib] proxy delegate crash guard: \(error)")
            // 发生异常，直接透传原始帧，保证App不闪退
            originalDelegate?.captureOutput(output, didOutput: sampleBuffer, from: connection)
        }
    }
}
