@echo off
rem ---------------------------------------------------------------------------
rem  TNGram in enhanced-quality mode: smooths the edges of shapes (MSAA).
rem  Needs a graphics card with Vulkan or DirectX 12 support.
rem  If the app does not start - just run the usual TNGram.exe.
rem ---------------------------------------------------------------------------
start "" "%~dp0TNGram.exe" --rendering-method mobile
