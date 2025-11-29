# Agro-suoha

> TT Cloudflare Tunnel 一键suoha脚本  无需公网 IP | 无需端口转发 Agro隧道 | 支持 VMess/VLESS | 自动优选伪装域名

## 功能特点
* 🚀 **无需公网 IP**：基于 Cloudflare Tunnel (Argo) 穿透技术。
* 🔒 **安全隐蔽**：自动配置 `www.visa.com.sg` 等优选域名进行伪装。
* 🛠 **多协议支持**：可选 VMess 或 VLESS 协议。
* 💻 **多架构支持**：支持 x86_64, arm64, armv7 等。

## 一键安装命令 (Usage)

复制以下命令在 VPS 中执行即可：

```bash
wget -N --no-check-certificate [https://raw.githubusercontent.com/ttttwei/Agro-suoha/main/suoha.sh](https://raw.githubusercontent.com/ttttwei/Agro-suoha/main/suoha.sh) && chmod +x suoha.sh && ./suoha.sh
