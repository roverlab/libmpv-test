import LibffmpegBinary

/// Libffmpeg — FFmpeg 音视频编解码库封装
///
/// 此模块提供对 FFmpeg (libavcodec, libavformat, libavutil, libswresample, libswscale)
/// 和 dav1d (AV1 解码器) 的 Swift 接口。
///
/// ## 使用方式
///
/// ### 作为独立编解码库使用：
/// ```swift
/// import Libffmpeg
/// // 直接调用 FFmpeg C API
/// ```
///
### ### 与 Libmpv 配合使用（自动链接）：
/// ```swift
/// import Libmpv  // 自动包含 Libffmpeg
/// ```

// MARK: - FFmpeg Version Info

/// 获取 FFmpeg 编译配置信息
public func ffmpegConfiguration() -> String {
    let ptr = avcodec_configuration()
    return String(cString: ptr!)
}

/// 获取 libavcodec 版本号
public func avCodecVersion() -> Int {
    return Int(avcodec_version())
}

/// 获取 libavformat 版本号
public func avFormatVersion() -> Int {
    return Int(avformat_version())
}

/// 获取 libavutil 版本号
public func avUtilVersion() -> Int {
    return Int(avutil_version())
}
