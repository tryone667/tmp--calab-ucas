# viz —— 可视化线

与实验代码（`prj1/`、`prj2/`）并行的一条线；内容自包含，可整体搬到独立仓库。

- `verilog-viz/`：Verilog 可视化 + 离线调试工具链（含 exp7 正/反 demo、离线仿真材料；见其 README）。
- `datapath-preview/`：exp7~11 数据通路预览静态页（收束图 / 布线可拖版 / DigitalJS 全量图；入口 `index.html`）。

约定：
- 本目录只放可视化/工具本身及其素材，不反向修改实验代码。
- 实验代码更新后，如需刷新预览，用 `datapath-preview/datapath_gen.py` 按需重新生成为止（单向低耦合）。