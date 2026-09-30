/* Host build of pchess_rules.c for pchess_rules_test.py: one command per
 * stdin line, one reply per stdout line. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "../src/pchess_rules.c"
#include "../src/pchess_sha.c"

static char line[256];
static uint8_t list_move(uint8_t from,uint8_t to,char promo) {
    char san[16];
    make_san(from,to,promo,san);
    printf(" %c%c%c%c%s:%s",'a'+COL(from),'8'-ROW(from),'a'+COL(to),'8'-ROW(to),
           promo?(char[]){promo|32,0}:"",san);
    return 0;
}
int main(void) {
    char fen[100]; uint8_t from,to; char promo;
    setvbuf(stdout,NULL,_IOLBF,0);
    while(fgets(line,sizeof line,stdin)) {
        line[strcspn(line,"\r\n")]=0;
        if(!strcmp(line,"reset")) { rules_reset(); puts("ok"); }
        else if(!strcmp(line,"fen")) { make_fen(&pos,fen); puts(fen); }
        else if(!strcmp(line,"digest")) { char d[17]; make_fen(&pos,fen); sha_digest16(fen,d); puts(d); }
        else if(!strcmp(line,"moves")) { generate(&pos,list_move); puts(""); }
        else if(!strcmp(line,"outcome")) printf("%d\n",rules_outcome());
        else if(!strncmp(line,"parse ",6)) {
            if(rules_parse(line+6,&from,&to,&promo))
                printf("%c%c%c%c%s\n",'a'+COL(from),'8'-ROW(from),'a'+COL(to),'8'-ROW(to),promo?(char[]){promo|32,0}:"");
            else puts("none");
        }
        else if(!strncmp(line,"play ",5)) {
            if(rules_parse(line+5,&from,&to,&promo)) { rules_play(from,to,promo); puts("ok"); }
            else puts("illegal");
        }
        else puts("?");
    }
    return 0;
}
