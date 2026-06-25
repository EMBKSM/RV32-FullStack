/* =====================================================================
 * mc_model.c  -  C reference for rv32_shared.vhd + the dual-core SPMD
 * vector-add scenario. Models the shared block's port semantics exactly
 * (per-port hart id, one-shot barrier, A>B>T scratchpad write priority)
 * and replays the exact accesses the two cores make, so the VHDL testbench
 * can check the RTL against the golden scratchpad this emits.
 *   build:  gcc -O2 -o mc_model mc_model.c && ./mc_model
 * ===================================================================== */
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#define SP_WORDS 256
#define SP_BASE  64            /* word offset of scratchpad (byte 0x100) */
#define N        8

static int32_t sp[SP_WORDS];
static int     arrived[2];     /* bit per hart */

static int woff(uint32_t a){ return (a & 0xFFF) >> 2; }
static int is_sp(uint32_t a){ return woff(a) >= SP_BASE; }
static int spx (uint32_t a){ return (woff(a) - SP_BASE) % SP_WORDS; }

/* --- rv32_shared port models (port = 0:A/hart0, 1:B/hart1, 2:T/tb) --- */
static int32_t rd(int port, uint32_t a){
    if (woff(a)==0) return port;                 /* HARTID: A->0 B->1 (T->2 unused) */
    if (woff(a)==1) return arrived[0] && arrived[1];   /* BARRIER one-shot */
    if (is_sp(a))   return sp[spx(a)];
    return 0;
}
static void wr(int port, uint32_t a, int32_t d){
    if (woff(a)==1){ if(port<2) arrived[port]=1; return; }   /* barrier arrive */
    if (is_sp(a))   sp[spx(a)] = d;              /* (priority handled by call order) */
}

int main(void){
    int fail=0;
    int32_t A[N],B[N];
    memset(sp,0,sizeof sp); arrived[0]=arrived[1]=0;

    /* TB preloads A,B into the shared scratchpad (port T) */
    for(int i=0;i<N;i++){
        A[i]=i+1; B[i]=10*(i+1);
        wr(2, 0x80000100u + i*4,        A[i]);
        wr(2, 0x80000100u + (N+i)*4,    B[i]);
    }

    /* two cores run the SAME SPMD program; each does 4 elements by hart id */
    for(int hart=0; hart<2; hart++){
        int base = hart*4;                 /* core0:0..3  core1:4..7 */
        for(int i=base;i<base+4;i++){
            int32_t a = rd(hart, 0x80000100u + i*4);        /* A[i] */
            int32_t b = rd(hart, 0x80000100u + (N+i)*4);    /* B[i] */
            wr(hart, 0x80000100u + (2*N+i)*4, a+b);         /* C[i] */
        }
        wr(hart, 0x80000004u, hart);       /* barrier arrive */
    }

    /* barrier must now read high on both ports */
    if(!rd(0,0x80000004u) || !rd(1,0x80000004u)){ printf("BARRIER not released\n"); fail++; }

    /* check C and emit golden */
    printf("=== dual-core SPMD vector-add (C[i]=A[i]+B[i], split by hart id) ===\n   C: ");
    FILE*f=fopen("sim/multicore/golden_mc.mem","w");
    if(!f) f=fopen("golden_mc.mem","w");
    for(int i=0;i<N;i++){
        int32_t c = rd(2, 0x80000100u + (2*N+i)*4);
        int exp = A[i]+B[i];
        printf("%d ", c); if(c!=exp) fail++;
        if(f) fprintf(f,"%08X\n",(uint32_t)c);
    }
    if(f) fclose(f);
    printf("\n   (hart0 wrote C[0..3], hart1 wrote C[4..7]; barrier synced)\n");
    printf(fail? "\nFAIL: %d\n" : "\nMULTICORE GOLDEN CHECK PASS\n", fail);
    return fail?1:0;
}
