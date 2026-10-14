# 单周期 MIPS CPU 可视化 demo

> 目标：验证「Verilog → 仿真 → 电路图 → 交互式查看器」整条链路，作为 VSCode 插件路线的原型。
> 日期：2026-10-12

## 用了什么

| 组件 | 来源 | 许可证 |
| --- | --- | --- |
| CPU 源码 | [diadatp/mips_cpu](https://github.com/diadatp/mips_cpu)（经典教材式 32 位单周期 MIPS） | MIT |
| 仿真 | Icarus Verilog 11.0（WSL） | GPL |
| 综合 | yowasp-yosys（WASM 版 Yosys，免安装） | ISC |
| 静态原理图 | netlistsvg + ELK | MIT / EPL-2.0 |
| 交互式电路 | DigitalJS + yosys2digitaljs | BSD-2 |

## 目录结构

```
demo-single-cycle/
├── mips_cpu-master/            # 原始仓库（未改动）+ sim_add/ 我们的 ADD 仿真
│   └── sim_add/                #   程序里只有一条 add $3,$1,$2（$1=5,$2=3 由 tb 预置）
├── visual/                     # 可视化产物与工具链
│   ├── alu_rtl.svg/png         #   ALU 原理图（RTL 粗粒度，推荐看图）
│   ├── datapath_flat.svg/png   #   数据通路展平图
│   ├── top_flat3.svg/png       #   整个 CPU 展平图（较大）
│   ├── web/                    #   ★ 交互式查看器（VSCode webview 雏形）
│   │   ├── viewer.html         #     打开它（见下方说明）
│   │   ├── circuit_data.js     #     DigitalJS 电路数据（75KB）
│   │   ├── main.js             #     DigitalJS 浏览器 bundle（2.5MB，本地）
│   │   └── start_viewer.cmd    #     一键启动本地服务并打开浏览器
│   └── *.json / *.py / *.js    #   中间产物与工具脚本（rtl4.json = 网表源）
└── README.md
```

## 怎么跑

```powershell
# 1) 仿真：只跑一条 add，验证 $3 = 5 + 3 = 8
wsl -u rain -- bash -lc "cd /mnt/c/course_files/verilog-viz/demo-single-cycle/mips_cpu-master/sim_add && iverilog -o sim_add.out *.v && vvp sim_add.out"

# 2) 交互式查看器（推荐，零安装：需要本机 Python 起静态服务）
.\visual\web\start_viewer.cmd
#    浏览器会自动打开 http://127.0.0.1:8123/viewer.html
#    - 顶部下拉框可切换模块：top / mips / datapath / alu / regfile / dmem ...
#    - alu 页面可交互：给 a_in/b_in/f_in 输入值 → 运行 → 看 y_out（f_in=2 即加法）
```

## 踩过的坑（重要）

1. **top 模块没有任何输出端口** → `opt` / `memory` 等 pass 会把整个 CPU 当死代码删除。
   解法：可视化流程不要跑会触发清理的 pass；用 `proc; memory_collect` 后直接 `write_json`。
2. `memory -nomap` 会做 opt_clean，top 实例被清空（这次调试花时间最多的坑）。
3. yosys2digitaljs 不认识 `$memwr_v2/$memrd`，必须用 `memory_collect` 合并成 `$mem_v2`。
4. netlistsvg 认粗粒度单元（$add/$mux/$dff/$eq...），但 top 只有子模块实例时什么都不画——
   展平（flatten）或单独渲染某个模块才是正确用法。皮肤可用 `--skin` 自定义（我们加了 `$sdff`）。
5. 编辑器页面用 Edge 无头模式自动截图验收：`visual/shot.js`（puppeteer-core）。

## 与 VSCode 插件的距离

- 今天的 `viewer.html` **就是**插件 webview 里要显示的东西：插件只需
  1) 调用 WASM Yosys 生成 JSON（yowasp-yosys 在 Node Worker 里跑，DigitalJS-Schematic-Viewer 已验证）；
  2) 把 JSON 塞进同样的 DigitalJS 页面。
- 参考实现：`VENOMNBB/DigitalJS-Schematic-Viewer`（VSCode + WASM Yosys + DigitalJS + 波形面板）。
- 我们的差异化仍在「手调/回写」：现成工具都只读。
