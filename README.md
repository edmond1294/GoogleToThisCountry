# GoogleToThisCountry (GTTC)

<p align="center">
  <a href="https://www.nekoqwq.com">
    <img src="https://img.shields.io/badge/官网-www.nekoqwq.com-blue?style=for-the-badge&logo=google-chrome" alt="官网">
  </a>
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License">
  <img src="https://img.shields.io/badge/Shell-Bash-orange?style=for-the-badge&logo=gnu-bash" alt="Bash">
</p>

**GoogleToThisCountry (GTTC)** 是一款专为 VPS 节点设计的 Google 定位重定向与送中/送台/送日/送美修复工具。通过 **EDNS Client Subnet (ECS) 伪装宣告** 与 **多维保活定时发包** 技术，强行纠正 Google 服务的地理位置识别，将您的 IP 重新送回指定的目标国家或地区。

---

## 🌟 核心特色

- **多地区支持**：一键切换至 🇹🇼 台湾、🇨🇳 中国大陆、🇯🇵 日本、🇲🇴 澳门、🇺🇸 美国。
- **EDNS 子网宣告**：通过自定义 DNS 客户端子网（ECS），向 Google CDN 宣告特定地区 IP 段，精准获取对应区域的 IP 响应。
- **多维保活机制**：后台轻量化服务，自动模拟移动端 HTTP/204 请求，定期向 Google 核心节点打卡，持续维持地区定位。
- **极轻量无感**：纯 Shell 与 Python 逻辑，不占用额外的网络中转资源，完全不影响原有的 VPS 传输速度与延迟。
- **全平台兼容**：完美支持 Debian / Ubuntu / CentOS / RHEL / Alpine Linux 等主流 Linux 发行版。

---

## 🚀 一键安装与使用

在终端中直接运行以下单行指令即可启动脚本：

```bash
bash <(curl -sSL https://raw.githubusercontent.com/edmond1294/GoogleToThisCountry/main/gttc.sh)
```

后续随时在命令行输入：
```bash
gttc
```

即可直接呼出主管理界面！

---

## 🔬 技术原理
### EDNS Client Subnet (ECS)
当脚本启用时，会在 Xray 的 DNS 配置中针对 geosite:google 及相关域名添加特定的 clientSubnet 段（例如台湾 168.95.1.1/24、美国 64.233.160.0/24）。Google DoH 收到请求后，会将请求分配至对应该子网的最佳 CDN 节点。

### 多维地理位置保活 (Keep-Alive)
脚本会在后台启动 gttc-ping 服务，以随机间隔（2~5 分钟）向 Google 的位置与状态接口（如 generate_204、geolocate）发送带有特定语言标头（Accept-Language）与移动端 UA 的请求，使 Google 持续记录并锁定当前 IP 的地理位置。

## 📖 常见问题 (FAQ)
### Q1: EDNS 宣告与传统 DNS 解锁（SmartDNS/SNI Proxy）有什么区别？
EDNS 宣告：仅在 DNS 查询阶段向 Google 欺骗来源 IP 段，后续建立连接时完全不经过第三方中转服务器，网速与延迟不受任何影响。适合用于修正 Google 搜索定位、YouTube 地区判定等。

传统 DNS 解锁：将特定流量中转至第三方解锁服务器，适合用于对抗检测严格的流媒体（如 Netflix、Disney+ 等）。
