import UIKit
import XCTest
import Libmpv

final class MPVScreenshotTests: XCTestCase {
    
    private var player: MPVTestPlayer!
    private var videoPath: String!
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        
        // 获取测试视频路径
        let bundle = Bundle(for: type(of: self))
        videoPath = bundle.path(forResource: "input", ofType: "mp4")
        
        if videoPath == nil {
            // 尝试其他路径
            let altPaths = [
                bundle.bundlePath + "/input.mp4",
                bundle.resourcePath! + "/input.mp4"
            ]
            for path in altPaths {
                if FileManager.default.fileExists(atPath: path) {
                    videoPath = path
                    break
                }
            }
        }
        
        print("[Test] 视频路径: \(videoPath ?? "未找到")")
        print("[Test] 视频存在: \(videoPath != nil && FileManager.default.fileExists(atPath: videoPath))")
        
        player = MPVTestPlayer()
    }
    
    override func tearDown() {
        player = nil
        super.tearDown()
    }
    
    func testScreenshotAtProgress() {
        // 确保视频文件存在
        XCTAssertNotNil(videoPath, "测试视频文件不存在")
        XCTAssertTrue(FileManager.default.fileExists(atPath: videoPath), "视频文件不存在于: \(videoPath!)")
        
        // 加载视频
        player.loadVideo(path: videoPath)
        
        // 等待文件加载完成的期望
        let loadExpectation = expectation(description: "等待视频加载")
        loadExpectation.assertForOverFulfill = false
        
        // 延迟检查文件是否加载
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            loadExpectation.fulfill()
        }
        
        wait(for: [loadExpectation], timeout: 10.0)
        
        // 截图期望
        let screenshotExpectation = expectation(description: "截图完成")
        
        // 在 20% 进度处截图
        player.takeScreenshotAtProgress(0.2) { result in
            switch result {
            case .success(let image):
                XCTAssertNotNil(image, "截图图像不应为 nil")
                XCTAssertGreaterThan(image.size.width, 0, "图像宽度应大于0")
                XCTAssertGreaterThan(image.size.height, 0, "图像高度应大于0")
                print("[Test] 截图成功: \(Int(image.size.width))x\(Int(image.size.height))")
                
            case .failure(let error):
                XCTFail("截图失败: \(error.localizedDescription)")
            }
            screenshotExpectation.fulfill()
        }
        
        wait(for: [screenshotExpectation], timeout: 30.0)
    }
    
}

// MARK: - MPV Test Player

class MPVTestPlayer: NSObject {
    
    private var mpv: OpaquePointer?
    private var isFileLoaded: Bool = false
    private var videoDuration: Double = 0
    
    override init() {
        super.init()
        setupMPV()
    }
    
    deinit {
        cleanup()
    }
    
    private func setupMPV() {
        mpv = mpv_create()
        guard let mpv = mpv else { return }
        
        // CI/模拟器友好配置
        mpv_set_option_string(mpv, "vo", "sws")          // 软件渲染
        mpv_set_option_string(mpv, "ao", "null")         // 静音
        mpv_set_option_string(mpv, "hwdec", "no")        // 禁用硬解码
        mpv_set_option_string(mpv, "force-window", "no") // 无窗口
        mpv_set_option_string(mpv, "terminal", "yes")
        mpv_set_option_string(mpv, "keep-open", "yes")   // 播放完后保持打开
        mpv_request_log_messages(mpv, "info")
        
        guard mpv_initialize(mpv) >= 0 else { return }
        
        // 观察关键属性
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 1, "pause", MPV_FORMAT_FLAG)
        
