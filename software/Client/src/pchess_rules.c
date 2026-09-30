/*
 * PChess rules for the TCP/IP link, where no MSXPi server checks moves.
 *
 * Included by pchess.c (make.bat compiles one file) and, unchanged, by the
 * host test pchess_rules_test.c, which plays random games against
 * python-chess. Everything a peer compares must match python-chess exactly:
 * FEN (the IRC protocol hashes it), SAN (the move list) and the end of the
 * game, including draws a player may claim (threefold, fifty moves), which
 * the server counts as over.
 *
 * Squares are 0-63, row-major from a8 (0) to h1 (63), as in the client's
 * board[8][8]; pieces are FEN letters, 0 for empty.
 */

typedef struct {
    char sq[64];
    uint8_t white;     /* side to move */
    uint8_t castle;    /* 1 K, 2 Q, 4 k, 8 q */
    int8_t ep;         /* square passed by a double push, or -1 */
    uint8_t half;
    uint16_t full;
} Pos;

static Pos pos;
static Pos scratch;
/* Bumped whenever pos changes, so callers can cache per position. */
static uint8_t pos_gen;
/* One candidate position per nesting level of generate(): a callback may
 * itself enumerate moves (the FEN's ep test, draw claims). */
static Pos tries[3];
static uint8_t depth;

/* Positions since the last irreversible move, for threefold repetition. */
#define REP_MAX 104
static uint32_t rep_key[REP_MAX];
static uint8_t rep_count;

#define ROW(s) ((s)>>3)
#define COL(s) ((s)&7)
#define IS_WHITE(p) ((p)>='A' && (p)<='Z')
#define UPPER(p) ((char)((p)>='a'?(p)-32:(p)))

static const int8_t knight_d[8][2]={{-2,-1},{-2,1},{-1,-2},{-1,2},{1,-2},{1,2},{2,-1},{2,1}};
static const int8_t king_d[8][2]={{-1,-1},{-1,0},{-1,1},{0,-1},{0,1},{1,-1},{1,0},{1,1}};

static int8_t step(uint8_t s,int8_t dr,int8_t dc) {
    int8_t r=ROW(s)+dr,c=COL(s)+dc;
    if(r<0 || r>7 || c<0 || c>7) return -1;
    return (int8_t)(r*8+c);
}

/* Is square s attacked by the side 'white'? */
static uint8_t attacked(const Pos *p,uint8_t s,uint8_t white) {
    uint8_t i; int8_t t; char c;
    t=step(s,white?1:-1,-1); if(t>=0 && p->sq[t]==(white?'P':'p')) return 1;
    t=step(s,white?1:-1,1);  if(t>=0 && p->sq[t]==(white?'P':'p')) return 1;
    for(i=0;i<8;i++) {
        t=step(s,knight_d[i][0],knight_d[i][1]);
        if(t>=0 && p->sq[t]==(white?'N':'n')) return 1;
        t=step(s,king_d[i][0],king_d[i][1]);
        if(t>=0 && p->sq[t]==(white?'K':'k')) return 1;
    }
    for(i=0;i<8;i++) {
        int8_t dr=king_d[i][0],dc=king_d[i][1];
        uint8_t diag=dr && dc;
        t=(int8_t)s;
        while((t=step((uint8_t)t,dr,dc))>=0) {
            c=p->sq[t];
            if(!c) continue;
            if(IS_WHITE(c)==white) {
                c=UPPER(c);
                if(c=='Q' || (diag?c=='B':c=='R')) return 1;
            }
            break;
        }
    }
    return 0;
}

static int8_t king_square(const Pos *p,uint8_t white) {
    uint8_t s;
    for(s=0;s<64;s++) if(p->sq[s]==(white?'K':'k')) return (int8_t)s;
    return -1;
}

static uint8_t in_check(const Pos *p) {
    int8_t k=king_square(p,p->white);
    return k>=0 && attacked(p,(uint8_t)k,!p->white);
}

