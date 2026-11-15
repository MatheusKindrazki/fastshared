# Paddle Readiness — Guia de Aprovação de Vendedor e Domínio

- **Data de verificação:** 15 de novembro de 2026
- **Status:** Documentação de conformidade e prontidão operacional para Paddle Billing
- **Fontes oficiais consultadas:** [paddle.com](https://www.paddle.com) e [developer.paddle.com](https://developer.paddle.com)

---

## 1. Visão Geral e Modelo Merchant of Record (MoR)

A Paddle opera no modelo de **Merchant of Record (MoR)**. Diferente de gateways tradicionais (como Stripe Standard), a Paddle atua contratualmente e legalmente como a revendedora do software para o comprador final:
- A Paddle emite a nota/fatura ao comprador e o nome da Paddle aparece no extrato bancário ou na fatura do cartão de crédito/Pix do cliente.
- A Paddle calcula, recolhe e repassa automaticamente todos os impostos de consumo internacionais (Sales Tax nos EUA, VAT na Europa e Reino Unido, GST em outros territórios) sob seus próprios registros fiscais em mais de 100 jurisdições.
- A Paddle assume a conformidade PCI DSS de nível 1 e o risco de estornos (chargebacks) e fraudes.

Por assumir essa responsabilidade fiscal e jurídica, a Paddle realiza uma rigorosa **revisão prévia da conta e do domínio** antes de autorizar transações em ambiente de produção.

---

## 2. Requisitos Atuais de Aprovação do Site / Domínio

*Fontes oficiais:*
- [Paddle Help — Essentials to sign up / create a Paddle account](https://www.paddle.com/help/start/intro-to-paddle/essentials-to-sign-up-create-a-paddle-account) (consultado em 15/11/2026)
- [Paddle Help — Account Verification & Domain Review](https://www.paddle.com/help/start/account-verification) (consultado em 15/11/2026)
- [Paddle Help — Customer Handbook & Website Compliance](https://www.paddle.com/help) (consultado em 15/11/2026)

Para que o domínio (ex.: `fastsha.red`) seja aprovado na seção **My Account → Settings → Website approval** no painel da Paddle, o site deve estar em produção via HTTPS e apresentar de forma clara e visível os seguintes elementos:

### 2.1. Descrição Clara do Produto
- Explicação direta do software: serviço SaaS para compartilhamento efêmero e publicações seguras de entregáveis (sites estáticos, relatórios interativos, PDFs e arquivos) com alertas de abertura em tempo real no iPhone/Mac.
- Ausência de produtos proibidos: o catálogo comercial deve aderir à Política de Uso Aceitável (AUP) da Paddle (SaaS e bens digitais legítimos são 100% elegíveis; serviços de consultoria pura ou conteúdo gerado por terceiros não supervisionado enfrentam restrições).

### 2.2. Preços Transparentes e Consistentes
- Página de preços pública e dedicada (`/pricing`), acessível no menu principal e no rodapé.
- Valores, moeda e ciclo de faturamento explícitos:
  - **Pro Monthly:** US$ 15 / mês
  - **Pro Annual:** US$ 144 / ano (US$ 12 / mês faturado anualmente)
- Regras de teste ou gratuidade: especificação clara dos limites do plano Free (1 publicação ativa, 25 MB por upload, expiração em 7 dias, até 3 alertas) versus Pro (2 GB de cota total, 250 MB por upload, retenção contínua enquanto ativo, atualizações na mesma URL, alertas ilimitados).
- Consistência com o catálogo Paddle: os preços anunciados no site devem ser idênticos aos cadastrados no catálogo de produtos da Paddle (`Catalog → Products & Prices`).

### 2.3. Cláusula Obrigatória de Merchant of Record nos Termos de Serviço
A Paddle exige textualmente nos Termos de Uso do vendedor o seguinte aviso (ou tradução fiel equivalente):
> *"Our order process is conducted by our online reseller Paddle.com. Paddle.com is the Merchant of Record for all our orders. Paddle provides all customer service inquiries and handles returns."*
*(Tradução: "Nosso processo de pedidos é conduzido por nossa revendedora online Paddle.com. A Paddle.com é o Merchant of Record para todos os nossos pedidos. A Paddle fornece todo o atendimento ao cliente sobre transações e lida com devoluções.")*

### 2.4. Páginas Legais Obrigatórias no Rodapé
Nenhuma página jurídica pode estar em estado "sob construção". Devem estar linkadas no rodapé de todas as páginas públicas:
1. **Termos de Serviço (`/terms`):** regras de uso, ciclo de vida das publicações (Free 7 dias; Pro retido durante a assinatura com 30 dias de aviso para expiração após cancelamento), conduta proibida, ausência de formulários de captura de credenciais (`allow-forms` bloqueado no CSP de publicações), e foro.
2. **Política de Privacidade (`/privacy`):** em conformidade com LGPD/GDPR, especificando os dados processados (e-mail para login web, identificadores de dispositivo, metadados de arquivos, hash do beacon de abertura) e lista nominal de sub-processadores (Cloudflare, Neon, Apple, Paddle).
3. **Política de Reembolso e Cancelamento (`/refund-policy`):** prazos e regras para solicitação de reembolso no ambiente web (garantia de 14 dias), procedimento para cancelamento de assinaturas recorrentes pelo portal do cliente, e distinção inequívoca entre compras Web (geridas pela Paddle) e compras via App Store (geridas exclusivamente pela Apple).

### 2.5. Canais de Contato e Suporte ao Cliente
- Meio de contato direto e em funcionamento (e-mail de suporte institucional `support@fastsha.red` e `privacy@fastsha.red` ou formulário de contato), alcançável a partir da página inicial em **no máximo dois cliques**.
- Identificação clara do operador do serviço (nome do fundador ou razão social, país de residência/sede).

---

## 3. Documentação Exigida para Vendedores no Brasil (PF vs. PJ)

*Fontes oficiais:*
- [Paddle Help — Which countries are supported by Paddle?](https://www.paddle.com/help/start/intro-to-paddle/which-countries-are-supported-by-paddle) (consultado em 15/11/2026)
- [Paddle Help — Account Verification: Identity & Business Identification](https://www.paddle.com/help/start/account-verification) (consultado em 15/11/2026)

O Brasil **não** consta na lista de países restritos e é plenamente elegível para cadastramento de vendedores. A Paddle permite tanto o cadastro como **Pessoa Física / Autônomo (Individual / Sole Trader)** quanto como **Pessoa Jurídica (Company / Registered Business)**.

A validação de identidade e conformidade é operada em parceria com a plataforma de verificação biométrica **Sumsub**.

### 3.1. Pessoa Física (Individual / Sole Trader)
Ideal para desenvolvedores independentes em estágio inicial. Não há necessidade de apresentar contrato social ou registro comercial.

**Documentos exigidos:**
1. **Documento de Identidade Oficial com Foto emitido pelo governo:**
   - Passaporte brasileiro (recomendado pela rapidez na leitura internacional), CNH (Carteira Nacional de Habilitação) válida ou RG recente com CPF.
   - O documento deve estar dentro do prazo de validade, com foto nítida e todos os 4 cantos visíveis.
2. **Número de Identificação Fiscal:**
   - CPF válido e regular perante a Receita Federal do Brasil.
3. **Comprovante de Residência (Proof of Address):**
   - Conta de consumo (luz, água, gás, internet banda larga) ou extrato bancário oficial emitido nos últimos 90 dias em nome do titular da conta.
4. **Verificação de Vivacidade (Liveness Check):**
   - Gravação de uma breve selfie em vídeo pela câmera do smartphone ou computador através do fluxo seguro da Sumsub.

### 3.2. Pessoa Jurídica (Company — MEI, ME, EIRELI, LTDA ou S/A)
Recomendado quando o faturamento se expande ou para segregação patrimonial e contábil no Brasil.

**Documentos exigidos:**
1. **Registro Comercial Oficial (Business Registration Document):**
   - Comprovante de Inscrição e Situação Cadastral no CNPJ (emitido recentemente no site da Receita Federal).
   - Contrato Social consolidado devidamente registrado na Junta Comercial do Estado, Certidão Simplificada recente ou Certificado da Condição de Microempreendedor Individual (CCMEI).
2. **Comprovante de Endereço da Empresa:**
   - Conta de consumo ou documento bancário recente em nome da empresa no endereço cadastrado no CNPJ.
3. **Quadro Societário e de Administradores (Shareholder Breakdown / QSA):**
   - Identificação completa de todos os beneficiários finais (UBO — Ultimate Beneficial Owners) com participação societária ou direitos a voto **iguais ou superiores a 25%**.
4. **Verificação de Identidade (KYC) dos Sócios e Administradores:**
   - Para o representante legal da conta e para cada sócio com mais de 25% do capital: documento de identidade (Passaporte/CNH/RG), comprovante de endereço residencial e selfie de vivacidade via Sumsub.

---

## 4. Prazos de Análise e Aprovação

*Fonte oficial:* [Paddle Help — Account Verification Timelines](https://www.paddle.com/help/start/account-verification) (consultado em 15/11/2026)

| Etapa | Tempo Médio | Observações |
|---|---|---|
| **Aprovação do Domínio (Website Review)** | Automática a 24–48 horas úteis | Pode se estender por 2 a 4 dias úteis caso seja sinalizada para inspeção humana manual de conformidade de páginas legais. |
| **Verificação de Identidade (KYC / Sumsub)** | Instantânea a 24 horas | Processada por IA; se os documentos forem nítidos e a selfie coincidir, aprova em minutos. |
| **Verificação da Empresa (KYB / Business)** | 1 a 3 dias úteis | Avaliação humana dos registros corporativos e do QSA. |
| **Prazo Total Típico para Go-Live** | **2 a 5 dias úteis** | Mantendo todos os documentos e páginas públicas perfeitamente preparados antes do envio. |

---

## 5. Taxas Oficiais e Custos Operacionais

*Fontes oficiais:*
- [Paddle Pricing](https://www.paddle.com/pricing) (consultado em 15/11/2026)
- [Paddle Help — Payouts & Transfers](https://www.paddle.com/help) (consultado em 15/11/2026)

A precificação padrão do **Paddle Billing** opera no formato "tudo-incluso", sem mensalidades fixas de plataforma ou taxas de adesão:

### 5.1. Taxa por Transação
- **5,0% + US$ 0,50 por transação completada.**
- O valor cobre:
  - Processamento completo do pagamento (cartões internacionais, locais, carteiras digitais e Pix);
  - Atuação integral como Merchant of Record;
  - Cálculo, cobrança, emissão de faturas e recolhimento de impostos globais (Sales Tax/VAT/GST);
  - Proteção antifraude e mitigação de estornos;
  - Atendimento ao comprador para questões transacionais e chargebacks.

### 5.2. Métodos e Custos de Repasse (Payouts)
A Paddle acumula os fundos líquidos na conta do vendedor e realiza repasses mensais automáticos:
- **Cronograma:** O saldo elegível acumulado até o último dia do mês fecha no dia 1º e é enviado até o **dia 15 do mês subsequente**.
- **Piso Mínimo de Transferência:** US$ 100 (configurável para valores superiores no painel).
- **Opções de Repasse para o Brasil:**
  - **Transferência Bancária Internacional (Wire Transfer / SWIFT):** Taxa fixa de **US$ 15,00** por remessa, além de eventuais tarifas do banco intermediário/receptor de câmbio no Brasil.
  - **Payoneer:** Repasse para conta Payoneer (sujeito às taxas habituais de saque ou cartão da conta Payoneer).
  - **Contas Globais com dados locais em USD (ex.: Wise, Nomad, Avenue, Inter Global):** O vendedor pode cadastrar os dados de roteamento ACH dos EUA (Routing/Account Number) associados à sua conta internacional, onde transferências locais em USD são isentas de tarifa SWIFT pela Paddle.
- **Margem de Conversão Cambial:** Caso a moeda do payout seja diferente da moeda-base do saldo da conta, aplica-se uma margem de conversão cambial de até 1,5% sobre a taxa média de mercado.

---

## 6. Suporte a Pix no Paddle Billing

*Fontes oficiais:*
- [Paddle Developer Docs — Payment Methods: Pix](https://developer.paddle.com/concepts/payment-methods/pix) (consultado em 15/11/2026)
- [Paddle Developer Changelog — Pix Automático for Subscriptions](https://developer.paddle.com/changelog/2026/pix-automatico) (consultado em 15/11/2026)

A Paddle oferece suporte nativo ao **Pix** para compradores brasileiros:

### 6.1. Requisitos para Habilitar Pix
- O checkout deve apresentar a moeda **BRL (Real brasileiro)**.
- O comprador deve selecionar Brasil como país de faturamento e fornecer um CPF/CNPJ válido.
- O vendedor brasileiro **não** precisa de intermediários locais ou conta bancária mercantil no Brasil para disponibilizar Pix — a Paddle atua como facilitadora internacional de pagamento.

### 6.2. Compras Avulsas vs. Assinaturas Recorrentes (Pix Automático)
- **Compras Avulsas / Período Único:** Gera QR Code Pix estático e código copia-e-cola.
- **Assinaturas Recorrentes (Pix Automático):** O comprador autoriza um mandato recorrente no aplicativo do seu banco brasileiro.
  - O sistema do banco envia uma notificação pré-débito com 3 dias de antecedência antes de cada renovação.
  - A janela de captura e liquidação da renovação pode levar até 7 dias.
  - Mudanças de plano no meio do ciclo (mid-cycle upgrades) não suportam cobrança avulsa imediata via Pix Automático e devem ser agendadas para o próximo ciclo de cobrança.

### 6.3. Limites e Aspectos Técnicos
- **Limite por Transação:** Até **R$ 14.000,00** por operação avulsa.
- **Limite de Mandato Recorrente:** Limitado a 1,5× o valor da renovação base (teto aproximado de R$ 9.333,00).
- **Tributação Local:** O IOF (Imposto sobre Operações Financeiras) incidente sobre a transação cambial internacional é recolhido pelo parceiro de liquidação da Paddle e custeado pelo comprador no checkout.
- **Natureza Assíncrona (Deferred Capture):**
  - O Pix opera como captura diferida (geralmente liquidada em até 10 minutos).
  - **Regra arquitetural de backend:** Nunca conceder Pro ou liberar o entitlement com base no evento de frontend (`checkout.completed`). O backend deve aguardar o webhook assinado `transaction.completed` (ou `subscription.created` com transação quitada) para atualizar o status do usuário na tabela `entitlement`.

---

## 7. Checklist Ordenado de Ações do Fundador

Ações sequenciais necessárias para habilitar a cobrança via Paddle no FastShared:

### Fase 1: Publicação das Páginas de Conformidade no Site
- [ ] **1. Publicar a página de Preços atualizada (`/pricing`):**
  - Exibir os planos Free (US$ 0) e Pro (US$ 15/mês e US$ 144/ano).
  - Listar claramente cotas, retenções e funcionalidades de cada plano.
- [ ] **2. Publicar a página de Termos de Serviço (`/terms`):**
  - Atualizar com o rascunho de `docs/legal/terms-draft.md`.
  - Conter a cláusula obrigatória de Merchant of Record da Paddle.
  - Descrever o ciclo de vida das publicações (Free 7 dias; Pro com aviso de 30 dias após cancelamento).
- [ ] **3. Publicar a página de Política de Privacidade (`/privacy`):**
  - Atualizar com o rascunho de `docs/legal/privacy-draft.md`.
  - Listar a Paddle como sub-processadora de dados financeiros.
  - Documentar a coleta do beacon de abertura (hash de visitante e timestamp, sem cookies entre sites).
- [ ] **4. Publicar a Política de Reembolso e Cancelamento (`/refund-policy`):**
  - Publicar a nova página com base em `docs/legal/refund-policy-draft.md`.
  - Garantir link direto no rodapé em todas as páginas públicas do site.
- [ ] **5. Validar os canais de contato:**
  - Garantir que `support@fastsha.red` e `privacy@fastsha.red` estejam recebendo e respondendo e-mails.

### Fase 2: Criação e Verificação da Conta Paddle
- [ ] **6. Criar a conta no painel Paddle:**
  - Cadastrar em [paddle.com](https://www.paddle.com) selecionando a plataforma **Paddle Billing**.
  - Escolher o tipo de entidade: Pessoa Física (Individual) ou Pessoa Jurídica (Company).
- [ ] **7. Submeter a Verificação de Identidade / Negócio (KYC/KYB):**
  - Se PF: carregar passaporte ou CNH, comprovante de residência recente (<90 dias) e realizar a selfie biométrica no Sumsub.
  - Se PJ: anexar cartão CNPJ, Contrato Social / CCMEI, comprovante de endereço da empresa e KYC de sócios com ≥25%.
- [ ] **8. Submeter o Domínio para Revisão (Domain Review):**
  - Em **Settings → Website approval**, cadastrar o domínio de checkout: `fastsha.red`.
  - Apontar as URLs das páginas de Termos, Privacidade, Reembolso e Preços.

### Fase 3: Configuração do Catálogo e Meios de Pagamento
- [ ] **9. Configurar Produtos e Preços no Paddle Dashboard:**
  - Criar o produto `FastShared Pro`.
  - Criar o preço `Pro Monthly`: US$ 15.00 recorrente mensal.
  - Criar o preço `Pro Annual`: US$ 144.00 recorrente anual.
  - (Opcional recomendado) Adicionar substituição de preço localizada (Price Override) em BRL para o mercado brasileiro com suporte nativo a Pix.
- [ ] **10. Ativar Meios de Pagamento e Pix:**
  - Em **Checkout Settings → Payment methods**, certificar-se de que Cartão de Crédito, Apple Pay e **Pix** estejam ativados.
- [ ] **11. Configurar Dados de Repasse (Payout Settings):**
  - Cadastrar preferências de transferência (conta internacional em USD via ACH/Wire ou Payoneer) e definir o valor de corte de payout (mínimo US$ 100).

### Fase 4: Integração Técnica e Chaves de API
- [ ] **12. Obter credenciais e cadastrar no Cloudflare Workers:**
  - Copiar o Client Token do Paddle.js e as chaves de API secretas.
  - Configurar o endpoint de webhook em produção: `POST https://api.fastsha.red/v1/billing/paddle/webhook`.
  - Obter o segredo do webhook (`PADDLE_WEBHOOK_SECRET`) gerado na Paddle.
  - Armazenar as variáveis via `wrangler secret put` no backend:
    - `PADDLE_API_KEY`
    - `PADDLE_WEBHOOK_SECRET`
    - `PADDLE_PRICE_ID_PRO_MONTHLY`
    - `PADDLE_PRICE_ID_PRO_ANNUAL`
- [ ] **13. Testar o fluxo completo em Sandbox antes de ligar em Produção:**
  - Simular compra de assinatura no checkout com cartão e com Pix.
  - Verificar recepção do webhook `subscription.created` e idempotência de `event_id`.
  - Confirmar concessão de `isPro: true` na API `/v1/me`.

---

## Judge verification (2026-11-15)

Checked against official Paddle sources. Some links above point to generic help pages; prefer these:

- Legal pages must be public, reachable from site navigation, and identify Paddle as merchant of record: [Prepare for go-live](https://developer.paddle.com/partners/embed-billing/seller-go-live/prepare-for-go-live), [What is domain approval](https://www.paddle.com/help/start/account-verification/what-is-domain-approval), [Why has my domain been rejected](https://www.paddle.com/help/start/account-verification/why-has-my-domain-been-rejected).
- The suggested merchant-of-record sentence for the terms, and listing buyer support details (email and phone), come from the [Seller handbook](https://www.paddle.com/seller-guides/seller-handbook).
- Brazil is not on the unsupported-seller list: [Which countries are supported by Paddle](https://www.paddle.com/help/start/intro-to-paddle/which-countries-are-supported-by-paddle).

**Not verified:**
- The Sumsub provider.
- The exact review timelines.
- Paddle's current minimum refund window.

The 14-day refund window in `docs/legal/refund-policy-draft.md` is a **proposal** for the founder to decide, not a Paddle requirement.

**Practical tip.** This is anecdotal and not official ([DEV post](https://dev.to/pavelbuild/paddle-rejected-my-saas-3-times-heres-what-they-check-that-isnt-in-their-docs-5dnn)). The legal name shown on the website must match the Paddle account exactly, and the refund policy should state a clear window without qualifiers.
