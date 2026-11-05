#!/bin/zsh
# Builds More Formats, Nook's optional download: one universal `ffmpeg` with the open-source encoders macOS
# doesn't have (MP3, WebP, VP9 for WebM, Opus). FFmpeg is built LGPL-only (no --enable-gpl, no
# --enable-nonfree), so it can be shipped beside Nook's MIT code; every source is pinned below and this
# script is the build recipe, which the LGPL asks for.
# Needs: Xcode command line tools, Homebrew's pkgconf and nasm.
# Usage: scripts/formats-pack.sh [sign identity]   → build/formats/NookFormats-<version>.zip
set -euo pipefail
cd "${0:A:h}/.."
PACK_VERSION=1
IDENTITY=${1:-}
ROOT=$PWD/build/formats
SRC=$ROOT/src
mkdir -p $SRC
MIN_MACOS=15.0
JOBS=$(sysctl -n hw.ncpu)

# name|url|sha256
SOURCES=(
  "ffmpeg-7.1.1.tar.xz|https://ffmpeg.org/releases/ffmpeg-7.1.1.tar.xz|"
  "lame-3.100.tar.gz|https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz|"
  "libwebp-1.5.0.tar.gz|https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.5.0.tar.gz|"
  "libvpx-1.15.0.tar.gz|https://github.com/webmproject/libvpx/archive/refs/tags/v1.15.0.tar.gz|"
  "opus-1.5.2.tar.gz|https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz|"
)

