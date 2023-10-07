$LLVM_VERSION = $args[0]
$LLVM_REPO_URL = $args[1]
$LLVM_BUILD_TOOL = $args[2]
$CMAKE_TYPE = $args[3]
$LTO = $args[4]
$PROJECT_LOCATION = $args[5]

if ([string]::IsNullOrEmpty($LLVM_REPO_URL)) {
  $LLVM_REPO_URL = "https://github.com/llvm/llvm-project.git"
}

if ([string]::IsNullOrEmpty($LLVM_VERSION)) {
  Write-Output "Usage: $PSCommandPath <llvm-version> <llvm-repository-url>"
  Write-Output ""
  Write-Output "# Arguments"
  Write-Output "  llvm-version         The name of a LLVM release branch without the 'release/' prefix"
  Write-Output "  llvm-repository-url  The URL used to clone LLVM sources (default: https://github.com/llvm/llvm-project.git)"

  exit 1
}

# Clone the LLVM project.
if (-not (Test-Path -Path "llvm-project" -PathType Container)) {
  git clone "$LLVM_REPO_URL" "$PROJECT_LOCATION"
}

Set-Location "$PROJECT_LOCATION"
git fetch origin
git checkout "$LLVM_VERSION"

$LlvmPath = $((Resolve-Path ./llvm).Path)

# Create a directory to build the project.
New-Item -Path "build" -Force -ItemType "directory"
Set-Location build

# Create a directory to receive the complete installation.
New-Item -Path "install" -Force -ItemType "directory"

# Adjust compilation based on the OS.
$CMAKE_ARGUMENTS = ""

# Adjust cross compilation
$CROSS_COMPILE = ""

# pip install pygments yaml

$SHARED_FLAGS = "-DCMAKE_BUILD_TYPE=$CMAKE_TYPE",
  "-DCMAKE_INSTALL_PREFIX=destdir",
  "-DLLVM_ENABLE_PROJECTS=`"clang;lld;clang-tools-extra;polly`"",
  # "-DLLVM_ENABLE_TERMINFO=OFF",
  # "-DLLVM_ENABLE_ZLIB=OFF",
  "-DLLVM_INCLUDE_DOCS=OFF",
  "-DLLVM_INCLUDE_BENCHMARKS=OFF",
  "-DLLVM_INCLUDE_EXAMPLES=OFF",
  "-DLLVM_INCLUDE_GO_TESTS=OFF",
  "-DLLVM_INCLUDE_TESTS=OFF",
  "-DLLVM_INCLUDE_TOOLS=ON",
  "-DLLVM_INCLUDE_UTILS=ON",
  "-DLLVM_OPTIMIZED_TABLEGEN=ON",
  "-DLLVM_TARGETS_TO_BUILD=`"X86;AArch64;RISCV;WebAssembly`"",
  # enable LTO if desired
  "-DLLVM_ENABLE_LTO=$LTO",
  # Enable pedantic mode. This disables compiler-specific extensions, if possible. Defaults to ON.
  "-DLLVM_ENABLE_PEDANTIC=OFF",

  # enable sccache
  "-DCMAKE_C_COMPILER_LAUNCHER=sccache",
  "-DCMAKE_CXX_COMPILER_LAUNCHER=sccache",

  # disable warnings
  "-DCMAKE_C_FLAGS=`"-w`"",
  "-DCMAKE_CXX_FLAGS=`"-w`"",

  "$CROSS_COMPILE",
  "$CMAKE_ARGUMENTS"

$LTO_FLAGS = ""

if ($LLVM_BUILD_TOOL -eq "vs") {
  # Run `cmake` to configure the project.
  cmake `
    -G "Visual Studio 17 2022" `
    @SHARED_FLAGS `
    -DLLVM_USE_LINKER=lld `
    -DCMAKE_LINKER="C:\Program Files\LLVM\bin\lld-link.exe" `
    "$LlvmPath"

  # Showtime!
  cmake --build . --config $CMAKE_TYPE

  # Not using DESTDIR here, quote from
  # https://cmake.org/cmake/help/latest/envvar/DESTDIR.html
  # > `DESTDIR` may not be used on Windows because installation prefix
  # > usually contains a drive letter like in `C:/Program Files` which cannot
  # > be prepended with some other prefix.
  cmake --install . --strip --config $CMAKE_TYPE
} elseif ($LLVM_BUILD_TOOL -eq "clang") {
  if ($LTO -eq "Thin") {
    $LTO_FLAGS = "-DCMAKE_C_FLAGS=`"-flto=thin`"",
      "-DCMAKE_CXX_FLAGS=`"-flto=thin`"",
      "-DCMAKE_C_LINK_FLAGS=`"-flto=thin`"",
      "-DCMAKE_CXX_LINK_FLAGS=`"-flto=thin`"",
      "-DLLVM_ENABLE_LTO=Off"
  }
  if ($LTO -ne "Off") {
    $LTO_FLAGS = $LTO_FLAGS,"-DLLVM_PARALLEL_LINK_JOBS=1"
  }

  cmake `
    -G Ninja `
    @SHARED_FLAGS `
    -DLLVM_USE_LINKER=lld `
    -DCMAKE_LINKER="C:\Program Files\LLVM\bin\lld-link.exe" `
    -DLLVM_HOST_TRIPLE=x86_64 `
    -DLLVM_POLLY_LINK_INTO_TOOLS=ON `
    @LTO_FLAGS `
    "$LlvmPath"

  # Showtime!
  cmake --build . --config $CMAKE_TYPE

  cmake --install . --strip --config $CMAKE_TYPE
} else {
  $env:PATH = "$env:RUNNER_TEMP\msys64\bin;$env:RUNNER_TEMP\msys64\$env:MSYSTEM\bin;$env:RUNNER_TEMP\msys64\usr\bin;$env:RUNNER_TEMP\msys64\mingw64\bin;$env:RUNNER_TEMP\msys64\mingw32\bin;$env:PATH"

  cmake `
    -G Ninja `
    @SHARED_FLAGS `
    -DLLVM_HOST_TRIPLE=x86_64 `
    -DCMAKE_C_FLAGS="-D ffs=__builtin_ffs" `
    -DCMAKE_CXX_FLAGS="-D ffs=__builtin_ffs" `
    "$LlvmPath"

  # Showtime!
  cmake --build . --config $CMAKE_TYPE

  cmake --install . --strip --config $CMAKE_TYPE
}
