#!/bin/bash

# AI Translate 安装脚本
# 版本: v1.0.0

set -e  # 遇到错误时退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的信息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查系统架构和操作系统
detect_system() {
    print_info "检测系统信息..."
    
    # 检测操作系统
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        print_error "不支持的操作系统: $OSTYPE"
        exit 1
    fi
    
    # 检测架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            print_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    
    print_success "系统: $OS, 架构: $ARCH"
}

# 检查依赖
check_dependencies() {
    print_info "检查依赖..."
    
    # 检查 curl 或 wget
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
    else
        print_error "需要安装 curl 或 wget"
        exit 1
    fi
    
    print_success "下载工具: $DOWNLOADER"
}

# 下载文件
download_file() {
    local url=$1
    local output=$2
    
    print_info "正在下载 $url ..."
    
    if [[ "$DOWNLOADER" == "curl" ]]; then
        curl -L -o "$output" "$url"
    else
        wget -O "$output" "$url"
    fi
    
    if [[ $? -eq 0 ]]; then
        print_success "下载完成"
    else
        print_error "下载失败"
        exit 1
    fi
}

# 主安装函数
install_ai_translate() {
    print_info "开始安装 AI Translate..."
    
    # 下载 URL
    DOWNLOAD_URL="https://github.com/kimliss/fork-AITranslate/releases/download/v1.0.0/ai-translate-$ARCH"
    
    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    TEMP_FILE="$TEMP_DIR/ai-translate"
    
    # 下载文件
    download_file "$DOWNLOAD_URL" "$TEMP_FILE"
    
    # 设置安装目录
    if [[ "$OS" == "linux" ]]; then
        # Linux 系统优先使用 /usr/local/bin
        if [[ -w "/usr/local/bin" ]]; then
            INSTALL_DIR="/usr/local/bin"
        elif [[ -w "$HOME/.local/bin" ]]; then
            INSTALL_DIR="$HOME/.local/bin"
            mkdir -p "$INSTALL_DIR"
        else
            INSTALL_DIR="$HOME/bin"
            mkdir -p "$INSTALL_DIR"
        fi
    else
        # macOS 系统
        if [[ -w "/usr/local/bin" ]]; then
            INSTALL_DIR="/usr/local/bin"
        else
            INSTALL_DIR="$HOME/.local/bin"
            mkdir -p "$INSTALL_DIR"
        fi
    fi
    
    # 复制文件到安装目录
    print_info "安装到 $INSTALL_DIR ..."
    cp "$TEMP_FILE" "$INSTALL_DIR/ai-translate"
    chmod +x "$INSTALL_DIR/ai-translate"
    
    # 清理临时文件
    rm -rf "$TEMP_DIR"
    
    print_success "安装完成！"
    
    # 检查 PATH
    check_path
    
    # 验证安装
    verify_installation
}

# 检查 PATH 设置
check_path() {
    print_info "检查 PATH 设置..."
    
    if echo "$PATH" | grep -q "$INSTALL_DIR"; then
        print_success "$INSTALL_DIR 已在 PATH 中"
    else
        print_warning "$INSTALL_DIR 不在 PATH 中"
        print_info "正在自动配置 PATH..."
        
        # 自动添加到 shell 配置
        add_to_path
    fi
}

# 自动添加到 PATH
add_to_path() {
    local shell_configs=()
    
    # 检测可能的 shell 配置文件
    if [[ -f "$HOME/.zshrc" ]]; then
        shell_configs+=("$HOME/.zshrc")
    fi
    if [[ -f "$HOME/.bashrc" ]]; then
        shell_configs+=("$HOME/.bashrc")
    fi
    if [[ -f "$HOME/.bash_profile" ]]; then
        shell_configs+=("$HOME/.bash_profile")
    fi
    if [[ -f "$HOME/.profile" ]]; then
        shell_configs+=("$HOME/.profile")
    fi
    
    # 如果没有找到配置文件，创建 .profile
    if [[ ${#shell_configs[@]} -eq 0 ]]; then
        shell_configs=("$HOME/.profile")
        touch "$HOME/.profile"
        print_info "创建了 $HOME/.profile"
    fi
    
    # 自动添加到第一个找到的配置文件
    local shell_config="${shell_configs[0]}"
    
    # 检查是否已经添加过
    if ! grep -q "export PATH.*$INSTALL_DIR" "$shell_config" 2>/dev/null; then
        print_info "正在添加到 $shell_config ..."
        echo "" >> "$shell_config"
        echo "# AI Translate PATH - Added by install script" >> "$shell_config"
        echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$shell_config"
        print_success "已自动添加到 $shell_config"
        print_info "请运行以下命令使配置生效："
        print_info "  source $shell_config"
        print_info "或者重新打开终端"
    else
        print_info "$shell_config 中已存在 PATH 配置"
    fi
}

# 验证安装
verify_installation() {
    print_info "验证安装..."
    
    if [[ -x "$INSTALL_DIR/ai-translate" ]]; then
        print_success "ai-translate 安装成功！"
        print_info "安装路径: $INSTALL_DIR/ai-translate"
        
        # 尝试运行版本检查
        if command -v ai-translate >/dev/null 2>&1; then
            print_info "可以直接使用命令: ai-translate"
        else
            print_info "使用完整路径: $INSTALL_DIR/ai-translate"
        fi
    else
        print_error "安装验证失败"
        exit 1
    fi
}

# 卸载函数
uninstall_ai_translate() {
    print_info "正在卸载 AI Translate..."
    
    # 查找可能的安装位置
    local locations=(
        "/usr/local/bin/ai-translate"
        "$HOME/.local/bin/ai-translate"
        "$HOME/bin/ai-translate"
    )
    
    local found=false
    for location in "${locations[@]}"; do
        if [[ -f "$location" ]]; then
            print_info "删除 $location"
            rm -f "$location"
            found=true
        fi
    done
    
    if [[ "$found" == true ]]; then
        print_success "卸载完成！"
    else
        print_warning "未找到已安装的 ai-translate"
    fi
}

# 显示帮助信息
show_help() {
    echo "AI Translate 安装脚本"
    echo ""
    echo "用法:"
    echo "  $0 [选项]"
    echo ""
    echo "选项:"
    echo "  install     安装 ai-translate (默认)"
    echo "  uninstall   卸载 ai-translate"
    echo "  help        显示此帮助信息"
    echo ""
}

# 主函数
main() {
    case "${1:-install}" in
        "install")
            detect_system
            check_dependencies
            install_ai_translate
            ;;
        "uninstall")
            uninstall_ai_translate
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            print_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"