        startEventLoop()
    }
    
    private func startEventLoop() {
        guard let mpv = mpv else { return }
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            while let mpv = self.mpv {
                let event = mpv_wait_event(mpv, 0.1)
                if event?.pointee.event_id == MPV_EVENT_NONE { continue }
                self.handleMPVEvent(event!)
            }
        }
    }
    
    private func handleMPVEvent(_ event: UnsafePointer<mpv_event>) {
        switch event.pointee.event_id {
        case MPV_EVENT_FILE_LOADED:
            isFileLoaded = true
            print("[mpv] 文件加载完成")
        case MPV_EVENT_PROPERTY_CHANGE:
            if let prop = event.pointee.data?.assumingMemoryBound(to: mpv_event_property.self).pointee,
               let cname = prop.name,
               String(cString: cname) == "duration",
               let ptr = prop.data?.assumingMemoryBound(to: Double.self) {
                videoDuration = ptr.pointee
                print("[mpv] 视频时长: \(videoDuration) 秒")
            }
        case MPV_EVENT_END_FILE:
            isFileLoaded = false
        default: break
        }
    }
    
    func loadVideo(path: String) {
        guard let mpv = mpv else { return }
        print("[mpv] 加载视频: \(path), 文件存在: \(FileManager.default.fileExists(atPath: path))")
        isFileLoaded = false
        videoDuration = 0
        mpv_command_string(mpv, "loadfile \"\(path)\"")
    }
    
    func takeScreenshotAtProgress(_ progress: Double, completion: @escaping (Result<UIImage, Error>) -> Void) {
        waitForFileLoaded { [weak self] loaded in
            guard let self = self else { return }
            guard loaded, self.videoDuration > 0 else {
                print("[mpv] 文件未加载完成: isFileLoaded=\(self.isFileLoaded), duration=\(self.videoDuration)")
                completion(.failure(NSError(domain: "MPV", code: -1, userInfo: [NSLocalizedDescriptionKey: "文件未加载完成"])))
                return
            }
            
            let time = progress * self.videoDuration
            // 使用 Documents 目录以便 GitHub Actions 能找到截图
            let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let filePath = documentsDir.appendingPathComponent("screenshot_\(Int(progress * 100)).png").path
            print("[mpv] 截图保存路径: \(filePath)")
            print("[mpv] seek 到时间: \(time) 秒 (进度: \(Int(progress * 100))%)")
            
            guard let mpv = self.mpv else {
                completion(.failure(NSError(domain: "MPV", code: -2, userInfo: [NSLocalizedDescriptionKey: "MPV未初始化"])))
                return
            }
            
            // 精确 seek 到 progress 位置
            mpv_command_string(mpv, "seek \(time) absolute+exact")
            
            // 延迟确保帧渲染
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.0) {
                let result = mpv_command_string(mpv, "screenshot-to-file \"\(filePath)\" video")
                print("[mpv] screenshot 命令结果: \(result)")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let data = FileManager.default.contents(atPath: filePath),
                       let image = UIImage(data: data) {
                        // 保留截图文件供 CI 上传，不删除
                        print("[mpv] 截图成功，大小: \(data.count) bytes")
                        print("[mpv] 截图尺寸: \(Int(image.size.width))x\(Int(image.size.height))")
                        completion(.success(image))
                    } else {
                        // 打印目录内容帮助调试
                        print("[mpv] 截图文件未生成: \(filePath)")
                        if let docContents = try? FileManager.default.contentsOfDirectory(atPath: documentsDir.path) {
                            print("[mpv] Documents目录内容: \(docContents)")
                        }
                        completion(.failure(NSError(domain: "MPV", code: -3, userInfo: [NSLocalizedDescriptionKey: "截图文件未生成"])))
                    }
                }
            }
        }
    }
    
    private func waitForFileLoaded(attempts: Int = 200, completion: @escaping (Bool) -> Void) {
        if isFileLoaded && videoDuration > 0 {
            print("[mpv] 文件已加载，时长: \(videoDuration)")
            completion(true)
            return
        }
        if attempts <= 0 {
            print("[mpv] 等待文件加载超时，isFileLoaded=\(isFileLoaded), duration=\(videoDuration)")
            completion(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.waitForFileLoaded(attempts: attempts - 1, completion: completion)
        }
    }
    
    private func cleanup() {
        if let mpv = mpv {
            mpv_terminate_destroy(mpv)
            self.mpv = nil
        }
    }
}
