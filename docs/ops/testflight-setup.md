# TestFlight · first-time setup

Gets FastShared to a point where `make testflight` from the repo root archives
the iOS app and uploads it to TestFlight → Internal Testing. Amigos adicionados
no dashboard ficam com a build em ~10 min (review Apple é só na primeira submissão
para External Testing, Internal não tem review).

## 1 · No Apple Developer Portal (≈ 30s)

Abra https://developer.apple.com/account/resources/identifiers e **confirme** que
existem os três App IDs listados abaixo. Se Xcode Automatic Signing já rodou em
algum build, eles foram criados automaticamente — normalmente já está tudo OK:

| Bundle ID | Capabilities |
|---|---|
| `dev.kindrazki.fastshared` | App Groups, Keychain Sharing, Associated Domains (futuro) |
| `dev.kindrazki.fastshared.ShareExt` | App Groups |
| `dev.kindrazki.fastshared.LiveActivity` | App Groups |

App Group a ser associado nos três: `group.dev.kindrazki.fastshared`.

## 2 · No App Store Connect — criar o app (≈ 2 min, só uma vez)

https://appstoreconnect.apple.com/apps → **+** → **New App**

| Campo | Valor |
|---|---|
| Platforms | iOS (macOS opcional, pode marcar depois) |
| Name | **FastShared** (pode mudar a qualquer momento antes de submit pra App Store) |
| Primary language | Portuguese (Brazil) |
| Bundle ID | `dev.kindrazki.fastshared` |
| SKU | `fastshared-ios-001` (qualquer string única para a sua conta) |
| User Access | Full Access |

Depois de criado, o app aparece em **Apps**. Clique nele, vá em **TestFlight**
→ seção "Test Information" → preencha:

- **Beta App Description** (tudo público, visível pros testers): `Share anything. Get a temporary link. Vanishes on schedule.`
- **Email** + **Privacy Policy URL**: `https://fastsha.red/privacy`
- **Marketing URL** (opcional): `https://fastsha.red`
- **Export Compliance**: na sua primeira build, o TestFlight vai te perguntar se
  usa criptografia não-isenta. FastShared só usa HTTPS via iOS/URLSession, o que
  **é isento** pela Apple — pode responder "Yes, but only standard encryption"
  ou marcar a declaração de isenção (ECCN 5D002 exemption).

## 3 · Gerar a App Store Connect API Key (≈ 30s, só uma vez)

https://appstoreconnect.apple.com → **Users and Access** → **Integrations** →
**App Store Connect API** → **Generate API Key**

| Campo | Valor |
|---|---|
| Name | `FastShared CI` |
| Access | **App Manager** (suficiente pra pilot/upload; "Developer" também serve) |

Clique em **Generate**. Apple vai te deixar baixar o arquivo `.p8` **uma única
vez** — salve em `~/.config/fastshared/AuthKey_XXXXXXXXXX.p8` (ou outro caminho
fora do repo). Anote também:

- **Key ID** (10 caracteres, exibido na linha da key)
- **Issuer ID** (UUID no topo da mesma página)

## 4 · Popular o `.env.testflight` local

```bash
cp apple/.env.testflight.example apple/.env.testflight
$EDITOR apple/.env.testflight
```

Preencha com os valores dos passos anteriores. O arquivo está gitignored —
não vai parar em commit nenhum.

## 5 · Instalar fastlane uma vez

```bash
make testflight-bootstrap
```

Isso instala `fastlane ~> 2.226` via Bundler dentro de `apple/vendor/bundle/`
(também gitignored). Reutilize em cada push.

## 6 · Smoke test

```bash
make testflight-doctor
```

Deve imprimir "App Store Connect API key loaded: XXXXXXXXXX" e regenerar o
Xcode project. Se reclamar de chave / path, revise o `.env.testflight`.

## 7 · Primeira build

```bash
make testflight
```

O que acontece:
1. `xcodegen generate` regenera o projeto a partir de `apple/project.yml`.
2. `increment_build_number` carimba o `CURRENT_PROJECT_VERSION` com um timestamp
   monotônico (epoch seconds desde 2020) — Apple só aceita builds com build
   numbers crescentes.
3. `build_app` arquiva o scheme `FastSharedApp` em Release, exporta com
   `ExportOptions.plist` (app-store-connect, team `YFYB6NKC73`, automatic signing).
4. `upload_to_testflight` envia o IPA para App Store Connect. **Não submete** pra
   review externa — fica apenas disponível pra Internal Testing.

Primeira execução demora 6–10 min (archive completo + upload). A partir daí, o
App Store Connect processa o binário por mais uns 5–8 min e a build aparece no
TestFlight.

## 8 · Adicionar amigos como Internal Testers

App Store Connect → FastShared → TestFlight → **Internal Testing** → **+** no
grupo (ou crie um grupo novo "Friends"). Adicione cada um por e-mail Apple ID.
Eles recebem convite pelo TestFlight app no iPhone e instalam em 2 cliques.

Até **100 usuários internos**, sem review Apple, build disponível a cada push
assim que processar.

## 9 · (Opcional) External Testing

Se quiser links públicos pra convidar mais gente:

App Store Connect → TestFlight → **External Testing** → cria um grupo → adiciona
a build → **Submit for Review**. Beta review leva 24–48h na primeira vez, ~4h
nas próximas. Depois de aprovada, cada build nova precisa só de ≈15 min de review
"shallow" se a Apple julgar que não mudou o suficiente pra re-review full.

## CI · GitHub Actions (futuro)

Quando quiser automatizar, publica um secret com o conteúdo do `.p8` em base64:

```bash
base64 -i ~/.config/fastshared/AuthKey_XXXXXXXXXX.p8 | pbcopy
```

Cole em `APPSTORE_CONNECT_API_KEY_B64` nos secrets do repo, junto com `KEY_ID`
e `ISSUER_ID`. Um workflow em `.github/workflows/testflight.yml` pode decodar
pra `$RUNNER_TEMP/AuthKey.p8`, exportar as envs, e invocar `make testflight`.
Fica pra um follow-up quando o push manual já não for suficiente.

## Troubleshooting

- **`No signing certificate "iOS Distribution" found`**: o signing está automatic
  mas a primeira distribution cert ainda não existe. Abra Xcode → FastSharedApp
  → Signing & Capabilities → clique em "Try Again" (ou selecione "Any iOS
  Device" no destination e faça um Archive pelo Xcode — ele cria o cert na hora).
- **`You are not authorized to upload this package`**: o `APPSTORE_CONNECT_API_KEY_ISSUER_ID`
  está errado, ou a API key não tem role suficiente. Generate novamente com
  "App Manager".
- **`The bundle version must be higher than the previously uploaded version`**:
  o `increment_build_number` não foi persistido. Commite o `project.pbxproj`
  regerado OU deixe o Fastfile sobrescrever o valor via timestamp (já faz isso
  por default).
- **"Missing Privacy Manifest" at upload**: o `PrivacyInfo.xcprivacy` já está em
  `apple/FastSharedApp/` e é incluído no target via project.yml. Se sumir, o
  upload falha com ITMS-91061.
