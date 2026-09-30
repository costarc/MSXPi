/*
 * SHA-256 of a short string, for the PCH1 IRC protocol's position digest:
 * the first 16 hex digits of sha256(FEN), as msxpi_pchess_irc.digest().
 * Included by pchess.c and by the host test.
 */

static const uint32_t sha_k[64]={
    0x428a2f98UL,0x71374491UL,0xb5c0fbcfUL,0xe9b5dba5UL,0x3956c25bUL,0x59f111f1UL,0x923f82a4UL,0xab1c5ed5UL,
    0xd807aa98UL,0x12835b01UL,0x243185beUL,0x550c7dc3UL,0x72be5d74UL,0x80deb1feUL,0x9bdc06a7UL,0xc19bf174UL,
    0xe49b69c1UL,0xefbe4786UL,0x0fc19dc6UL,0x240ca1ccUL,0x2de92c6fUL,0x4a7484aaUL,0x5cb0a9dcUL,0x76f988daUL,
    0x983e5152UL,0xa831c66dUL,0xb00327c8UL,0xbf597fc7UL,0xc6e00bf3UL,0xd5a79147UL,0x06ca6351UL,0x14292967UL,
    0x27b70a85UL,0x2e1b2138UL,0x4d2c6dfcUL,0x53380d13UL,0x650a7354UL,0x766a0abbUL,0x81c2c92eUL,0x92722c85UL,
    0xa2bfe8a1UL,0xa81a664bUL,0xc24b8b70UL,0xc76c51a3UL,0xd192e819UL,0xd6990624UL,0xf40e3585UL,0x106aa070UL,
    0x19a4c116UL,0x1e376c08UL,0x2748774cUL,0x34b0bcb5UL,0x391c0cb3UL,0x4ed8aa4aUL,0x5b9cca4fUL,0x682e6ff3UL,
    0x748f82eeUL,0x78a5636fUL,0x84c87814UL,0x8cc70208UL,0x90befffaUL,0xa4506cebUL,0xbef9a3f7UL,0xc67178f2UL
};
static uint32_t sha_h[8],sha_w[64];

#ifdef __SDCC
/* Z80 compression: SDCC's 32-bit C took 1.5 s a digest. A 32-bit value
 * lives in B (msb) C D E (lsb); words in memory are little-endian. The
 * helpers take a word pointer in HL and keep it. */
static uint32_t sha_v[8],sha_t1,sha_t2,sha_tmp;
static const uint8_t *sha_src;
static uint8_t sha_i;
static uint32_t *sha_kp,*sha_wp;

