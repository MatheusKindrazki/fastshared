# Pesquisa: Técnicas de Atualização Remota em Apps Mobile Nativos

> Data: 2026-04-21  
> Contexto: Avaliação de OTA (Over-The-Air) e alternativas para o FastShared iOS (SwiftUI nativo).

## TL;DR

O FastShared permanecerá **100% nativo SwiftUI**. Não incorporaremos React Native/Expo nem SDUI completo neste momento. As técnicas viáveis para iOS nativo são **Feature Flags/Remote Config** (baixa complexidade) e **Server-Driven UI** (alta complexidade, alto retorno). A Apple proíbe OTA de código compilado (Guideline 3.3.2), tornando impossível replicar o modelo Expo Updates em um app SwiftUI puro.

---

## 1. OTA (Over-The-Air) — O que o Expo faz

No ecossistema Expo/React Native, OTA updates permitem enviar novos bundles JavaScript diretamente aos dispositivos sem passar pela App Store. O app contém um bootstrap nativo mínimo que, ao iniciar, verifica se há um bundle mais novo no servidor e o substitui.

**Por que não funciona para SwiftUI nativo:**
- A Apple proíbe baixar e executar código que altere a funcionalidade do app fora da App Store Review (Guideline 3.3.2).
- O Swift é compilado para binário nativo. Não existe um "bundle interpretável" que possa ser trocado em runtime como o JavaScript do RN.

---

## 2. Server-Driven UI (SDUI) — A técnica mais comentada

SDUI é a arquitetura onde o **backend define a estrutura e o comportamento da interface** via JSON (ou GraphQL), e o app nativo atua como um renderizador que interpreta essas instruções e monta componentes nativos pré-existentes.

### Quem usa e como

| Empresa | Sistema | Destaque |
|---|---|---|
| **Airbnb** | **Ghost Platform (GP)** | Schema GraphQL unificado para web, iOS e Android. Non-engineers configuram UI sem código nativo. |
| **Uber** | **Sindarin** | Mapeia a linguagem de design "Base" para o backend via DSL em Go. Reportaram **10x de velocidade** em ~24 features. |
| **Lyft** | — | Reduz complexidade de negócio e aumenta velocity de release. |
| **DoorDash** | — | Experimentação rápida e lançamentos seguros. |
| **Netflix** | — | Fluxos de lifecycle direcionados dinamicamente. |
| **Shopify** | — | Personalização da experiência do merchant. |
| **Nubank** | **BDC** | Acelera time-to-market e dev speed no Brasil. |
| **Delivery Hero** | **Fluid** | Templates reutilizáveis com cache offline e versionamento. |
| **Faire** | — | Schema em 3 camadas: `ViewLayout` → `Section` → `Component`. |
| **PGA Tour** | — | App iOS nativo em SwiftUI com SDUI; editores respondem em tempo real a torneios. |

### Como funciona

```
┌─────────────┐      JSON schema (tipo, props, children)      ┌─────────────┐
│   Backend   │ ─────────────────────────────────────────────> │  App iOS    │
│             │                                               │  SwiftUI    │
└─────────────┘                                               └─────────────┘
                                                                       │
                                                                       ▼
                                                               ┌─────────────┐
                                                               │  Renderer   │
                                                               │  nativo que │
                                                               │  interpreta │
                                                               │  o JSON e   │
                                                               │  monta views│
                                                               │  nativas    │
                                                               └─────────────┘
```

**Regra crítica da Apple:** todos os componentes (Button, Card, Text, Carousel) devem **já existir no binário** do app. O servidor apenas decide **quais usar e como arranjá-los**. Não é permitido introduzir novos tipos de componentes via download.

### Quando faz sentido

- A interface muda com frequência (e-commerce, promoções, onboarding).
- A/B testing massivo e simultâneo.
- Consistência cross-platform (iOS, Android, web) com um único backend.

### Quando NÃO faz sentido

- O app tem poucas telas e fluxos estáveis.
- O time não tem capacidade de backend para manter o schema e o motor de renderização.
- A performance de parsing JSON em runtime é crítica (ex: animações complexas a 60fps).

---

## 3. Feature Flags / Remote Config — A técnica mais adotada

Feature Flags permitem ligar/desligar funcionalidades, alterar comportamentos e fazer A/B tests remotamente, sem novo build.

### Casos de uso

- **Kill switch:** desligar uma feature com bug instantaneamente.
- **Rollout gradual:** 1% → 5% → 25% → 100% dos usuários.
- **Segmentação:** mostrar feature só para Pro, ou só no Brasil.
- **A/B test:** comparar dois onboards diferentes.

### Ferramentas populares

| Ferramenta | Destaque | Custo |
|---|---|---|
| **Firebase Remote Config** | Integração com Firebase/Analytics, gratuito | Gratuito (até 2k params) |
| **LaunchDarkly** | Enterprise-grade, streaming realtime, audit logs | Pago (~$10/seat/mês) |
| **Statsig** | Flags + analytics + experimentação automática | Freemium (1M events) |
| **Backend custom** | Controle total, sem vendor lock-in | Custo de infra |

### Limitação

O código da feature precisa **já estar no binário**. Você só consegue ligar/desligar o que já existe. Não é possível adicionar telas ou lógicas novas via Remote Config.

---

## 4. JavaScriptCore (JSC) — Híbrido controlado

É possível embeddar um interpretador JavaScript no app iOS e usar para regras de negócio que mudam com frequência (validações, cálculos, fluxos condicionais).

**Risco:** Se o JS alterar funcionalidade significativa, a Apple pode rejeitar o app. Deve ser usado para regras/validações, não para substituir a UI inteira.

---

## 5. Comparativo

| Critério | OTA (Expo/RN) | SDUI Nativo | Feature Flags |
|---|---|---|---|
| **O que atualiza** | Código JS inteiro | Layout e arranjo de componentes | Liga/desliga features |
| **Precisa de App Store review?** | Não | Não | Não |
| **Offline?** | Sim (bundle cacheado) | Parcial (precisa do JSON) | Sim (valores default) |
| **Complexidade** | Baixa | Alta | Baixa |
| **Performance** | Pode sofrer (bridge RN) | Próxima do nativo | Nativa |
| **Permitido pela Apple** | Apenas para RN/JS | Sim (componentes no binário) | Sim |

---

## 6. Recomendação para o FastShared

Dado que o FastShared é um app SwiftUI nativo maduro, sem necessidade de mudanças diárias de interface:

1. **Manter nativo puro.** Não embeddar RN/Expo.
2. **Adotar Feature Flags** (Firebase Remote Config ou custom) quando houver necessidade de kill switches, A/B tests ou rollout gradual.
3. **SDUI só em follow-up futuro**, se surgir uma superfície muito volátil (ex: tela de promoções, onboarding de marketing) que justifique o investimento em um motor de renderização.

---

## Referências

- [Airbnb — Ghost Platform](https://medium.com/airbnb-engineering)
- [Uber — Sindarin / Base Design Language](https://www.infoq.com/presentations/sduie/)
- [Faire — Transitioning to Server-Driven UI](https://craft.faire.com/transitioning-to-server-driven-ui-a76b216ed408)
- [Mobile Native Foundation — SDUI Discussion](https://github.com/MobileNativeFoundation/discussions/discussions/47)
- [Server-Driven UI with iOS — BrightDigit](https://brightdigit.com/articles/server-driven-ui-ios)
- [Apple App Store Review Guidelines 3.3.2](https://developer.apple.com/app-store/review/guidelines/)
