/* netcore_cost bench (tests/netcore_cost.py): nc_xchg on the Z80 in SDCC's simulator.
 * Stub host: one SETUP arrives (the session goes READY), then nothing. Two markers bracket 40 sending exchanges. */
#include <stdint.h>
#include "netcore.h"
volatile uint16_t ticks;
static uint8_t fed;
void nc_send(const nc_addr *to, const uint8_t *d, uint8_t l){(void)to;(void)d;(void)l;}
uint8_t nc_recv(nc_addr *f, uint8_t *b, uint8_t m){
  (void)m;
  if(!fed){fed=1;f->ip[0]=1;f->ip[1]=1;f->ip[2]=1;f->ip[3]=1;f->port=5000;
    b[0]=4;b[1]=1;b[2]=1;b[3]=0;b[4]=0;b[5]=0;b[6]=3;b[7]=0;b[8]=0;b[9]=0;b[10]=0;b[11]=0;b[12]=0;b[13]=0;return 14;}
  return 0;}
uint16_t nc_now(void){return ticks;}
uint32_t nc_rand32(void){return 5;}
uint8_t pkt[22]; uint8_t rx[46]; uint8_t reason;
void marker(void){}
void main(void){
  nc_addr a={{1,1,1,1},5000}; uint8_t i;
  pkt[0]=0x10;pkt[3]=1;
  nc_init(0,1,0,60); nc_set_peers(&a,1); nc_restart();
  nc_xchg(0,0,rx,&reason);
  marker();
  for(i=0;i<40;i++) nc_xchg(pkt,22,rx,&reason);
  marker();
  for(;;);
}
