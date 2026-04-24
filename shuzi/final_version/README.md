# 单bit通信端口设计（主机侧RTL实现）
# Single-Bit Communication Port Design (Host-Side RTL)

## 项目简介 | Overview
本项目面向课堂实验场景，基于 Verilog/SystemVerilog 实现单线双向 DQ 总线主机控制逻辑。主机通过复位-响应、配置、启动、转换、读取等流程与从机（由 BFM 模拟）交互，并在 `data_out_en` 有效时输出 24bit 并行数据。工程提供了完整的仿真平台（BFM + CHECKER + 数据文件），可用于功能验证与波形分析。

This project is a classroom-oriented RTL implementation of a single-wire bidirectional DQ host controller using Verilog/SystemVerilog. The host communicates with a slave device (modeled by BFM) through reset-response, configuration, start, conversion, and read stages, and outputs 24-bit parallel data when `data_out_en` is asserted. A complete verification environment (BFM + CHECKER + data files) is included for functional validation and waveform analysis.

## 项目描述（100-300字） | Project Description (100-300 Chinese Characters)
本项目实现了一个基于单线双向 DQ 总线的 AD 采集主机控制模块，使用 Verilog/SystemVerilog 完成协议时序、命令发送与数据读取逻辑。设计按“复位-配置-启动-转换-读取”流程工作，支持发送 0x4E/0x48/0x44/0xBE 命令，并在读取阶段输出 24bit 并行结果。项目配套 BFM 与 CHECKER 验证环境，通过参考数据文件自动比对输出正确性，能够在课堂实验中完成从代码实现、仿真运行、波形观察到结果验收的完整闭环。

This project implements a host-side AD acquisition controller over a single-wire bidirectional DQ bus. The RTL covers protocol timing, command transmission, and data reception using Verilog/SystemVerilog. The flow follows reset, configuration, start, conversion, and read stages, supporting commands 0x4E/0x48/0x44/0xBE and producing 24-bit parallel output data. With the provided BFM and CHECKER, the output is automatically compared against reference data files, enabling a complete classroom workflow from coding and simulation to waveform inspection and final acceptance.

## 目录结构 | Directory Structure

```text
final_version/
  project/
    data/
      AD_trans_data.txt
      bfm_received_data.txt
    rtl/
      data_interface_rtl.sv
    sim/
      files.f
      Makefile
      run.tcl
      modelsim.ini
    tb/
      tb.sv
      adc_bfm.sv
      CHECKER.sv
  单bit通信端口设计.pdf
```

## 开发与仿真环境 | Environment
- OS: Windows
- Simulator: ModelSim/Questa（建议可用版本；旧版本请使用 `-novopt`）
- Simulator: ModelSim/Questa (recommended supported version; use `-novopt` for older versions)
- Toolchain: GNU Make + ModelSim CLI

## 快速开始（仿真） | Quick Start (Simulation)
在系统终端（cmd 或 PowerShell）执行：
Run the following in a system terminal (cmd or PowerShell):

```bash
cd project/sim
make clean
make all
```

说明 | Notes:
- `make all` 会完成编译与运行。
- `make all` performs both compilation and simulation.
- 若出现波形文件占用提示，请关闭已打开的 ModelSim 波形窗口后重试。
- If waveform files are locked, close existing ModelSim waveform windows and retry.

## 查看波形 | View Waveforms

```bash
cd project/sim
vsim -view wave.wlf
```

建议展示信号 | Recommended Signals:
- `/tb/clk`
- `/tb/rst_n`
- `/tb/DQ`
- `/tb/rx_data_en`
- `/tb/rx_data`

## 验收标准 | Acceptance Criteria
满足以下条件可视为通过：
The project is considered passed when all conditions below are met:

1. `comp.log` 编译无报错。  
   No compilation errors in `comp.log`.
2. `run.log` 中命令流程被识别（可见 `receive byte data 4e/48/44/be`）。  
   Command sequence is recognized in `run.log` (shows `receive byte data 4e/48/44/be`).
3. `run.log` 无 `verification error`。  
   No `verification error` appears in `run.log`.
4. `run.log` 出现 `has all been checked`，表示 CHECKER 全量比对完成。  
   `has all been checked` appears in `run.log`, indicating full checker completion.

## 说明 | Additional Notes
- 工程中包含课程实验所需的测试平台与参考数据。
- The repository includes a complete testbench and reference data for classroom experiments.
- 若使用较老 ModelSim/Questa 版本，可能在优化阶段出现工具内部错误；可通过非优化运行参数规避。
- Older ModelSim/Questa versions may hit internal optimizer issues; use non-optimized run options to avoid them.
