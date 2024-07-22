set -e

MAIN_DIR=$( git rev-parse --show-toplevel )
CLONE_DIR="$MAIN_DIR/repo"
PATCHES_DIR="$MAIN_DIR/patches"

CROSSFILE="$MAIN_DIR/crossfile.ini"
AOSP_INCLUDE="$MAIN_DIR/aosp/include"

case $(uname -m) in
    arm64 | aarch64) ARCH="armeabi-v8a" ;;
    arm | armhf | armv7l | armv8l) ARCH="armeabi-v7a" ;;
    *) echo "Unsupported architecture $(uname -m)" && exit 1 ;;
esac

generate_crossfile() {
	echo "Generating crossfile for arch: $ARCH"
	if [[ $ARCH = "armeabi-v7a" ]]; then
		echo """
[constants]
prefix = '$PREFIX'

toolchain_arch = 'arm-linux-androideabi'
toolchain_path = prefix + '/bin/' + toolchain_arch

[binaries]
ar = toolchain_path + '-ar'
c = [prefix + '/bin/ccache', toolchain_path + '-clang']
cpp = [prefix + '/bin/ccache', toolchain_path + '-clang++']
c_ld = toolchain_path + '-ld'
cpp_ld = toolchain_path + '-ld'
strip = toolchain_path + '-strip'
pkg-config = prefix + '/bin/pkg-config'

[built-in options]
c_args = ['-Wno-unused-parameter', '-O3', '--target=armv7a-linux-androideabi30', '-I$AOSP_INCLUDE']
c_link_args = ['-L/system/lib', '-landroid-shmem', '-llog', '-lcutils', '-lsync']
cpp_args = ['-O3', '--target=armv7a-linux-androideabi30', '-I$AOSP_INCLUDE']
cpp_link_args = ['-L/system/lib', '-landroid-shmem', '-llog', '-lcutils', '-lsync']

[host_machine]
system = 'linux'
cpu_family = 'arm'
cpu = 'armv7'
endian = 'little'
		""" > $CROSSFILE
	else
		echo """
[constants]
prefix = '$PREFIX'

toolchain_arch = 'aarch64-linux-androideabi'
toolchain_path = prefix + '/bin/' + toolchain_arch

[binaries]
ar = toolchain_path + '-ar'
c = [prefix + '/bin/ccache', toolchain_path + '-clang']
cpp = [prefix + '/bin/ccache', toolchain_path + '-clang++']
c_ld = toolchain_path + '-ld'
cpp_ld = toolchain_path + '-ld'
strip = toolchain_path + '-strip'
pkg-config = prefix + '/bin/pkg-config'

[built-in options]
c_args = ['-Wno-unused-parameter', '-O3', '--target=aarch64-linux-androideabi30', '-I$AOSP_INCLUDE']
c_link_args = ['-L/system/lib', '-landroid-shmem', '-llog', '-lcutils', '-lsync']
cpp_args = ['-O3', '--target=aarch64-linux-androideabi30', '-I$AOSP_INCLUDE']
cpp_link_args = ['-L/system/lib', '-landroid-shmem', '-llog', '-lcutils', '-lsync']

[host_machine]
system = 'linux'
cpu_family = 'arm'
cpu = 'armv8'
endian = 'little'
		""" > $CROSSFILE
	fi
}

clone_d1() { git clone --depth 1 $1 ;:; }

install_deps() {
	pkg in \
		ccache clang libandroid-shmem \
		vulkan-headers git cmake vulkan-loader-generic \
		vulkan-tools libandroid-support libandroid-shmem \
		libdrm libepoxy libglvnd libx11 xorgproto libxrandr \
		libc++ libxshmfence libxcb zlib zstd ninja
}

main() {
	cd $MAIN_DIR
	
	if [ ! -d "$CLONE_DIR" ]; then mkdir -p $CLONE_DIR ;:; fi
	
	install_deps
	generate_crossfile
	
	cd $CLONE_DIR
	
	if [ ! -d "mesa-mirror" ]; then
		clone_d1 "https://github.com/chaotic-cx/mesa-mirror.git"
	else echo "'mesa-mirror' already exists, no need to clone." ;:; fi
	
	cd mesa-mirror
	
	git apply "$PATCHES_DIR/mesa-virtio.patch" || echo "Seems like patching failed or it is already applied, skipping..."
	
	if [ -d "build" ]; then
		echo "No need to setup meson as the build directory already exists."
	else
		meson setup "build" \
			--cross-file=$CROSSFILE \
			-Dprefix=$PREFIX \
			-Dvulkan-drivers=virtio \
			-Dgallium-drivers= \
			-Dplatforms=x11,android \
			-Dandroid-libbacktrace=disabled \
			-Dandroid-stub=true \
			-Dopengl=false \
			-Dgbm=disabled \
			-Dllvm=disabled \
			-Dshared-llvm=disabled \
			-Dperfetto=false \
			-Dxmlconfig=disabled \
			-Dbuildtype=debug
	fi
		
	ninja -C "build" install -j$(nproc)
	
	cd $CLONE_DIR
	
	if [ ! -d "virglrenderer" ]; then
	clone_d1 "https://gitlab.freedesktop.org/virgl/virglrenderer.git"
	else echo "'virglrenderer' already exists, no need to clone." ;:; fi
	
	cd virglrenderer
	
	git apply "$PATCHES_DIR/virgl-venus.patch" || echo "Seems like patching failed or it is already applied, skipping..."
	
	if [ -d "build" ]; then
		echo "No need to setup meson as the build directory already exists."
	else
		meson setup "build" \
			--cross-file=$CROSSFILE \
			-Dprefix=$PREFIX \
			-Dplatforms=egl,glx \
			-Dvenus=true \
			-Dvideo=false \
			-Dbuildtype=release
	fi
	
	ninja -C "build" install -j$(nproc)
	
	cd $MAIN_DIR
}

echo "Building Mesa with 'virtio' and VirGL with 'venus'..."
main
echo "Done."