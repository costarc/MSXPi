/*
 * PCheckers rules and AI: Brazilian draughts (damas) on the 8x8 board.
 *
 * Men move one square diagonally forward and capture forward or backward;
 * kings fly any distance. Capturing is mandatory and the capture that takes
 * the most pieces must be chosen (a king counts as one piece). Captured
 * pieces stay on the board until the move ends and cannot be jumped twice.
 * A man that ends its move on the far row becomes a king; one that only
 * passes through it keeps capturing as a man.
 *
 * Squares are row*8+col with row 0 at the top (black's side). Dark squares
 * are those where row+col is odd. White starts at the bottom and moves first.
 * Plain C with no MSX dependencies: pcheckers_rules_host.c includes it too.
 */

#define EMPTY 0
#define WM 1
#define WK 2
#define BM 3
#define BK 4
#define TAKEN 8
/* MAXM bounds the list the player's moves are kept in; the AI's search lists
 * (one per ply, so they dominate the data size) are shorter. */
#define MAXM 48
#define SMAXM 26
#define MAXN 13
#define MAXPLY 12
#define ROW(s) ((s)>>3)
#define COL(s) ((s)&7)
#define INB(r,c) ((r)>=0 && (r)<8 && (c)>=0 && (c)<8)
#define SIDE_OF(p) ((((p)&7)-1)>>1)

typedef struct { uint8_t n, caps, sq[MAXN]; } Move;

/* Scanning only the 32 dark squares halves every board loop. */
static const uint8_t dark[32]={1,3,5,7,8,10,12,14,17,19,21,23,24,26,28,30,
                               33,35,37,39,40,42,44,46,49,51,53,55,56,58,60,62};
static const int8_t dir_r[4]={-1,-1,1,1};
static const int8_t dir_c[4]={-1,1,-1,1};

static void rules_init(void);
static void rules_setup(uint8_t *b) {
    uint8_t r,c;
    rules_init();
    memset(b,0,64);
    for(r=0;r<8;r++) for(c=0;c<8;c++) if((r+c)&1) {
        if(r<3) b[r*8+c]=BM;
        else if(r>4) b[r*8+c]=WM;
    }
}

/* Generator state: gb is the board being searched (captured pieces are
 * marked TAKEN in place and restored), gl/gn the move list being filled. */
static uint8_t *gb;
static Move *gl;
static uint8_t gn,gmax,gbest,gen_capture,plen,path[MAXN];

static void record(uint8_t caps) {
    if(caps>gbest) {gbest=caps; gn=0;}
    if(caps==gbest && gn<gmax) {
        gl[gn].n=plen; gl[gn].caps=caps;
        memcpy(gl[gn].sq,path,plen);
        gn++;
    }
}

/* nbr[s*4+d] is the square next to s in direction d, or NONE off the board:
 * a table lookup is much cheaper than row/column arithmetic on the Z80. */
#define NONE 255
static uint8_t nbr[256];
static void rules_init(void) {
    uint8_t s,d; int8_t r,c;
    for(s=0;s<64;s++) for(d=0;d<4;d++) {
        r=ROW(s)+dir_r[d]; c=COL(s)+dir_c[d];
        nbr[s*4+d]=INB(r,c)?r*8+c:NONE;
    }
}

static uint8_t cap_dfs(uint8_t sq,uint8_t king,uint8_t side,uint8_t caps) {
    uint8_t d,found=0,r,n2,p;
    for(d=0;d<4;d++) {
        r=nbr[sq*4+d];
        if(king) while(r!=NONE && !gb[r]) r=nbr[r*4+d];
        if(r==NONE) continue;
        p=gb[r];
        if(!p || (p&TAKEN) || SIDE_OF(p)==side) continue;
        n2=nbr[r*4+d];
        if(n2==NONE || gb[n2]) continue;
        gb[r]|=TAKEN;
        do {
            found=1;
            path[plen++]=n2;
            if(!cap_dfs(n2,king,side,caps+1)) record(caps+1);
            plen--;
            n2=nbr[n2*4+d];
        } while(king && n2!=NONE && !gb[n2]);
        gb[r]&=~TAKEN;
    }
    return found;
}

/* Fills list with every legal move for side (0 white, 1 black); returns the
 * count and sets gen_capture when the moves are captures. With captures_only
 * the plain moves are not generated: the result is only complete when
 * gen_capture is set, which is all a quiet-position check needs. */
