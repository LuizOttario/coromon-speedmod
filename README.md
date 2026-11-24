# Coromon Speed Mod

Mod não oficial para **Coromon** (PC, Steam) que acelera o jogo e mostra um guia na tela
para fechar a história e a platina. Feito e testado no Linux (Steam/Proton), jogando em pt-BR.

*Unofficial Coromon mod: game speed control (up to 100x), on-screen step-by-step guide
for story and achievements, battle assistant and quiz answers. Texts are in Brazilian Portuguese.*

## O que ele faz

- **Velocidade do jogo:** 1x, 2x, 5x, 10x, 20x e 100x. Menus e textos continuam em velocidade normal.
- **Passo a passo na tela (esquerda):** o que fazer na história, as missões da cidade atual e,
  depois dos créditos, as conquistas que faltam para a platina.
- **Assistente (direita):** em batalha mostra tipo, vida, perigo, chance de captura e o melhor golpe;
  em perguntas de quiz mostra a resposta.
- **Abas MISSOES e ROTA:** lista de todas as conquistas com dicas, e uma rota de capturas por mapa.
- **Páscoa e Natal:** liga os eventos pelo menu para pegar as orelhas de coelho (Hayville) e a
  roupa de Papai Noel (Lux Solis) sem esperar a data.
- **Correções:** evita os fechamentos do jogo nos avisos de conquista/skin e nos créditos quando acelerado.

## Instalar

Precisa de **Python 3** e do **luac5.1** (pacote `lua51` no Arch/CachyOS, `lua5.1` no Debian/Ubuntu).

Com o jogo **fechado**:

```bash
python3 install.py
```

Para voltar o jogo ao original:

```bash
python3 install.py uninstall
```

O instalador guarda um backup do `resource.car` original ao lado dele. Se o jogo estiver em outra
pasta, use `COROMON_DIR=/caminho/para/Coromon python3 install.py`.
Faça um backup do seu save antes de usar qualquer mod.

## Teclas

| Tecla | O que faz |
|---|---|
| **Home** | abre e fecha o menu |
| **Tab** | troca de aba: VELOC, MISSOES, ROTA, ASSIST |
| **1 a 6** (aba VELOC) | escolhe a velocidade |
| **PageUp / PageDown** | rola as listas de missões e rota |
| **1 / 2** (aba ASSIST) | assistente só com informações / com dicas completas |
| **3 / 4** (aba ASSIST) | liga/desliga Páscoa e Natal (vale ao entrar num mapa) |

O mod grava um log em `Documents/speedmod.log` (pasta de dados do jogo).

## Testes

Sem o jogo, dá para rodar os testes com Lua 5.1:

```bash
(echo do; for f in speedmod.lua missions_data.lua assist_data.lua ui.lua notify.lua assist.lua hud.lua; do cat $f; echo; done; echo "ASSIST_TEST = ASSIST"; echo end) > test/modfull.lua
lua5.1 test/harness.lua test/modfull.lua
lua5.1 test/eventos_test.lua test/modfull.lua
```

`render_map.py` desenha qualquer mapa do jogo em PNG (precisa do Pillow), útil para achar lugares.
