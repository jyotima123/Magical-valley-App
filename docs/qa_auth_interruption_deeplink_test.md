# Roteiro de Teste QA — Interrupções no Fluxo de Auth e Deeplinks

> **Aplicativo:** mvc_app (Flutter)
> **Ambiente de referência:** QA / Development (Flavor)
> **Última atualização:** 2026-05-07
> **Autor:** Time de QA

---

## Objetivo

Este guia cobre cenários onde o usuário **interrompe** o fluxo de autenticação (fecha o app, manda pro background, recebe um deeplink) em diferentes pontos e verifica se o app retoma o estado correto — ou se inadvertidamente pula etapas obrigatórias como a verificação de conta.

Os cenários são organizados por ponto de interrupção, do mais cedo no fluxo ao mais tardio.

---

## Sumário

1. [Convenções e Setup](#1-convenções-e-setup)
2. [Ponto de interrupção: antes de escolher o método de verificação](#2-ponto-de-interrupção-antes-de-escolher-o-método-de-verificação)
3. [Ponto de interrupção: durante a verificação por Email](#3-ponto-de-interrupção-durante-a-verificação-por-email)
4. [Ponto de interrupção: durante a verificação por SMS](#4-ponto-de-interrupção-durante-a-verificação-por-sms)
5. [Deeplinks de verificação de email (link antigo / expirado / já usado)](#5-deeplinks-de-verificação-de-email-link-antigo--expirado--já-usado)
6. [Deeplinks de Esqueci a Senha](#6-deeplinks-de-esqueci-a-senha)
7. [Combinações e edge cases](#7-combinações-e-edge-cases)
8. [Checklist geral de regressão](#8-checklist-geral-de-regressão)

---

## 1. Convenções e Setup

### O que anotar em cada caso

Para cada cenário, registre:
- **Tela exibida após a interrupção** (Welcome Screen / tela de escolha de método / tela de OTP / tela principal / outra)
- **A conta foi verificada sem completar o OTP?** (sim / não)
- **Comportamento esperado vs. observado**
- **Plataforma:** iOS ou Android, versão do SO, device físico ou emulador

### Contas de teste

Use aliases Gmail para criar contas novas a cada execução completa do roteiro — evita reutilizar uma conta já verificada sem querer.

**Formato sugerido:** `seuemail+int_MMDD_XX@gmail.com` (ex.: `+int_0507_01`)

### Como "fechar o app completamente"

| Plataforma | Como fazer |
|---|---|
| iOS | Swipe up na Home Bar e swipe up no card do app para matar o processo |
| Android | Botão de apps recentes → swipe lateral no card do app |

> Importante: minimize (background) e fechar completamente são diferentes. Cada cenário especifica qual dos dois usar.

---

## 2. Ponto de interrupção: antes de escolher o método de verificação

O usuário completou o signup mas ainda está na tela "Verify Your Account" (escolha entre Email e SMS) e **não tocou em nenhuma das opções**.

---

### INT-001 — Fechar o app completamente antes de escolher o método
**Prioridade:** 🔴 Crítico
**Pré-condição:** Conta recém-criada, tela de escolha de método visível ("Verify Your Account").

**Passos:**
1. Completar o signup com email e senha.
2. Aguardar a tela de escolha de método aparecer.
3. **Não tocar em nada.** Fechar o app completamente.
4. Reabrir o app.

**Resultado esperado `[PASS]`:**
- App retorna para a **tela de escolha de método** ("Verify Your Account") — a conta ainda não está verificada e o fluxo deve continuar.
- **Não deve** ir direto para a tela principal sem verificação.
- **Não deve** ir para a Welcome Screen sem oferecer a retomada do fluxo.

**O que anotar:**
- [ ] Tela exibida ao reabrir:
- [ ] A conta estava verificada sem completar o OTP?

---

### INT-002 — Minimizar (background) o app antes de escolher o método e retornar
**Prioridade:** 🟡 Alto
**Pré-condição:** Tela de escolha de método visível.

**Passos:**
1. Com a tela de escolha de método visível, pressionar o botão Home (minimizar).
2. Aguardar 30 segundos.
3. Retornar ao app pela lista de apps recentes.

**Resultado esperado `[PASS]`:**
- App retorna exatamente para a tela de escolha de método.
- Nenhum dado de signup foi perdido.
- A tela não piscou ou navegou sozinha.

**O que anotar:**
- [ ] Tela exibida ao retornar:

---

### INT-003 — Fechar o app e reabrir via ícone com conta pendente de verificação
**Prioridade:** 🔴 Crítico
**Pré-condição:** Conta criada mas não verificada (nenhum método de verificação iniciado). App fechado.

**Passos:**
1. Realizar o signup normalmente e fechar o app na tela de escolha de método (INT-001).
2. Aguardar 5 minutos.
3. Reabrir o app tocando no ícone.

**Resultado esperado `[PASS]`:**
- App detecta que há uma conta pendente de verificação.
- Exibe a tela de escolha de método novamente ou navega diretamente para a verificação de email.
- **Não deve** exibir a tela principal como se o usuário estivesse logado e verificado.

**O que anotar:**
- [ ] Tela exibida:
- [ ] A sessão estava ativa ou o app pediu login novamente?

---

### INT-004 — Criar uma nova conta e tentar fazer login antes de verificar
**Prioridade:** 🔴 Crítico
**Pré-condição:** Conta criada mas não verificada. App fechado.

**Passos:**
1. Completar o signup mas não verificar o email.
2. Fechar o app.
3. Reabrir e ir para a tela de login.
4. Fazer login com o email e senha recém-criados.

**Resultado esperado:**
- Verificar junto com o time de dev qual é o comportamento esperado: o login é permitido antes da verificação? Ou o app redireciona para o fluxo de verificação?
- **Se o login for permitido sem verificação:** reportar como bug potencial, pois a verificação pode ser uma exigência de segurança.
- **Se redirecionar para verificação:** confirmar que a tela correta é exibida.

**O que anotar:**
- [ ] O login foi aceito sem verificação?
- [ ] Se sim, quais funcionalidades estavam disponíveis?

---

## 3. Ponto de interrupção: durante a verificação por Email

O usuário já escolheu "Verify via Email" e está na tela de OTP de email.

---

### INT-101 — Fechar o app na tela de OTP de email antes de digitar qualquer código
**Prioridade:** 🔴 Crítico
**Pré-condição:** Tela "Verify Your Email" exibida. Código OTP recebido no email mas não digitado.

**Passos:**
1. Estar na tela de OTP de email.
2. Fechar o app completamente sem digitar nada.
3. Reabrir o app.

**Resultado esperado `[PASS]`:**
- App retorna à tela de OTP de email (ou à tela de escolha de método).
- **Não deve** ir para a tela principal.
- O código OTP anterior ainda deve ser válido para uso.

**O que anotar:**
- [ ] Tela exibida ao reabrir:
- [ ] O código OTP ainda funciona depois de reabrir?

---

### INT-102 — Fechar o app após digitar parte do código OTP (incompleto)
**Prioridade:** 🟡 Alto
**Pré-condição:** Tela de OTP de email. Digitar 3 dos 6 dígitos.

**Passos:**
1. Digitar 3 dígitos nos campos de OTP.
2. Fechar o app completamente.
3. Reabrir o app.

**Resultado esperado `[PASS]`:**
- App retorna à tela de OTP de email.
- Campos estão limpos (sem os dígitos parciais) — ou preenchidos, mas aceitando edição.
- **Não houve** submissão acidental do código incompleto.

**O que anotar:**
- [ ] Tela exibida:
- [ ] Os campos estavam preenchidos ou limpos?

---

### INT-103 — Minimizar o app, abrir o email, copiar o código e retornar
**Prioridade:** 🟡 Alto
**Pré-condição:** Tela de OTP de email. Email recebido mas app minimizado para acessar o email.

**Passos:**
1. Estar na tela de OTP de email.
2. Minimizar o app (não fechar).
3. Abrir o cliente de email, copiar o código OTP.
4. Retornar ao app pelo switcher de apps.
5. Colar/digitar o código no campo de OTP.
6. Confirmar a verificação.

**Resultado esperado `[PASS]`:**
- Tela de OTP está exatamente como foi deixada.
- Código colado/digitado é aceito normalmente.
- Verificação completada com sucesso.

---

### INT-104 — Fechar o app após o OTP correto ser submetido mas antes do redirecionamento
**Prioridade:** 🟡 Alto
**Pré-condição:** Código OTP correto já foi digitado. O submit aconteceu (botão tocado ou auto-submit), mas o app ainda está processando.

**Passos:**
1. Digitar o código correto e submeter.
2. Imediatamente fechar o app (antes do SnackBar de sucesso aparecer ou do redirecionamento acontecer).
3. Reabrir o app.

**Resultado esperado `[PASS]`:**
- Se a verificação foi concluída no servidor: app vai diretamente para a tela principal.
- Se a verificação não foi concluída: app retorna para a tela de OTP pedindo novo código.
- **Não deve** ficar em estado inconsistente (ex.: tela principal mas conta não verificada no banco).

**O que anotar:**
- [ ] Tela exibida ao reabrir:
- [ ] A conta estava verificada no backend? (verificar via painel admin ou banco se possível)

---

### INT-105 — Código OTP de email expira enquanto o app está fechado
**Prioridade:** 🔴 Crítico
**Pré-condição:** Código OTP recebido. Aguardar o tempo de expiração configurado no backend (confirmar com o time — geralmente 60 minutos).

**Passos:**
1. Estar na tela de OTP de email.
2. Fechar o app **sem usar o código**.
3. Aguardar o código expirar.
4. Reabrir o app.
5. Tentar usar o código expirado.

**Resultado esperado `[PASS]`:**
- App retorna à tela de OTP.
- Ao submeter o código expirado, exibe erro claro ("code expired" ou equivalente).
- Oferece opção de reenviar um novo código.

**O que anotar:**
- [ ] Mensagem de erro exibida:
- [ ] Opção de reenvio disponível?

---

### INT-106 — Fechar o app após clicar em "Resend" mas antes de receber o novo email
**Prioridade:** 🟢 Médio
**Pré-condição:** Tela de OTP de email. Reenvio solicitado.

**Passos:**
1. Tocar em `Resend` na tela de OTP.
2. Imediatamente fechar o app.
3. Aguardar 30 segundos.
4. Reabrir o app.
5. Verificar o email e tentar usar o novo código.

**Resultado esperado `[PASS]`:**
- O reenvio foi processado no servidor mesmo com o app fechado.
- Ao reabrir, a tela de OTP está disponível.
- O novo código funciona normalmente.

---

## 4. Ponto de interrupção: durante a verificação por SMS

> **Lembrete:** Em QA, números de qualquer país funcionam. Em produção, apenas números com prefixo `+1` (EUA) são aceitos.

---

### INT-201 — Fechar o app na tela de inserção do número de telefone
**Prioridade:** 🟡 Alto
**Pré-condição:** Bottom sheet "Enter Phone Number" aberto.

**Passos:**
1. Abrir o bottom sheet de número de telefone (via "Verify via SMS").
2. Digitar o número mas **não tocar em "Send SMS Code"**.
3. Fechar o app completamente.
4. Reabrir o app.

**Resultado esperado `[PASS]`:**
- App retorna à tela de escolha de método ("Verify Your Account") ou à tela de OTP de SMS (se o número já havia sido submetido anteriormente).
- **Não deve** ir para a tela principal sem verificação.

**O que anotar:**
- [ ] Tela exibida ao reabrir:

---

### INT-202 — Fechar o app enquanto aguarda o SMS chegar
**Prioridade:** 🔴 Crítico
**Pré-condição:** Número de telefone submetido. SMS ainda não chegou. Tela "Verify Your Phone" exibida.

**Passos:**
1. Submeter o número de telefone e aguardar a tela de OTP de SMS aparecer.
2. Fechar o app antes de o SMS chegar.
3. Aguardar o SMS chegar (verificar no aparelho).
4. Reabrir o app.

**Resultado esperado `[PASS]`:**
- App retorna à tela de OTP de SMS.
- O SMS recebido ainda é válido e pode ser usado.

**O que anotar:**
- [ ] Tela exibida ao reabrir:
- [ ] O código SMS ainda funcionou?

---

### INT-203 — Minimizar o app para ler o SMS e retornar
**Prioridade:** 🟡 Alto
**Pré-condição:** Tela de OTP de SMS exibida. SMS recebido como notificação.

**Passos:**
1. Com a tela de OTP de SMS visível, minimizar o app ao receber a notificação do SMS.
2. Abrir o app de mensagens, ler o código.
3. Retornar ao app pelo switcher.
4. Digitar o código.

**Resultado esperado `[PASS]`:**
- App está na mesma tela de OTP de SMS, sem mudanças.
- Código digitado e verificação concluída com sucesso.

---

### INT-204 — iOS: SMS autofill enquanto app estava em background
**Prioridade:** 🟡 Alto
**Plataforma:** iOS (device físico obrigatório)
**Pré-condição:** Tela de OTP de SMS exibida. App minimizado.

**Passos:**
1. Minimizar o app (não fechar).
2. Aguardar o SMS chegar — o iOS detecta o código e exibe sugestão na barra acima do teclado ou na notificação.
3. **Sem abrir o app de mensagens**, retornar ao app pelo switcher.
4. Verificar se a sugestão de autofill ainda aparece.
5. Tocar na sugestão.

**Resultado esperado `[PASS]`:**
- A sugestão de autofill do iOS está disponível ao retornar.
- Código preenchido automaticamente via `AutofillHints.oneTimeCode`.
- Auto-submit acionado.

---

### INT-205 — Fechar o app após digitar o código SMS correto mas antes do redirecionamento
**Prioridade:** 🟡 Alto
**Pré-condição:** Código SMS correto digitado e submetido. App ainda processando.

**Passos:**
1. Digitar o código SMS correto e submeter.
2. Fechar o app imediatamente.
3. Reabrir o app.

**Resultado esperado `[PASS]`:**
- Se verificação concluída no servidor: app vai para a tela principal.
- Se não: app retorna à tela de OTP de SMS.
- Sem estado inconsistente.

**O que anotar:**
- [ ] Tela exibida:
- [ ] A conta estava verificada no backend?

---

## 5. Deeplinks de verificação de email (link antigo / expirado / já usado)

Deeplinks de verificação chegam por email após o signup. Os cenários abaixo testam o que acontece com links em diferentes estados.

> **Como obter os links para teste:** nos clientes de email usados durante o signup (ou aliases Gmail), copiar o link do botão de verificação antes de clicar nele.

---

### DL-001 — Abrir app via deeplink de verificação válido (caminho feliz)
**Prioridade:** 🔴 Crítico
**Pré-condição:** Conta criada, email de verificação recebido, link ainda válido. App fechado ou em background.

**Passos:**
1. Abrir o cliente de email.
2. Tocar no link de verificação do email.
3. Confirmar abertura no app (se solicitado pelo SO).

**Resultado esperado `[PASS]`:**
- App abre (ou é trazido ao foreground).
- Conta é verificada automaticamente pelo token no link.
- SnackBar de sucesso exibido.
- App redireciona para a tela principal.
- Nenhum campo de OTP é exibido — o link é suficiente.

---

### DL-002 — Abrir app via deeplink de verificação com outro usuário já logado
**Prioridade:** 🔴 Crítico
**Pré-condição:** Usuário A está logado. Link de verificação pertence ao Usuário B (conta diferente).

**Passos:**
1. Logar como Usuário A.
2. Abrir (em outro dispositivo ou simulando) o link de verificação do Usuário B.

**Resultado esperado:**
- Verificar com o time de dev qual é o comportamento esperado.
- Possibilidades: erro de contexto, logout forçado do Usuário A, ou verificação do Usuário B mesmo com sessão ativa de A.
- **Qualquer que seja o comportamento, ele deve ser explícito e não silencioso.**

**O que anotar:**
- [ ] O que aconteceu com a sessão do Usuário A?
- [ ] O Usuário B foi verificado?

---

### DL-003 — Abrir app via deeplink de verificação já utilizado
**Prioridade:** 🔴 Crítico
**Pré-condição:** Link de verificação já foi usado com sucesso anteriormente.

**Passos:**
1. Após verificar a conta com sucesso (qualquer método), retornar ao email de verificação.
2. Tocar no link de verificação novamente.

**Resultado esperado `[FAIL]`:**
- App exibe erro claro: "link já utilizado", "token inválido", ou equivalente.
- **Não deve** verificar a conta uma segunda vez sem efeito colateral.
- **Não deve** silenciosamente redirecionar para a tela principal sem mensagem.

**O que anotar:**
- [ ] Mensagem exibida:
- [ ] O app travou ou se comportou de forma estranha?

---

### DL-004 — Abrir app via deeplink de verificação expirado
**Prioridade:** 🔴 Crítico
**Pré-condição:** Link de verificação recebido mas aguardado até expirar (checar tempo com o time — geralmente 60 minutos).

**Passos:**
1. Receber o email de verificação.
2. Aguardar o prazo de expiração do token.
3. Tocar no link.

**Resultado esperado `[FAIL]`:**
- App exibe mensagem de erro: "link expirado", "token inválido", ou equivalente.
- Oferece alguma ação ao usuário (ex.: botão de reenvio, ou navega para a tela de OTP para tentar pelo fluxo normal).

**O que anotar:**
- [ ] Mensagem exibida:
- [ ] App ofereceu opção de reenvio ou retomada?

---

### DL-005 — Abrir app via deeplink de verificação com token manipulado
**Prioridade:** 🔴 Crítico (segurança)
**Pré-condição:** Link de verificação válido recebido.

**Passos:**
1. Copiar o link de verificação do email.
2. Modificar manualmente o token na URL (ex.: trocar os últimos 5 caracteres por caracteres aleatórios).
3. Abrir o link modificado no app (via browser → "Abrir no app" ou colando diretamente).

**Resultado esperado `[FAIL]`:**
- App exibe erro de token inválido.
- Nenhuma conta é verificada.
- App não trava.

---

### DL-006 — App fechado recebe deeplink de verificação via notificação de email
**Prioridade:** 🟡 Alto
**Pré-condição:** App completamente fechado. Notificação de email com link de verificação disponível.

**Passos:**
1. Fechar o app completamente.
2. Abrir a notificação do email diretamente da Central de Notificações do SO.
3. Tocar no link de verificação dentro do email.

**Resultado esperado `[PASS]`:**
- App é iniciado (cold start) e processa o deeplink.
- Verificação ocorre normalmente.
- App vai para a tela principal após a verificação.

---

## 6. Deeplinks de Esqueci a Senha

---

### DL-101 — Abrir app via link de "Esqueci a Senha" válido (caminho feliz)
**Prioridade:** 🔴 Crítico
**Pré-condição:** Email de reset de senha recebido. Link ainda válido. App fechado.

**Passos:**
1. Tocar no link de reset de senha no email.
2. Confirmar abertura no app.
3. Observar a tela exibida.

**Resultado esperado `[PASS]`:**
- App abre na tela `ResetPasswordScreen`.
- Dois campos de nova senha visíveis.
- Botão `UPDATE PASSWORD` visível.
- Nenhuma outra tela é exibida antes.

---

### DL-102 — Abrir app via link de "Esqueci a Senha" com usuário já logado
**Prioridade:** 🔴 Crítico
**Pré-condição:** Usuário A está logado e ativo no app. Link de reset pertence ao Usuário A (mesmo usuário).

**Passos:**
1. Manter o app aberto e logado.
2. Tocar no link de reset no email (minimizar o app → abrir email → tocar no link → app volta ao foreground).

**Resultado esperado:**
- Verificar com o time o comportamento esperado.
- Possibilidades: abre a tela de reset na sessão atual, ou faz logout primeiro, ou ignora o link.
- Independente do comportamento, ele deve ser explícito — não silencioso.

**O que anotar:**
- [ ] O app foi para a tela de reset ou ignorou o link?
- [ ] A sessão ativa foi afetada?

---

### DL-103 — Abrir app via link de "Esqueci a Senha" de outro usuário (com usuário diferente logado)
**Prioridade:** 🔴 Crítico
**Pré-condição:** Usuário A está logado. Link de reset pertence ao Usuário B.

**Passos:**
1. Logar como Usuário A.
2. Abrir o link de reset do Usuário B.

**Resultado esperado `[FAIL]`:**
- O app deve detectar o conflito de contexto.
- **Não deve** permitir que Usuário A redefina a senha do Usuário B usando o token.
- O comportamento deve ser explícito (erro ou logout de A antes de prosseguir).

**O que anotar:**
- [ ] O que aconteceu?
- [ ] Alguma senha foi alterada indevidamente?

---

### DL-104 — Link de "Esqueci a Senha" expirado
**Prioridade:** 🔴 Crítico
**Pré-condição:** Link de reset recebido. Aguardar expiração do token.

**Passos:**
1. Receber o email de reset.
2. Aguardar o prazo de expiração.
3. Tocar no link.

**Resultado esperado `[FAIL]`:**
- App exibe mensagem de erro: "link expirado" ou equivalente.
- Oferece opção de solicitar novo link.
- Nenhuma senha é alterada.

---

### DL-105 — Link de "Esqueci a Senha" já utilizado
**Prioridade:** 🔴 Crítico
**Pré-condição:** Link de reset já foi utilizado com sucesso (senha redefinida).

**Passos:**
1. Após redefinir a senha com sucesso, retornar ao email de reset.
2. Tocar no link novamente.

**Resultado esperado `[FAIL]`:**
- App exibe erro: "link já utilizado" ou "token inválido".
- Nenhuma tela de nova senha é exibida.

---

### DL-106 — Link de "Esqueci a Senha" com token manipulado
**Prioridade:** 🔴 Crítico (segurança)
**Pré-condição:** Link de reset recebido.

**Passos:**
1. Copiar o link de reset.
2. Modificar o token manualmente na URL.
3. Abrir o link modificado.

**Resultado esperado `[FAIL]`:**
- App exibe erro de token inválido.
- Nenhuma senha é alterada.
- App não trava.

---

### DL-107 — App fechado recebe deeplink de reset via notificação
**Prioridade:** 🟡 Alto
**Pré-condição:** App completamente fechado. Email de reset na Central de Notificações.

**Passos:**
1. Fechar o app completamente.
2. Abrir a notificação do email.
3. Tocar no link de reset.

**Resultado esperado `[PASS]`:**
- App inicia (cold start) e abre diretamente na `ResetPasswordScreen`.
- Fluxo de redefinição funciona normalmente.

---

### DL-108 — Fechar o app na tela de reset antes de submeter a nova senha
**Prioridade:** 🟡 Alto
**Pré-condição:** App aberto na tela de reset (via deeplink válido). Nova senha digitada mas ainda não submetida.

**Passos:**
1. Abrir o app via deeplink de reset.
2. Digitar a nova senha e a confirmação.
3. **Não tocar em `UPDATE PASSWORD`.** Fechar o app completamente.
4. Reabrir o app pelo ícone.

**Resultado esperado `[PASS]`:**
- App retorna para a Welcome Screen (o token do deeplink não é re-processado).
- A senha **não foi alterada** (não houve submit).
- O link de reset ainda pode ser utilizado se ainda estiver válido.

**O que anotar:**
- [ ] Tela exibida ao reabrir:
- [ ] A senha antiga ainda funciona para login?

---

## 7. Combinações e edge cases

Cenários que combinam múltiplos pontos de interrupção ou situações incomuns.

---

### COMB-001 — Signup → fechar app → reabrir → clicar no deeplink de verificação → verificar se vai pro lugar certo
**Prioridade:** 🔴 Crítico
**Descrição:** Simula o fluxo mais comum do usuário real — criar conta, sair do app, abrir o email, clicar no link.

**Passos:**
1. Criar conta via signup.
2. Fechar o app **sem verificar** (antes de escolher o método).
3. Abrir o email de verificação que chegou automaticamente.
4. Tocar no link de verificação.
5. Observar se o app abre e verifica a conta corretamente.

**Resultado esperado `[PASS]`:**
- App abre, verifica a conta via token do link, e vai para a tela principal.
- Não exige que o usuário passe pela tela de OTP manual.

---

### COMB-002 — Verificação por email iniciada → fechar app → reabrir → tentar pelo deeplink de verificação
**Prioridade:** 🟡 Alto
**Descrição:** Usuário começou a verificar pelo OTP manual, fechou o app, e então decidiu usar o link do email.

**Passos:**
1. Após o signup, escolher "Verify via Email".
2. Receber o código OTP mas fechar o app sem usá-lo.
3. Abrir o email e clicar no link de verificação (se o email contiver link além do código).
4. Observar o resultado.

**Resultado esperado `[PASS]`:**
- A verificação ocorre normalmente via link.
- Sem conflito entre o fluxo de OTP e o deeplink.

> **Confirmar com o time:** o email de verificação envia apenas código OTP ou também um link clicável? O comportamento esperado depende disso.

---

### COMB-003 — Solicitar "Esqueci a Senha" com a sessão ativa, fechar o app, reabrir pelo link de reset
**Prioridade:** 🟡 Alto

**Passos:**
1. Estar logado no app.
2. Fazer logout.
3. Na tela de login, usar "Forgot Password?" e solicitar o reset.
4. Fechar o app completamente.
5. Abrir o email de reset e clicar no link.
6. Observar o comportamento.

**Resultado esperado `[PASS]`:**
- App abre direto na tela de reset.
- Fluxo de redefinição funciona normalmente.
- Após redefinir, login com a nova senha funciona.

---

### COMB-004 — Dois emails de verificação na caixa de entrada — usar o mais antigo
**Prioridade:** 🟡 Alto
**Descrição:** O usuário clicou em "Resend" e agora tem dois emails de verificação. Verifica o que acontece ao usar o primeiro (mais antigo).

**Passos:**
1. Chegar na tela de OTP de email.
2. Clicar em `Resend` — um segundo email é enviado.
3. Abrir o **primeiro email** (mais antigo) e tocar no link ou copiar o código.
4. Tentar usar o código/link do email mais antigo.

**Resultado esperado `[FAIL]`:**
- O código/link antigo foi invalidado pelo reenvio.
- Exibe mensagem de erro clara ("code expired" ou "invalid token").
- Usar o código/link **do segundo email** funciona normalmente.

---

## 8. Checklist geral de regressão

Use após qualquer alteração no fluxo de autenticação, navegação pós-auth, ou tratamento de deeplinks.

### Interrupções durante signup/verificação
- [ ] Fechar app antes de escolher método → retorna para tela de escolha (não para home)
- [ ] Fechar app na tela de OTP de email → retorna para tela de OTP (não para home)
- [ ] Fechar app na tela de OTP de SMS → retorna para tela de OTP (não para home)
- [ ] Minimizar e retornar → estado preservado em todos os pontos do fluxo
- [ ] Nenhum cenário de interrupção resulta em acesso à tela principal sem verificação concluída

### Deeplinks de verificação de email
- [ ] Link válido → verifica conta e vai para tela principal
- [ ] Link já utilizado → erro claro, sem efeito colateral
- [ ] Link expirado → erro claro, com opção de ação
- [ ] Link com token manipulado → erro, sem verificação
- [ ] Cold start via deeplink → funciona corretamente

### Deeplinks de reset de senha
- [ ] Link válido → abre tela de reset
- [ ] Link já utilizado → erro claro
- [ ] Link expirado → erro claro
- [ ] Link com token manipulado → erro, sem alteração de senha
- [ ] Cold start via deeplink → funciona corretamente
- [ ] Usuário logado abre link de reset → comportamento explícito (não silencioso)
- [ ] Usuário logado A abre link de reset de B → não permite alteração de senha de B

### Segurança
- [ ] Nenhum token manipulado resulta em verificação ou alteração de senha
- [ ] Nenhuma interrupção permite pular etapas obrigatórias de verificação
- [ ] Sessão de outro usuário não é afetada por deeplinks de terceiros

---

*Documento mantido pelo time de QA. Para atualizar, editar `docs/qa_auth_interruption_deeplink_test.md`.*
