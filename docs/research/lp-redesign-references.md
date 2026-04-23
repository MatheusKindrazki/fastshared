# Referências para Redesign da Landing Page FastShared
## Apple Premium · Anti-IA · 2026

---

## 1. O que é "Apple Premium" (o que copiar)

### Princípios fundamentais do design Apple (baseado em análise de apple.com e HIG 2025/26)

| Princípio | Como Apple faz | O que isso significa para FastShared |
|---|---|---|
| **Clareza antes de criatividade** | Uma ideia por tela. Uma mensagem por scroll. | A headline atual já é boa, mas a página tenta dizer muita coisa. Precisamos de uma narrativa linear: problema → solução → prova → ação |
| **Restrição como disciplina** | Não é minimalismo decorativo — é remoção intencional do que não serve | Remover: cartões demais, texto excessivo no hero, o "tech annotation strip" que parece specs de data center |
| **O produto é o protagonista** | A interface desaparece; o produto brilha | O PlaneArc é bonito, mas é uma ilustração. Precisamos do **app em um iPhone real** — mockup fotográfico, não vetor |
| **Uma mensagem por seção** | Cada bloco comunica exatamente uma coisa | "How It Works" tem 3 passos (bom), mas "Zero Friction Surface" tem 4 cards + ghost row (muito denso) |
| **Tipografia como hierarquia** | SF Pro com pesos extremos: Light vs Bold, grande vs pequeno | Bricolage funciona, mas precisa de mais contraste de peso. Subheads em 22px competem com body copy |
| **Espaço em branco generoso** | Padding enorme entre seções. Nada encosta em nada | A LP atual tem `pt-20 pb-20` em tudo. Apple usa ~120–160px entre seções em desktop |
| **Cinema, não slides** | Scroll revela conteúdo com parallax, fade-ins, vídeos em loop | A animação do PlaneArc é legal, mas é a única. Precisamos de scroll-driven reveals em cada seção |
| **CTAs calmos e confiantes** | "Buy" — uma palavra. Cor primária só no botão. | "Join the TestFlight →" é OK, mas o violet HOT em todo lugar dilui a hierarquia |

### O que Apple NÃO faz (e que a LP atual faz)

- ❌ Não usa gradientes de fundo em seções (Apple usa cores sólidas ou fotos/vídeos)
- ❌ Não usa cards com bordas e sombras em grid (Apple usa full-bleed ou minimal tiles)
- ❌ Não mostra specs técnicas no hero ("Signed redirect · 60s" parece datasheet, não produto)
- ❌ Não usa fonte mono para body text (Apple usa SF Pro em toda parte; mono é só para código/dados)

---

## 2. Tendências 2025/2026 relevantes

### Liquid Glass (iOS 26, WWDC 2025)
- Material translúcido que refrata o conteúdo por trás
- Usado em controles, tab bars, widgets
- **Oportunidade para FastShared**: o conceito de "transparência + efemeridade" casa perfeitamente com o produto. Podemos usar glassmorphism sutil em overlays do app mockup — mas com muita restrição, para não virar genérico

### Anti-Liquid Glass / Pro-Function (Linear, etc.)
- A reação contrária: se o vidro atrapalha legibilidade, remove
- FastShared deve ficar no meio: glass só onde transmite o conceito do produto ("desaparece, deixa passar"), nunca em texto

### Bento Grids
- Layout em tiles inspirado no macOS/iOS widgets
- Apple usa extensivamente nas páginas de feature (AirPods, iPhone)
- **Oportunidade**: reorganizar "Zero Friction Surface" como bento grid de 2×2 ou 1+2+1

### Raw Aesthetics / Brutalismo Amigável
- Monospace, grids visíveis, wireframe logic
- NÃO se aplica diretamente ao FastShared (produto consumer, não B2B fintech)
- Mas: a tipografia mono como "eyebrow/label" pode ser mantida — é um toque de personalidade que diferencia

---

## 3. Referências específicas para estudar

### Tier 1 — Apple Product Pages (estudo obrigatório)
1. **apple.com/iphone** — como Apple conta uma história em 10+ seções de scroll
2. **apple.com/airpods** — parallax, vídeos em loop, transições suaves
3. **apple.com/ios** — como apresentar features em grid sem parecer cartões de bootstrap

