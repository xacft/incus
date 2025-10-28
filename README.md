一键运行
bash <(curl -L -s https://raw.githubusercontent.com/xacft/incus/main/incus_auto_optimize.sh)

# 1️⃣ 优化宿主
sudo bash incus_auto_optimize_v2.sh

# 2️⃣ 应用 sysctl
sudo systemctl restart systemd-sysctl

# 3️⃣ 重启生效
sudo reboot
