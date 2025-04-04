
#!/bin/bash
# Minimal Custom ios.sh for ffmpeg-kit
# Tailored for a Flutter project generating 1080x1920 H264 videos with overlays, drawtext, and scaling/cropping.
# This build only enables: x264, freetype, fribidi, and a custom HarfBuzz.
# It targets iOS (arm64 for devices; x86_64/arm64 for simulators) and produces an XCFramework.

# --- Check Xcode Tools ---
if [ ! -x "$(command -v xcrun)" ]; then
  echo -e "\n(*) xcrun command not found. Please check your Xcode installation.\n"
  exit 1
fi
if [ ! -x "$(command -v xcodebuild)" ]; then
  echo -e "\n(*) xcodebuild command not found. Please check your Xcode installation.\n"
  exit 1
fi

# --- Set Base Directory and Build Type ---
export BASEDIR="$(pwd)"
export FFMPEG_KIT_BUILD_TYPE="ios"

# Load helper variables and functions (assumes these exist in scripts folder)
source "${BASEDIR}/scripts/variable.sh"
source "${BASEDIR}/scripts/function-ios.sh"
disabled_libraries=()

# --- Architectures ---
# Enable only modern iOS architectures: arm64 (device) and x86_64/arm64 (simulator)
enable_default_ios_architectures
disable_arch "armv7"
disable_arch "armv7s"
disable_arch "i386"
disable_arch "x86-64-mac-catalyst"
disable_arch "arm64-mac-catalyst"
disable_arch "arm64e"

# --- Xcode Version ---
XCODE_FOR_FFMPEG_KIT=$(ls ~/.xcode.for.ffmpeg.kit.sh 2>>"${BASEDIR}/build.log")
if [[ -f ${XCODE_FOR_FFMPEG_KIT} ]]; then
  source "${XCODE_FOR_FFMPEG_KIT}" 1>>"${BASEDIR}/build.log" 2>&1
fi

# --- Detect iOS SDK Version ---
export DETECTED_IOS_SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version 2>>${BASEDIR}/build.log)"
echo -e "\nINFO: Using SDK ${DETECTED_IOS_SDK_VERSION} by Xcode provided at $(xcode-select -p)\n" >> "${BASEDIR}/build.log"
echo -e "INFO: Build options: $*\n" >> "${BASEDIR}/build.log"

# --- Build Options ---
export GPL_ENABLED="yes"  # Enable GPL libraries (needed for x264)
DISPLAY_HELP=""
BUILD_TYPE_ID=""
# We do NOT use the global --full option since it enables all libraries.
# Instead, we explicitly enable only the ones we need.
FFMPEG_KIT_XCF_BUILD="1"   # Force building an XCFramework
BUILD_FORCE=""

BUILD_VERSION=$(git describe --tags --always 2>>"${BASEDIR}/build.log")
if [[ -z ${BUILD_VERSION} ]]; then
  echo -e "\n(*) Cannot run git commands in this folder. See build.log.\n"
  exit 1
fi

# --- Process Command-Line Arguments ---
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
      echo "Unknown option: $1"
      ;;
  esac
  shift
done

# --- Display Build Summary ---
print_enabled_architectures
print_enabled_libraries

# --- Download Sources ---
download_gnu_config
downloaded_library_sources "${ENABLED_LIBRARIES[@]}"

# --- Enable Only Required Libraries ---
# Enable freetype for drawtext, fribidi for bidirectional text, and x264 for H.264 encoding.
enable_library "freetype"
enable_library "fribidi"
enable_library "x264"

# Set up HarfBuzz as a custom library (required for drawtext in modern FFmpeg)
# This uses custom library slot 1.
generate_custom_library_environment_variables "1-name" "harfbuzz"
generate_custom_library_environment_variables "1-repo" "https://github.com/harfbuzz/harfbuzz.git"
generate_custom_library_environment_variables "1-repo-tag" "8.1.1"
generate_custom_library_environment_variables "1-package-config-file-name" "harfbuzz.pc"
generate_custom_library_environment_variables "1-ffmpeg-enable-flag" "libharfbuzz"

# --- Build for Each Enabled Architecture ---
TARGET_ARCH_LIST=()
for run_arch in {0..12}; do
  if [[ ${ENABLED_ARCHITECTURES[$run_arch]} -eq 1 ]]; then
    export ARCH=$(get_arch_name "$run_arch")
    export FULL_ARCH=$(get_full_arch_name "$run_arch")
    export SDK_PATH=$(get_sdk_path)
    export SDK_NAME=$(get_sdk_name)
    
    # Call main build script for this architecture
    . "${BASEDIR}/scripts/main-ios.sh" "${ENABLED_LIBRARIES[@]}"
    TARGET_ARCH_LIST+=("${FULL_ARCH}")
    
    # Clear per-library flags to avoid interference between arch builds
    for library in {0..61}; do
      library_name=$(get_library_name "$library")
      unset "$(echo "OK_${library_name}" | sed 's/-/_/g')"
      unset "$(echo "DEPENDENCY_REBUILT_${library_name}" | sed 's/-/_/g')"
    done
  fi
done

# --- Package XCFramework ---
if [[ ${NO_FRAMEWORK:-0} -ne 1 ]]; then
  if [[ -n ${TARGET_ARCH_LIST[0]} ]]; then
    initialize_prebuilt_ios_folders
    build_apple_architecture_variant_strings
    if [[ -n ${FFMPEG_KIT_XCF_BUILD} ]]; then
      echo -n "Creating xcframeworks under prebuilt: "
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