### Tier 2 — Apps que "cheiram Apple"
4. **linear.app** — o estado da arte em landing page premium 2025. Observe: hero com produto em contexto real, dark mode como padrão, animações de scroll, zero cards genéricos
5. **raycast.com** — launcher Mac. Página super minimal, produto em destaque, screenshot real
6. **arc.net** — navegador. storytelling por seção, cada uma com uma imagem/mockup que ocupa 60%+ da tela
7. **notion.so** — antes de virar AI slop, a landing page era um exemplo de clareza

### Tier 3 — App Landing Pages iOS
8. **timeful.com** (ou buscar no archive) — app de calendário. Hero com iPhone mockup
9. **instapaper.com** — minimalismo absoluto, foco total no produto
10. **mailbox** (histórico) — clean, simples, confiante

---

## 4. Diagnóstico: Por que a LP atual "cheira IA"

| Elemento | Por que parece IA | O que fazer |
|---|---|---|
| **Hero split (texto + ilustração)** | Todo template de IA SaaS usa essa estrutura: texto à esquerda, gráfico gradiente à direita | Substituir por: **texto centralizado + mockup de iPhone abaixo**, ou **full-bleed vídeo/imagens do app** |
| **Cards com borda sutil + sombra** | O padrão Tailwind card mais genérico existe | Substituir por: **full-width sections alternando fundo**, ou **bento grid sem bordas** |
| **Gradiente violet/rosa no fundo do PlaneArc** | Glows coloridos são marca registrada de IA slop (Copilot, Jasper, etc.) | Remover. O PlaneArc deve flutuar em fundo transparente ou solid cream |
| **Fonte mono para body text** | Muitas landing pages de IA usam mono para parecer "técnica/hacker" | Manter mono para **labels, eyebrows, captions** (identidade), mas usar **sans-serif para body** (legibilidade) |
| **"Technical facts" no hero** | "Signed redirect · 60s" — specs técnicas no hero é coisa de infra/dev tool | Mover para uma seção de "Security" no footer, ou transformar em badges visuais minimalistas |
| **Números grandes de step (01, 02, 03)** | Funciona, mas comum demais. Não é problema grave | Manter, mas com mais espaço e menos bordas |
| **4 cards de feature em grid 2×2** | O padrão "feature grid" é o cartão de visitas de landing page genérica | Transformar em **bento grid** ou **seções individuais com mockups** |
| **Dynamic Island como elemento separado** | É legal, mas parece um widget solto | Integrar o Dynamic Island como parte de um **mockup de iPhone real mostrando o app em ação** |

---

## 5. Direção de redesign proposta

### Conceito: "The file that disappears"

A narrativa da página deve ser:
1. **Você compartilha algo** → hero com iPhone, mão arrastando um arquivo, link aparece
2. **O link tem uma data de validade** → a contagem regressiva visual
3. **E depois... some** → fade to nothing, a prova do conceito
4. **É assim que funciona** → 3 passos em bento
5. **É seguro** → uma linha, não uma tabela de specs
6. **Baixe** → CTA final

### Estrutura proposta (seções)

```
Nav (fixo, minimal, blur bg on scroll — alá iOS tab bar)

Hero
├── Headline centralizada, grande
├── Subhead em sans-serif, curta
├── Mockup de iPhone mostrando o app
└── CTA único: "Get FastShared" (App Store quando lançar, TestFlight agora)

How It Works (bento grid 3 tiles)
├── "Pick" → "Share" → "Forget"
├── Cada tile: ícone minimal + headline + uma linha
└── Sem bordas, sem sombras, só espaço

The Promise (full-bleed)
├── Fundo escuro (sempre dark, independente do tema — é um momento)
├── "Every link expires. Every file is deleted."
├── Contagem regressiva animada ou fade visual
└── Uma frase: "That's the product."

In Action (scroll reveal)
├── Vídeo ou loop de GIF do app sendo usado
├── Action Button → Siri → Back Tap → Clipboard
└── Mostrar, não contar

Privacy (uma linha)
├── "No accounts. No tracking. No residue."
├── Link para /privacy
└── Um ícone de cadeado ou checkmark — nada mais

FAQ (mantido, mas com mais espaço)

Footer
├── Brand lockup
├── Links: Press, Privacy, Terms, GitHub
└── Copyright minimal
```