fetch() {
  for entry in $SOURCES; do
    local name=${entry%%|*} rest=${entry#*|}
    local url=${rest%%|*} sum=${rest#*|}
    [[ -f $SRC/$name ]] || curl -fsSL --retry 3 -o $SRC/$name "$url"
    local got=$(shasum -a 256 $SRC/$name | cut -d' ' -f1)
    if [[ -n $sum && $got != $sum ]]; then echo "checksum mismatch: $name ($got)"; exit 1; fi
    echo "$got  $name"
  done
}

# Unpacks a source tarball fresh for one architecture and prints its folder.
unpack() {
  local tarball=$1 arch=$2 into=$ROOT/work-$2
  mkdir -p $into
  local dir=$into/$(tar -tf $SRC/$tarball | head -1 | cut -d/ -f1)
  rm -rf $dir
  tar -xf $SRC/$tarball -C $into
  echo $dir
}

build_arch() {
  local arch=$1
  local host=$([[ $arch == arm64 ]] && echo aarch64-apple-darwin || echo x86_64-apple-darwin)
  local prefix=$ROOT/prefix-$arch
  rm -rf $prefix; mkdir -p $prefix
  export CC="clang -arch $arch" CXX="clang++ -arch $arch"
  export CFLAGS="-O2 -mmacosx-version-min=$MIN_MACOS" CXXFLAGS="-O2 -mmacosx-version-min=$MIN_MACOS"
  export LDFLAGS="-mmacosx-version-min=$MIN_MACOS"
  export PKG_CONFIG_PATH=$prefix/lib/pkgconfig PKG_CONFIG_LIBDIR=$prefix/lib/pkgconfig
  local common=(--host=$host --build=aarch64-apple-darwin --prefix=$prefix --disable-shared --enable-static)

  # LAME: its symbol list names a function it no longer has, which the macOS linker rejects.
  local dir=$(unpack lame-3.100.tar.gz $arch)
  ( cd $dir && sed -i '' '/lame_init_old/d' include/libmp3lame.sym && ./configure $common --disable-frontend --disable-decoder >/dev/null && make -j$JOBS >/dev/null && make install >/dev/null )

  dir=$(unpack opus-1.5.2.tar.gz $arch)
  ( cd $dir && ./configure $common --disable-doc --disable-extra-programs >/dev/null && make -j$JOBS >/dev/null && make install >/dev/null )

  dir=$(unpack libwebp-1.5.0.tar.gz $arch)
  ( cd $dir && ./configure $common --disable-libwebpextras --disable-gif --disable-gl --disable-sdl --disable-png --disable-jpeg --disable-tiff >/dev/null \
      && make -j$JOBS >/dev/null && make install >/dev/null )

  # libvpx has its own configure, with targets named for the newest Darwin it knows.
  dir=$(unpack libvpx-1.15.0.tar.gz $arch)
  local vpxcpu=$([[ $arch == arm64 ]] && echo arm64 || echo x86_64)
  local vpxtarget=$(cd $dir && ./configure --help | grep -o "${vpxcpu}-darwin[0-9][0-9]*-gcc" | sort -V | tail -1)
  ( cd $dir && unset CC CXX CFLAGS CXXFLAGS LDFLAGS && ./configure --target=$vpxtarget --prefix=$prefix --disable-shared --enable-static --enable-pic \
      --disable-examples --disable-tools --disable-docs --disable-unit-tests --enable-vp8 --enable-vp9 \
      --extra-cflags="-mmacosx-version-min=$MIN_MACOS" >/dev/null && make -j$JOBS >/dev/null && make install >/dev/null )

  dir=$(unpack ffmpeg-7.1.1.tar.xz $arch)
  local cross=(); [[ $arch != $(uname -m) ]] && cross=(--enable-cross-compile)
  ( cd $dir && ./configure --prefix=$prefix --arch=$arch --target-os=darwin $cross --cc="clang -arch $arch" \
      --extra-cflags="-I$prefix/include -mmacosx-version-min=$MIN_MACOS" --extra-ldflags="-L$prefix/lib -mmacosx-version-min=$MIN_MACOS" \
      --pkg-config=pkg-config --pkg-config-flags=--static \
      --disable-shared --enable-static --disable-doc --disable-ffplay --disable-ffprobe --disable-network --disable-debug \
      --disable-autodetect --enable-videotoolbox --enable-audiotoolbox --enable-zlib \
      --enable-libmp3lame --enable-libwebp --enable-libvpx --enable-libopus >$ROOT/ffmpeg-configure-$arch.log \
      && make -j$JOBS >/dev/null && cp ffmpeg $ROOT/ffmpeg-$arch )
}

fetch
for arch in arm64 x86_64; do echo "building $arch"; build_arch $arch; done

# One binary for both kinds of Mac, signed so macOS will run it.
OUT=$ROOT/NookFormats
rm -rf $OUT; mkdir -p $OUT
lipo -create $ROOT/ffmpeg-arm64 $ROOT/ffmpeg-x86_64 -output $OUT/ffmpeg
strip -x $OUT/ffmpeg
if [[ -n $IDENTITY ]]; then codesign --force --options runtime --timestamp --sign "$IDENTITY" $OUT/ffmpeg; else codesign --force --sign - $OUT/ffmpeg; fi
cp $(dirname $(unpack ffmpeg-7.1.1.tar.xz arm64))/ffmpeg-7.1.1/COPYING.LGPLv2.1 $OUT/LICENSE-LGPL.txt
cat > $OUT/NOTICE.md <<NOTICE
# More Formats for Nook (pack $PACK_VERSION)

\`ffmpeg\` here is FFmpeg 7.1.1, built LGPL-only (no GPL or non-free parts) for Apple silicon and Intel by
scripts/formats-pack.sh in https://github.com/sanvithreddyy/nook, with:

- LAME 3.100 (LGPL): https://lame.sourceforge.io
- libwebp 1.5.0 (BSD): https://chromium.googlesource.com/webm/libwebp
- libvpx 1.15.0 (BSD): https://chromium.googlesource.com/webm/libvpx
- Opus 1.5.2 (BSD): https://opus-codec.org
- FFmpeg 7.1.1 (LGPL 2.1): https://ffmpeg.org — source: https://ffmpeg.org/releases/ffmpeg-7.1.1.tar.xz

Sources are the exact tarballs that script downloads; the LGPL's text is in LICENSE-LGPL.txt.
NOTICE
ZIP=$ROOT/NookFormats-$PACK_VERSION.zip
rm -f $ZIP
( cd $ROOT && ditto -c -k --keepParent NookFormats $ZIP )
lipo -archs $OUT/ffmpeg
ls -la $ZIP
shasum -a 256 $ZIP
