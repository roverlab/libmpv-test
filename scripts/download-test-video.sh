#!/bin/sh
set -e

# 下载测试用的小视频文件（用于 CI 截图测试）
# 使用一个公开的小型测试视频

echo "=== Downloading test video ==="

TEST_VIDEO_DIR="$ROOT/Tests/Resources"
mkdir -p "$TEST_VIDEO_DIR"

# Big Buck Bunny 64x64 极小版本 (约几秒，几百KB)
# 使用一个公开的、稳定的小视频 URL
VIDEO_URL="https://www.w3schools.com/html/mov_bbb.mp4"
VIDEO_PATH="$TEST_VIDEO_DIR/input.mp4"

if [ -f "$VIDEO_PATH" ]; then
    echo "Test video already exists: $VIDEO_PATH"
    ls -la "$VIDEO_PATH"
    exit 0
fi

echo "Downloading test video from $VIDEO_URL..."
curl -f -L -o "$VIDEO_PATH" "$VIDEO_URL"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to download test video"
    exit 1
fi

if [ ! -f "$VIDEO_PATH" ]; then
    echo "ERROR: Video file was not created"
    exit 1
fi

FILE_SIZE=$(stat -f%z "$VIDEO_PATH" 2>/dev/null || stat -c%s "$VIDEO_PATH" 2>/dev/null)
echo "Test video downloaded successfully: $VIDEO_PATH ($FILE_SIZE bytes)"

# 验证文件是有效的 MP4
file "$VIDEO_PATH"
