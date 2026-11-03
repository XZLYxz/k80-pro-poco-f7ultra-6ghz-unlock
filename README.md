# K80 Pro 6 GHz unlock — experimental, version locked

用于 Redmi K80 Pro（`miro`）指定国际版 ROM 的 Wi-Fi 6 GHz 驱动补丁与 Magisk 模块生成工具。
仓库只包含独立编写的脚本和文档。使用者提供本机原驱动，在电脑上校验并生成安装包。

## 已验证范围

| 项目 | 唯一已验证的配置 |
| --- | --- |
| 设备 | Redmi K80 Pro / miro |
| ROM | OS3.0.302.0.WOMMIXM |
| 运行内核 | 6.6.118-android15-8-ge56cf6b09cca-ab15511674-4k |
| 驱动 | qca_cld3_peach_v2.ko / PEACH_V2 |
| 原驱动 SHA-256 | `7c819c0f62642272466673e337e8bba64b95a624bcd8dbd62895666cf1a14f5d` |
| 补丁后 SHA-256 | `ce569057afb29cd691c84391f2d278d3e2dc235e851104d193ef69d0ff8f5335` |
| Wi-Fi INI SHA-256 | `d9786ba2cd67cc1a569d1f101abbf0b96b51c5093f6ef563936616f9b0ac5732` |

需要已解锁 Bootloader、可用的 Magisk root，以及系统自带的 `/system/bin/iw`。
其他 ROM、内核、驱动哈希和设备均不在支持范围内；不适用于小米平板。
不要删除版本或哈希检查来尝试跨版本加载。

## 本地构建

电脑需要 Python 3 和 ADB，先确认只连接目标手机：

```sh
adb devices
adb pull /vendor/lib/modules/qca_cld3_peach_v2.ko ./original-driver.ko
python3 build.py ./original-driver.ko
```

输出为 `build/K80Pro-6GHz-Magisk-v1.3-local.zip`。构建只读取本机驱动文件，不连接手机、不下载文件、不修改系统。
原驱动校验不符时拒绝构建；原文件不会被覆盖。

在 Magisk 应用内从本地安装生成的 ZIP。安装后正常重启，保持 Wi-Fi 开启，等待系统启动及两分钟观察完成。
模块操作会短暂断开 Wi-Fi；测试前请保存工作，保留可用的 USB 调试连接。

## 补丁原理

该版本驱动在 `get_hw_version_platform() == 3` 时，会覆盖配置中的频段设置，强制仅支持 2.4/5 GHz，并设置 OEM 6 GHz 禁用标志。
补丁将两条条件跳转改为跳过这些覆盖的无条件跳转，保留原驱动其余内容。

| .text 相对位置 | 文件偏移 | 原指令 | 新指令 |
| --- | --- | --- | --- |
| 0x1a8b6c | 0x40bb2c | 0x54000261 | 0x14000013 |
| 0x1ac6a0 | 0x40f660 | 0x54000141 | 0x1400000a |

以上是该哈希对应的 ARM64 小端指令字。构建工具同时校验输入哈希、原指令和输出哈希。
这不是通用的频段解锁方案，也不能补齐其他驱动缺失的 6 GHz 实现。

## 模块行为与恢复

模块 v1.3 在 Android 启动完成后检查设备、ROM、内核、驱动与 INI 哈希，再正常卸载原驱动并加载模块目录内的副本。
不强制卸载，不改写原始 vendor 文件、固件、校准数据或启动分区。脚本会应用 `US` 国家代码覆盖；请仅在所在地区法规允许的频段和条件下使用，不要把该覆盖当作监管许可。

- Wi-Fi 关闭时等待至多两分钟，然后跳过；开启 Wi-Fi 后可在 Magisk 模块页点“操作”。
- 版本不符、正常卸载失败或加载失败会停用模块；加载失败会尝试重载原驱动。
- 驱动变更前写入观察标记。若在观察完成前发生重启，下次执行脚本时会停用模块，避免重复加载。
- 保护措施不能保证避免所有内核崩溃或启动故障，也不能证明长期稳定性。

`ACTIVE` 只表示通过检查并注册 6 GHz 频段，不代表已经连接到 6 GHz AP。
可用以下命令检查状态和实际连接信息；日志可能含设备或网络标识，分享前自行脱敏：

```sh
adb shell "su -c 'cat /data/adb/modules/k80pro_wifi6g/status'"
adb shell cmd wifi status
```

停用或卸载后正常重启，以重新加载原驱动。若 ADB 和 root 可用，也可执行：

```sh
adb shell "su -c 'touch /data/adb/modules/k80pro_wifi6g/disable'"
adb reboot
```

## 验证与局限

2026-11-01 单台设备测试：独立 6 GHz AP 实际连接在 6295 MHz，802.11be、320 MHz、双空间流；局域网网关 ping 15 次无丢包。模块 v1.3 经一次正常重启后自动加载并完成观察，原驱动及 INI 哈希未改变，SELinux 保持 Enforcing。

此前临时测试曾发生一次设备自行重启，记录的重启原因是 `rollback_staged_install`；没有证据足以完全确认与补丁的因果关系。未做长期稳定性测试，未验证所有信道、热点模式或所有 MLO 行为。没有公开原始扫描记录或设备日志。

## 许可证

独立脚本与文档采用 [MIT](LICENSE)；厂商驱动不属于本项目的 MIT 授权范围。有关本地生成安装包中的驱动，请先阅读 [NOTICE](NOTICE)。仓库不提供厂商驱动二进制或固件。

Magisk 模块机制参考[官方开发文档](https://topjohnwu.github.io/Magisk/guides.html)。
