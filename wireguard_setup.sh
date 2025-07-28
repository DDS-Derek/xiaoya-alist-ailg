#!/bin/bash

# WireGuard自动安装配置脚本
# 兼容xy_ailg.sh的日志风格

Green="\033[32m"
Red="\033[31m"
Yellow='\033[33m'
Blue='\033[34m'
Font="\033[0m"
INFO="[${Green}INFO${Font}]"
ERROR="[${Red}ERROR${Font}]"
WARN="[${Yellow}WARN${Font}]"

function INFO() {
    echo -e "${INFO} ${1}"
}
function ERROR() {
    echo -e "${ERROR} ${1}"
}
function WARN() {
    echo -e "${WARN} ${1}"
}

# 全局变量
WG_DIR="/etc/wireguard"
WG_CONFIG_DIR="${WG_DIR}/configs"
WG_KEYS_DIR="${WG_DIR}/keys"
WG_INTERFACE="wg0"
WG_PORT="51820"
WG_NETWORK="10.3.3.0/24"
WG_SERVER_IP="10.3.3.1"
PUBLIC_IP=""

# 检测操作系统和包管理器
detect_os() {
    # 检测特殊系统
    if [ -f /etc/synoinfo.conf ]; then
        OS="synology"
        WARN "检测到群晖系统，WireGuard安装可能需要特殊处理"
        return 1
    elif [ -f /etc/unraid-version ]; then
        OS="unraid"
        WARN "检测到Unraid系统，WireGuard安装可能需要特殊处理"
        return 1
    fi
    
    # 检测包管理器
    if command -v apt-get &> /dev/null; then
        PACKAGE_MANAGER="apt-get"
        OS="debian-based"
    elif command -v yum &> /dev/null; then
        PACKAGE_MANAGER="yum"
        OS="rhel-based"
    elif command -v dnf &> /dev/null; then
        PACKAGE_MANAGER="dnf"
        OS="fedora-based"
    elif command -v zypper &> /dev/null; then
        PACKAGE_MANAGER="zypper"
        OS="suse-based"
    elif command -v pacman &> /dev/null; then
        PACKAGE_MANAGER="pacman"
        OS="arch-based"
    elif command -v apk &> /dev/null; then
        PACKAGE_MANAGER="apk"
        OS="alpine"
    elif command -v opkg &> /dev/null; then
        PACKAGE_MANAGER="opkg"
        OS="openwrt-based"
    else
        ERROR "未找到支持的包管理器"
        return 1
    fi
    
    INFO "检测到系统类型: $OS，包管理器: $PACKAGE_MANAGER"
    return 0
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        ERROR "此脚本需要root权限运行"
        exit 1
    fi
}

