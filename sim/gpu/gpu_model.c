/* =====================================================================
 * gpu_model.c  -  bit-exact C reference for the SIMT-lite coprocessor.
 * Mirrors rtl/gpu/gpu_core.vhd semantics exactly (same opcodes, banked
 * scratchpad, mask predication). Defines the golden results the VHDL
 * testbench checks against, and emits the kernel words as $readmemh hex.
 *   build:  gcc -O2 -o gpu_model gpu_model.c && ./gpu_model
 * ===================================================================== */
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#define LANES   8
#define VREGS   8
#define SREGS   8
#define IMEM    256
#define BANKD   256

/* opcodes -- must match rtl/gpu/gpu_pkg.vhd */
enum { HALT=0,VLID,VMOVI,VLD,VST,VADD,VSUB,VAND,VOR,VXOR,VSLL,VSRL,VSRA,
       VMIN,VMAX,VMUL,VMAC,VSLT,VSEQ,MASKON,VBCAST,SADDI,SBNZ };

static uint32_t enc(int op,int d,int a,int b,int imm){
    return ((uint32_t)(op&0x3f)<<26)|((d&7)<<23)|((a&7)<<20)|((b&7)<<17)|(imm&0x1ffff);
}
static int32_t sext17(uint32_t w){ int32_t v=w&0x1ffff; if(v&0x10000) v-=0x20000; return v; }

static int32_t alu(int op,int32_t a,int32_t b,int32_t c){
    uint32_t ua=(uint32_t)a; int sh=b&31;
    switch(op){
      case VADD:return a+b; case VSUB:return a-b;
      case VAND:return a&b; case VOR:return a|b; case VXOR:return a^b;
      case VSLL:return (int32_t)(ua<<sh);
      case VSRL:return (int32_t)(ua>>sh);
      case VSRA:return a>>sh;
      case VMIN:return a<b?a:b; case VMAX:return a>b?a:b;
      case VMUL:return (int32_t)((int16_t)a*(int16_t)b);       /* 16x16 -> 32 (1 DSP/lane) */
      case VMAC:return (int32_t)((int16_t)a*(int16_t)b + c);
    }
    return 0;
}

typedef struct {
    int32_t vreg[VREGS][LANES];
    int32_t sreg[SREGS];
    int     mask[LANES];
    int32_t bank[LANES][BANKD];
    uint32_t imem[IMEM];
} gpu_t;

/* run mirrors gpu_core's FSM exactly */
static void run(gpu_t*g){
    int pc=0; for(int k=0;k<LANES;k++) g->mask[k]=1;
    for(int steps=0; steps<100000; steps++){
        uint32_t w=g->imem[pc];
        int op=(w>>26)&0x3f, d=(w>>23)&7, a=(w>>20)&7, b=(w>>17)&7;
        int32_t imm=sext17(w);
        if(op==HALT) return;
        switch(op){
          case VLID:   for(int k=0;k<LANES;k++) if(g->mask[k]) g->vreg[d][k]=k; break;
          case VMOVI:  for(int k=0;k<LANES;k++) if(g->mask[k]) g->vreg[d][k]=imm; break;
          case VBCAST: for(int k=0;k<LANES;k++) if(g->mask[k]) g->vreg[d][k]=g->sreg[a]; break;
          case VLD: { int row=(g->sreg[a]+imm)/LANES;
                      for(int k=0;k<LANES;k++) if(g->mask[k]) g->vreg[d][k]=g->bank[k][row]; } break;
          case VST: { int row=(g->sreg[a]+imm)/LANES;
                      for(int k=0;k<LANES;k++) if(g->mask[k]) g->bank[k][row]=g->vreg[b][k]; } break;
          case VSLT: for(int k=0;k<LANES;k++) g->mask[k]=(g->vreg[a][k]< g->vreg[b][k]); break;
          case VSEQ: for(int k=0;k<LANES;k++) g->mask[k]=(g->vreg[a][k]==g->vreg[b][k]); break;
          case MASKON: for(int k=0;k<LANES;k++) g->mask[k]=1; break;
          case SADDI: g->sreg[d]=g->sreg[a]+imm; break;
          case SBNZ:  if(g->sreg[a]!=0){ pc+=imm; continue; } break;
          default:    for(int k=0;k<LANES;k++) if(g->mask[k])
                          g->vreg[d][k]=alu(op,g->vreg[a][k],g->vreg[b][k],g->vreg[d][k]); break;
        }
        pc++;
    }
}

