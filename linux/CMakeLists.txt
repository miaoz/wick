cmake_minimum_required(VERSION 3.16)

# Prefer Qt 6.8 (Debian 13 / Omarchy). 6.4 is the floor if 6.8 is not findable.
project(wick VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 6.4 REQUIRED COMPONENTS Quick Widgets Svg)

qt_add_executable(wick
    src/main.cpp
    src/TimeProgress.cpp
    src/TimeProgress.h
    src/TrayController.cpp
    src/TrayController.h
    src/ProgressWindow.cpp
    src/ProgressWindow.h
    resources/resources.qrc
)

target_link_libraries(wick PRIVATE
    Qt6::Quick
    Qt6::Widgets
    Qt6::Svg
)

target_compile_definitions(wick PRIVATE
    QT_NO_CAST_FROM_ASCII
    QT_NO_NARROWING_CONVERSIONS_IN_CONNECT
)

set_target_properties(wick PROPERTIES
    OUTPUT_NAME wick
)