# 检测并配置公网IP
configure_public_ip() {
    local external_ipv4
    local external_ipv6
    local selected_ip
    local ip_version

    # 获取外部检测到的IPv4地址
    INFO "正在检测IPv4地址..."
    external_ipv4=$(curl -s --max-time 10 ipv4.icanhazip.com 2>/dev/null || curl -s --max-time 10 -4 ifconfig.me 2>/dev/null || curl -s --max-time 10 -4 ip.sb 2>/dev/null)

    # 获取外部检测到的IPv6地址
    INFO "正在检测IPv6地址..."
    external_ipv6=$(curl -s --max-time 10 ipv6.icanhazip.com 2>/dev/null || curl -s --max-time 10 -6 ifconfig.me 2>/dev/null || curl -s --max-time 10 -6 ip.sb 2>/dev/null)

    # 显示检测结果
    echo -e "\n${Blue}=== IP地址检测结果 ===${Font}"
    if [[ -n "$external_ipv4" ]]; then
        INFO "检测到IPv4地址: $external_ipv4"
    else
        WARN "未检测到IPv4地址"
    fi

    if [[ -n "$external_ipv6" ]]; then
        INFO "检测到IPv6地址: $external_ipv6"
    else
        WARN "未检测到IPv6地址"
    fi

    # 选择IP版本
    local manual_input=false
    if [[ -n "$external_ipv4" && -n "$external_ipv6" ]]; then
        echo -e "\n${Yellow}检测到双栈网络环境，请选择使用的IP版本：${Font}"
        echo "1. IPv4: $external_ipv4"
        echo "2. IPv6: $external_ipv6"
        echo "3. 手动输入IP地址"
        read -p "请选择 [1-3, 默认: 1]: " ip_choice

        case "$ip_choice" in
            2)
                selected_ip="$external_ipv6"
                ip_version="ipv6"
                ;;
            3)
                read -p "请输入服务器公网IP地址: " selected_ip
                manual_input=true
                # 判断输入的是IPv4还是IPv6
                if [[ "$selected_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    ip_version="ipv4"
                elif [[ "$selected_ip" =~ : ]]; then
                    ip_version="ipv6"
                else
                    ERROR "无效的IP地址格式"
                    exit 1
                fi
                ;;
            *)
                selected_ip="$external_ipv4"
                ip_version="ipv4"
                ;;
        esac
    elif [[ -n "$external_ipv4" ]]; then
        echo -e "\n${Yellow}选择IP版本：${Font}"
        echo "1. 使用检测到的IPv4: $external_ipv4"
        echo "2. 手动输入IP地址"
        read -p "请选择 [1-2, 默认: 1]: " ip_choice

        if [[ "$ip_choice" == "2" ]]; then
            read -p "请输入服务器公网IP地址: " selected_ip
            manual_input=true
            if [[ "$selected_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                ip_version="ipv4"
            elif [[ "$selected_ip" =~ : ]]; then
                ip_version="ipv6"
            else
                ERROR "无效的IP地址格式"
                exit 1
            fi
        else
            selected_ip="$external_ipv4"
            ip_version="ipv4"
        fi
    elif [[ -n "$external_ipv6" ]]; then
        echo -e "\n${Yellow}选择IP版本：${Font}"
        echo "1. 使用检测到的IPv6: $external_ipv6"
        echo "2. 手动输入IP地址"
        read -p "请选择 [1-2, 默认: 1]: " ip_choice

        if [[ "$ip_choice" == "2" ]]; then
            read -p "请输入服务器公网IP地址: " selected_ip
            manual_input=true
            if [[ "$selected_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                ip_version="ipv4"
            elif [[ "$selected_ip" =~ : ]]; then
                ip_version="ipv6"
            else
                ERROR "无效的IP地址格式"
                exit 1
            fi
        else
            selected_ip="$external_ipv6"
            ip_version="ipv6"
        fi
    else
        WARN "无法自动获取外部IP，请手动输入"
        read -p "请输入服务器公网IP地址: " selected_ip
        manual_input=true
        if [[ "$selected_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            ip_version="ipv4"
        elif [[ "$selected_ip" =~ : ]]; then
            ip_version="ipv6"
        else
            ERROR "无效的IP地址格式"
            exit 1
        fi
    fi

    INFO "选择使用 $ip_version 地址: $selected_ip"

    # IPv6或手动输入时跳过WAN口IP比较
    if [[ "$ip_version" == "ipv6" ]]; then
        INFO "IPv6地址无需进行WAN口IP比较"
    elif [[ "$manual_input" == true ]]; then
        INFO "使用手动输入的IP地址"
    else
        # 仅对IPv4进行WAN口IP比较
        echo -e "\n${Yellow}请确认您的路由器WAN口IP地址：${Font}"
        echo "您可以登录路由器管理界面查看WAN口IP（注意：不是LAN口内网IP）"

        echo
        read -p "请输入您的路由器WAN口IP地址（与检测IP一致可按Y/y回车）: " user_wan_ip

        # 处理Y/y快捷确认
        if [[ "$user_wan_ip" =~ ^[Yy]$ ]]; then
            user_wan_ip="$selected_ip"
            INFO "已确认WAN口IP与检测IP一致: $selected_ip"
        fi

        # 比较外部IP和WAN口IP
        if [[ "$selected_ip" != "$user_wan_ip" ]]; then
            ERROR "检测到大内网环境！"
            echo -e "${Red}外部检测IP: $selected_ip${Font}"
            echo -e "${Red}路由器WAN口IP: $user_wan_ip${Font}"
            echo
            echo "当前服务器处于大内网环境（如运营商NAT），无法直接提供WireGuard服务"
            echo "解决方案："
            echo "1. 联系运营商申请公网IP"
            echo "2. 使用内网穿透服务（如frp、ngrok等）"
            echo "3. 使用云服务器搭建WireGuard"
            echo
            read -p "是否继续安装？(不推荐，客户端可能无法连接) (y/N): " force_install

            if [[ ! "$force_install" =~ ^[Yy]$ ]]; then
                echo "安装已取消"
                exit 1
            else
                WARN "强制继续安装，但客户端可能无法正常连接"
                PUBLIC_IP="$selected_ip"
                return
            fi
        fi

        INFO "检测到真实公网IP环境"
    fi

    # 询问是否为动态IP（无论是自动检测还是手动输入都需要确认）
    echo -e "\n${Blue}=== 公网IP类型确认 ===${Font}"
    echo "1. 静态公网IP (IP地址固定不变)"
    echo "2. 动态公网IP (IP地址会定期变化)"
    read -p "请选择您的公网IP类型 [1-2]: " ip_type

    if [[ "$ip_type" == "2" ]]; then
        echo -e "${Yellow}动态公网IP建议使用域名配置WireGuard，而不是直接使用IP地址${Font}"

        while true; do
            read -p "是否要使用域名配置？(y/N): " use_domain

            if [[ "$use_domain" =~ ^[Yy]$ ]]; then
                while true; do
                    read -p "请输入您的域名: " domain_name
                    if [[ -z "$domain_name" ]]; then
                        WARN "域名不能为空，请重新输入"
                        continue
                    fi

                    # 检查域名解析
                    INFO "正在检查域名解析..."
                    local domain_ip

                    if [[ "$ip_version" == "ipv4" ]]; then
                        # IPv4解析
                        domain_ip=$(nslookup "$domain_name" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | head -1)
                        if [[ -z "$domain_ip" ]]; then
                            # 尝试使用dig命令
                            domain_ip=$(dig +short "$domain_name" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
                        fi
                    else
                        # IPv6解析
                        domain_ip=$(nslookup "$domain_name" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | grep ":" | head -1)
                        if [[ -z "$domain_ip" ]]; then
                            # 尝试使用dig命令
                            domain_ip=$(dig +short "$domain_name" AAAA 2>/dev/null | grep ":" | head -1)
                        fi
                    fi

                    if [[ -z "$domain_ip" ]]; then
                        ERROR "无法解析域名 $domain_name 的 $ip_version 记录"
                        read -p "是否重新输入域名？(y/N): " retry_domain
                        if [[ ! "$retry_domain" =~ ^[Yy]$ ]]; then
                            break
                        fi
                        continue
                    fi

                    INFO "域名 $domain_name 解析到 $ip_version 地址: $domain_ip"

                    if [[ "$domain_ip" == "$selected_ip" ]]; then
                        INFO "域名解析IP与检测IP一致，可以使用"
                        PUBLIC_IP="$domain_name"
                        return
                    else
                        WARN "域名解析IP ($domain_ip) 与检测IP ($selected_ip) 不一致"
                        echo "这可能是因为："
                        echo "1. DDNS尚未更新到最新IP"
                        echo "2. 域名配置错误"
                        echo "3. DNS缓存问题"
                        echo
                        echo "建议："
                        echo "1. 确保DDNS服务正常工作并已更新"
                        echo "2. 等待DNS传播完成（可能需要几分钟到几小时）"
                        echo "3. 检查域名配置是否正确"
                        echo
                        read -p "选择操作: [1]重新输入域名 [2]配置好DDNS后再安装 [3]继续使用此域名: " domain_choice

                        case "$domain_choice" in
                            1)
                                continue
                                ;;
                            2)
                                echo "请配置好DDNS后重新运行安装脚本"
                                exit 1
                                ;;
                            3)
                                WARN "继续使用域名 $domain_name，但可能导致连接问题"
                                echo "请确保在安装完成后配置好DDNS，否则客户端可能无法连接"
                                PUBLIC_IP="$domain_name"
                                return
                                ;;
                            *)
                                WARN "无效选择，重新输入域名"
                                continue
                                ;;
                        esac
                    fi
                done
                break
            else
                WARN "使用动态IP地址配置可能导致客户端连接失败"
                echo "当IP地址变化时，需要重新生成客户端配置"
                break
            fi
        done
    fi

    PUBLIC_IP="$selected_ip"
}

# 获取公网IP（兼容旧版本调用）
get_public_ip() {
    echo "$PUBLIC_IP"
}

# 检测网络接口
get_network_interface() {
    local interface
    interface=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [[ -z "$interface" ]]; then
        interface=$(ls /sys/class/net | grep -v lo | head -n1)
    fi
    echo "$interface"
}

# 安装WireGuard
install_wireguard() {
    INFO "开始安装WireGuard..."
    
    case $PACKAGE_MANAGER in
        "apt-get")
            apt-get update -y
            apt-get install -y wireguard wireguard-tools
            ;;
        "yum")
            # CentOS 7 需要 EPEL
            if grep -q "CentOS Linux 7" /etc/os-release 2>/dev/null; then
                yum install -y epel-release
            fi
            yum makecache fast
            yum install -y wireguard-tools
            ;;
        "dnf")
            dnf makecache
            dnf install -y wireguard-tools
            ;;
        "zypper")
            zypper refresh
            zypper install -y wireguard-tools
            ;;
        "pacman")
            pacman -Sy
            pacman -S --noconfirm wireguard-tools
            ;;
        "apk")
            apk update
            apk add --no-cache wireguard-tools
            ;;
        "opkg")
            opkg update
            opkg install wireguard-tools
            ;;
        *)
            ERROR "不支持的包管理器: $PACKAGE_MANAGER"
            return 1
            ;;
    esac
    
    if ! command -v wg &> /dev/null; then
        ERROR "WireGuard安装失败"
        return 1
    fi
    
    INFO "WireGuard安装成功"
    return 0
}

