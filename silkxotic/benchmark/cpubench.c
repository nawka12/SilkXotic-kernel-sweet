/* cpubench — deterministic CPU microbenchmark for SilkXotic A/B testing.
 * Static-PIE bionic aarch64 binary. Emits one JSON line of metrics.
 *
 * Metrics chosen to exercise exactly what SilkXotic's knobs touch:
 *   int_ms/float_ms  single-thread throughput (raw perf, governor ceiling)
 *   alloc_ms         malloc/free churn          -> SLUB_CPU_PARTIAL
 *   mt_ms            N-thread integer work      -> SCHED_CORE_CTL / scheduler
 *   burst_us[]       short work bursts after idle gaps
 *                    -> CPU_BOOST / MSM_PERFORMANCE / governor ramp latency
 * Lower is better for every metric. burst jitter (p90-p50) is the responsiveness signal.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#include <pthread.h>
#include <unistd.h>

static double now_ms(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec*1e3 + t.tv_nsec/1e6; }
static void sleep_ms(long ms){ struct timespec t={ms/1000,(ms%1000)*1000000L}; nanosleep(&t,NULL); }

static volatile uint64_t sink_u; static volatile double sink_d;

static uint64_t int_work(uint64_t iters){
    uint64_t a=1,b=2,c=3;
    for(uint64_t i=0;i<iters;i++){ a=a*6364136223846793005ULL+1442695040888963407ULL; b^=a>>13; c+=b|1; b*=c|1; }
    return a^b^c;
}
static double float_work(uint64_t iters){
    double a=1.0001,b=0.9999,s=0;
    for(uint64_t i=0;i<iters;i++){ a=a*1.0000001+0.5; b=b*0.9999999-0.25; s+=a*b - a/b + (a>b?a:b); }
    return s;
}
struct targ{ uint64_t iters; };
static void* tworker(void* p){ struct targ* a=p; sink_u^=int_work(a->iters); return NULL; }

int main(int argc, char** argv){
    /* scale factor (default 1) lets you tune runtime per-SoC */
    double scale = (argc>1)? atof(argv[1]) : 1.0;
    long nproc = sysconf(_SC_NPROCESSORS_ONLN); if(nproc<1) nproc=1;

    uint64_t INT_ITERS   = (uint64_t)(220ull*1000*1000*scale);
    uint64_t FLT_ITERS   = (uint64_t)(120ull*1000*1000*scale);
    uint64_t ALLOC_ITERS = (uint64_t)(2ull*1000*1000*scale);
    uint64_t MT_ITERS    = (uint64_t)(180ull*1000*1000*scale);
    int      BURSTS      = 40;
    uint64_t BURST_ITERS = (uint64_t)(8ull*1000*1000*scale);
    long     BURST_GAPMS = 60;

    double t;

    t=now_ms(); sink_u^=int_work(INT_ITERS);   double int_ms=now_ms()-t;
    t=now_ms(); sink_d =float_work(FLT_ITERS);  double flt_ms=now_ms()-t;

    /* alloc churn: varied sizes, touch first+last byte to force pages */
    t=now_ms();
    for(uint64_t i=0;i<ALLOC_ITERS;i++){
        size_t sz = 16 + ((i*2654435761u) & 0x3FFF);
        unsigned char* m = (unsigned char*)malloc(sz);
        if(m){ m[0]=(unsigned char)i; m[sz-1]=(unsigned char)(i>>8); sink_u+=m[0]+m[sz-1]; free(m); }
    }
    double alloc_ms=now_ms()-t;

    /* multithread integer work: nproc threads, equal share */
    pthread_t th[64]; struct targ ta[64]; int n=(nproc>64)?64:(int)nproc;
    t=now_ms();
    for(int i=0;i<n;i++){ ta[i].iters=MT_ITERS/n; pthread_create(&th[i],NULL,tworker,&ta[i]); }
    for(int i=0;i<n;i++) pthread_join(th[i],NULL);
    double mt_ms=now_ms()-t;

    /* burst latency: idle gap (freq drops) then a short fixed burst (boost/governor ramps) */
    printf("{");
    printf("\"nproc\":%ld,\"scale\":%.3f,", nproc, scale);
    printf("\"int_ms\":%.2f,\"float_ms\":%.2f,\"alloc_ms\":%.2f,\"mt_ms\":%.2f,",
           int_ms, flt_ms, alloc_ms, mt_ms);
    printf("\"burst_us\":[");
    for(int i=0;i<BURSTS;i++){
        sleep_ms(BURST_GAPMS);
        double b=now_ms(); sink_u^=int_work(BURST_ITERS); double us=(now_ms()-b)*1000.0;
        printf("%s%.0f", i?",":"", us);
    }
    printf("]}");
    printf("\n");
    (void)sink_d;
    return 0;
}
