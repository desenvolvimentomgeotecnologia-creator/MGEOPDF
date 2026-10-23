# MGEO PDF

Leitor de GeoPDF offline, com fundo Google Mapa/Satélite e GPS em tempo real.

## Como colocar no ar (gera o link)

O app precisa de um link **https** para o GPS e o modo offline funcionarem.
Opção mais fácil, grátis e sem programação:

1. Abra **app.netlify.com/drop** no computador.
2. Arraste a pasta `mgeo-pdf` inteira para a página.
3. Pronto: você recebe um link `https://...netlify.app`.

(Também funciona no GitHub Pages, Cloudflare Pages ou qualquer hospedagem https.)

## Instalar no celular

- **iPhone (Safari):** abra o link → botão Compartilhar → *Adicionar à Tela de Início*.
- **Android (Chrome):** abra o link → *Instalar app* (ou menu ⋮ → *Instalar app*).

Depois da primeira abertura, o app funciona sem internet.

## Uso

- **Mapas → Importar:** escolha um ou mais GeoPDFs. Eles ficam salvos no celular e aparecem na lista; toque para abrir.
- **⌖:** liga o GPS e segue sua posição. Arrastar o mapa pausa o seguimento; toque de novo para voltar.
- **Cartão do GPS:** mostra a precisão (±metros), coordenadas, altitude e velocidade. Toque nele para alternar entre graus decimais, GMS e UTM.
- **Camadas:** Mapa, Satélite, Híbrido ou nenhum fundo; opacidade do GeoPDF; manter tela ligada.

## Observações

- Lê GeoPDFs no padrão OGC/ISO 32000 (QGIS, ArcGIS, Global Mapper, USGS, IBGE e similares).
- O GeoPDF funciona 100% offline. O fundo do Google só aparece offline nas áreas já vistas com internet.
- Os blocos do Google são carregados direto dos servidores do Google; para uso comercial, verifique os termos de uso do Google Maps.