# 安装qrencode（可选）
install_qrencode() {
    INFO "尝试安装qrencode用于生成二维码..."
    
    case $PACKAGE_MANAGER in
        "apt-get")
            apt-get install -y qrencode 2>/dev/null || WARN "qrencode安装失败，将跳过二维码功能"
            ;;
        "yum")
            yum install -y qrencode 2>/dev/null || WARN "qrencode安装失败，将跳过二维码功能"
            ;;
        "dnf")
            dnf install -y qrencode 2>/dev/null || WARN "qrencode安装失败，将跳过二维码功能"
            ;;
        "zypper")
            zypper install -y qrencode 2>/dev/null || WARN "qrencode安装失败，将跳过二维码功能"
            ;;
        "pacman")
            pacman -S --noconfirm qrencode 2>/dev/null || WARN "qrencode安装失败，将跳过二维码功能"
            ;;
        "apk")
            apk add --no-cache libqrencode 2>/dev/null || WARN "qrencode安装失败，将跳过二维码功能"
            ;;
        "opkg")
            # OpenWrt系统的qrencode包名可能不同
            opkg install qrencode 2>/dev/null || WARN "qrencode安装失败，将跳过二维码功能"
            ;;
        *)
            WARN "未知包管理器，跳过qrencode安装"
            ;;
    esac
}

# 创建目录结构
create_directories() {
    mkdir -p "$WG_DIR" "$WG_CONFIG_DIR" "$WG_KEYS_DIR"
    chmod 700 "$WG_DIR" "$WG_KEYS_DIR"
    chmod 755 "$WG_CONFIG_DIR"
}

# 生成密钥对
generate_keys() {
    local name=$1
    local private_key="${WG_KEYS_DIR}/${name}_private.key"
    local public_key="${WG_KEYS_DIR}/${name}_public.key"
    
    if [[ ! -f "$private_key" ]]; then
        wg genkey > "$private_key"
        chmod 600 "$private_key"
        wg pubkey < "$private_key" > "$public_key"
        chmod 644 "$public_key"
        INFO "生成密钥对: $name"
    else
        INFO "密钥对已存在: $name"
    fi
}