/* Play from-to (promo 0 or a piece letter, either case) on p, no checks. */
static void play(Pos *p,uint8_t from,uint8_t to,char promo) {
    char piece=p->sq[from],kind=UPPER(piece);
    uint8_t white=IS_WHITE(piece);
    p->half++;
    if(kind=='P' || p->sq[to]) p->half=0;
    if(kind=='P' && (int8_t)to==p->ep && COL(from)!=COL(to) && !p->sq[to])
        p->sq[ROW(from)*8+COL(to)]=0;
    p->ep=-1;
    if(kind=='P' && (ROW(from)==ROW(to)+2 || ROW(to)==ROW(from)+2))
        p->ep=(int8_t)((from+to)/2);
    if(kind=='K' && (COL(to)==COL(from)+2 || COL(from)==COL(to)+2)) {
        uint8_t rook_from=COL(to)==6?to+1:to-2, rook_to=COL(to)==6?to-1:to+1;
        p->sq[rook_to]=p->sq[rook_from]; p->sq[rook_from]=0;
    }
    p->sq[to]=piece; p->sq[from]=0;
    if(promo) p->sq[to]=white?UPPER(promo):(char)(UPPER(promo)+32);
    if(from==60 || to==60) p->castle&=~3;
    if(from==4 || to==4) p->castle&=~12;
    if(from==63 || to==63) p->castle&=~1;
    if(from==56 || to==56) p->castle&=~2;
    if(from==7 || to==7) p->castle&=~4;
    if(from==0 || to==0) p->castle&=~8;
    if(!white) p->full++;
    p->white=!white;
}

/* Legal-move enumeration: visit() is called for each legal move of the
 * side to move in 'gen_pos', with the resulting position in *try_pos; a
 * non-zero return stops the walk. */
typedef uint8_t (*Visit)(uint8_t from,uint8_t to,char promo);
static const Pos *gen_pos;
static Pos *try_pos;
static Visit visit;
/* Only moves to this square are tried (255: all). Testing legality is the
 * expensive part, and SAN, parsing and the ep test need one square. */
static uint8_t gen_to;

static uint8_t try_move(uint8_t from,uint8_t to,char promo) {
    int8_t k;
    if(gen_to!=255 && to!=gen_to) return 0;
    memcpy(try_pos,gen_pos,sizeof(Pos));
    play(try_pos,from,to,promo);
    k=king_square(try_pos,gen_pos->white);
    if(k>=0 && attacked(try_pos,(uint8_t)k,try_pos->white)) return 0;
    return visit(from,to,promo);
}

static uint8_t try_pawn(uint8_t from,uint8_t to) {
    if(ROW(to)==0 || ROW(to)==7)
        return try_move(from,to,'q') || try_move(from,to,'r') ||
               try_move(from,to,'b') || try_move(from,to,'n');
    return try_move(from,to,0);
}

static uint8_t walk(const Pos *p) {
    uint8_t s,i,white=p->white; int8_t t; char c,kind;
    for(s=0;s<64;s++) {
        c=p->sq[s];
        if(!c || IS_WHITE(c)!=white) continue;
        kind=UPPER(c);
        if(kind=='P') {
            int8_t dir=white?-1:1;
            t=step(s,dir,0);
            if(t>=0 && !p->sq[t]) {
                if(try_pawn(s,(uint8_t)t)) return 1;
                if(ROW(s)==(white?6:1)) {
                    t=step((uint8_t)t,dir,0);
                    if(!p->sq[t] && try_move(s,(uint8_t)t,0)) return 1;
                }
            }
            for(i=0;i<2;i++) {
                t=step(s,dir,i?1:-1);
                if(t<0) continue;
                if((p->sq[t] && IS_WHITE(p->sq[t])!=white) || t==p->ep)
                    if(try_pawn(s,(uint8_t)t)) return 1;
            }
        } else if(kind=='N' || kind=='K') {
            for(i=0;i<8;i++) {
                t=kind=='N'?step(s,knight_d[i][0],knight_d[i][1]):step(s,king_d[i][0],king_d[i][1]);
                if(t>=0 && (!p->sq[t] || IS_WHITE(p->sq[t])!=white) &&
                   try_move(s,(uint8_t)t,0)) return 1;
            }
            if(kind=='K' && s==(white?60:4) && !attacked(p,s,!white)) {
                uint8_t k=white?1:4, q=white?2:8;
                if((p->castle&k) && !p->sq[s+1] && !p->sq[s+2] &&
                   !attacked(p,s+1,!white) && try_move(s,s+2,0)) return 1;
                if((p->castle&q) && !p->sq[s-1] && !p->sq[s-2] && !p->sq[s-3] &&
                   !attacked(p,s-1,!white) && try_move(s,s-2,0)) return 1;
            }
        } else {
            for(i=0;i<8;i++) {
                int8_t dr=king_d[i][0],dc=king_d[i][1];
                if(kind=='B' && !(dr && dc)) continue;
                if(kind=='R' && dr && dc) continue;
                t=(int8_t)s;
                while((t=step((uint8_t)t,dr,dc))>=0) {
                    if(p->sq[t] && IS_WHITE(p->sq[t])==white) break;
                    if(try_move(s,(uint8_t)t,0)) return 1;
                    if(p->sq[t]) break;
                }
            }
        }
    }
    return 0;
}

