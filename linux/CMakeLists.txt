cmake_minimum_required(VERSION 3.16)

# Prefer Qt 6.8 (Debian 13 / Omarchy). 6.4 is the floor if 6.8 is not findable.
project(wick VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(OpenSSL REQUIRED)

include(FetchContent)
FetchContent_Declare(
  nlohmann_json
  URL https://github.com/nlohmann/json/releases/download/v3.11.3/json.tar.xz
  URL_HASH SHA256=d6c65aca6b1ed68e7a182f4757257b107ae403032760ed6ef121c9d55e81757d
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
set(JSON_BuildTests OFF CACHE INTERNAL "")
set(JSON_Install OFF CACHE INTERNAL "")
FetchContent_MakeAvailable(nlohmann_json)

# miniz 3.0.2 split sources (same files the local CTest run used).
# Vendoring via push_files exceeded payload size; FetchContent keeps the tree small.
FetchContent_Declare(
  miniz
  URL https://github.com/richgel999/miniz/archive/refs/tags/3.0.2.tar.gz
  URL_HASH SHA256=c4b4c25a4eb81883448ff8924e6dba95c800094a198dc9ce66a292ac2ef8e018
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_GetProperties(miniz)
if(NOT miniz_POPULATED)
  FetchContent_Populate(miniz)
endif()

# miniz's CMake generates this via GenerateExportHeader. We compile the
# split sources directly, so write a static-lib stub.
if(NOT EXISTS "${miniz_SOURCE_DIR}/miniz_export.h")
  file(WRITE "${miniz_SOURCE_DIR}/miniz_export.h" "#define MINIZ_EXPORT\n#define MINIZ_NO_EXPORT\n")
endif()

add_library(wick_miniz STATIC
    ${miniz_SOURCE_DIR}/miniz.c
    ${miniz_SOURCE_DIR}/miniz_tdef.c
    ${miniz_SOURCE_DIR}/miniz_tinfl.c
    ${miniz_SOURCE_DIR}/miniz_zip.c
)
set_target_properties(wick_miniz PROPERTIES C_STANDARD 99 C_STANDARD_REQUIRED ON)
target_include_directories(wick_miniz PUBLIC ${miniz_SOURCE_DIR})
target_compile_options(wick_miniz PRIVATE -w)

find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
  pkg_check_modules(LIBSECRET IMPORTED_TARGET libsecret-1)
endif()

add_library(wick_core STATIC
    src/core/JournalModels.cpp
    src/core/JournalSyncEncoding.cpp
    src/core/JournalCatalog.cpp
    src/core/JournalPaths.cpp
    src/core/JournalStore.cpp
    src/core/JournalArchive.cpp
    src/sync/FakeSyncBackend.cpp
    src/sync/JournalDayMerge.cpp
    src/sync/JournalSyncState.cpp
    src/sync/JournalSyncEngine.cpp
    src/sync/PKCE.cpp
    src/sync/SecretTokenStore.cpp
)

target_include_directories(wick_core
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/src/core
        ${CMAKE_CURRENT_SOURCE_DIR}/src/sync
)

target_link_libraries(wick_core PUBLIC OpenSSL::Crypto nlohmann_json::nlohmann_json wick_miniz)

if(TARGET PkgConfig::LIBSECRET)
  target_link_libraries(wick_core PUBLIC PkgConfig::LIBSECRET)
  target_compile_definitions(wick_core PUBLIC WICK_HAVE_LIBSECRET=1)
  message(STATUS "libsecret-1: found, Dropbox refresh tokens use the Secret Service")
else()
  message(WARNING "libsecret-1 not found; Dropbox refresh tokens cannot be stored (stub SecretTokenStore). Set WICK_DEV_SECRETS=1 for a 0600 file under ~/.local/share/wick/dev-secrets.json.")
endif()

target_compile_features(wick_core PUBLIC cxx_std_20)

enable_testing()

add_executable(test_journal_core
    tests/test_journal_core.cpp
)
target_link_libraries(test_journal_core PRIVATE wick_core)
add_test(NAME test_journal_core COMMAND test_journal_core)

add_executable(test_journal_archive
    tests/test_journal_archive.cpp
)
target_link_libraries(test_journal_archive PRIVATE wick_core)
add_test(NAME test_journal_archive COMMAND test_journal_archive)

add_executable(test_journal_sync
    tests/test_journal_sync.cpp
)
target_link_libraries(test_journal_sync PRIVATE wick_core)
add_test(NAME test_journal_sync COMMAND test_journal_sync)

add_executable(test_pkce
    tests/test_pkce.cpp
)
target_link_libraries(test_pkce PRIVATE wick_core)
add_test(NAME test_pkce COMMAND test_pkce)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 6.4 REQUIRED COMPONENTS Quick Widgets Svg QuickControls2 Network QuickDialogs2)

qt_add_executable(wick
    src/main.cpp
    src/TimeProgress.cpp
    src/TimeProgress.h
    src/TrayController.cpp
    src/TrayController.h
    src/ProgressWindow.cpp
    src/ProgressWindow.h
    src/app/JournalLibrary.cpp
    src/app/JournalLibrary.h
    src/app/JournalLibraryZip.cpp
    src/app/JournalWindow.cpp
    src/app/JournalWindow.h
    src/app/LunarCalendar.cpp
    src/app/LunarCalendar.h
    src/app/AppSettings.cpp
    src/app/AppSettings.h
    src/app/SettingsWindow.cpp
    src/app/SettingsWindow.h
    src/app/ReminderScheduler.cpp
    src/app/ReminderScheduler.h
    src/app/JournalSyncCoordinator.cpp
    src/app/JournalSyncCoordinator.h
    src/app/SyncWorker.cpp
    src/app/SyncWorker.h
    src/app/DropboxAuthSession.cpp
    src/app/DropboxAuthSession.h
    src/app/WickIpc.cpp
    src/app/WickIpc.h
    src/sync/DropboxSyncBackend.cpp
    src/sync/DropboxSyncBackend.h
    resources/resources.qrc
)

target_include_directories(wick PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/app
)

target_link_libraries(wick PRIVATE
    wick_core
    Qt6::Quick
    Qt6::Widgets
    Qt6::Svg
    Qt6::QuickControls2
    Qt6::Network
    Qt6::QuickDialogs2
)

target_compile_definitions(wick PRIVATE
    QT_NO_CAST_FROM_ASCII
    QT_NO_NARROWING_CONVERSIONS_IN_CONNECT
)

set_target_properties(wick PROPERTIES
    OUTPUT_NAME wick
)

add_executable(test_dropbox_backend
    tests/test_dropbox_backend.cpp
    src/sync/DropboxSyncBackend.cpp
    src/sync/DropboxSyncBackend.h
)
target_include_directories(test_dropbox_backend PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/sync
)
target_link_libraries(test_dropbox_backend PRIVATE
    wick_core
    Qt6::Network
    Qt6::Core
)
add_test(NAME test_dropbox_backend COMMAND test_dropbox_backend)