# 配置服务端
setup_server() {
    INFO "配置WireGuard服务端..."

    # 配置公网IP
    configure_public_ip

    # 获取配置参数
    local public_ip="$PUBLIC_IP"
    local network_interface=$(get_network_interface)
    
    # 用户自定义配置
    echo -e "\n${Blue}=== 服务端配置 ===${Font}"
    read -p "设置WireGuard监听端口 [默认: $WG_PORT]: " custom_port
    WG_PORT=${custom_port:-$WG_PORT}
    
    read -p "设置VPN网段，CIDR写法，示例：192.168.3.0/24 [默认: $WG_NETWORK]: " custom_network
    WG_NETWORK=${custom_network:-$WG_NETWORK}
    WG_SERVER_IP=$(echo $WG_NETWORK | sed 's/0\/24/1/')
    
    # read -p "服务器公网IP [默认: $public_ip]: " custom_ip
    # public_ip=${custom_ip:-$public_ip}
    
    read -p "设置网络接口 [默认: $network_interface]: " custom_interface
    network_interface=${custom_interface:-$network_interface}

    # 配置目录路径
    echo
    read -p "设置WireGuard配置目录 [默认: $WG_DIR]: " custom_dir
    if [[ -n "$custom_dir" ]]; then
        WG_DIR="$custom_dir"
        WG_CONFIG_DIR="${WG_DIR}/configs"
        WG_KEYS_DIR="${WG_DIR}/keys"
        INFO "配置目录设置为: $WG_DIR"
    fi

    # 创建目录结构
    create_directories

    # 生成服务端密钥
    generate_keys "server"
    
    local server_private=$(cat "${WG_KEYS_DIR}/server_private.key")
    
    # 根据IP版本配置防火墙规则
    local postup_rules
    local postdown_rules

    # 检查当前使用的IP版本
    if [[ "$PUBLIC_IP" =~ : ]]; then
        # IPv6环境
        INFO "配置IPv6防火墙规则"

        # 检查IPv6 NAT支持
        if ! modinfo ip6table_nat &>/dev/null && ! lsmod | grep -q ip6table_nat; then
            WARN "系统可能不支持IPv6 NAT，某些功能可能受限"
            echo "如果客户端无法访问互联网，请考虑："
            echo "1. 使用IPv6路由而不是NAT"
            echo "2. 配置IPv6防火墙规则"
            echo "3. 或切换到IPv4环境"
        fi

        # IPv6通常使用路由而不是NAT，但这里仍提供NAT选项
        echo "IPv6配置选项："
        echo "1. 使用NAT (MASQUERADE) - 通过NAT转换处理流量转发"
        echo "2. 使用路由转发 - 通过路由表处理流量转发，IPv6推荐方式"
        read -p "请选择 [1-2, 默认: 1]: " ipv6_mode

        if [[ "$ipv6_mode" == "2" ]]; then
            # 仅转发，不使用NAT
            postup_rules="ip6tables -A FORWARD -i %i -j ACCEPT; ip6tables -A FORWARD -o %i -j ACCEPT"
            postdown_rules="ip6tables -D FORWARD -i %i -j ACCEPT; ip6tables -D FORWARD -o %i -j ACCEPT"
            INFO "使用IPv6路由转发模式"
        else
            # 使用NAT
            postup_rules="ip6tables -A FORWARD -i %i -j ACCEPT; ip6tables -A FORWARD -o %i -j ACCEPT; ip6tables -t nat -A POSTROUTING -o $network_interface -j MASQUERADE"
            postdown_rules="ip6tables -D FORWARD -i %i -j ACCEPT; ip6tables -D FORWARD -o %i -j ACCEPT; ip6tables -t nat -D POSTROUTING -o $network_interface -j MASQUERADE"
            INFO "使用IPv6 NAT模式"
        fi
    else
        # IPv4环境
        INFO "配置IPv4防火墙规则"
        postup_rules="iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $network_interface -j MASQUERADE"
        postdown_rules="iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $network_interface -j MASQUERADE"
    fi

    # 创建服务端配置文件
    cat > "${WG_DIR}/${WG_INTERFACE}.conf" << EOF
[Interface]
PrivateKey = $server_private
Address = $WG_SERVER_IP/24
ListenPort = $WG_PORT
PostUp = $postup_rules
PostDown = $postdown_rules

# 客户端配置将自动添加到此处
EOF
    
    # 保存服务端信息
    cat > "${WG_DIR}/server_info.conf" << EOF
PUBLIC_IP=$public_ip
WG_PORT=$WG_PORT
WG_NETWORK=$WG_NETWORK
WG_SERVER_IP=$WG_SERVER_IP
NETWORK_INTERFACE=$network_interface
SERVER_PUBLIC_KEY=$(cat "${WG_KEYS_DIR}/server_public.key")
EOF
    
    # 启用IP转发
    if [[ "$PUBLIC_IP" =~ : ]]; then
        # IPv6环境
        INFO "启用IPv6转发"
        # 检查当前运行时的值
        if [[ "$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null)" != "1" ]]; then
            # 删除所有相关的旧配置行（包括注释的）
            sed -i '/net\.ipv6\.conf\.all\.forwarding/d' /etc/sysctl.conf
            # 添加新配置
            echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
            # 立即生效
            sysctl -w net.ipv6.conf.all.forwarding=1
        else
            INFO "IPv6转发已启用"
        fi
    else
        # IPv4环境
        INFO "启用IPv4转发"
        # 检查当前运行时的值
        if [[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" != "1" ]]; then
            # 删除所有相关的旧配置行（包括注释的）
            sed -i '/net\.ipv4\.ip_forward/d' /etc/sysctl.conf
            # 添加新配置
            echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
            # 立即生效
            sysctl -w net.ipv4.ip_forward=1
        else
            INFO "IPv4转发已启用"
        fi
    fi
    
    INFO "服务端配置完成"
    INFO "服务端公钥: $(cat "${WG_KEYS_DIR}/server_public.key")"
    INFO "服务端地址: ${public_ip}:${WG_PORT}"
    INFO "VPN网段: $WG_NETWORK"
}

# 生成客户端配置
generate_client_config() {
    if [[ ! -f "${WG_DIR}/server_info.conf" ]]; then
        ERROR "服务端未配置，请先运行服务端安装"
        return 1
    fi
    
    # 加载服务端信息
    source "${WG_DIR}/server_info.conf"
    
    echo -e "\n${Blue}=== 生成客户端配置 ===${Font}"
    read -p "请输入客户端名称 (如: laptop, phone, tablet): " client_name
    
    if [[ -z "$client_name" ]]; then
        ERROR "客户端名称不能为空"
        return 1
    fi
    
    # 检查是否已存在
    if [[ -f "${WG_CONFIG_DIR}/${client_name}.conf" ]]; then
        read -p "客户端 $client_name 已存在，是否覆盖? (y/N): " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # 生成客户端密钥
    generate_keys "$client_name"
    
    # 分配IP地址
    local client_ip=$(get_next_client_ip)
    
    # 询问路由配置
    echo "路由配置选项:"
    echo "1. 全部流量通过VPN (AllowedIPs = 0.0.0.0/0)"
    echo "2. 仅VPN网段流量 (AllowedIPs = $WG_NETWORK)"
    read -p "请选择 [1-2, 默认: 1]: " route_choice
    
    local allowed_ips="0.0.0.0/0"
    if [[ "$route_choice" == "2" ]]; then
        allowed_ips="$WG_NETWORK"
    fi
    
    # 询问DNS配置
    read -p "DNS服务器 [默认: 8.8.8.8,1.1.1.1]: " custom_dns
    local dns_servers=${custom_dns:-"8.8.8.8,1.1.1.1"}
    
    local client_private=$(cat "${WG_KEYS_DIR}/${client_name}_private.key")
    
    # 生成客户端配置文件
    cat > "${WG_CONFIG_DIR}/${client_name}.conf" << EOF
[Interface]
PrivateKey = $client_private
Address = $client_ip/32
DNS = $dns_servers

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $PUBLIC_IP:$WG_PORT
AllowedIPs = $allowed_ips
PersistentKeepalive = 25
EOF
    
    # 添加客户端到服务端配置
    local client_public=$(cat "${WG_KEYS_DIR}/${client_name}_public.key")
    cat >> "${WG_DIR}/${WG_INTERFACE}.conf" << EOF

# Client: $client_name
[Peer]
PublicKey = $client_public
AllowedIPs = $client_ip/32
EOF
    
    INFO "客户端配置生成完成: ${WG_CONFIG_DIR}/${client_name}.conf"
    INFO "客户端IP地址: $client_ip"
    
    # 显示配置文件内容
    echo -e "\n${Blue}=== 客户端配置文件内容 ===${Font}"
    cat "${WG_CONFIG_DIR}/${client_name}.conf"
    
    # 生成二维码（如果支持）
    if command -v qrencode &> /dev/null; then
        echo -e "\n${Blue}=== 配置二维码 ===${Font}"
        qrencode -t ansiutf8 < "${WG_CONFIG_DIR}/${client_name}.conf"
    fi
    
    # 重启WireGuard服务以应用新配置
    if systemctl is-active --quiet wg-quick@${WG_INTERFACE}; then
        systemctl restart wg-quick@${WG_INTERFACE}
        INFO "WireGuard服务已重启"
    fi
}

# 获取下一个可用的客户端IP
get_next_client_ip() {
    local base_ip=$(echo $WG_SERVER_IP | cut -d'.' -f1-3)
    local used_ips=$(grep -h "AllowedIPs.*32" "${WG_DIR}/${WG_INTERFACE}.conf" 2>/dev/null | grep -o "${base_ip}\.[0-9]*" | sort -V)
    
    for i in {2..254}; do
        local test_ip="${base_ip}.${i}"
        if [[ "$test_ip" != "$WG_SERVER_IP" ]] && ! echo "$used_ips" | grep -q "^${test_ip}$"; then
            echo "$test_ip"
            return
        fi
    done
    
    ERROR "无可用IP地址"
    exit 1
}

# 检测操作系统类型（用于开机自启动）
detect_startup_method() {
    if [ -f /etc/synoinfo.conf ]; then
        STARTUP_METHOD="synology"
    elif [ -f /etc/unraid-version ]; then
        STARTUP_METHOD="unraid"
    elif [ -f /etc/rc.local ] && grep -q "exit 0" /etc/rc.local; then
        STARTUP_METHOD="rc_local"
    elif command -v crontab >/dev/null 2>&1; then
        STARTUP_METHOD="crontab"
    else
        STARTUP_METHOD="manual"
    fi
    INFO "开机自启动方式: $STARTUP_METHOD"
}

# 配置开机自启动
setup_autostart() {
    local wg_command="wg-quick up \"${WG_DIR}/${WG_INTERFACE}.conf\""
    
    case $STARTUP_METHOD in
        "synology")
            if ! grep -qF -- "$wg_command" /etc/rc.local; then
                cp -f /etc/rc.local /etc/rc.local.bak 2>/dev/null
                sed -i '/wg-quick/d' /etc/rc.local
                if grep -q 'exit 0' /etc/rc.local; then
                    sed -i "/exit 0/i\\$wg_command" /etc/rc.local
                else
                    echo "$wg_command" >> /etc/rc.local
                fi
                INFO "已配置群晖开机自启动"
            fi
            ;;
        "unraid")
            if ! grep -qF -- "$wg_command" /boot/config/go; then
                echo "$wg_command" >> /boot/config/go
                INFO "已配置Unraid开机自启动"
            fi
            ;;
        "rc_local")
            if ! grep -qF -- "$wg_command" /etc/rc.local; then
                cp -f /etc/rc.local /etc/rc.local.bak 2>/dev/null
                sed -i '/wg-quick/d' /etc/rc.local
                if grep -q 'exit 0' /etc/rc.local; then
                    sed -i "/exit 0/i\\$wg_command" /etc/rc.local
                else
                    echo "$wg_command" >> /etc/rc.local
                fi
                chmod +x /etc/rc.local
                INFO "已配置rc.local开机自启动"
            fi
            ;;
        "crontab")
            local cron_command="@reboot $wg_command"
            crontab -l 2>/dev/null | grep -v "wg-quick" > /tmp/cronjob.tmp
            echo "$cron_command" >> /tmp/cronjob.tmp
            crontab /tmp/cronjob.tmp
            rm -f /tmp/cronjob.tmp
            INFO "已配置crontab开机自启动"
            ;;
        "manual")
            WARN "无法自动配置开机自启动，请手动添加以下命令到系统启动脚本："
            echo -e "${Yellow}$wg_command${Font}"
            ;;
    esac
}

