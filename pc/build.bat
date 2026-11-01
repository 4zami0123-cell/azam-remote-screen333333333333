@echo off
cd /d %~dp0
python -m pip install -r requirements.txt
python -m PyInstaller --noconfirm --onefile --windowed --name "Azam Share" --icon icon.ico --add-data "icon.ico;." azam_share.py
echo.
echo Done: dist\Azam Share.exe
pause
