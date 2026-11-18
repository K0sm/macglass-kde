cmake_minimum_required(VERSION 3.22)
project(macglass-stack VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(ECM 6.0 REQUIRED NO_MODULE)
list(APPEND CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)

find_package(Qt6 6.6 REQUIRED COMPONENTS Core Gui Widgets Quick QuickControls2 DBus)
find_package(KF6 6.0 REQUIRED COMPONENTS KIO CoreAddons Config WindowSystem Service)
find_package(LayerShellQt REQUIRED)

add_executable(macglass-stack
    src/main.cpp
    src/stackcontroller.cpp
    src/foldermodel.cpp
    src/thumbprovider.cpp
)

# QML is loaded from disk so it can be tweaked without recompiling.
target_compile_definitions(macglass-stack PRIVATE
    MACGLASS_QML_DIR="${KDE_INSTALL_FULL_DATADIR}/macglass/stack/qml"
    MACGLASS_VERSION="${PROJECT_VERSION}")

target_link_libraries(macglass-stack PRIVATE
    Qt6::Widgets Qt6::Quick Qt6::QuickControls2 Qt6::DBus
    KF6::KIOCore KF6::KIOGui KF6::KIOWidgets
    KF6::CoreAddons KF6::ConfigCore KF6::WindowSystem KF6::Service
    LayerShellQt::Interface)

install(TARGETS macglass-stack DESTINATION ${KDE_INSTALL_BINDIR})
install(DIRECTORY qml/ DESTINATION ${KDE_INSTALL_DATADIR}/macglass/stack/qml)