static uint8_t generate_to(const Pos *p,Visit cb,uint8_t to) {
    const Pos *old_pos=gen_pos; Pos *old_try=try_pos; Visit old_visit=visit;
    uint8_t r,old_to=gen_to;
    gen_pos=p; visit=cb; gen_to=to; try_pos=&tries[depth++];
    r=walk(p);
    depth--; gen_pos=old_pos; try_pos=old_try; visit=old_visit; gen_to=old_to;
    return r;
}
static uint8_t generate(const Pos *p,Visit cb) {
    return generate_to(p,cb,255);
}

static uint8_t stop_any(uint8_t from,uint8_t to,char promo) {
    (void)from; (void)to; (void)promo; return 1;
}
static uint8_t has_moves(const Pos *p) {
    return generate(p,stop_any);
}

/* A legal en-passant capture exists: python-chess only then shows the ep
 * square in the FEN and counts it in repetitions. */
static const Pos *ep_pos;
static uint8_t stop_ep(uint8_t from,uint8_t to,char promo) {
    (void)promo;
    return (int8_t)to==ep_pos->ep && UPPER(ep_pos->sq[from])=='P' && COL(from)!=COL(to);
}
static uint8_t legal_ep(const Pos *p) {
    const Pos *old=ep_pos; uint8_t r;
    if(p->ep<0) return 0;
    ep_pos=p; r=generate_to(p,stop_ep,(uint8_t)p->ep); ep_pos=old;
    return r;
}

static char *put_square(char *out,uint8_t s) {
    *out++=(char)('a'+COL(s)); *out++=(char)('8'-ROW(s)); return out;
}

static char *put_number(char *out,uint16_t n) {
    char digits[6]; uint8_t i=0;
    do { digits[i++]=(char)('0'+n%10); n/=10; } while(n);
    while(i) *out++=digits[--i];
    return out;
}

/* python-chess Board.fen(): the ep square only when a legal capture exists. */
static void make_fen(const Pos *p,char *out) {
    uint8_t r,c,empty;
    for(r=0;r<8;r++) {
        empty=0;
        for(c=0;c<8;c++) {
            char x=p->sq[r*8+c];
            if(!x) { empty++; continue; }
            if(empty) { *out++=(char)('0'+empty); empty=0; }
            *out++=x;
        }
        if(empty) *out++=(char)('0'+empty);
        if(r<7) *out++='/';
    }
    *out++=' '; *out++=p->white?'w':'b'; *out++=' ';
    if(!p->castle) *out++='-';
    if(p->castle&1) *out++='K';
    if(p->castle&2) *out++='Q';
    if(p->castle&4) *out++='k';
    if(p->castle&8) *out++='q';
    *out++=' ';
    if(legal_ep(p)) out=put_square(out,(uint8_t)p->ep); else *out++='-';
    *out++=' '; out=put_number(out,p->half);
    *out++=' '; out=put_number(out,p->full);
    *out=0;
}

/* python-chess _transposition_key(): pieces, turn, castling, legal ep. */
static uint32_t position_key(const Pos *p) {
    uint32_t h=2166136261UL; uint8_t s;
    for(s=0;s<64;s++) h=(h^(uint8_t)p->sq[s])*16777619UL;
    h=(h^p->white)*16777619UL;
    h=(h^p->castle)*16777619UL;
    h=(h^(uint8_t)(legal_ep(p)?p->ep:-1))*16777619UL;
    return h;
}

static void rules_reset(void) {
    static const char start[]="rnbqkbnrpppppppp................................PPPPPPPPRNBQKBNR";
    uint8_t s;
    memset(&pos,0,sizeof(pos));
    for(s=0;s<64;s++) pos.sq[s]=start[s]=='.'?0:start[s];
    pos.white=1; pos.castle=15; pos.ep=-1; pos.full=1;
    pos_gen++;
    rep_count=1; rep_key[0]=position_key(&pos);
}

/* python-chess is_irreversible(): zeroing, losing castling rights, or
 * giving up a legal en-passant capture. */
