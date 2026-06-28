/* loadbench — heavy, contention-focused benchmark for SilkXotic A/B.
 * Dynamic bionic aarch64 (build with NDK, like cpubench). Emits one JSON line.
 *
 * Targets exactly what SilkXotic's knobs move (which peak-score apps do NOT):
 *
 *  latency-under-load : a "foreground" request thread does a small fixed task every ~50ms
 *      while a SEPARATE background PROCESS (own session via setsid) saturates all cores.
 *      Reports response-latency p50/p95/p99/max. This is "does the UI stay responsive
 *      while the system is busy" — exercises SCHED_AUTOGROUP (request vs load are different
 *      autogroups), CPU_BOOST/MSM_PERFORMANCE (freq ramp after the idle gap), CORE_CTL
 *      (gold cores online for the burst). Lower + tighter tail = better.
 *
 *  sustained-throttle : saturate all cores for N seconds, sample aggregate throughput every
 *      interval -> a decay curve. Steady-state vs peak reveals CORE_CTL/MSM_PERFORMANCE
 *      thermal/power behavior. Higher steady-state = better sustained perf.
 *
 * Usage: loadbench [latency_secs=15] [sustained_secs=120] [interval_s=10]
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <pthread.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>

static double now_ms(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec*1e3 + t.tv_nsec/1e6; }
static void sleep_ms(long ms){ struct timespec t={ms/1000,(ms%1000)*1000000L}; nanosleep(&t,NULL); }

static volatile uint64_t g_sink;
/* ~3.7ns/iter on SD732G; 270k iters ~= 1ms of work at full clock */
static inline uint64_t churn(uint64_t iters){ uint64_t a=0x9e3779b97f4a7c15ULL ^ iters,b=iters|1;
  for(uint64_t i=0;i<iters;i++){ a=a*6364136223846793005ULL+1442695040888963407ULL; b^=a>>13; b*=0x2545F4914F6CDD1DULL; } return a^b; }

/* ---------- background load threads (used inside the load child process) ---------- */
static volatile int g_stop;
static uint64_t g_count[64];
static void* loader(void* p){ long id=(long)p; uint64_t c=0; while(!g_stop){ g_sink^=churn(100000); c++; g_count[id]=c; } return NULL; }

static long g_nproc;
static void run_load_forever(void){
  pthread_t th[64]; long n=g_nproc>64?64:g_nproc;
  for(long i=0;i<n;i++) pthread_create(&th[i],NULL,loader,(void*)i);
  for(long i=0;i<n;i++) pthread_join(th[i],NULL);
}

static int cmp_d(const void*a,const void*b){ double x=*(const double*)a,y=*(const double*)b; return (x>y)-(x<y); }
static double pct(double*s,int n,double p){ if(n<=0)return 0; int i=(int)(p*(n-1)+0.5); if(i<0)i=0; if(i>=n)i=n-1; return s[i]; }

int main(int argc,char**argv){
  double lat_s = argc>1?atof(argv[1]):15.0;
  double sus_s = argc>2?atof(argv[2]):120.0;
  double iv_s  = argc>3?atof(argv[3]):10.0;
  g_nproc = sysconf(_SC_NPROCESSORS_ONLN); if(g_nproc<1) g_nproc=1;

  /* ---------------- latency under load ---------------- */
  pid_t load_pid = fork();
  if(load_pid==0){ setsid(); run_load_forever(); _exit(0); }   /* background load in its own autogroup */
  sleep_ms(300);                                               /* let load saturate */

  int cap = (int)(lat_s/0.05)+8; if(cap<8) cap=8;
  double* lat = (double*)malloc(sizeof(double)*cap); int ns=0;
  double end = now_ms()+lat_s*1000.0;
  while(now_ms()<end && ns<cap){
    sleep_ms(50);                       /* idle gap: freq drops, then a small foreground task */
    double t0=now_ms(); g_sink^=churn(270000); double d=now_ms()-t0;   /* ~1ms of work if uncontended */
    lat[ns++]=d*1000.0;                 /* microseconds */
  }
  if(load_pid>0){ kill(-load_pid,SIGKILL); kill(load_pid,SIGKILL); waitpid(load_pid,NULL,0); }

  qsort(lat,ns,sizeof(double),cmp_d);
  double l50=pct(lat,ns,0.50),l95=pct(lat,ns,0.95),l99=pct(lat,ns,0.99),lmax=ns?lat[ns-1]:0;
  double lsum=0; for(int i=0;i<ns;i++) lsum+=lat[i]; double lmean=ns?lsum/ns:0;

  /* ---------------- sustained throttle ---------------- */
  memset(g_count,0,sizeof(g_count)); g_stop=0;
  pthread_t th[64]; long n=g_nproc>64?64:g_nproc;
  for(long i=0;i<n;i++) pthread_create(&th[i],NULL,loader,(void*)i);
  int nsamp=(int)(sus_s/iv_s)+1; double* mit=(double*)malloc(sizeof(double)*nsamp); int si=0;
  uint64_t prev=0; double prevt=now_ms(); double t_end=prevt+sus_s*1000.0;
  while(now_ms()<t_end && si<nsamp){
    sleep_ms((long)(iv_s*1000));
    uint64_t sum=0; for(long i=0;i<n;i++) sum+=g_count[i];
    double tnow=now_ms(); double dt=(tnow-prevt)/1000.0;
    double miter=( (double)(sum-prev) * 100000.0 / 1e6 ) / dt;   /* each count=100k iters -> Miter/s */
    mit[si++]=miter; prev=sum; prevt=tnow;
  }
  g_stop=1; for(long i=0;i<n;i++) pthread_join(th[i],NULL);

  /* steady = median of 2nd half of samples */
  double peak=0; for(int i=0;i<si;i++) if(mit[i]>peak) peak=mit[i];
  int h0=si/2; double* tail=(double*)malloc(sizeof(double)*(si-h0+1)); int tn=0;
  for(int i=h0;i<si;i++) tail[tn++]=mit[i];
  qsort(tail,tn,sizeof(double),cmp_d); double steady=tn?tail[tn/2]:0;
  double retention = peak>0? steady/peak*100.0 : 0;

  printf("{\"nproc\":%ld,", g_nproc);
  printf("\"latency\":{\"n\":%d,\"p50_us\":%.0f,\"p95_us\":%.0f,\"p99_us\":%.0f,\"max_us\":%.0f,\"mean_us\":%.0f},",
         ns,l50,l95,l99,lmax,lmean);
  printf("\"sustained\":{\"interval_s\":%.0f,\"peak_miter_s\":%.1f,\"steady_miter_s\":%.1f,\"retention_pct\":%.1f,\"miter_s\":[",
         iv_s,peak,steady,retention);
  for(int i=0;i<si;i++) printf("%s%.1f", i?",":"", mit[i]);
  printf("]}}\n");
  return 0;
}
