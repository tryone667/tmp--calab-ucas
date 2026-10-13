@echo off
REM ============================================================================
REM  Vivado xsim CLI simulation for C:\vivado_prj\expN
REM  usage:  run_sim_cli.bat 8      (default N=8)
REM  steps : xvlog --incr --relax  ->  xelab --snapshot tb_top_sim tb_top glbl
REM          ->  xsim tb_top_sim -R
REM  log   : <run_vivado>\project\loongson.sim\sim_1\behav\xsim_cli\simulate.log
REM  needs : C:\vivado_prj\expN\gettrace\golden_trace.txt  (tb opens it via
REM          relative path 8 levels up)  and  func\obj\*.mif
REM  note  : --relax is required, mycpu_top.v has a forward reference that
REM          plain xvlog rejects (project mode passes --relax automatically)
REM ============================================================================
setlocal
set N=%1
if "%N%"=="" set N=8
call "C:\Application\Xilinx\Vivado\2019.2\settings64.bat" >nul 2>&1
set "VPROJ=C:\vivado_prj\exp%N%"
set "RUN=%VPROJ%\soc_verify\soc_bram\run_vivado\project\loongson.sim\sim_1\behav\xsim_cli"
set "TB=%VPROJ%\soc_verify\soc_bram\testbench"
set "RTL=%VPROJ%\soc_verify\soc_bram\rtl"
set "CPU=%VPROJ%\myCPU"
if not exist "%RUN%" mkdir "%RUN%"
copy /y "%RTL%\xilinx_ip\inst_ram\inst_ram.mif" "%RUN%\" >nul
copy /y "C:\Application\Xilinx\Vivado\2019.2\data\verilog\src\glbl.v" "%RUN%\" >nul
cd /d "%RUN%"
echo ==== XVLOG (compile) ====
call xvlog --incr --relax "%RTL%\xilinx_ip\clk_pll\clk_pll_clk_wiz.v" "%RTL%\xilinx_ip\clk_pll\clk_pll.v" "%RTL%\xilinx_ip\data_ram\sim\data_ram.v" "%RTL%\xilinx_ip\inst_ram\sim\inst_ram.v" "%CPU%\alu.v" "%RTL%\BRIDGE\bridge_1x2.v" "%RTL%\CONFREG\confreg.v" "%CPU%\mycpu_top.v" "%CPU%\regfile.v" "%RTL%\soc_lite_top.v" "%CPU%\tools.v" "%TB%\mycpu_tb.v" glbl.v -log xvlog.log
if errorlevel 1 goto FAIL
echo ==== XELAB (elaborate) ====
call xelab --incr --debug typical --relax --mt 2 -L blk_mem_gen_v8_4_4 -L unisims_ver -L unimacro_ver -L secureip -L xpm --snapshot tb_top_sim tb_top glbl -log xelab.log
if errorlevel 1 goto FAIL
echo ==== XSIM (run all) ====
call xsim tb_top_sim -R -log simulate.log
if errorlevel 1 goto FAIL
echo ==== SIM OK : %RUN%\simulate.log ====
exit /b 0
:FAIL
echo ==== SIM FAILED : see xvlog.log / xelab.log / simulate.log in %RUN% ====
exit /b 1
