@echo off

:: Make sure this is a decent name and not generic
set exe_name=odin.exe

:: Debug = 0, Release = 1
if "%1" == "1" (
	set release_mode=1
) else if "%1" == "release" (
	set release_mode=1
) else (
	set release_mode=0
)

:: Normal = 0, CI Nightly = 1
if "%2" == "1" (
    set nightly=1
) else (
    set nightly=0
)

set compiler_flags= -nologo -Oi -TP -fp:precise -Gm- -MP -FC -EHsc- -GR- -GF
set compiler_defines= -DLLVM_BACKEND_SUPPORT -DUSE_NEW_LLVM_ABI_SYSTEM

for /f %%i in ('git rev-parse --short HEAD') do set GIT_SHA=%%i
if %ERRORLEVEL% equ 0 set compiler_defines=%compiler_defines% -DGIT_SHA=\"%GIT_SHA%\"
if %nightly% equ 1 set compiler_defines=%compiler_defines% -DNIGHTLY

if %release_mode% EQU 0 ( rem Debug
	set compiler_flags=%compiler_flags% -Od -MDd -Z7
) else ( rem Release
	set compiler_flags=%compiler_flags% -O2 -MT -Z7
	set compiler_defines=%compiler_defines% -DNO_ARRAY_BOUNDS_CHECK
)

set compiler_warnings= ^
	-W4 -WX ^
	-wd4100 -wd4101 -wd4127 -wd4189 ^
	-wd4201 -wd4204 ^
	-wd4456 -wd4457 -wd4480 ^
	-wd4512

set compiler_includes=
set libs= ^
	kernel32.lib ^
	bin\llvm\windows\LLVM-C.lib

set linker_flags= -incremental:no -opt:ref -subsystem:console

if %release_mode% EQU 0 ( rem Debug
	set linker_flags=%linker_flags% -debug
) else ( rem Release
	set linker_flags=%linker_flags% -debug
)

set compiler_settings=%compiler_includes% %compiler_flags% %compiler_warnings% %compiler_defines%
set linker_settings=%libs% %linker_flags%

del *.pdb > NUL 2> NUL
del *.ilk > NUL 2> NUL

cl %compiler_settings% "src\main.cpp" /link %linker_settings% -OUT:%exe_name% ^
	&& odin check examples/demo

rem odin run examples/demo -llvm-api

rem odin build examples/demo -llvm-api -build-mode:llvm-ir -o:minimal

rem odin build examples/demo -llvm-api -keep-temp-files -opt:2

rem cl %compiler_settings% "src\main.cpp" /link %linker_settings% -OUT:%exe_name% ^
rem 	&& odin doc examples/demo -doc-format -all-packages ^
rem 	&& odin run misc/tools/odin-doc-reader -strict-style -llvm-api

rem odin run misc/tools/odin-doc-reader -strict-style -llvm-api

rem odin build examples/demo -llvm-api -build-mode:assembly -target:darwin_arm64
rem odin build examples/new_sync -llvm-api -target:linux_amd64 -define:ODIN_USE_PTHREADS=true
rem odin test core/path -llvm-api
rem odin test core/thread -llvm-api -target:windows_amd64
rem odin test core/sync/sync2 -llvm-api -target:linux_amd64 -define:ODIN_USE_PTHREADS=true
rem odin test core/thread -llvm-api -target:linux_amd64
rem odin test core/thread -llvm-api -target:linux_amd64
rem odin check core/os/os2 -no-entry-point -vet
rem odin test core/sync/sync2 -llvm-api -target:windows_amd64

rem cl %compiler_settings% "src\main.cpp" /link %linker_settings% -OUT:%exe_name%
rem 	&& odin run examples/new_sync -llvm-api


if %errorlevel% neq 0 goto end_of_build
rem if %release_mode% EQU 0 odin run examples/demo/demo.odin

del *.obj > NUL 2> NUL

:end_of_build
