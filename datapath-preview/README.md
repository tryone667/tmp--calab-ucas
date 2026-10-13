# datapath-preview —— 数据通路预览（exp7~11）

研讨-计算机体系结构课程、LA32R 五级流水 CPU 的**网页版数据通路预览**。单文件、无依赖、双击即看（换机后不用装任何东西）。

## 打开

直接双击 **`index.html`**，一张表链到全部页面：

- `expN/datapath.html` —— **收束版（带端口）**：每个模块按连接画出"进/出"引脚；徽标计数、端口明细表与图上连线自动一致。
- `expN/datapath_drag.html` —— **布线可拖版**：同上结构 + 交互——拖模块、滚轮缩放、空白拖平移、悬停高亮、连线悬停显示信号名；连线自动**避让模块框**（不穿过框图），直角/圆角可切，右上角有"适配视图 / 复位布局"。
- `expN/web/viewer.html` —— **DigitalJS 全量门级图**（exp8~11）：可钻模块、悬停高亮。

## 重新生成 / 改图

```
python -X utf8 datapath_gen.py
```

- 所有 spec（SPEC7~SPEC11：模块、端口、连线、说明）都写在 `datapath_gen.py` 里；改完重跑，即按 `expN/datapath.html`、`expN/datapath_drag.html` 覆盖生成。
- 只用 Python 标准库（3.8+），无第三方依赖；控制台中文乱码不影响生成文件。
- `expN/web/` 是 `verilog-viz/tools/build.py`（Yosys→DigitalJS）的产物，重新生成走那条链。

## 复习对照提示

- exp8：前端 ①②③④ 四根红线（cancel + 改道）+ 底部三根撞车红线与虚线反压（阻塞）。
- exp9："操作数选择"底下三根前递长线（EX/MEM/WB → ID）。
- exp10：新增"除法器（32 拍）"块与 busy 红线。
- exp11：`ls_type[4]` 随 ID/EX、EX/MEM 传递；数据 RAM 掩码写、"MEM 取值 / 载入选择"五路选择；分支判定多两个比较器（signed/unsigned）。
