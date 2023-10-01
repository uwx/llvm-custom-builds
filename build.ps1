$LLVM_VERSION = $args[0]
$LLVM_REPO_URL = $args[1]
$LLVM_BUILD_TOOL = $args[2]

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

$PROJECT_LOCATION = "C:\llvm-project"

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

$SHARED_FLAGS = "-DCMAKE_BUILD_TYPE=MinSizeRel",
  "-DCMAKE_INSTALL_PREFIX=destdir",
  "-DLLVM_ENABLE_PROJECTS=`"clang;lld;clang-tools-extra;polly`"",
  "-DLLVM_ENABLE_TERMINFO=OFF",
  "-DLLVM_ENABLE_ZLIB=OFF",
  "-DLLVM_INCLUDE_DOCS=OFF",
  "-DLLVM_INCLUDE_EXAMPLES=OFF",
  "-DLLVM_INCLUDE_GO_TESTS=OFF",
  "-DLLVM_INCLUDE_TESTS=OFF",
  "-DLLVM_INCLUDE_TOOLS=ON",
  "-DLLVM_INCLUDE_UTILS=OFF",
  "-DLLVM_OPTIMIZED_TABLEGEN=ON",
  "-DLLVM_TARGETS_TO_BUILD=`"X86;AArch64;RISCV;WebAssembly`"",
  "$CROSS_COMPILE",
  "$CMAKE_ARGUMENTS"

if ($LLVM_BUILD_TOOL -eq "vs") {
    # Run `cmake` to configure the project.
    cmake `
      -G "Visual Studio 17 2022" `
      @SHARED_FLAGS `
      "$LlvmPath"
    
    # Showtime!
    cmake --build . --config Release
    
    # Not using DESTDIR here, quote from
    # https://cmake.org/cmake/help/latest/envvar/DESTDIR.html
    # > `DESTDIR` may not be used on Windows because installation prefix
    # > usually contains a drive letter like in `C:/Program Files` which cannot
    # > be prepended with some other prefix.
    cmake --install . --strip --config Release
} elseif ($LLVM_BUILD_TOOL -eq "clang") {
    $env:PATH = "$env:RUNNER_TEMP\msys64\bin;$env:RUNNER_TEMP\msys64\$env:MSYSTEM\bin;$env:RUNNER_TEMP\msys64\usr\bin;$env:RUNNER_TEMP\msys64\mingw64\bin;$env:RUNNER_TEMP\msys64\mingw32\bin;$env:PATH"
 
    cmake `
      -G Ninja `
      @SHARED_FLAGS `
      "$LlvmPath"

    # Showtime!
    cmake --build . --config MinSizeRel

    cmake --install . --strip --config MinSizeRel
}