static void rules_play(uint8_t from,uint8_t to,char promo) {
    uint8_t irreversible=pos.sq[to] || UPPER(pos.sq[from])=='P' || legal_ep(&pos);
    uint8_t castle=pos.castle;
    play(&pos,from,to,promo);
    pos_gen++;
    if(pos.castle!=castle) irreversible=1;
    if(irreversible) rep_count=0;
    if(rep_count==REP_MAX) { memmove(rep_key,rep_key+1,sizeof(rep_key)-4); rep_count--; }
    rep_key[rep_count++]=position_key(&pos);
}

static uint8_t count_key(uint32_t key) {
    uint8_t i,n=0;
    for(i=0;i<rep_count;i++) if(rep_key[i]==key) n++;
    return n;
}

/* Claims python-chess allows before the move: the position is already the
 * third, or a legal move would make it so; fifty moves, or a legal move
 * would complete them. */
static uint8_t check_claim(uint8_t from,uint8_t to,char promo) {
    Pos *p=try_pos;
    (void)from; (void)to; (void)promo;
    if(p->half>=100 && has_moves(p)) return 1;
    return rep_count>=3 && count_key(position_key(p))>=2;
}
static uint8_t can_claim_draw(void) {
    if(count_key(rep_key[rep_count-1])>=3) return 1;
    if(pos.half>=100 && has_moves(&pos)) return 1;
    if(pos.half<99 && rep_count<3) return 0;
    return generate(&pos,check_claim);
}

/* Sufficient-material test copied from python-chess. */
static uint8_t insufficient(uint8_t white) {
    uint8_t s,own=0,knights=0,bishops=0,dark=0,light=0,other_active=0,any_pawn=0,any_knight=0;
    for(s=0;s<64;s++) {
        char c=pos.sq[s],k;
        if(!c) continue;
        k=UPPER(c);
        if(k=='P') any_pawn=1;
        if(k=='N') any_knight=1;
        if(k=='B') { if((COL(s)+7-ROW(s))&1) light=1; else dark=1; }
        if(IS_WHITE(c)==white) {
            own++;
            if(k=='P' || k=='R' || k=='Q') return 0;
            if(k=='N') knights++;
            if(k=='B') bishops++;
        } else if(k!='K' && k!='Q') other_active=1;
    }
    if(knights) return own<=2 && !other_active;
    if(bishops) return (!dark || !light) && !any_pawn && !any_knight;
    return 1;
}

/* 0 playing, 1 white wins, 2 black wins, 3 draw (python-chess
 * outcome(claim_draw=True)). */
static uint8_t outcome_gen,outcome_value,outcome_ok;
static uint8_t outcome_of_pos(void) {
    if(!has_moves(&pos)) return in_check(&pos)?(pos.white?2:1):3;
    if(insufficient(1) && insufficient(0)) return 3;
    if(can_claim_draw()) return 3;
    return 0;
}
static uint8_t rules_outcome(void) {
    if(!outcome_ok || outcome_gen!=pos_gen) {
        outcome_value=outcome_of_pos(); outcome_gen=pos_gen; outcome_ok=1;
    }
    return outcome_value;
}

/* SAN as python-chess writes it. */
static uint8_t san_from,san_to,san_rows,san_cols,san_others;
static char san_kind;
static uint8_t san_peers(uint8_t from,uint8_t to,char promo) {
    (void)promo;
    if(to==san_to && from!=san_from && UPPER(gen_pos->sq[from])==san_kind) {
        san_others=1;
        if(ROW(from)==ROW(san_from)) san_cols=1;
        if(COL(from)==COL(san_from)) san_rows=1;
    }
    return 0;
}
static void make_san(uint8_t from,uint8_t to,char promo,char *out) {
    char kind=UPPER(pos.sq[from]);
    uint8_t capture=pos.sq[to] || (kind=='P' && COL(from)!=COL(to));
    if(kind=='K' && (COL(to)==COL(from)+2 || COL(from)==COL(to)+2)) {
        strcpy(out,COL(to)==6?"O-O":"O-O-O"); out+=strlen(out);
    } else {
        if(kind=='P') {
            if(capture) *out++=(char)('a'+COL(from));
        } else {
            *out++=kind;
            san_from=from; san_to=to; san_kind=kind; san_rows=san_cols=san_others=0;
            generate_to(&pos,san_peers,to);
            if(san_others) {
                if(san_rows) { if(san_cols) *out++=(char)('a'+COL(from)); *out++=(char)('8'-ROW(from)); }
                else *out++=(char)('a'+COL(from));
            }
        }
        if(capture) *out++='x';
        out=put_square(out,to);
        if(promo) { *out++='='; *out++=UPPER(promo); }
    }
    memcpy(&scratch,&pos,sizeof(Pos));
    play(&scratch,from,to,promo);
    if(in_check(&scratch)) *out++=has_moves(&scratch)?'+':'#';
    *out=0;
}