# 移除开机自启动
remove_autostart() {
    local wg_command="wg-quick up \"${WG_DIR}/${WG_INTERFACE}.conf\""
    
    case $STARTUP_METHOD in
        "synology")
            if [ -f /etc/rc.local ]; then
                sed -i '/wg-quick/d' /etc/rc.local
                INFO "已移除群晖开机自启动"
            fi
            ;;
        "unraid")
            if [ -f /boot/config/go ]; then
                sed -i '/wg-quick/d' /boot/config/go
                INFO "已移除Unraid开机自启动"
            fi
            ;;
        "rc_local")
            if [ -f /etc/rc.local ]; then
                sed -i '/wg-quick/d' /etc/rc.local
                INFO "已移除rc.local开机自启动"
            fi
            ;;
        "crontab")
            crontab -l 2>/dev/null | grep -v "wg-quick" > /tmp/cronjob.tmp
            crontab /tmp/cronjob.tmp
            rm -f /tmp/cronjob.tmp
            INFO "已移除crontab开机自启动"
            ;;
        "manual")
            WARN "请手动从系统启动脚本中移除WireGuard启动命令"
            ;;
    esac
}

# 启动WireGuard服务
start_wireguard() {
    INFO "启动WireGuard服务..."
    
    case $SERVICE_MANAGER in
        "systemd")
            # 检查是否使用默认目录
            if [[ "$WG_DIR" == "/etc/wireguard" ]]; then
                # 使用默认目录，可以使用systemd模板服务
                systemctl enable wg-quick@${WG_INTERFACE}
                systemctl start wg-quick@${WG_INTERFACE}

                if systemctl is-active --quiet wg-quick@${WG_INTERFACE}; then
                    INFO "WireGuard服务启动成功"
                    wg show
                else
                    ERROR "WireGuard服务启动失败"
                    systemctl status wg-quick@${WG_INTERFACE}
                    return 1
                fi
            else
                # 使用自定义目录，手动启动并配置开机自启动
                WARN "检测到自定义配置目录，将使用手动启动方式"
                wg-quick up "${WG_DIR}/${WG_INTERFACE}.conf"
                if wg show ${WG_INTERFACE} &> /dev/null; then
                    INFO "WireGuard接口启动成功"
                    wg show
                    # 配置开机自启动
                    setup_autostart
                else
                    ERROR "WireGuard接口启动失败"
                    return 1
                fi
            fi
            ;;
        "openrc")
            rc-update add wg-quick.${WG_INTERFACE} default
            rc-service wg-quick.${WG_INTERFACE} start
            if wg show ${WG_INTERFACE} &> /dev/null; then
                INFO "WireGuard服务启动成功"
                wg show
            else
                ERROR "WireGuard服务启动失败"
                return 1
            fi
            ;;
        *)
            # 手动启动接口
            wg-quick up "${WG_DIR}/${WG_INTERFACE}.conf"
            if wg show ${WG_INTERFACE} &> /dev/null; then
                INFO "WireGuard接口启动成功"
                wg show
                # 配置开机自启动
                setup_autostart
            else
                ERROR "WireGuard接口启动失败"
                return 1
            fi
            ;;
    esac
}

