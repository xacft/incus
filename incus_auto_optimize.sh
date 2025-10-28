#!/bin/bash

set -e

echo "=============================================="
echo "🔧 Incus / LXC 宿主性能优化脚本启动..."
echo "=============================================="

# -------------------------
# 检测架构
# -------------------------
ARCH=$(uname -m)
if [[ "$ARCH" =~ "x86_64" ]]; then
  CPU_ARCH="x86_64"
elif [[ "$ARCH" =~ "aarch64" ]]; then
  CPU_ARCH="ARM64"
else
  CPU_ARCH="OTHER"
fi

echo "🧩 检测到架构: $CPU_ARCH"

# -------------------------
# 检测包管理器
# -------------------------
if command -v apt >/dev/null 2>&1; then
  PKG_INSTALL="apt install -y"
  PKG_UPDATE="apt update -y"
elif command -v yum >/dev/null 2>&1; then
  PKG_INSTALL="yum install -y"
  PKG_UPDATE="yum makecache"
elif command -v dnf >/dev/null 2>&1; then
  PKG_INSTALL="dnf install -y"
  PKG_UPDATE="dnf makecache"
else
  echo "❌ 未检测到支持的包管理器（apt/yum/dnf）"
  exit 1
fi

$PKG_UPDATE >/dev/null 2>&1

# ==========================================================
# CPU 优化
# ==========================================================
echo "⚙️ [1/6] CPU 调度模式优化..."

if [[ "$CPU_ARCH" == "x86_64" ]]; then
  if command -v cpupower >/dev/null 2>&1; then
    cpupower frequency-set -g performance || true
  else
    $PKG_INSTALL linux-tools-common >/dev/null 2>&1 || true
    cpupower frequency-set -g performance || true
  fi
elif [[ "$CPU_ARCH" == "ARM64" ]]; then
  echo "ARM 平台：设置 CPU governor 为 performance"
  for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
    echo performance > "${cpu}/cpufreq/scaling_governor" 2>/dev/null || true
  done
fi

# ==========================================================
# I/O 优化
# ==========================================================
echo "💾 [2/6] 优化 I/O 调度器为 none/mq-deadline..."
for dev in /sys/block/sd* /sys/block/vd* /sys/block/nvme*; do
  [ -e "$dev/queue/scheduler" ] && echo none > "$dev/queue/scheduler" 2>/dev/null || true
done

# ==========================================================
# 内核 sysctl 优化
# ==========================================================
echo "🧠 [3/6] 内核与网络参数优化..."

cat <<EOF | tee /etc/sysctl.d/99-incus-performance.conf >/dev/null
# 网络优化
net.core.somaxconn = 1024
net.core.netdev_max_backlog = 4096
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# 内存优化
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.vfs_cache_pressure = 50
vm.overcommit_memory = 1

# 文件系统优化
fs.aio-max-nr = 1048576
fs.file-max = 2097152
EOF

sysctl --system >/dev/null 2>&1

# ==========================================================
# HugePages 优化
# ==========================================================
echo "📦 [4/6] 启用 HugePages..."
echo "vm.nr_hugepages = 128" >> /etc/sysctl.d/99-incus-performance.conf
sysctl -p /etc/sysctl.d/99-incus-performance.conf >/dev/null 2>&1

# ==========================================================
# IRQ 平衡
# ==========================================================
echo "⚡ [5/6] 启用中断均衡 (irqbalance)..."
if ! command -v irqbalance >/dev/null 2>&1; then
  $PKG_INSTALL irqbalance >/dev/null 2>&1 || true
fi
systemctl enable irqbalance >/dev/null 2>&1 || true
systemctl start irqbalance >/dev/null 2>&1 || true

# ==========================================================
# 嵌套虚拟化检测
# ==========================================================
echo "🔍 [6/6] 检查嵌套虚拟化支持..."
if [ -f /sys/module/kvm_intel/parameters/nested ]; then
  echo "Intel Nested KVM: $(cat /sys/module/kvm_intel/parameters/nested)"
elif [ -f /sys/module/kvm_amd/parameters/nested ]; then
  echo "AMD Nested KVM: $(cat /sys/module/kvm_amd/parameters/nested)"
elif [ -d /sys/module/kvm ]; then
  echo "检测到 KVM 模块 (ARM 或通用虚拟化)"
else
  echo "⚠️ 未检测到 KVM 模块，可能是二级虚拟环境或非 KVM 宿主。"
fi

echo "✅ 优化完成！建议执行 reboot 以完全生效。"

