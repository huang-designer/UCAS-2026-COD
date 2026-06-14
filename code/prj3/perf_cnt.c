#include "perf_cnt.h"

#define PERF_CNT_BASE ((volatile unsigned int *)0x60010000)

static unsigned long start_cycle;
static unsigned long start_mem_cycle;


unsigned long _uptime() {
    return (unsigned long)PERF_CNT_BASE[0];
}


unsigned long _read_mem_cycle() {
    return (unsigned long)PERF_CNT_BASE[1];
}

void bench_prepare(Result *res) {
    start_cycle = _uptime();
    start_mem_cycle = _read_mem_cycle();
    res->msec = 0;
    res->mem_cycle = 0;
}

void bench_done(Result *res) {
    res->msec = _uptime() - start_cycle;
    res->mem_cycle = _read_mem_cycle() - start_mem_cycle;
}
