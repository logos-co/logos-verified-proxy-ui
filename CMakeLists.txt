cmake_minimum_required(VERSION 3.14)
project(VerifiedProxyUiPlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

# Universal UI module: we write the .rep view contract and the backend class;
# REP_FILE runs repc and the generated *Plugin glue (Q_PLUGIN_METADATA,
# initLogos wiring, QtRO registration) is compiled in automatically.
logos_module(
    NAME verified_proxy_ui
    REP_FILE src/VerifiedProxyBackend.rep
    SOURCES
        src/VerifiedProxyBackend.h
        src/VerifiedProxyBackend.cpp
    INCLUDE_DIRS
        src
)

# Expose the UI version (from metadata.json) to the backend at compile time.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json" _ui_metadata)
string(JSON VERIFIED_PROXY_UI_VERSION GET "${_ui_metadata}" version)
target_compile_definitions(verified_proxy_ui_module_plugin
    PRIVATE VERIFIED_PROXY_UI_VERSION="${VERIFIED_PROXY_UI_VERSION}")
