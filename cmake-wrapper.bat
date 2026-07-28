@echo off
setlocal
if "%~1"=="--build" (
    "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native\build-tools\cmake\bin\cmake.exe" %*
) else (
    "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native\build-tools\cmake\bin\cmake.exe" -DCMAKE_MAKE_PROGRAM=C:/ohos/sdk/build-tools/cmake/bin/ninja.exe %*
)
