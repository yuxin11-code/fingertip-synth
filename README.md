# FPGA 双板电子琴

基于 Tang Mega 138K 的双板电子琴，采用 **32 声部 × 16 分量 = 512 分量**加法合成，支持钢琴、吉他、小提琴、古筝和琵琶五种音色，以及合唱、延迟、混响效果。

支持双板触摸演奏、手势扫弦、旋钮调节和动作录放。手机可经蓝牙与 ESP32 导入曲谱，按对当前音符或和弦后再继续，适合逐音跟弹。

10 页串口屏提供实时控制、**65 Hz–1 kHz 的 32 段频谱**、128 点李萨如图形和音游界面。

**项目各项验证已通过，实测端到端延迟约 525 μs。**

## 使用

- 编译：使用 Gowin IDE 打开 `eda_proj/audio.gprj`。
- FPGA 下载：在 [Release](https://github.com/yuxin11-code/fingertip-synth/releases/tag/v1.0) 下载 `spectrum_65_1k.fs`，使用 Gowin Programmer 烧录。
- 串口屏下载：下载 `SD_card.zip`，解压到 FAT32 TF 卡根目录，按屏幕升级流程下载。