# 停止WireGuard服务
stop_wireguard() {
    INFO "停止WireGuard服务..."
    
    case $SERVICE_MANAGER in
        "systemd")
            if [[ "$WG_DIR" == "/etc/wireguard" ]]; then
                systemctl stop wg-quick@${WG_INTERFACE}
                systemctl disable wg-quick@${WG_INTERFACE}
            else
                wg-quick down "${WG_DIR}/${WG_INTERFACE}.conf"
                remove_autostart
            fi
            ;;
        "openrc")
            rc-service wg-quick.${WG_INTERFACE} stop
            rc-update del wg-quick.${WG_INTERFACE} default
            ;;
        *)
            wg-quick down "${WG_DIR}/${WG_INTERFACE}.conf"
            # 移除开机自启动
            remove_autostart
            ;;
    esac
    
    INFO "WireGuard服务已停止"
}

# 查看服务状态
show_status() {
    echo -e "\n${Blue}=== WireGuard服务状态 ===${Font}"
    # 检查接口是否运行（兼容systemd和手动启动）
    if wg show ${WG_INTERFACE} &> /dev/null; then
        echo -e "${Green}服务状态: 运行中${Font}"
        echo -e "\n${Blue}=== 接口信息 ===${Font}"
        wg show
        echo -e "\n${Blue}=== 连接统计 ===${Font}"
        wg show ${WG_INTERFACE} dump
    else
        echo -e "${Red}服务状态: 未运行${Font}"
    fi

    if [[ -f "${WG_DIR}/server_info.conf" ]]; then
        source "${WG_DIR}/server_info.conf"
        echo -e "\n${Blue}=== 服务端信息 ===${Font}"
        echo "公网地址: ${PUBLIC_IP}:${WG_PORT}"
        echo "VPN网段: $WG_NETWORK"
        echo "服务端IP: $WG_SERVER_IP"
    fi

    # 检查防火墙状态
    echo -e "\n${Blue}=== 防火墙状态 ===${Font}"
    detect_firewall

    case "$FIREWALL_TYPE" in
        "ufw")
            echo "UFW规则:"
            ufw status | grep -E "(${WG_PORT}|${WG_INTERFACE})"
            ;;
        "firewalld")
            echo "firewalld规则:"
            firewall-cmd --list-ports | grep -q "${WG_PORT}/udp" && echo "端口${WG_PORT}/udp: 已开放" || echo "端口${WG_PORT}/udp: 未开放"
            firewall-cmd --zone=trusted --list-interfaces | grep -q "${WG_INTERFACE}" && echo "接口${WG_INTERFACE}: 已信任" || echo "接口${WG_INTERFACE}: 未信任"
            ;;
        "iptables")
            echo "iptables规则:"
            iptables -L INPUT -n | grep -q "${WG_PORT}" && echo "端口${WG_PORT}: 已开放" || echo "端口${WG_PORT}: 未开放"
            iptables -L FORWARD -n | grep -q "${WG_INTERFACE}" && echo "转发规则: 已配置" || echo "转发规则: 未配置"
            ;;
        *)
            echo "无防火墙或未检测到"
            ;;
    esac
}

