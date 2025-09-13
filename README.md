# 客户机固件

本仓库用于构建/存放预编译的 AxVisor 客户机固件，以便进行统一测试！

## 飞腾派

基于 https://gitee.com/phytium_embedded/phytium-pi-os 构建，详见 https://arceos-hypervisor.github.io/axvisorbook/docs/quickstart/phytiumpi

## ROC-RK568-PC

基于官方 SDK 构建，详见 https://arceos-hypervisor.github.io/axvisorbook/docs/quickstart/roc-rk3568-pc

## QEMU

TODO

# 服务端

执行 http_server.py 可以在 IMAGES 目录下启动一个 HTTP 服务端，以便可以通过 wget 等工具直接下载镜像文件。