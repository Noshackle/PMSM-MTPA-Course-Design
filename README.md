# 基于 MTPA 的 PMSM 双闭环调速系统课程设计

本仓库公开保存该课程设计的最终交付材料，包括仿真模型、工况文件、MTPA 查表文件、课程报告和答辩 PPT。

## 目录说明

- `仿真文件/`
  - `PMSM_MTPA.slx`：当前可运行的 Simulink 主模型
  - `scenario.mat`：Signal Editor 使用的四个工况场景
  - `mtpa_lookup_tables.mat`：MTPA 查表法所需的 `Te_table`、`id_table`、`iq_table`
  - `PMSM双闭环调速系统MTPA课程设计任务书.docx`：原始任务书
  - `工具/generate_pmsm_support_files.m`：用于重新生成 `scenario.mat` 和 `mtpa_lookup_tables.mat` 的 MATLAB 脚本
- `课程报告/`
  - `PMSM_MTPA_课程设计报告.docx`：课程设计报告
- `答辩PPT/`
  - `PMSM_SVPWM_MTPA_负责部分_5页.pptx`
  - `PMSM_SVPWM_MTPA_负责部分_6页详细版.pptx`
  - `PMSM_SVPWM_MTPA_负责部分_7页优化版.pptx`

## 四个工况

`scenario.mat` 中包含以下四个场景：

1. `Scenario1`：空载启动，`n_ref` 在 `0.05 s` 从 `0` 跳到 `1000 rpm`，`Tm = 0 N·m`
2. `Scenario2`：带载启动，`n_ref` 在 `0.05 s` 从 `0` 跳到 `1000 rpm`，`Tm = 2 N·m`
3. `Scenario3`：转速阶跃，`n_ref` 在 `2.5 s` 从 `500 rpm` 跳到 `1000 rpm`，`Tm = 1 N·m`
4. `Scenario4`：负载突加，`n_ref` 在 `0.05 s` 从 `0` 跳到 `1000 rpm`，`Tm` 在 `2.5 s` 从 `0` 跳到 `2 N·m`

## MTPA 查表文件

`mtpa_lookup_tables.mat` 中包含：

- `Te_table`
- `id_table`
- `iq_table`

模型已在 `PostLoadFcn` 和 `InitFcn` 中配置自动加载这三个变量，因此正常打开模型后可直接仿真。

## 本次修复内容

- 恢复了 `Signal Editor` 丢失的外部工况文件
- 重建了 MTPA 查表法所需的 `.mat` 数据
- 将模型中的 `Signal Editor` 路径修正为当前工程目录下的本地文件
- 为模型补充了查表变量自动加载逻辑

## 验证说明

已对修复后的模型进行了短时仿真验证，模型可以正常完成初始化并运行，`Signal Editor` 场景文件和 MTPA 查表变量均可被正确读取。
