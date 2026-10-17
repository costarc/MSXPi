/* Self-test of pcheckers_rules.c, built for the Z80 with sdcc and run in the
 * sz80 simulator by pcheckers_rules_test.py. Each result[] entry is a count
 * or flag that the script compares with the expected value; the simulator
 * halts at the end and the script dumps result[]. */
#include <stdint.h>
#include <string.h>
#include "../src/pcheckers_rules.c"

volatile uint16_t result[16];
static uint8_t tb[64];
static Move tm[MAXM];

static uint32_t perft(uint8_t *b,uint8_t side,uint8_t depth) {
    Move list[MAXM]; uint8_t n,i,nb[64]; uint32_t t=0;
    n=gen(b,side,list,0,MAXM);
    if(depth==1) return n;
    for(i=0;i<n;i++) {
        memcpy(nb,b,64); apply(nb,&list[i]);
        t+=perft(nb,side^1,depth-1);
    }
    return t;
}
static void put(uint8_t r,uint8_t c,uint8_t p) { tb[r*8+c]=p; }

void main(void) {
    uint8_t n,b[64];
    rules_setup(b);
    result[0]=perft(b,0,1);
    result[1]=perft(b,0,2);
    result[2]=perft(b,0,3);
    result[3]=perft(b,0,4);

    /* Majority rule: the man on c3 (row 5, col 2) may take one piece to the
     * right or two to the left; only the two-piece capture is legal. */
    memset(tb,0,64);
    put(5,2,WM); put(4,3,BM); put(4,1,BM); put(2,1,BM);
    /* right: jump d4 -> e5 (row 3 col 4), left: b4 -> a5 (row 3 col 0) then
     * from a5 jump b6 (row 2 col 1) -> c7 (row 1 col 2). */
    n=gen(tb,0,tm,0,MAXM);
    result[4]=n; result[5]=n?tm[0].caps:0; result[6]=n?tm[0].n:0;

    /* Flying king a1 takes d4: lands on e5, f6, g7 or h8. */
    memset(tb,0,64);
    put(7,0,WK); put(4,3,BM);
    n=gen(tb,0,tm,0,MAXM);
    result[7]=n; result[8]=gen_capture;

    /* A man captures backward: white on c5 takes the black man on d4. */
    memset(tb,0,64);
    put(3,2,WM); put(4,3,BM);
    n=gen(tb,0,tm,0,MAXM);
    result[9]=n; result[10]=n?tm[0].caps:0;

    /* Passing through the far row without ending there keeps the man a man. */
    memset(tb,0,64);
    put(2,1,WM); put(1,2,BM); put(1,4,BM);
    n=gen(tb,0,tm,0,MAXM);
    result[11]=n; result[12]=n?tm[0].caps:0;
    if(n) {apply(tb,&tm[0]); result[13]=tb[tm[0].sq[tm[0].n-1]];}

    /* A man ending on the far row is crowned. */
    memset(tb,0,64);
    put(1,2,WM);
    n=gen(tb,0,tm,0,MAXM);
    result[14]=n;
    { uint8_t i; for(i=0;i<n;i++) if(tm[i].sq[1]==3) {apply(tb,&tm[i]); result[15]=tb[3];} }

    __asm
    halt
    __endasm;
}
