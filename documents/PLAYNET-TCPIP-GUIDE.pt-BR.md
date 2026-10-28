# Jogando os jogos PLAYNET por TCP/IP

*Português do Brasil. English: [PLAYNET-TCPIP-GUIDE.en.md](PLAYNET-TCPIP-GUIDE.en.md)*

> **Alfa.** O jogo online ainda está em teste. Até agora só foi experimentado entre emuladores. Não foi testado em um GR8NET
> nem em hardware real por TCP/IP. Espere arestas.

Duas pessoas, cada uma com um MSX, conversam no chat e depois jogam uma contra a outra pela Internet. Este guia é para MSX que
acessam a rede por uma **placa TCP/IP** (e não pelo link do MSXPi).

## Que tipo de placa você tem?

| Sua placa | Exemplos | Instalar o InterNestor Lite (INL)? |
|---|---|---|
| **Placa Ethernet** | a Ethernet do MSXPi, ObsoNET | **Sim** (Passo 2A) |
| **Placa com TCP/IP embutido** | GR8NET, DenYoNet | **Não** (Passo 2B) |

O resto é igual para os dois.

## Passo 1 - Reúna os arquivos

Os dois jogadores precisam destes arquivos juntos **em um disco ou em uma pasta**. Copie-os de um PC (o MSX não consegue baixá-los).

**Para todos**

| Arquivo | O que é | Onde obter |
|---|---|---|
| `MCHAT.COM` | o chat | `software/target/` |
| `PLAYNET.COM` | inicia o jogo | `software/target/` |
| `PLAYNET.OVL` | acompanha o `PLAYNET.COM` | `software/target/` |
| `SOCCER.GPF` (ou o `.GPF` de outro jogo, inclusive `1942.GPF`) | o pacote do jogo | `software/target/games/` |
| `SOCCER.ROM` (ou a ROM do jogo) | **a sua própria cópia do jogo** | você (não é fornecida) |
| `MCHAT.INI` | suas configurações (opcional, veja o Passo 4) | você escreve |

**Só para placas Ethernet (Passo 2A)**

| Arquivo | Onde obter |
|---|---|
| `INL.COM` e `INL.CFG` | `software/UNAPI/bin/` e `software/target/` |
| `MSR.COM` (só se usar MSX-DOS 1) | `software/UNAPI/bin/` |
| `RAMHELPR.COM` (só se usar Nextor ou MSX-DOS 2) | `software/UNAPI/bin/` |
| o driver da própria placa (ObsoNET e outras; não é necessário no MSXPi) | vem com a placa |

**Os jogos e os arquivos de ROM**

| Jogo | Arquivo do jogo | Sua ROM deve se chamar | Tamanho |
|---|---|---|---|
| Soccer da Konami | `SOCCER.GPF` | `SOCCER.ROM` | 32768 bytes |
| Ping Pong da Konami | `PINGPONG.GPF` | `PINGPONG.ROM` | 16384 bytes |
| Yie Ar Kung-Fu da Konami | `YIEAR.GPF` | `KUNGFU.ROM` | 16384 bytes |
| Salamander da Konami | `SALAMAND.GPF` | `SALAMAND.ROM` | 131072 bytes (veja "Salamander" no final) |
| 1942 da ASCII (2 jogadores, alternando) | `1942.GPF` | `1942.ROM` | 131072 bytes (veja "1942" no final) |

**Confira seus arquivos (SHA-256).** Para ter certeza de que a ROM e o arquivo do jogo estão corretos, compare o SHA-256 deles (em um
PC: `certutil -hashfile ARQUIVO SHA256` no Windows, `sha256sum ARQUIVO` no Linux). A ROM também deve bater com o CRC-32 (o jogo confere ao iniciar; o SHA-256 foi conferido pelo código que gerou o arquivo do jogo).