/* Parse UCI (e2e4, e7e8q, dashes allowed) or SAN; fills the move and
 * returns 1 when it names a legal move. */
static uint8_t want_from,want_to,want_fc,want_fr,found_n,found_from,found_to;
static char want_kind,want_promo,found_promo;
static uint8_t match_move(uint8_t from,uint8_t to,char promo) {
    char kind=UPPER(gen_pos->sq[from]);
    if(want_from!=255 && from!=want_from) return 0;
    if(to!=want_to) return 0;
    if(want_kind && kind!=want_kind) return 0;
    if(want_fc!=255 && COL(from)!=want_fc) return 0;
    if(want_fr!=255 && ROW(from)!=want_fr) return 0;
    if(promo && UPPER(promo)!=want_promo) return 0;
    found_from=from; found_to=to; found_promo=promo; found_n++;
    return 0;
}
static uint8_t is_file(char c) { return c>='a' && c<='h'; }
static uint8_t is_rank(char c) { return c>='1' && c<='8'; }
static uint8_t run_match(void) {
    found_n=0; generate_to(&pos,match_move,want_to);
    return found_n==1;
}
/* Like the server: UCI first, then SAN (so "B3f4" is a bishop move). */
static uint8_t rules_parse(const char *text,uint8_t *from,uint8_t *to,char *promo) {
    char s[20],u[20]; uint8_t n=0,m=0,k=0,i;
    for(i=0;text[i] && n<19;i++) {
        char c=text[i];
        if(c=='+' || c=='#' || c=='!' || c=='?') continue;
        s[n++]=c;
    }
    s[n]=0;
    for(i=0;i<n;i++) if(s[i]!='-') u[m++]=(char)(s[i]>='A' && s[i]<='Z' && i?s[i]+32:s[i]);
    u[m]=0;
    want_from=want_fc=want_fr=255; want_kind=0; want_promo='Q';
    if((m==4 || m==5) && is_file(u[0]|32) && is_rank(u[1]) && is_file(u[2]) && is_rank(u[3])) {
        want_from=(uint8_t)(('8'-u[1])*8+((u[0]|32)-'a'));
        want_to=(uint8_t)(('8'-u[3])*8+(u[2]-'a'));
        if(m==5) want_promo=UPPER(u[4]);
        if(run_match()) goto found;
        want_from=255; want_promo='Q';
    }
    if(!strcmp(s,"O-O") || !strcmp(s,"0-0") || !strcmp(s,"o-o") ||
       !strcmp(s,"O-O-O") || !strcmp(s,"0-0-0") || !strcmp(s,"o-o-o")) {
        want_kind='K'; want_from=pos.white?60:4;
        want_to=(uint8_t)(want_from+(n==3?2:-2));
    } else {
        if(u[0]=='N' || u[0]=='B' || u[0]=='R' || u[0]=='Q' || u[0]=='K' ||
           u[0]=='n' || u[0]=='r' || u[0]=='q' || u[0]=='k') { want_kind=UPPER(u[0]); k=1; }
        else want_kind='P';
        if(m>=2 && u[m-2]=='=') { want_promo=UPPER(u[m-1]); m-=2; }
        else if(want_kind=='P' && m>=3 && !is_rank(u[m-1])) { want_promo=UPPER(u[m-1]); m--; }
        if(m<k+2 || !is_file(u[m-2]) || !is_rank(u[m-1])) return 0;
        want_to=(uint8_t)(('8'-u[m-1])*8+(u[m-2]-'a'));
        m-=2;
        if(m>k && u[m-1]=='x') m--;
        if(m>k && is_rank(u[m-1])) want_fr=(uint8_t)('8'-u[--m]);
        if(m>k && is_file(u[m-1])) want_fc=(uint8_t)(u[--m]-'a');
        if(m!=k) return 0;
    }
    if(!run_match()) return 0;
found:
    *from=found_from; *to=found_to; *promo=found_promo;
    return 1;
}
