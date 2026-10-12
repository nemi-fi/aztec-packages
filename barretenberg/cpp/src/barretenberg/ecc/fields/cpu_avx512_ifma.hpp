// Runtime detection of AVX-512F/DQ/VL + IFMA with OS support for the 512-bit register state, x86-64 only.
//
// Uses CPUID and XGETBV directly instead of __builtin_cpu_supports: the zig-wrapped clang used for release builds
// does not link the compiler runtime that provides __cpu_model / __cpu_indicator_init.

#pragma once

#if defined(__x86_64__) && !defined(__wasm__) && (defined(__clang__) || defined(__GNUC__))

#include <cpuid.h>
#include <cstdint>

namespace bb::detail {

inline bool cpu_supports_avx512_ifma() noexcept
{
    unsigned int eax = 0;
    unsigned int ebx = 0;
    unsigned int ecx = 0;
    unsigned int edx = 0;
    if (__get_cpuid(1, &eax, &ebx, &ecx, &edx) == 0) {
        return false;
    }
    constexpr unsigned int OSXSAVE = 1U << 27;
    if ((ecx & OSXSAVE) == 0) {
        return false;
    }
    uint32_t xcr0_lo = 0;
    uint32_t xcr0_hi = 0;
    __asm__ volatile("xgetbv" : "=a"(xcr0_lo), "=d"(xcr0_hi) : "c"(0));
    // SSE, AVX, opmask, ZMM0-15 upper halves and ZMM16-31 state must all be enabled by the OS.
    constexpr uint32_t AVX512_STATE = 0xE6;
    if ((xcr0_lo & AVX512_STATE) != AVX512_STATE) {
        return false;
    }
    if (__get_cpuid_count(7, 0, &eax, &ebx, &ecx, &edx) == 0) {
        return false;
    }
    constexpr unsigned int AVX512F = 1U << 16;
    constexpr unsigned int AVX512DQ = 1U << 17;
    constexpr unsigned int AVX512IFMA = 1U << 21;
    constexpr unsigned int AVX512VL = 1U << 31;
    constexpr unsigned int REQUIRED = AVX512F | AVX512DQ | AVX512IFMA | AVX512VL;
    return (ebx & REQUIRED) == REQUIRED;
}

} // namespace bb::detail

#endif
