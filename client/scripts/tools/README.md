# 打包用工具

## zip.exe

- **用途**：打 Windows 便携包（`--platform win-x64`）时用于生成标准 .zip 压缩包。
- **来源**：Info-ZIP Zip 3.0 Windows 32-bit 二进制（<http://www.info-zip.org/>），从 `ftp://ftp.icm.edu.pl/packages/info-zip/win32/zip300xn.zip` 解出。
- **协议**：Info-ZIP 许可证（类 BSD）。
- 打包脚本会优先使用本目录下的 `zip.exe`，无需系统安装 zip 或 7z。
