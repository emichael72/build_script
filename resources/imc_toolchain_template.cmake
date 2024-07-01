# Tool-chain file for cross-compiling
# Ensure that you update paths and options as per your specific environment requirements.

${CMAKE_CROSS_COMPILER}

set( CMAKE_VERBOSE_MAKEFILE OFF )
set( CMAKE_COLOR_MAKEFILE=OFF )
set( CMAKE_SYSTEM_NAME elf )
set( CMAKE_SYSTEM_PROCESSOR aarch64 )
set( CMAKE_C_COMPILER aarch64-intel-elf-gcc )
set( CMAKE_CXX_COMPILER aarch64-intel-elf-g++ )
set( CMAKE_C_COMPILER_LAUNCHER  )
set( CMAKE_CXX_COMPILER_LAUNCHER  )
set( CMAKE_ASM_COMPILER aarch64-intel-elf-gcc )
set( CMAKE_AR aarch64-intel-elf-gcc-a CACHE FILEPATH "Archiver" )
set( CMAKE_C_FLAGS "  --sysroot=${SDKTARGETSYSROOT} ${CFLAGS}" CACHE STRING "CFLAGS" )
set( CMAKE_BUILD_TYPE ${CMAKE_BUILD_TYPE} )
set( CMAKE_C_FLAGS_DEBUG "${C_FLAGS_DEBUG}" )
set( CMAKE_CXX_FLAGS_DEBUG "${CXX_FLAGS_DEBUG}" )
set( CMAKE_CXX_FLAGS "  --sysroot=${SDKTARGETSYSROOT} ${CXXFLAGS}" CACHE STRING "CXXFLAGS" )
set( CMAKE_ASM_FLAGS "  --sysroot=${SDKTARGETSYSROOT} ${CFLAGS}" CACHE STRING "ASM FLAGS" )
set( CMAKE_C_FLAGS_RELEASE "-DNDEBUG" CACHE STRING "Additional CFLAGS for release" )
set( CMAKE_CXX_FLAGS_RELEASE "-DNDEBUG" CACHE STRING "Additional CXXFLAGS for release" )
set( CMAKE_ASM_FLAGS_RELEASE "-DNDEBUG" CACHE STRING "Additional ASM FLAGS for release" )
set( CMAKE_C_LINK_FLAGS "  --sysroot=${SDKTARGETSYSROOT}  ${LDFLAGS}" CACHE STRING "LDFLAGS" )
set( CMAKE_CXX_LINK_FLAGS "  --sysroot=${SDKTARGETSYSROOT} ${CXXFLAGS} ${LDFLAGS}" CACHE STRING "LDFLAGS" )

# only search in the paths provided so cmake doesn't pick
# up libraries and tools from the native build machine
set( CMAKE_FIND_ROOT_PATH ${SDKTARGETSYSROOT} ${CROSS_DIR}   ${EXTERNAL_TOOLCHAIN} "/")
set( CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY )
set( CMAKE_FIND_ROOT_PATH_MODE_PROGRAM ONLY )
set( CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY )
set( CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY )
set( CMAKE_PROGRAM_PATH "/" )

# Use qt.conf settings
set( ENV{QT_CONF_PATH} ${BUILD_DIR}/qt.conf )

# We need to set the rpath to the correct directory as cmake does not provide any
# directory as rpath by default
set( CMAKE_INSTALL_RPATH  )

# Use RPATHs relative to build directory for reproducibility
set( CMAKE_BUILD_RPATH_USE_ORIGIN ON )

# Use our cmake modules
list(APPEND CMAKE_MODULE_PATH "${SDKTARGETSYSROOT}/usr/share/cmake/Modules/")

# add for non /usr/lib libdir, e.g. /usr/lib64
set( CMAKE_LIBRARY_PATH /usr/lib /lib)

# add include dir to implicit includes in case it differs from /usr/include
list(APPEND CMAKE_C_IMPLICIT_INCLUDE_DIRECTORIES /usr/include)
list(APPEND CMAKE_CXX_IMPLICIT_INCLUDE_DIRECTORIES /usr/include)
