set -e

# MAIN_DIR_PATH="$HOME/virtio_virgl"
MAIN_DIR_PATH=$( git rev-parse --show-toplevel )
CROSSFILE="$MAIN_DIR_PATH/crossfile.ini"
AOSP_INCLUDE="$MAIN_DIR_PATH/aosp/include"

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
prefix = '/data/data/com.termux/files/usr/'

toolchain_arch = 'arm-linux-androideabi'
toolchain_path = prefix + 'bin/' + toolchain_arch

[binaries]
ar = toolchain_path + '-ar'
c = [prefix + 'bin/ccache', toolchain_path + '-clang']
cpp = [prefix + 'bin/ccache', toolchain_path + '-clang++']
c_ld = toolchain_path + '-ld'
cpp_ld = toolchain_path + '-ld'
strip = toolchain_path + '-strip'
pkg-config = prefix + 'bin/pkg-config'

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
prefix = '/data/data/com.termux/files/usr/bin/'

toolchain_arch = 'aarch64-linux-androideabi'
toolchain_path = prefix + toolchain_arch

[binaries]
ar = toolchain_path + '-ar'
c = [prefix + 'bin/ccache', toolchain_path + '-clang']
cpp = [prefix + 'bin/ccache', toolchain_path + '-clang++']
c_ld = toolchain_path + '-ld'
cpp_ld = toolchain_path + '-ld'
strip = toolchain_path + '-strip'
pkg-config = prefix + 'bin/pkg-config'

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
	mkdir -p $MAIN_DIR_PATH
	cd $MAIN_DIR_PATH
	
	install_deps
	generate_crossfile
	
	: '
	if [ ! -f "$MAIN_DIR_PATH/wsi-no-pthread_cancel.patch" ]; then
		wget "https://raw.githubusercontent.com/xMeM/termux-packages/23cf5ca365a1c3feb9960ae6490165dabcc9112b/packages/mesa-vulkan-icd-freedreno-dri3/wsi-no-pthread_cancel.patch"
	fi '
	
	if [ ! -d "$MAIN_DIR_PATH/mesa-mirror" ]; then
		clone_d1 "https://github.com/chaotic-cx/mesa-mirror.git"
	else echo "'mesa-mirror' already exists, no need to clone." ;:; fi
	cd mesa-mirror
	
	git apply "$MAIN_DIR_PATH/mesa-virtio.patch"
	
	if [ -d "build" ]; then
		echo "No need to setup meson as 'build' already exists."
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
			-Dbuildtype=release
	fi
		
	ninja -C "build" install -j$(nproc)
	
	cd $MAIN_DIR_PATH
	
	if [ ! -d "$MAIN_DIR_PATH/virglrenderer" ]; then
	clone_d1 "https://gitlab.freedesktop.org/virgl/virglrenderer.git"
	else echo "'virglrenderer' already exists, no need to clone." ;:; fi
	cd virglrenderer
	
	git apply "$MAIN_DIR_PATH/virgl-venus.patch"
	
	if [ -d "build" ]; then
		echo "No need to setup meson as 'build' already exists."
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
	
	cd $HOME
}

echo "Building Mesa with 'virtio' and VirGL with 'venus'..."
main
echo "Done."