# 列出客户端配置
list_clients() {
    echo -e "\n${Blue}=== 客户端配置列表 ===${Font}"
    if [[ -d "$WG_CONFIG_DIR" ]]; then
        local configs=$(ls "$WG_CONFIG_DIR"/*.conf 2>/dev/null)
        if [[ -n "$configs" ]]; then
            for config in $configs; do
                local name=$(basename "$config" .conf)
                local ip=$(grep "Address" "$config" | awk '{print $3}' | cut -d'/' -f1)
                echo "- $name ($ip)"
            done
        else
            echo "暂无客户端配置"
        fi
    else
        echo "配置目录不存在"
    fi
}

# 删除客户端配置
delete_client() {
    list_clients
    echo
    read -p "请输入要删除的客户端名称: " client_name
    
    if [[ -z "$client_name" ]]; then
        ERROR "客户端名称不能为空"
        return 1
    fi
    
    local config_file="${WG_CONFIG_DIR}/${client_name}.conf"
    if [[ ! -f "$config_file" ]]; then
        ERROR "客户端配置不存在: $client_name"
        return 1
    fi
    
    read -p "确认删除客户端 $client_name? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return 1
    fi
    
    # 删除配置文件
    rm -f "$config_file"
    
    # 删除密钥文件
    rm -f "${WG_KEYS_DIR}/${client_name}_private.key"
    rm -f "${WG_KEYS_DIR}/${client_name}_public.key"
    
    # 从服务端配置中删除客户端
    if [[ -f "${WG_DIR}/${WG_INTERFACE}.conf" ]]; then
        sed -i "/# Client: $client_name/,/^$/d" "${WG_DIR}/${WG_INTERFACE}.conf"
    fi
    
    INFO "客户端 $client_name 已删除"
    
    # 重启服务以应用更改
    if systemctl is-active --quiet wg-quick@${WG_INTERFACE}; then
        systemctl restart wg-quick@${WG_INTERFACE}
        INFO "WireGuard服务已重启"
    fi
}

# 显示客户端配置
show_client_config() {
    list_clients
    echo
    read -p "请输入要查看的客户端名称: " client_name
    
    if [[ -z "$client_name" ]]; then
        ERROR "客户端名称不能为空"
        return 1
    fi
    
    local config_file="${WG_CONFIG_DIR}/${client_name}.conf"
    if [[ ! -f "$config_file" ]]; then
        ERROR "客户端配置不存在: $client_name"
        return 1
    fi
    
    echo -e "\n${Blue}=== 客户端配置: $client_name ===${Font}"
    cat "$config_file"
    
    echo -e "\n${Blue}=== 二维码生成 ===${Font}"
    echo "可以将上述配置内容复制到以下在线工具生成二维码："
    echo "https://www.qr-code-generator.com/"
    echo "https://qr.io/"
}

# 卸载WireGuard
uninstall_wireguard() {
    echo -e "\n${Red}警告: 此操作将完全删除WireGuard及所有配置文件${Font}"
    read -p "确认卸载? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return 1
    fi
    
    # 停止服务
    systemctl stop wg-quick@${WG_INTERFACE} 2>/dev/null
    systemctl disable wg-quick@${WG_INTERFACE} 2>/dev/null
    
    # 删除配置文件
    rm -rf "$WG_DIR"
    
    # 卸载软件包
    case $OS in
        ubuntu|debian)
            $PACKAGE_MANAGER remove -y wireguard wireguard-tools
            ;;
        centos|rhel|fedora)
            $PACKAGE_MANAGER remove -y wireguard-tools
            ;;
        alpine)
            $PACKAGE_MANAGER del wireguard-tools
            ;;
    esac
    
    INFO "WireGuard已完全卸载"
}

# 主菜单
main_menu() {
    while true; do
        clear
        echo -e "———————————————————————————————————— \033[1;33mWireGuard 管理工具\033[0m —————————————————————————————————"
        echo -e "\n"
        echo -e "\033[1;32m1、安装WireGuard服务端\033[0m"
        echo -e "\033[1;32m2、生成客户端配置\033[0m"
        echo -e "\033[1;32m3、查看服务状态\033[0m"
        echo -e "\033[1;32m4、查看客户端配置\033[0m"
        echo -e "\033[1;32m5、删除客户端配置\033[0m"
        echo -e "\033[1;32m6、启动WireGuard服务\033[0m"
        echo -e "\033[1;32m7、停止WireGuard服务\033[0m"
        echo -e "\033[1;32m8、卸载WireGuard\033[0m"
        echo -e "\n"
        echo -e "——————————————————————————————————————————————————————————————————————————————————"
        read -p "请输入您的选择（1-8，按q退出）：" choice
        
        case "$choice" in
            1)
                detect_os
                detect_service_manager
                detect_firewall
                detect_startup_method
                install_wireguard
                setup_server
                configure_firewall
                start_wireguard
                ;;
            2)
                generate_client_config
                ;;
            3)
                show_status
                ;;
            4)
                show_client_config
                ;;
            5)
                delete_client
                ;;
            6)
                start_wireguard
                ;;
            7)
                stop_wireguard
                ;;
            8)
                uninstall_wireguard
                ;;
            [Qq])
                exit 0
                ;;
            *)
                ERROR "输入错误，按任意键重新输入！"
                read -r -n 1
                continue
                ;;
        esac
        
        echo
        read -n 1 -p "按任意键继续..."
    done
}

# 检测服务管理系统
detect_service_manager() {
    if command -v systemctl &> /dev/null && systemctl --version &> /dev/null; then
        SERVICE_MANAGER="systemd"
    elif command -v service &> /dev/null; then
        SERVICE_MANAGER="sysv"
    elif command -v rc-service &> /dev/null; then
        SERVICE_MANAGER="openrc"
    else
        SERVICE_MANAGER="none"
        WARN "未检测到支持的服务管理系统，WireGuard需要手动管理"
    fi
    INFO "服务管理系统: $SERVICE_MANAGER"
}

# 检测防火墙系统
detect_firewall() {
    FIREWALL_TYPE="none"

    # 检测UFW
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "Status: active"; then
            FIREWALL_TYPE="ufw"
            INFO "检测到活跃的UFW防火墙"
        else
            INFO "检测到UFW但未启用"
        fi
    # 检测firewalld
    elif command -v firewall-cmd &> /dev/null; then
        if systemctl is-active --quiet firewalld; then
            FIREWALL_TYPE="firewalld"
            INFO "检测到活跃的firewalld防火墙"
        else
            INFO "检测到firewalld但未启用"
        fi
    # 检测iptables
    elif command -v iptables &> /dev/null; then
        # 检查是否有自定义iptables规则
        if iptables -L | grep -q "Chain INPUT (policy DROP)" || iptables -L INPUT | grep -v "ACCEPT.*0.0.0.0/0" | grep -q "ACCEPT\|DROP\|REJECT"; then
            FIREWALL_TYPE="iptables"
            INFO "检测到自定义iptables规则"
        else
            INFO "检测到iptables但无严格规则"
        fi
    else
        WARN "未检测到防火墙系统"
    fi

    INFO "防火墙类型: $FIREWALL_TYPE"
}

# 配置防火墙规则
configure_firewall() {
    if [[ "$FIREWALL_TYPE" == "none" ]]; then
        INFO "无需配置防火墙规则"
        return 0
    fi

    INFO "配置防火墙规则..."

    case "$FIREWALL_TYPE" in
        "ufw")
            # UFW配置
            INFO "配置UFW防火墙规则"

            # 允许WireGuard端口
            ufw allow ${WG_PORT}/udp comment "WireGuard"

            # 配置转发规则
            ufw route allow in on ${WG_INTERFACE}
            ufw route allow out on ${WG_INTERFACE}

            # 重新加载UFW
            ufw reload

            INFO "UFW防火墙配置完成"
            ;;

        "firewalld")
            # firewalld配置
            INFO "配置firewalld防火墙规则"

            # 允许WireGuard端口
            firewall-cmd --permanent --add-port=${WG_PORT}/udp

            # 添加WireGuard接口到trusted区域
            firewall-cmd --permanent --zone=trusted --add-interface=${WG_INTERFACE}

            # 启用伪装（NAT）
            firewall-cmd --permanent --add-masquerade

            # 重新加载配置
            firewall-cmd --reload

            INFO "firewalld防火墙配置完成"
            ;;

        "iptables")
            # iptables配置
            INFO "配置iptables防火墙规则"

            # 允许WireGuard端口
            iptables -A INPUT -p udp --dport ${WG_PORT} -j ACCEPT

            # 保存iptables规则（根据不同发行版）
            if command -v iptables-save &> /dev/null; then
                if [[ -f /etc/iptables/rules.v4 ]]; then
                    iptables-save > /etc/iptables/rules.v4
                elif [[ -f /etc/sysconfig/iptables ]]; then
                    iptables-save > /etc/sysconfig/iptables
                else
                    WARN "无法自动保存iptables规则，请手动保存"
                fi
            fi

            INFO "iptables防火墙配置完成"
            ;;

        *)
            WARN "未知防火墙类型，请手动配置以下规则："
            echo "- 允许UDP端口 ${WG_PORT}"
            echo "- 允许${WG_INTERFACE}接口的转发流量"
            ;;
    esac
}

# 检测防火墙系统
detect_firewall() {
    FIREWALL_TYPE="none"

    # 检测UFW
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "Status: active"; then
            FIREWALL_TYPE="ufw"
            INFO "检测到活跃的UFW防火墙"
        else
            INFO "检测到UFW但未启用"
        fi
    # 检测firewalld
    elif command -v firewall-cmd &> /dev/null; then
        if systemctl is-active --quiet firewalld; then
            FIREWALL_TYPE="firewalld"
            INFO "检测到活跃的firewalld防火墙"
        else
            INFO "检测到firewalld但未启用"
        fi
    # 检测iptables
    elif command -v iptables &> /dev/null; then
        # 检查是否有自定义iptables规则
        if iptables -L | grep -q "Chain INPUT (policy DROP)" || iptables -L INPUT | grep -v "ACCEPT.*0.0.0.0/0" | grep -q "ACCEPT\|DROP\|REJECT"; then
            FIREWALL_TYPE="iptables"
            INFO "检测到自定义iptables规则"
        else
            INFO "检测到iptables但无严格规则"
        fi
    else
        WARN "未检测到防火墙系统"
    fi

    INFO "防火墙类型: $FIREWALL_TYPE"
}

# 配置防火墙规则
configure_firewall() {
    if [[ "$FIREWALL_TYPE" == "none" ]]; then
        INFO "无需配置防火墙规则"
        return 0
    fi

    INFO "配置防火墙规则..."

    case "$FIREWALL_TYPE" in
        "ufw")
            # UFW配置
            INFO "配置UFW防火墙规则"

            # 允许WireGuard端口
            ufw allow ${WG_PORT}/udp comment "WireGuard"

            # 配置转发规则
            ufw route allow in on ${WG_INTERFACE}
            ufw route allow out on ${WG_INTERFACE}

            # 重新加载UFW
            ufw reload

            INFO "UFW防火墙配置完成"
            ;;

        "firewalld")
            # firewalld配置
            INFO "配置firewalld防火墙规则"

            # 允许WireGuard端口
            firewall-cmd --permanent --add-port=${WG_PORT}/udp

            # 添加WireGuard接口到trusted区域
            firewall-cmd --permanent --zone=trusted --add-interface=${WG_INTERFACE}

            # 启用伪装（NAT）
            firewall-cmd --permanent --add-masquerade

            # 重新加载配置
            firewall-cmd --reload

            INFO "firewalld防火墙配置完成"
            ;;

        "iptables")
            # iptables配置
            INFO "配置iptables防火墙规则"

            # 允许WireGuard端口
            iptables -A INPUT -p udp --dport ${WG_PORT} -j ACCEPT

            # 保存iptables规则（根据不同发行版）
            if command -v iptables-save &> /dev/null; then
                if [[ -f /etc/iptables/rules.v4 ]]; then
                    iptables-save > /etc/iptables/rules.v4
                elif [[ -f /etc/sysconfig/iptables ]]; then
                    iptables-save > /etc/sysconfig/iptables
                else
                    WARN "无法自动保存iptables规则，请手动保存"
                fi
            fi

            INFO "iptables防火墙配置完成"
            ;;

        *)
            WARN "未知防火墙类型，请手动配置以下规则："
            echo "- 允许UDP端口 ${WG_PORT}"
            echo "- 允许${WG_INTERFACE}接口的转发流量"
            ;;
    esac
}

# 脚本入口
check_root
main_menu
