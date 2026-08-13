cmake_minimum_required(VERSION 3.14)
project(LogosNode1clickPlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

# ── Version drift guard ──────────────────────────────────────────────────────────
# The dashboard renders "Module v<x>" from a literal in NodeDashboardView.qml. It carried
# a "keep in sync with metadata.json" comment and drifted three releases anyway: the UI
# said 0.2.6 while the module shipped as 0.2.12. Comments do not enforce; this does.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json" _meta_json)
string(JSON _meta_version GET "${_meta_json}" version)
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/qml/views/NodeDashboardView.qml" _dash_qml)
if(NOT _dash_qml MATCHES "property string moduleVersion: \"([^\"]+)\"")
    message(FATAL_ERROR "Version guard: could not find moduleVersion in NodeDashboardView.qml")
endif()
set(_qml_version "${CMAKE_MATCH_1}")
if(NOT _qml_version STREQUAL _meta_version)
    message(FATAL_ERROR
        "Version drift: NodeDashboardView.qml says ${_qml_version} but metadata.json says "
        "${_meta_version}. Update the moduleVersion literal so the UI does not report a "
        "version the module is not.")
endif()
message(STATUS "Version guard: UI and metadata agree at ${_meta_version}")

logos_module(
    NAME logos_node_1click
    REP_FILE src/BlockchainBackend.rep
    SOURCES
        src/logos_node_1click_backend.h
        src/logos_node_1click_backend.cpp
        src/AccountsModel.h
        src/AccountsModel.cpp
        src/BlockModel.h
        src/BlockModel.cpp
    INCLUDE_DIRS
        src
    FIND_PACKAGES
        Qt6Gui
    LINK_LIBRARIES
        Qt6::Gui
)