static void sha_asm(void) __naked {
__asm
    push ix
    ; --- W[0..15] from the big-endian block
    ld hl,(_sha_src)
    ld de,#_sha_w
    ld b,#16
shaa_load:
    push bc
    ld a,(hl)
    inc hl
    ld b,a
    ld a,(hl)
    inc hl
    ld c,a
    ld a,(hl)
    inc hl
    push af
    ld a,(hl)
    inc hl
    ld (de),a
    inc de
    pop af
    ld (de),a
    inc de
    ld a,c
    ld (de),a
    inc de
    ld a,b
    ld (de),a
    inc de
    pop bc
    djnz shaa_load
    ; --- W[16..63]
    ld ix,#_sha_w+64
    ld a,#48
    ld (_sha_i),a
shaa_sched:
    ; W[i]=W[i-16]
    push ix
    pop hl
    ld de,#-64
    add hl,de
    call shaa_ld32
    push ix
    pop hl
    call shaa_st32
    ; += s0(W[i-15]) = ror7 ^ ror18 ^ shr3
    push ix
    pop hl
    ld de,#-60
    add hl,de
    push hl
    call shaa_ld32
    ld a,#3
    call shaa_shrn
    ld hl,#_sha_tmp
    call shaa_st32
    pop hl
    call shaa_ld32
    ld a,#7
    call shaa_rorn
    ld hl,#_sha_tmp
    call shaa_xorm
    call shaa_ror8
    ld a,#3
    call shaa_rorn
    call shaa_xorm
    call shaa_ld32
    push ix
    pop hl
    call shaa_addm
    ; += s1(W[i-2]) = ror17 ^ ror19 ^ shr10
    push ix
    pop hl
    ld de,#-8
    add hl,de
    push hl
    call shaa_ld32
    call shaa_shr8
    ld a,#2
    call shaa_shrn
    ld hl,#_sha_tmp
    call shaa_st32
    pop hl
    call shaa_ld32
    call shaa_ror8
    call shaa_ror8
    ld a,#1
    call shaa_rorn
    ld hl,#_sha_tmp
    call shaa_xorm
    ld a,#2
    call shaa_rorn
    call shaa_xorm
    call shaa_ld32
    push ix
    pop hl
    call shaa_addm
    ; += W[i-7]
    push ix
    pop hl
    ld de,#-28
    add hl,de
    call shaa_ld32
    push ix
    pop hl
    call shaa_addm
    ld de,#4
    add ix,de
    ld hl,#_sha_i
    dec (hl)
    jp nz,shaa_sched
    ; --- a..h = H
    ld hl,#_sha_h
    ld de,#_sha_v
    ld bc,#32
    ldir
    ld hl,#_sha_k
    ld (_sha_kp),hl
    ld hl,#_sha_w
    ld (_sha_wp),hl
    ld a,#64
    ld (_sha_i),a
shaa_round:
    ; t1 = h + S1(e) + Ch(e,f,g) + K[i] + W[i]
    ld hl,#_sha_v+28
    call shaa_ld32
    ld hl,#_sha_t1
    call shaa_st32
    ld hl,#_sha_v+16
    call shaa_ld32
    ld a,#6
    call shaa_rorn
    ld hl,#_sha_tmp
    call shaa_st32
    ld a,#5
    call shaa_rorn
    call shaa_xorm
    call shaa_ror8
    ld a,#6
    call shaa_rorn
    call shaa_xorm
    call shaa_ld32
    ld hl,#_sha_t1
    call shaa_addm
    ld hl,#_sha_v+20            ; Ch = g ^ (e & (f ^ g))
    call shaa_ld32
    ld hl,#_sha_v+24
    call shaa_xorr
    ld hl,#_sha_v+16
    call shaa_andr
    ld hl,#_sha_v+24
    call shaa_xorr
    ld hl,#_sha_t1
    call shaa_addm
    ld hl,(_sha_kp)
    call shaa_ld32
    ld hl,#_sha_t1
    call shaa_addm
    ld hl,(_sha_wp)
    call shaa_ld32
    ld hl,#_sha_t1
    call shaa_addm
    ; tmp = S0(a) + Maj(a,b,c); Maj = (a & b) | (c & (a | b))
    ld hl,#_sha_v
    call shaa_ld32
    ld a,#2
    call shaa_rorn
    ld hl,#_sha_tmp
    call shaa_st32
    call shaa_ror8
    ld a,#3
    call shaa_rorn
    call shaa_xorm
    call shaa_ror8
    ld a,#1
    call shaa_rorn
    call shaa_xorm
    ld hl,#_sha_v
    call shaa_ld32
    ld hl,#_sha_v+4
    call shaa_orr
    ld hl,#_sha_v+8
    call shaa_andr
    ld hl,#_sha_t2
    call shaa_st32
    ld hl,#_sha_v
    call shaa_ld32
    ld hl,#_sha_v+4
    call shaa_andr
    ld hl,#_sha_t2
    call shaa_orr
    ld hl,#_sha_tmp
    call shaa_addm
    ; h..b = g..a
    ld hl,#_sha_v+27
    ld de,#_sha_v+31
    ld bc,#28
    lddr
    ; e = d + t1; a = t1 + tmp
    ld hl,#_sha_t1
    call shaa_ld32
    ld hl,#_sha_v+16
    call shaa_addm
    ld hl,#_sha_tmp
    call shaa_addm
    call shaa_ld32
    ld hl,#_sha_v
    call shaa_st32
    ld hl,(_sha_kp)
    ld de,#4
    add hl,de
    ld (_sha_kp),hl
    ld hl,(_sha_wp)
    add hl,de
    ld (_sha_wp),hl
    ld hl,#_sha_i
    dec (hl)
    jp nz,shaa_round
    ; --- H += a..h
    ld ix,#_sha_v
    ld hl,#_sha_h
    ld a,#8
shaa_final:
    push af
    ld e,0(ix)
    ld d,1(ix)
    ld c,2(ix)
    ld b,3(ix)
    call shaa_addm
    ld de,#4
    add hl,de
    add ix,de
    pop af
    dec a
    jr nz,shaa_final
    pop ix
    ret

shaa_ld32:
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld c,(hl)
    inc hl
    ld b,(hl)
    dec hl
    dec hl
    dec hl
    ret
shaa_st32:
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld (hl),c
    inc hl
    ld (hl),b
    dec hl
    dec hl
    dec hl
    ret
shaa_xorm:                      ; (HL) ^= BCDE
    ld a,(hl)
    xor e
    ld (hl),a
    inc hl
    ld a,(hl)
    xor d
    ld (hl),a
    inc hl
    ld a,(hl)
    xor c
    ld (hl),a
    inc hl
    ld a,(hl)
    xor b
    ld (hl),a
    dec hl
    dec hl
    dec hl
    ret
shaa_addm:                      ; (HL) += BCDE
    ld a,(hl)
    add a,e
    ld (hl),a
    inc hl
    ld a,(hl)
    adc a,d
    ld (hl),a
    inc hl
    ld a,(hl)
    adc a,c
    ld (hl),a
    inc hl
    ld a,(hl)
    adc a,b
    ld (hl),a
    dec hl
    dec hl
    dec hl
    ret
shaa_xorr:                      ; BCDE ^= (HL)
    ld a,(hl)
    xor e
    ld e,a
    inc hl
    ld a,(hl)
    xor d
    ld d,a
    inc hl
    ld a,(hl)
    xor c
    ld c,a
    inc hl
    ld a,(hl)
    xor b
    ld b,a
    dec hl
    dec hl
    dec hl
    ret
shaa_andr:                      ; BCDE &= (HL)
    ld a,(hl)
    and e
    ld e,a
    inc hl
    ld a,(hl)
    and d
    ld d,a
    inc hl
    ld a,(hl)
    and c
    ld c,a
    inc hl
    ld a,(hl)
    and b
    ld b,a
    dec hl
    dec hl
    dec hl
    ret
shaa_orr:                       ; BCDE |= (HL)
    ld a,(hl)
    or e
    ld e,a
    inc hl
    ld a,(hl)
    or d
    ld d,a
    inc hl
    ld a,(hl)
    or c
    ld c,a
    inc hl
    ld a,(hl)
    or b
    ld b,a
    dec hl
    dec hl
    dec hl
    ret
shaa_rorn:                      ; BCDE = BCDE ror A (A = 1-7)
    push hl
    ld h,a
shaa_rorl:
    ld a,e
    rrca
    rr b
    rr c
    rr d
    rr e
    dec h
    jr nz,shaa_rorl
    pop hl
    ret
shaa_shrn:                      ; BCDE >>= A (A = 1-7)
    push hl
    ld h,a
shaa_shrl:
    srl b
    rr c
    rr d
    rr e
    dec h
    jr nz,shaa_shrl
    pop hl
    ret
shaa_ror8:
    ld a,e
    ld e,d
    ld d,c
    ld c,b
    ld b,a
    ret
shaa_shr8:
    ld e,d
    ld d,c
    ld c,b
    ld b,#0
    ret
__endasm;
}

