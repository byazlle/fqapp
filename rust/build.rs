// 桌面端构建：把短剧/漫剧的流式解密 C 核心（C11，平台无关）编译进
// cdylib。Android 端解密库走 Gradle/CMake（见 android/app 的
// externalNativeBuild），这里直接跳过，避免重复符号。
use std::path::PathBuf;

fn main() {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if target_os == "android" {
        return;
    }

    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let native = manifest.parent().unwrap().join("native");
    let core = native.join("crypto_core");
    let third = native.join("third_party").join("tiny_aes");

    let mut build = cc::Build::new();
    build
        .include(&core)
        .include(&third)
        // sp_aes.c 要求 tiny-AES-c 配置为 AES-128 ECB only。
        .define("CBC", "0")
        .define("CTR", "0")
        .define("ECB", "1")
        .file(core.join("mp4_cenc.c"))
        .file(core.join("sp_aes.c"))
        .file(core.join("sp_error.c"))
        .file(core.join("sp_stream.c"))
        .file(third.join("aes.c"));

    // sp_stream.c 使用 <stdatomic.h>。MSVC 需显式指定 C11（VS 2022 17.6+
    // 支持 stdatomic）；clang/gcc 默认即接受。
    if target_os == "windows" {
        build.flag_if_supported("/std:c11");
    }

    build.compile("shortplay_crypto");

    println!("cargo:rerun-if-changed=../native/crypto_core");
    println!("cargo:rerun-if-changed=../native/third_party");
}