| Jogo | Arquivo da ROM | CRC-32 da ROM | SHA-256 da ROM | Arquivo do jogo | SHA-256 do arquivo do jogo |
|---|---|---|---|---|---|
| soccer | `SOCCER.ROM` | `74BC8295` | `b9536809a1784afb2e49a43d80ba9c6c8c15cd31ecbd6c284e9bf62c6927dcd4` | `SOCCER.GPF` | `edba577c288e12a32fc967e5de76ea7c79917b90068a150fc30243ef7e868fd4` |
| pingpong | `PINGPONG.ROM` | `3F200491` | `8e0f57b2c52e85505505c1d4bb4643eb7311213676f0ecfe21dd06571fc0bbd5` | `PINGPONG.GPF` | `86c27bc629fbefebf4f2b474db82b7ea2196bafe8136579f07784864f6117bf8` |
| yiear | `KUNGFU.ROM` | `8A12EC4F` | `644c78c7d20bb30802888b513b384cf0ce4f9d8b6fd490f30e6211ac92274848` | `YIEAR.GPF` | `98fb924e2cb4bde2fb550c7ee2b50d68d396bac7ef4d37f51d5f6c10cb714dd7` |
| salamand | `SALAMAND.ROM` | `C36F559D` | `edbbba820ac67d6a55b9dc5da9309e45979936d5620c07d09793efaf077e86b9` | `SALAMAND.GPF` | `ff63ffc488093036e7699ec6ca87cb2706095a1e12028ddfd26792fdc86ef7e2` |
| 1942 | `1942.ROM` | `C99E5601` | `d8442d2c08958f0bc9be7d2078e3cf07224e1ec3493ddce3215ed8df2bd37b1f` | `1942.GPF` | `e26d8db77eb391cbfc9e98de27b6758d1f6e4bcf7a343196d928182482914686` |

> **Importante - quais ROMs são suportadas.** Só são suportadas as ROMs baixadas do MSX Archive:
> <https://www.msxarchive.nl/pub/msx/games/roms/msx1/> e <https://www.msxarchive.nl/pub/msx/games/roms/msx2/>.
> Quando o mesmo jogo existe nos dois lugares (por exemplo `1942.LZH`), **use o da pasta `msx2`**.
> Descompacte o download em um PC e copie o arquivo da ROM, com o nome da tabela acima, para o MSX. Uma ROM de outra origem pode
> ser outro dump, e o jogo se recusará a iniciar.

Os dois jogadores devem usar o **mesmo arquivo `.GPF`**. Se o jogo avisar que o outro jogador tem outra versão, copie o mesmo arquivo para os dois.

> **Quem tem MSXPi:** execute o atualizador `msxpiupd`. Ele já grava no disco o `MCHAT.COM`, `PLAYNET.COM`, `PLAYNET.OVL`,
> `INL.CFG` e os arquivos `.GPF`. Você só acrescenta suas ROMs, o `MSR.COM` e o `INL.COM`.

## Passo 2A - Placa Ethernet: ligue a rede (precisa do INL)

Faça isso **toda vez que ligar o MSX**. Digite as duas linhas do seu sistema:

| MSX-DOS 1 | Nextor ou MSX-DOS 2 |
|---|---|
| `MSR I` | `RAMHELPR I` |
| `INL I` | `INL I` |

Observações:
- Com **MSXPi**, nunca digite `RAMHELPR I` no MSX-DOS 1. Ele estraga o `MSR`.
- O `INL.CFG` guarda os endereços da rede. O que acompanha é para o MSXPi. Em outra rede, edite-o (ou apague-o para usar endereços
  automáticos por DHCP).
- Com uma placa que não seja o MSXPi, instale antes o driver da própria placa e depois as duas linhas acima.

Para conferir: digite `INL S` (mostra o seu endereço). Se tiver o `HOST.COM`, `HOST msx.org` deve mostrar um endereço.

## Passo 2B - GR8NET / DenYoNet: nada a instalar

A placa já tem o TCP/IP dela. Configure a rede com as ferramentas da própria placa (veja o manual) e confirme que está online.

O jogo também precisa de um **mapeador de memória** (RAM extra que o MSX consegue trocar):
- MSX2 ou posterior: normalmente você já tem. No MSX-DOS 1, digite `MSR I`.
- MSX1 com GR8NET: o GR8NET pode fornecer o mapeador (`CALL NETSETMAP(8,M)` no BASIC, veja o manual dele); depois digite `MSR I`.
  *Isto ainda não foi testado.*
- MSX1 com DenYoNet e sem mapeador: não joga. Acrescente um cartucho mapeador.

Nada mais deve estar usando as conexões de rede da placa enquanto você joga.

## Passo 3 - Deixe o outro jogador alcançar você

- **Mesma casa ou rede, ou uma VPN:** não precisa fazer nada.
- **Pela Internet:** você precisa fazer duas coisas, e o outro jogador também:
  1. No roteador, **encaminhe a porta UDP 5000 para o seu MSX**.
  2. Crie um arquivo `MCHAT.INI` (Passo 4) com a sua porta e o seu endereço IP público:
     ```
     GAMEPORT=5000
     GAMEADDR=203.0.113.25
     ```
     (Troque `203.0.113.25` pelo seu IP público. Pesquise "qual é o meu IP" em um PC.)