### Paleta ajustada

| Uso | Atual | Proposto |
|---|---|---|
| Background principal | `#fbf8f1` cream | Manter — é diferenciado |
| Texto principal | `#1d1d1f` charcoal | Manter — bom contraste |
| Ação primária | `#9d7aff` violet-hot | **Manter** — é a identidade. Mas usar **somente em CTAs e highlights**, nunca em fundos |
| Secundário | `#c1a9ff` violet-soft | Reduzir uso — soft pode parecer "mágico/IA" |
| Alerta/farewell | `#ff4e7c` coral | Manter para "expires/deleted" — transmite urgência |
| Cards | `#ffffff` canvas + borda | **Remover bordas**. Usar fundo `#f5f1e6` surface-warm quando necessário, sem stroke |

### Tipografia ajustada

| Uso | Atual | Proposto |
|---|---|---|
| Display/headlines | Bricolage Grotesque Bold | **Manter** — é boa e diferenciada |
| Body text | JetBrains Mono 14px | **Mudar para Bricolage Regular 17–18px** — mono é cansativo em longos trechos |
| Labels/eyebrows | JetBrains Mono 12px uppercase | **Manter** — é o toque de identidade |
| Captions | JetBrains Mono 13px | **Manter** — funciona bem em pequenos trechos |

### Animações propostas

| Elemento | Animação |
|---|---|
| Hero headline | Fade-up + slight scale on load |
| iPhone mockup | Parallax sutil no scroll (move mais lento que o texto) |
| Bento tiles | Staggered fade-up no scroll (IntersectionObserver) |
| "Expires" section | Texto que "pulsa" suavemente, ou contagem que conta até zero |
| FAQ | Expand com spring suave (não instantâneo) |
| Nav | Background blur + border-bottom aparecem após scroll de 100px |

---

## 6. Checklist de implementação

### Fase 1 — Fundação (estrutura)
- [ ] Reescrever `Hero.astro`: texto centralizado, mockup de iPhone, remover tech strip
- [ ] Criar componente `BentoGrid.astro` para substituir cards genéricos
- [ ] Reescrever `HowItWorks.astro` como 3 tiles sem bordas
- [ ] Reescrever `EphemeralPromise.astro` como seção full-bleed dark
- [ ] Integrar `DynamicIslandMoment` dentro de um mockup de iPhone real

### Fase 2 — Refinamento (estilo)
- [ ] Ajustar tipografia: body para Bricolage, manter mono só em labels
- [ ] Remover todas as bordas de cards (`border: 1px solid var(--rule)`)
- [ ] Aumentar padding entre seções (de `pt-20 pb-20` para `py-32 md:py-48`)
- [ ] Adicionar scroll-triggered animations (fade-up, parallax)
- [ ] Nav com blur background após scroll

### Fase 3 — Delight (animações)
- [ ] Hero load animation sequenciada (eyebrow → headline → subhead → mockup → CTA)
- [ ] Parallax no iPhone mockup
- [ ] Staggered reveal no bento grid
- [ ] Dynamic Island com animação mais suave (4s interval, spring transitions)

### Fase 4 — Assets
- [ ] Criar/mockar screenshots do app em iPhone real (ou usar frame genérico + screenshot)
- [ ] OG image final
- [ ] Ícones simplificados (ou remover ícones dos cards, usar apenas tipografia)

---

## 7. O que NÃO fazer

- ❌ Não usar glassmorphism em texto (só em elementos decorativos, se usar)
- ❌ Não usar gradient text (é marca de IA)
- ❌ Não usar dark glows/blurs coloridos (é marca de IA)
- ❌ Não usar ilustrações 3D genéricas (é marca de IA)
- ❌ Não ter mais de um CTA por seção
- ❌ Não usar mais de 2 fontes
- ❌ Não ter hero split (texto esquerda + gráfico direita)
- ❌ Não usar badges/flair em excesso ("NEW", "BETA", "HOT" — um só, se necessário)
