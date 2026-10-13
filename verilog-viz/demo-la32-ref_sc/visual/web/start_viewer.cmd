@echo off
cd /d "%~dp0"
start "" http://127.0.0.1:8124/viewer.html
python -m http.server 8124
