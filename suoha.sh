#!/bin/bash
# TT Agro-suoha 一键脚本 v2.0
# 支持临时梭哈和开机服务模式

# 系统判断
linux_os=("Debian" "Ubuntu" "CentOS" "Fedora" "Alpine")
linux_update=("apt update" "apt update" "yum -y update" "yum -y update" "apk update")
linux_install=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "apk add -f")
n=0
for i in "${linux_os[@]}"; do
    if [ "$i" = "$(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}')" ]; then
        break
    else
        n=$((n+1))
    fi
done
if [ $n -eq 5 ]; then
    echo "当前系统 $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2) 没有适配，默认使用APT包管理器"
    n=0
fi

# 依赖安装
check_install(){
    for cmd in unzip curl; do
        if ! command -v $cmd >/dev/null 2>&1; then
            ${linux_update[$n]}
            ${linux_install[$n]} $cmd
        fi
    done
    if [ "$(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}')" != "Alpine" ]; then
        if ! command -v systemctl >/dev/null 2>&1; then
            ${linux_update[$n]}
            ${linux_install[$n]} systemctl
        fi
    fi
}

# 下载Xray+Cloudflared
download_xray_cloudflared(){
    rm -rf xray cloudflared-linux xray.zip
    arch=$(uname -m)
    case "$arch" in
        x86_64|x64|amd64)
            curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip
            curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared-linux
            ;;
        i386|i686)
            curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-32.zip -o xray.zip
            curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-386 -o cloudflared-linux
            ;;
        armv8|arm64|aarch64)
            curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip -o xray.zip
            curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 -o cloudflared-linux
            ;;
        armv7l)
            curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm32-v7a.zip -o xray.zip
            curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm -o cloudflared-linux
            ;;
        *)
            echo "当前架构 $arch 没有适配"
            exit 1
            ;;
    esac
    mkdir -p xray
    unzip -d xray xray.zip
    chmod +x cloudflared-linux xray/xray
    rm -rf xray.zip
}

# 生成配置
generate_config(){
    uuid=$(cat /proc/sys/kernel/random/uuid)
    urlpath=$(echo $uuid | awk -F- '{print $1}')
    port=$((RANDOM+10000))

    if [ "$protocol" = "1" ]; then
        cat > xray/config.json <<EOF
{
  "inbounds":[
    {
      "port":$port,
      "listen":"localhost",
      "protocol":"vmess",
      "settings":{
        "clients":[{"id":"$uuid","alterId":0}]
      },
      "streamSettings":{
        "network":"ws",
        "wsSettings":{"path":"$urlpath"}
      }
    }
  ],
  "outbounds":[{"protocol":"freedom","settings":{}}]
}
EOF
    else
        cat > xray/config.json <<EOF
{
  "inbounds":[
    {
      "port":$port,
      "listen":"localhost",
      "protocol":"vless",
      "settings":{
        "decryption":"none",
        "clients":[{"id":"$uuid"}]
      },
      "streamSettings":{
        "network":"ws",
        "wsSettings":{"path":"$urlpath"}
      }
    }
  ],
  "outbounds":[{"protocol":"freedom","settings":{}}]
}
EOF
    fi
}

