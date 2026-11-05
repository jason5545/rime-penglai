# 蓬萊外掛模組（快速鍵、數字選字、送出後空白補標點、依外部頻率表重排）。
# build.sh 把這個資料夾連到 librime 的 plugins/penglai，跟 lua、octagram、predict 一樣靜態合併進 librime.1.dylib。
project(rime-penglai)
cmake_minimum_required(VERSION 3.10)

aux_source_directory(src penglai_src)

add_library(rime-penglai-objs OBJECT ${penglai_src})
if(BUILD_SHARED_LIBS)
  set_target_properties(rime-penglai-objs
    PROPERTIES
    POSITION_INDEPENDENT_CODE ON)
endif()

set(plugin_name rime-penglai PARENT_SCOPE)
set(plugin_objs $<TARGET_OBJECTS:rime-penglai-objs> PARENT_SCOPE)
set(plugin_deps ${rime_library} ${rime_gears_library} PARENT_SCOPE)
set(plugin_modules "penglai" PARENT_SCOPE)
