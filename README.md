# FPGA 双板电子琴发布版

最终版：**spectrum_65_1k（2026-11-04 04:43 构建）**。本目录是原工程的独立发布副本；本次仅复制整理，未重新综合、P&R、烧录或实机验收。

## 项目简介

双板 TTP229 演奏、PAJ7620 手势扫弦、RP108 六旋钮与两只 EC11；32 声部 × 16 分量 = 512 个加法分量，支持钢琴、吉他、小提琴、古筝和琵琶五种音色，以及 ADSR、音量声像、合唱/延迟/混响、动作录放。手机 App 经蓝牙 → ESP32 导入曲谱，采用按对再继续的等待式跟弹，和弦需按齐后推进。

界面为 10 页串口屏；真实 PCM 频谱为 **65 Hz–1 kHz、32 段**，李萨如采用 128 点轨迹。屏幕底部刻度按 UI 要求标为 63 / 125 / 250 / 500 / 1k，分析中心仍为 65 Hz–1 kHz。

硬件：Tang Mega 138K + Dock 31002，器件 **GW5AST-LV138PG484AC2/I1**，主时钟 52.5 MHz，采样率 fs ≈ 49.667 kHz。既有实测端到端延迟约 **525 μs**（用户提供；本次整理未重新测量）。

## 目录

```text
eda_proj/
  src/                       RTL、CST/SDC、ROM 与 IP 输入
  sim/                       仿真源文件，不含波形和编译产物
  tools/                     原 EDA 辅助脚本及随附 Icarus 工具
  audio.gprj                 Gowin 工程
  build_current.tcl          固定输出名的构建入口
  OPEN_CURRENT_PROGRAMMER.cmd  打开本发布位流，不自动烧录
  release.json               发布版本及哈希
hmi/ui_main/                 CF-Design 工程与实际引用资源
release/
  spectrum_65_1k.fs                 完整电子琴位流
  spectrum_65_1k.rpt.txt            原始 P&R 资源报告
  spectrum_65_1k.timing_paths       原始时序路径记录
  SD_card.zip                源工程现有串口屏下载数据
```

指定的 `eda_proj/results`：**无对应验证记录**；未用旧版 `current` 顶替。未额外复制源工程根目录的其他 results。

## 关键引脚

下表全部读取自 `eda_proj/src/audio.cst`，引脚号为 FPGA 封装球位。

|用途|RTL 端口（顺序对应）|芯片引脚|
|---|---|---|
|串口屏 TX / RX|UART_TX / UART_RX|R18 / T18|
|ESP32 TX / RX|BLE_TX / BLE_RX|AA20 / B18|
|左 TTP229 时钟 / 数据|TTP229_SCL / TTP229_SDO|AB21 / AB22|
|右 TTP229 时钟 / 数据|TTP_R_SCL / TTP_R_SDO|P16 / R17|
|PAJ7620 SCL / SDA|PAJ_SCL / PAJ_SDA|C14 / B13|
|RP108 SCL / SDA|KNOB_SCL / KNOB_SDA|C18 / C19|
|EC11 A / B / 按键|ENC_A / ENC_B / ENC_C|E14 / E13 / C15|
|八度 EC11 A / B / 按键|OCT_A / OCT_B / OCT_SW_N|A13 / A14 / B15|
|音频数据 / 字时钟 / 位时钟|HP_DIN / HP_WS / HP_BCK|AA16 / AB17 / Y17|
|功放使能|PA_EN|AB16|
|WS2812|WS2812_DIN|J16|
|板载 KEY1 / KEY2 / KEY3|KEY1 / KEY2 / TIMBRE_KEY|AB13 / Y12 / AA13|
|外接四键|K_LEFT / K_RIGHT / K_AUX3 / K_AUX4|E19 / D19 / D20 / C20|
|移调上 / 下|PITCH_UP_KEY / PITCH_DOWN_KEY|AA19 / AB20|
|测试键|TEST_MODE_KEY|Y22|
|复位|rst|F4|

FPGA `UART_TX` → 屏 RX，FPGA `UART_RX` ← 屏 TX；FPGA `BLE_TX` → ESP32 RX，FPGA `BLE_RX` ← ESP32 TX，均需共地。CST 中 `rst` 为 LVCMOS15 / 1.5 V，其余表列 GPIO 为 LVCMOS33 / 3.3 V。

## 编译

Gowin IDE V1.9.12.04 打开 `eda_proj/audio.gprj`，顶层 `top`，执行综合和布局布线。也可在 PowerShell 运行：

```powershell
& 'D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe' 'E:\FPGA\electronic_instrument_release\eda_proj\build_current.tcl'
```

该脚本固定输出 `spectrum_65_1k`，重新编译的产物位于 `eda_proj/impl/pnr/`；须重新检查新报告，不能沿用本次发布的时序结论。

## FPGA 下载

Programmer 手动选择 `release/spectrum_65_1k.fs`，器件选择 GW5AST-138B。临时运行使用 SRAM Program；断电保留按板卡配置选择外部 Flash 编程方式并核对 Flash 型号。`eda_proj/OPEN_CURRENT_PROGRAMMER.cmd` 只打开这个发布位流，最后的下载操作由用户执行。

## 串口屏下载

将 `release/SD_card.zip` 的内容解压到 FAT32 TF 卡根目录，`config.txt`、图片和字体文件直接位于卡根，避免多套一层目录；随后按屏幕厂家 TF 卡升级流程下载。压缩包逐文件复制源目录 `hmi/ui_main/output/SD_card`，包含 53 个文件；本次未重新运行 CF-Design 编译或实屏下载。

需修改 UI 时，使用 `hmi/ui_main/电子琴OS_双板五音色.cfprj` 重新编译、检查错误后下载新输出。源目录现有编译包的频谱背景已目视核对为 63 / 125 / 250 / 500 / 1k。

## 资源与时序

资源来自 `release/spectrum_65_1k.rpt.txt`：

|资源|使用 / 总量|报告占用率|
|---|---:|---:|
|Logic|28,785 / 138,240|21%|
|Register|21,714 / 139,095|16%|
|CLS|24,916 / 69,120|37%|
|I/O Port|34 / 297|12%|
|BSRAM|180 / 340|53%|
|DSP|97 / 298|33%|

时序路径记录最小 Setup **+3.675 ns**、Hold **+0.184 ns**；原构建 STA 的 Setup/Hold 违规端点均为 **0**。`.timing_paths` 记录 120 条 Setup、100 条 Hold 路径；端点总数由源工程同名 `spectrum_65_1k_tr_content.html` 补充核对，因为要求复制的两个报告不含端点汇总。未将有限条正裕量路径冒充全设计端点统计。

原构建仍有 TA1123 时钟一致性告警；本次未修改时钟、约束或功能源码。

数值来源：构建版本/器件/资源见 `.rpt.txt` 与构建脚本；52.5 MHz 见 `src/gowin_pll/gowin_pll.v` 和 `src/audio.sdc`；fs 按 PLL 的 31/(2×128)、CLKDIV ÷4、每帧 32 位推得；10 页见 CF 工程 Pages，32 段及频率见 `src/migration/spectrum_bins.v`，512 分量见 `mig_additive_engine.v`，128 点见 `hmi_viz_tx.v`；525 μs 来自用户既有实测说明。