static uint8_t gen(uint8_t *b,uint8_t side,Move *list,uint8_t captures_only,uint8_t max) {
    uint8_t i,s,p,d,king,r;
    gb=b; gl=list; gn=0; gbest=0; gmax=max;
    for(i=0;i<32;i++) {
        s=dark[i]; p=b[s];
        if(!p || SIDE_OF(p)!=side) continue;
        b[s]=0; plen=1; path[0]=s;
        cap_dfs(s,p==WK || p==BK,side,0);
        b[s]=p;
    }
    gen_capture=gbest>0;
    if(gbest || captures_only) return gn;
    for(i=0;i<32;i++) {
        s=dark[i]; p=b[s];
        if(!p || SIDE_OF(p)!=side) continue;
        king=p==WK || p==BK;
        for(d=0;d<4;d++) {
            if(!king && dir_r[d]!=(side?1:-1)) continue;
            r=nbr[s*4+d];
            while(r!=NONE && !b[r]) {
                if(gn<max) {
                    list[gn].n=2; list[gn].caps=0;
                    list[gn].sq[0]=s; list[gn].sq[1]=r;
                    gn++;
                }
                if(!king) break;
                r=nbr[r*4+d];
            }
        }
    }
    return gn;
}

/* Plays a move generated for this board; returns the pieces captured. */
static uint8_t apply(uint8_t *b,const Move *m) {
    uint8_t p=b[m->sq[0]],i,s,z,taken=0; int8_t dr,dc,step;
    b[m->sq[0]]=0;
    for(i=1;i<m->n;i++) {
        s=m->sq[i-1]; z=m->sq[i];
        if(!m->caps) break;
        dr=ROW(z)>ROW(s)?1:-1; dc=COL(z)>COL(s)?1:-1;
        step=dr*8+dc;
        while(s!=z) {
            s+=step;
            if(b[s]) {b[s]=0; taken++;}
        }
    }
    z=m->sq[m->n-1];
    if(p==WM && ROW(z)==0) p=WK;
    if(p==BM && ROW(z)==7) p=BK;
    b[z]=p;
    return taken;
}

/* Material, advancement and king centralisation, white minus black. */
static int16_t eval(const uint8_t *b) {
    int16_t v=0,x; uint8_t i,s,p,r,c;
    for(i=0;i<32;i++) {
        s=dark[i]; p=b[s];
        if(!p) continue;
        r=ROW(s); c=COL(s);
        if(p==WM || p==BM) {
            x=100+(p==WM?7-r:r)*4;
            if(r==(p==WM?7:0)) x+=6;
            else if(c>1 && c<6) x+=2;
        } else {
            x=320;
            if(c>1 && c<6 && r>1 && r<6) x+=8;
        }
        v+=SIDE_OF(p)?-x:x;
    }
    return v;
}

#define INF 30000
#define MATE 20000
static uint8_t bd[MAXPLY][64];
static Move mlist[MAXPLY][SMAXM];
static uint16_t ai_seed=1;
static uint16_t nodes;

static int16_t search(int8_t depth,int16_t alpha,int16_t beta,uint8_t side,uint8_t ply) {
    Move *ml=mlist[ply]; uint8_t n,i,cap; int16_t best=-INF,v;
    nodes++;
    /* A leaf with a capture on the board is searched on: the capture is
     * forced, so the line is not quiet yet. */
    n=gen(bd[ply],side,ml,depth<=0,SMAXM); cap=gen_capture;
    if(depth<=0 && (!cap || ply>=MAXPLY-1)) {
        v=eval(bd[ply]);
        return side?-v:v;
    }
    if(!n) return -(MATE-ply);
    for(i=0;i<n;i++) {
        memcpy(bd[ply+1],bd[ply],64);
        apply(bd[ply+1],&ml[i]);
        v=-search(depth-1,-beta,-alpha,side^1,ply+1);
        if(v>best) {
            best=v;
            if(v>alpha) {alpha=v; if(alpha>=beta) break;}
        }
    }
    return best;
}

/* Best move for side searching depth plies (>=1); fills *out. Moves of equal
 * value are chosen by starting the scan at a pseudo-random move. Returns the
 * score from the mover's point of view, or -INF when there is no move. */
static int16_t ai_pick(const uint8_t *b,uint8_t side,uint8_t depth,Move *out) {
    Move *ml=mlist[0]; uint8_t n,i,k,pick=0; int16_t best=-INF,v;
    memcpy(bd[0],b,64);
    n=gen(bd[0],side,ml,0,SMAXM);
    if(!n) return -INF;
    if(n==1) {*out=ml[0]; return 0;}
    ai_seed=ai_seed*25173u+13849u;
    k=(ai_seed>>8)%n;
    for(i=0;i<n;i++,k=(k+1)%n) {
        memcpy(bd[1],bd[0],64);
        apply(bd[1],&ml[k]);
        v=-search(depth-1,-INF,-best+0,side^1,1);
        if(depth==1) {ai_seed=ai_seed*25173u+13849u; v+=(ai_seed>>12)&15;}
        if(v>best) {best=v; pick=k;}
    }
    *out=ml[pick];
    return best;
}
