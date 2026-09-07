$ErrorActionPreference = "Stop"

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    throw "此构建脚本只能在 Windows 11 上运行。"
}

Set-Location $PSScriptRoot
$venvRoot = Join-Path $PSScriptRoot ".venv-build"
$venvPython = Join-Path $venvRoot "Scripts\python.exe"

py -3.12 -m venv $venvRoot
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $venvPython)) {
    throw "Python 3.12 虚拟环境创建失败。请先运行 'py -3.12 --version' 检查安装。"
}

& $venvPython -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "pip 更新失败。" }
& $venvPython -m pip install -r requirements-dev.txt
if ($LASTEXITCODE -ne 0) { throw "项目依赖安装失败。" }
& $venvPython -m pytest
if ($LASTEXITCODE -ne 0) { throw "测试失败，已停止打包。" }
& $venvPython -m PyInstaller --noconfirm --clean Emangato.spec
if ($LASTEXITCODE -ne 0) { throw "PyInstaller 构建失败。" }

$archive = Join-Path $PSScriptRoot "dist\Emangato_Windows.zip"
$packageRoot = Join-Path $PSScriptRoot "dist\Emangato"
if (-not (Test-Path -LiteralPath $packageRoot)) {
    throw "构建目录不存在：$packageRoot"
}
if (Test-Path $archive) {
    Remove-Item $archive
}
Compress-Archive -Path "$packageRoot\*" -DestinationPath $archive -CompressionLevel Optimal
Write-Host "构建完成：$archive"
