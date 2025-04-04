#!/bin/bash
# ioscustom.sh - Custom build script for ffmpeg-kit on iOS tailored for a Flutter project
# This script builds an XCFramework including only the libraries needed to generate
# 1080x1920 H264 videos with scaling, cropping, overlay, and drawtext (with freetype, fribidi, and harfbuzz support).
#
# Required libraries enabled:
#   - x264 (H.264 encoder)
#   - freetype (for drawtext)
#   - fribidi (for bidirectional text in drawtext)
#   - harfbuzz (custom build to support drawtext in modern FFmpeg)
#
# Unnecessary libraries (e.g., x265, xvidcore, etc.) are skipped.

# ------------------------
# 1. Check for Xcode Tools
# ------------------------
if [ ! -x "$(command -v xcrun)" ]; then
  echo -e "\n(*) xcrun not found. Check your Xcode installation.\n"
  exit 1
fi
if [ ! -x "$(command -v xcodebuild)" ]; then
  echo -e "\n(*) xcodebuild not found. Check your Xcode installation.\n"
  exit 1
fi

# ------------------------
# 2. Set Base and Build Type
# ------------------------
export BASEDIR="$(pwd)"
export FFMPEG_KIT_BUILD_TYPE="ios"
# Force full build variant to include all needed filters (not the minimal build)
export FFMPEG_KIT_BUILD_VARIANT="full"

# Load helper scripts (ensure these exist in your project)
source "${BASEDIR}/scripts/variable.sh"
source "${BASEDIR}/scripts/function-ios.sh"
disabled_libraries=()

# ------------------------
# 3. Architectures
# ------------------------
# Enable only modern architectures (arm64 for devices and x86_64/arm64 for simulators)
enable_default_ios_architectures
disable_arch "armv7"
disable_arch "armv7s"
disable_arch "i386"
disable_arch "x86-64-mac-catalyst"
disable_arch "arm64-mac-catalyst"
disable_arch "arm64e"

# ------------------------
# 4. Xcode and SDK Detection
# ------------------------
XCODE_FOR_FFMPEG_KIT=$(ls ~/.xcode.for.ffmpeg.kit.sh 2>>"${BASEDIR}/build.log")
if [[ -f ${XCODE_FOR_FFMPEG_KIT} ]]; then
  source "${XCODE_FOR_FFMPEG_KIT}" >> "${BASEDIR}/build.log" 2>&1
fi

export DETECTED_IOS_SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version 2>>"${BASEDIR}/build.log")"
echo -e "\nINFO: Using SDK ${DETECTED_IOS_SDK_VERSION} by Xcode at $(xcode-select -p)\n" >> "${BASEDIR}/build.log"
echo -e "INFO: Build options: $*\n" >> "${BASEDIR}/build.log"

# ------------------------
# 5. Build Options
# ------------------------
export GPL_ENABLED="yes"   # Required for x264 (GPL licensed)
DISPLAY_HELP=""
# We won't use a global --full flag on the command line here; instead, we manually enable only required libraries.
FFMPEG_KIT_XCF_BUILD="1"   # Force XCFramework output
BUILD_FORCE=""

BUILD_VERSION=$(git describe --tags --always 2>>"${BASEDIR}/build.log")
if [[ -z ${BUILD_VERSION} ]]; then
  echo -e "\n(*) Cannot run git commands in this folder. See build.log.\n"
  exit 1
fi

# Process command-line arguments (basic processing)
while [ ! $# -eq 0 ]; do
  case $1 in
    -h|--help)
      echo "Usage: $0 [--target=<iOS version>] [-x|--xcframework] [--skip-<lib>]"
      exit 0 ;;
    --target=*)
      TARGET=$(echo "$1" | sed -e 's/^--target=//')
      export IOS_MIN_VERSION=${TARGET} ;;
    -x|--xcframework)
      FFMPEG_KIT_XCF_BUILD="1" ;;
    --skip-*)
      SKIP_LIBRARY=$(echo "$1" | sed -e 's/^--skip-//')
      skip_library "${SKIP_LIBRARY}" ;;
    *)
      echo "Unknown option: $1" ;;
  esac
  shift
done

print_enabled_architectures
print_enabled_libraries

# ------------------------
# 6. Download Sources
# ------------------------
download_gnu_config
downloaded_library_sources "${ENABLED_LIBRARIES[@]}"

# ------------------------
# 7. Enable Only Required Libraries
# ------------------------
# Only enable libraries needed for your video generation:
enable_library "freetype"    # Needed for drawtext
enable_library "fribidi"     # For bidirectional text (drawtext)
enable_library "x264"        # For H.264 encoding
enable_library "ios-zlib"

# Set up HarfBuzz as a custom library.
# This custom block forces the build system to build HarfBuzz and pass --enable-libharfbuzz to FFmpeg.
generate_custom_library_environment_variables "1-name" "harfbuzz"
generate_custom_library_environment_variables "1-repo" "https://github.com/harfbuzz/harfbuzz.git"
generate_custom_library_environment_variables "1-repo-tag" "8.1.1"
generate_custom_library_environment_variables "1-package-config-file-name" "harfbuzz.pc"
generate_custom_library_environment_variables "1-ffmpeg-enable-flag" "libharfbuzz"

# ------------------------
# 8. Build for Each Architecture
# ------------------------
TARGET_ARCH_LIST=()
for run_arch in {0..12}; do
  if [[ ${ENABLED_ARCHITECTURES[$run_arch]} -eq 1 ]]; then
    export ARCH=$(get_arch_name "$run_arch")
    export FULL_ARCH=$(get_full_arch_name "$run_arch")
    export SDK_PATH=$(get_sdk_path)
    export SDK_NAME=$(get_sdk_name)
    
    # Build for this architecture using main-ios.sh
    . "${BASEDIR}/scripts/main-ios.sh" "${ENABLED_LIBRARIES[@]}"
    TARGET_ARCH_LIST+=("${FULL_ARCH}")
    
    # Clear flags for the next architecture
    for library in {0..61}; do
      library_name=$(get_library_name "$library")
      unset "$(echo "OK_${library_name}" | sed 's/-/_/g')"
      unset "$(echo "DEPENDENCY_REBUILT_${library_name}" | sed 's/-/_/g')"
    done
  fi
done

# ------------------------
# 9. Package XCFramework
# ------------------------
if [[ ${NO_FRAMEWORK:-0} -ne 1 ]]; then
  if [[ -n ${TARGET_ARCH_LIST[0]} ]]; then
    initialize_prebuilt_ios_folders
    build_apple_architecture_variant_strings
    if [[ -n ${FFMPEG_KIT_XCF_BUILD} ]]; then
      echo -n "Creating XCFramework under prebuilt: "
      create_universal_libraries_for_ios_xcframeworks
      create_frameworks_for_ios_xcframeworks
      create_ios_xcframeworks
    else
      echo -n "Creating frameworks under prebuilt: "
      create_universal_libraries_for_ios_default_frameworks
      create_ios_default_frameworks
    fi
    echo "ok"
  fi
else
  echo "INFO: Skipped creating iOS frameworks." >> "${BASEDIR}/build.log"
fi

echo "Build completed."
