// LibmpvWrapper - 自动链接 libmpv 所需的系统框架和库
//
// 用户只需 import Libmpv 即可使用，无需手动配置任何链接参数。
// 此 wrapper target 通过 linkerSettings 自动注入以下依赖：
//   - AVFoundation, AudioToolbox, CoreMedia, CoreVideo, VideoToolbox
//   - bz2, z, iconv

@_exported import LibmpvBinary