# 临时梭哈模式
quicktunnel(){
    check_install
    download_xray_cloudflared
    generate_config

    ./xray/xray run >/dev/null 2>&1 &
    ./cloudflared-linux tunnel --url http://localhost:$port --no-autoupdate --edge-ip-version $ips --protocol http2 >argo.log 2>&1 &
    sleep 1

    n=0
    while true; do
        n=$((n+1))
        clear
        echo "等待cloudflare argo生成地址 已等待 $n 秒"
        argo=$(grep trycloudflare.com argo.log | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
        if [ $n -eq 15 ]; then
            n=0
            kill -9 $(pgrep cloudflared-linux) >/dev/null 2>&1
            rm -rf argo.log
            echo "argo获取超时,重试中"
            ./cloudflared-linux tunnel --url http://localhost:$port --no-autoupdate --edge-ip-version $ips --protocol http2 >argo.log 2>&1 &
            sleep 1
        elif [ -n "$argo" ]; then
            rm -rf argo.log
            break
        else
            sleep 1
        fi
    done

    clear
    echo "临时链接生成完成,请查看 v2ray.txt"
}

# 服务安装
install_service(){
    check_install
    download_xray_cloudflared
    generate_config

    mkdir -p /usr/local/tt_suoha
    cp -r xray cloudflared-linux /usr/local/tt_suoha/
    cp xray/config.json /usr/local/tt_suoha/

    # Systemd service
    cat >/etc/systemd/system/tt_suoha.service <<EOF
[Unit]
Description=TT Agro-suoha Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/tt_suoha/xray/xray run
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable tt_suoha
    systemctl start tt_suoha
    echo "服务安装完成，已开机自启"
}

# 卸载服务
uninstall_service(){
    systemctl stop tt_suoha >/dev/null 2>&1
    systemctl disable tt_suoha >/dev/null 2>&1
    rm -rf /etc/systemd/system/tt_suoha.service /usr/local/tt_suoha
    systemctl daemon-reload
    echo "服务已卸载"
}

# 清理缓存
clean_cache(){
    kill -9 $(pgrep xray) >/dev/null 2>&1
    kill -9 $(pgrep cloudflared-linux) >/dev/null 2>&1
    rm -rf xray cloudflared-linux argo.log v2ray.txt
    echo "缓存已清理"
}

# 管理服务
manage_service(){
    systemctl status tt_suoha
    echo "1. 启动服务"
    echo "2. 停止服务"
    echo "3. 重启服务"
    read -p "选择操作: " op
    case "$op" in
        1) systemctl start tt_suoha ;;
        2) systemctl stop tt_suoha ;;
        3) systemctl restart tt_suoha ;;
        *) echo "无效操作" ;;
    esac
}

# 主菜单（保留你原来的欢迎界面和说明）
main_menu(){
    clear
    echo "       _        _                              _                "
    echo "      | |      | |       ___   _   _    ___   | |__     ____       "
    echo "    __| |______| |_     / __| | | | |  / _ \  | |_ \   / _  |   "
    echo "   |__   _______  _|    \__ \ | |_| | | (_) | | | | | | (_| | "
    echo "      | |_     | |_     |___/  \___/   \___/  |_| |_|  \____|"
    echo "       \__|     \__|"
    echo "                                 "
    echo -e "\n欢迎使用 TT Agro-suoha 一键梭哈脚本...\n"

    echo "梭哈模式不需要自己提供域名,使用CF ARGO QUICK TUNNEL创建快速临时链接"
    echo "梭哈模式在重启或者脚本再次运行后临时隧道失效,如果需要使用需要再次运行创建"
    echo "安装服务模式,需要有CF托管域名,并且需要按照提示手动绑定ARGO隧道固定服务"
    echo "首次绑定ARGO隧道固定服务后如果不想再次跳转网页绑定"
    echo "将已经绑定的系统目录下的 /root/.cloudflared 文件夹以及内容"
    echo "拷贝至新系统下同样的目录,会自动跳过登录验证"

    echo -e "\n基于 Cloudflare Tunnel 的新一代超轻量级穿透工具"
    echo -e "无需公网IP 无需端口转发 极致隐藏  专为 NAT VPS 打造"

    echo -e "\n注意：梭哈模式重启服务器后 ARGO 临时隧道失效！！！\n"

    echo "TT Cloudflare Tunnel 一键 suoha 脚本,无需公网IP,无需端口转发,Agro隧道"
    echo
    echo "1.梭哈模式（无需 cloudflare 域名，重启会失效）"
    echo "2.安装服务（需要 cloudflare 域名，重启不会失效）"
    echo "3.卸载服务"
    echo "4.清空缓存"
    echo "5.管理服务"
    echo -e "0.退出脚本\n"

    read -p "请选择模式(默认1): " mode
    mode=${mode:-1}

    case "$mode" in
        1)
            read -p "选择Xray协议(1.vmess 2.vless, 默认1): " protocol
            protocol=${protocol:-1}
            read -p "选择Argo IP模式(4/6, 默认4): " ips
            ips=${ips:-4}
            quicktunnel
            ;;
        2)
            install_service
            ;;
        3)
            uninstall_service
            ;;
        4)
            clean_cache
            ;;
        5)
            manage_service
            ;;
        0)
            exit 0
            ;;
        *)
            echo "无效选择"
            ;;
    esac
}

# 循环主菜单
while true; do
    main_menu
    read -p "按回车返回主菜单..."
done
