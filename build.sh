#!/bin/bash

# 设置项目名称
PRODUCT_NAME="ai-translate"
CONFIGURATION="release"

# 清理之前的构建
swift package clean

# 构建 arm64 版本
swift build --configuration $CONFIGURATION --arch arm64

# 构建 x86_64 版本
swift build --configuration $CONFIGURATION --arch x86_64

# 创建输出目录
mkdir -p .build/universal

# 使用 lipo 合并二进制
lipo -create \
    .build/arm64-apple-macosx/$CONFIGURATION/$PRODUCT_NAME \
    .build/x86_64-apple-macosx/$CONFIGURATION/$PRODUCT_NAME \
    -output .build/universal/$PRODUCT_NAME

cp .build/arm64-apple-macosx/$CONFIGURATION/$PRODUCT_NAME .build/universal/$PRODUCT_NAME-arm64
cp .build/x86_64-apple-macosx/$CONFIGURATION/$PRODUCT_NAME .build/universal/$PRODUCT_NAME-amd64

echo "Universal binary created at: .build/universal/$PRODUCT_NAME"