static void dump_kernel(const char*name,const uint32_t*k,int n){
    char fn[64]; snprintf(fn,sizeof fn,"kernel_%s.mem",name);
    FILE*f=fopen(fn,"w"); for(int i=0;i<n;i++) fprintf(f,"%08X\n",k[i]); fclose(f);
    printf("  kernel_%s.mem  (%d words)\n",name,n);
}
static void dump_vec(const char*name,const int32_t*v,int n){
    char fn[64]; snprintf(fn,sizeof fn,"golden_%s.mem",name);
    FILE*f=fopen(fn,"w"); for(int i=0;i<n;i++) fprintf(f,"%08X\n",(uint32_t)v[i]); fclose(f);
}

int main(void){
    int fail=0;
    printf("=== SIMT-lite GPU C golden model (LANES=%d) ===\n",LANES);

    /* ---------- 1) vector_add : C = A + B  (one N-chunk) ---------- */
    {
        gpu_t g; memset(&g,0,sizeof g);
        int32_t A[LANES],B[LANES],C[LANES];
        for(int k=0;k<LANES;k++){ A[k]=k+1; B[k]=10*(k+1); g.bank[k][0]=A[k]; g.bank[k][1]=B[k]; }
        uint32_t K[]={ enc(VLD,0,0,0,0), enc(VLD,1,0,0,LANES), enc(VADD,2,0,1,0),
                       enc(VST,0,0,2,2*LANES), enc(HALT,0,0,0,0) };
        int n=sizeof K/4; for(int i=0;i<n;i++) g.imem[i]=K[i];
        run(&g);
        printf("vector_add  A+B:\n   ");
        for(int k=0;k<LANES;k++){ C[k]=g.bank[k][2]; int exp=A[k]+B[k];
            printf("%d ",C[k]); if(C[k]!=exp) fail++; }
        printf("\n");
        dump_kernel("vadd",K,n); dump_vec("vadd",C,LANES);
    }

    /* ---------- 2) saxpy : Y = a*X + Y,  a in S1 ---------- */
    {
        gpu_t g; memset(&g,0,sizeof g);
        int32_t a=3, X[LANES],Y[LANES],R[LANES];
        for(int k=0;k<LANES;k++){ X[k]=k+1; Y[k]=100; g.bank[k][0]=X[k]; g.bank[k][1]=Y[k]; }
        g.sreg[1]=a;   /* scalar arg preset (sarg) */
        uint32_t K[]={ enc(VBCAST,3,1,0,0), enc(VLD,0,0,0,0), enc(VLD,1,0,0,LANES),
                       enc(VMUL,2,3,0,0), enc(VADD,1,1,2,0), enc(VST,0,0,1,LANES),
                       enc(HALT,0,0,0,0) };
        int n=sizeof K/4; for(int i=0;i<n;i++) g.imem[i]=K[i];
        run(&g);
        printf("saxpy  %d*X+Y:\n   ",a);
        for(int k=0;k<LANES;k++){ R[k]=g.bank[k][1]; int exp=a*X[k]+Y[k];
            printf("%d ",R[k]); if(R[k]!=exp) fail++; }
        printf("\n");
        dump_kernel("saxpy",K,n); dump_vec("saxpy",R,LANES);
    }

    /* ---------- 3) relu : Y = max(0,X)  (masking-free, VMAX) ---------- */
    {
        gpu_t g; memset(&g,0,sizeof g);
        int32_t X[LANES],R[LANES];
        for(int k=0;k<LANES;k++){ X[k]=(k%2)? -(k+1):(k+1); g.bank[k][0]=X[k]; }
        uint32_t K[]={ enc(VLD,0,0,0,0), enc(VMOVI,1,0,0,0), enc(VMAX,2,0,1,0),
                       enc(VST,0,0,2,LANES), enc(HALT,0,0,0,0) };
        int n=sizeof K/4; for(int i=0;i<n;i++) g.imem[i]=K[i];
        run(&g);
        printf("relu  max(0,X):\n   ");
        for(int k=0;k<LANES;k++){ R[k]=g.bank[k][1]; int exp=X[k]>0?X[k]:0;
            printf("%d ",R[k]); if(R[k]!=exp) fail++; }
        printf("\n");
        dump_kernel("relu",K,n); dump_vec("relu",R,LANES);
    }

    printf(fail? "\nFAIL: %d mismatches\n" : "\nALL GOLDEN CHECKS PASS\n", fail);
    return fail?1:0;
}
