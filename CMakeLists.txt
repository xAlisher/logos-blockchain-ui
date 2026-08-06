cmake_minimum_required(VERSION 3.14)
project(LogosNode1clickPlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

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