Algumas conexões não servem (dados móveis e alguns provedores dividem um mesmo IP entre muitos clientes). Se for o seu caso, use uma VPN.

## Passo 4 - `MCHAT.INI` (opcional)

Um pequeno arquivo de texto, uma configuração por linha:

| Linha | Significado |
|---|---|
| `IRCNICK=meunome` | seu apelido |
| `GAMEPORT=5000` | a porta do jogo (o mesmo número que você encaminhou) |
| `GAMEADDR=203.0.113.25` | seu endereço IP público (necessário pela Internet) |
| `MCHATROOM=#msxpi` | a sala do chat (os dois jogadores devem estar na mesma sala) |
| `GAMELINK=1` | só para quem tem MSXPi: envia também o jogo por TCP/IP |

Você pode dispensar o arquivo quando jogar na mesma rede.

## Passo 5 - Jogue

Vá ao disco ou à pasta com seus arquivos e digite:

```
MCHAT /T MEUNOME
```

(`MEUNOME` é o seu apelido. Em uma máquina **sem** MSXPi o `/T` é opcional; **com** MSXPi ele é obrigatório.)

Depois:

| | Jogador 1 (convida) | Jogador 2 |
|---|---|---|
| 1 | `/WHO` mostra quem está na sala, `/GAMES` mostra os seus jogos | |
| 2 | `/PLAY APELIDO2 SOCCER` (APELIDO2 = o apelido do outro jogador) | o convite aparece |
| 3 | | digite `/ACCEPT` (ou `/DECLINE`) |

As telas são limpas e o jogo começa nos dois MSX em poucos segundos. **Quem convidou é o jogador 1.** Use as setas ou o joystick 1, e
ESPAÇO ou o botão.

Para **parar o jogo**, pressione **Ctrl+Shift+F5**, ou termine a partida. Você volta ao chat.

`/CANCEL` retira um convite. `ESC` sai do chat.

## Se algo der errado

| O que você vê | O que fazer |
|---|---|
| `No TCP/IP UNAPI: run INL I first` | faça o Passo 2A (ou configure sua placa, Passo 2B) |
| `Not enough memory for TCP/IP` | reinicie o MSX; em máquina com drive próprio, segure **CTRL** enquanto ela liga |
| preso em `Connecting...` | a rede está fora: teste com `INL S` / `HOST msx.org`; confira se ninguém já usa o seu apelido |
| "cannot play it (needs a memory mapper)" | esse jogador deve digitar `MSR I` (MSX-DOS 1) ou usar Nextor |
| "does not have that game" / "different version" | os dois jogadores devem ter o mesmo arquivo `.GPF` |
| ROM não encontrada ou errada | a ROM deve estar na mesma pasta, com o nome exato da tabela do Passo 1, e ser o dump correto |
| o jogo nunca conecta | os dois devem iniciar quase ao mesmo tempo; confira o encaminhamento de porta no roteador e o `MCHAT.INI`; tente uma VPN |
| o jogo trava por instantes | a conexão está lenta ou perdendo pacotes; os dois MSX esperam um ao outro |

**Salamander:** usa muita memória. Use um mapeador de **1 MB** com Nextor (512 KB bastam no MSX-DOS 1). Em máquina com drive próprio
rodando MSX-DOS 1, reinicie segurando **CTRL** ou use o Nextor. Soccer, Ping Pong e Yie Ar Kung-Fu funcionam em qualquer uma.

**1942:** o modo de dois jogadores do 1942 é por turnos: escolha **2 PLAYERS** na tela de título; cada jogador pilota na sua vez. Precisa de um mapeador de memória com pelo menos **20 segmentos livres (24 recomendados)**, então use um mapeador de 512 KB ou mais. **Situação:** o `1942.GPF` está em `software/target/games/`. Foi testado por TCP/IP só com um dos dois jogadores em um MSXPi; dois jogadores só com TCP/IP ainda não foram experimentados.

## Jogando sem o chat (avançado, opcional)

Se vocês já combinaram os endereços por telefone, pule o chat. Cada jogador digita (adapte os endereços; `H` é o jogador 1, `C` é o jogador 2):

```
Jogador 1:  PLAYNET /T SOCCER H 5000 192.168.1.60:5000
Jogador 2:  PLAYNET /T SOCCER C 5000 192.168.1.50:5000
```

O endereço depois da porta é o do **outro** jogador. Inicie os dois com poucos segundos de diferença.

## Mais informações

`documents/MSXCHAT-GAMES.md`, `software/target/games/README.md`, `software/Client/src/MCHAT.md`.
