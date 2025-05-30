cmake_minimum_required(VERSION 3.20)

set(CMAKE_EXPORT_COMPILE_COMMANDS TRUE)

project(
    lang
    VERSION 0.0.1
    LANGUAGES CXX
)

add_executable(lang)
target_include_directories(lang PRIVATE src)

set_property(TARGET lang PROPERTY CXX_STANDARD 20)

if(WIN32)
    target_compile_options(
        lang PRIVATE
        /W4
        /Zc:preprocessor
    )
endif()

add_subdirectory(src)