static void sha_block(const uint8_t *b) {
    sha_src=b;
    sha_asm();
}
#else
static uint32_t ror(uint32_t x,uint8_t n) { return (x>>n)|(x<<(32-n)); }

static void sha_block(const uint8_t *b) {
    uint32_t a,bb,c,d,e,f,g,h,t1,t2;
    uint8_t i;
    for(i=0;i<16;i++,b+=4)
        sha_w[i]=((uint32_t)b[0]<<24)|((uint32_t)b[1]<<16)|((uint32_t)b[2]<<8)|b[3];
    for(i=16;i<64;i++) {
        a=sha_w[i-15]; e=sha_w[i-2];
        sha_w[i]=sha_w[i-16]+(ror(a,7)^ror(a,18)^(a>>3))+sha_w[i-7]+(ror(e,17)^ror(e,19)^(e>>10));
    }
    a=sha_h[0]; bb=sha_h[1]; c=sha_h[2]; d=sha_h[3]; e=sha_h[4]; f=sha_h[5]; g=sha_h[6]; h=sha_h[7];
    for(i=0;i<64;i++) {
        t1=h+(ror(e,6)^ror(e,11)^ror(e,25))+((e&f)^(~e&g))+sha_k[i]+sha_w[i];
        t2=(ror(a,2)^ror(a,13)^ror(a,22))+((a&bb)^(a&c)^(bb&c));
        h=g; g=f; f=e; e=d+t1; d=c; c=bb; bb=a; a=t1+t2;
    }
    sha_h[0]+=a; sha_h[1]+=bb; sha_h[2]+=c; sha_h[3]+=d; sha_h[4]+=e; sha_h[5]+=f; sha_h[6]+=g; sha_h[7]+=h;
}
#endif

/* out gets 16 lowercase hex digits and a NUL; text is at most 119 bytes. */
static void sha_digest16(const char *text,char *out) {
    static const uint32_t init[8]={0x6a09e667UL,0xbb67ae85UL,0x3c6ef372UL,0xa54ff53aUL,
                                  0x510e527fUL,0x9b05688cUL,0x1f83d9abUL,0x5be0cd19UL};
    static uint8_t block[128];
    uint8_t len=(uint8_t)strlen(text),blocks=len<56?1:2,i;
    uint16_t bits=(uint16_t)len*8;
    memcpy(sha_h,init,sizeof(init));
    memset(block,0,sizeof(block));
    memcpy(block,text,len);
    block[len]=0x80;
    block[blocks*64-2]=(uint8_t)(bits>>8); block[blocks*64-1]=(uint8_t)bits;
    for(i=0;i<blocks;i++) sha_block(block+i*64);
    for(i=0;i<8;i++) {
        uint8_t byte=(uint8_t)(sha_h[i>>2]>>(24-8*(i&3)));
        out[i*2]="0123456789abcdef"[byte>>4];
        out[i*2+1]="0123456789abcdef"[byte&15];
    }
    out[16]=0;
}
