# Guia de Testes QA — Fluxos de Login e Signup

> **Aplicativo:** mvc_app (Flutter)
> **Ambiente de referência:** QA / Development (Flavor)
> **Última atualização:** 2026-03-04
> **Autor:** Time de Engenharia

---

## Sumário

1. [Antes de Começar](#1-antes-de-começar)
2. [Convenções deste Documento](#2-convenções-deste-documento)
3. [Como criar cada tipo de conta](#3-como-criar-cada-tipo-de-conta)
4. [Onboarding (Tela Inicial)](#4-onboarding-tela-inicial)
5. [Fluxo de Login — Email/Senha](#5-fluxo-de-login--emailsenha)
6. [Fluxo de Signup — Email/Senha](#6-fluxo-de-signup--emailsenha)
7. [Verificação por Email (OTP)](#7-verificação-por-email-otp)
8. [Verificação por SMS (OTP)](#8-verificação-por-sms-otp)
9. [Tela de Escolha do Método de Verificação](#9-tela-de-escolha-do-método-de-verificação)
10. [Apple Login](#10-apple-login)
11. [Esqueci a Senha (Forgot Password)](#11-esqueci-a-senha-forgot-password)
12. [Redefinição de Senha (Reset Password)](#12-redefinição-de-senha-reset-password)
13. [Login por Perfis/Roles](#13-login-por-perfisroles)
14. [Logout](#14-logout)
15. [Testes de Falha e Edge Cases](#15-testes-de-falha-e-edge-cases)
16. [Testes de Acessibilidade e UX](#16-testes-de-acessibilidade-e-ux)
17. [Testes em Plataformas Específicas](#17-testes-em-plataformas-específicas)
18. [Checklist Geral de Regressão](#18-checklist-geral-de-regressão)

---

## 1. Antes de Começar

### Contas de teste necessárias

Antes de iniciar qualquer teste, certifique-se de ter acesso a:

| Tipo de conta | Uso |
|---|---|
| Conta regular (usuário comum) | Testes de login básico |
| Conta admin | Testes de login com role admin |
| Conta superadmin | Testes de login com role superadmin |
| Email temporário (MailSlurp, Mailinator, etc.) | Testes de signup e reset de senha |
| Número de telefone para SMS | Testes de verificação via SMS |
| Apple ID | Testes de Apple Login |

### Ambientes

- **QA/Development:** Use o flavor `development` do app. Conecta ao backend QA.
- **Produção:** Nunca criar contas de teste em produção sem autorização.

### Gmail aliases — crie múltiplas contas com um só email

O Gmail suporta aliases usando o caractere `+` no endereço. Tudo que vem depois do `+` é ignorado pela entrega, mas o sistema do app enxerga como um email diferente. Isso permite criar várias contas sem precisar de caixas de entrada separadas.

**Formato:** `seuemail+alias@gmail.com`

Exemplos práticos:
- `damascenoalisson+qa01@gmail.com`
- `damascenoalisson+qa02@gmail.com`
- `damascenoalisson+admin_test@gmail.com`

Todos os emails chegam em `damascenoalisson@gmail.com`. Use filtros no Gmail (`Para: +qa`) para separar as mensagens se necessário.

> **Dica:** crie uma convenção de nomenclatura para os aliases de teste, ex.: `+qa_regular_01`, `+qa_admin_01`, para facilitar a identificação das contas.

### Ferramentas úteis

- **Gmail aliases:** Veja seção acima — a forma mais prática de criar múltiplas contas de teste.
- **MailSlurp / Mailinator:** Alternativa quando não se quer usar uma conta Gmail pessoal.
- **Simulador iOS / Emulador Android:** Para testes de plataforma cruzada.
- **Device físico:** Obrigatório para testes de autofill de OTP via SMS (não funciona em simulador).

---

## 2. Convenções deste Documento

- `[PASS]` — Resultado esperado quando o teste funciona corretamente.
- `[FAIL]` — Comportamento esperado quando há falha intencional (ex.: credenciais erradas).
- **Pré-condição:** Estado do app antes do teste começar.
- **Passos:** Ações a executar em ordem.
- **Resultado esperado:** O que deve acontecer.
- **Prioridade:** 🔴 Crítico | 🟡 Alto | 🟢 Médio | ⚪ Baixo

---

## 3. Como criar cada tipo de conta

Entender como cada role é provisionada é essencial antes de começar os testes — especialmente porque algumas delas dependem de outra conta já existente com privilégios.

### Conta Regular

Qualquer pessoa pode criar. Basta seguir o fluxo normal de signup (email/senha ou Apple Login) e verificar o email.

**Resumo:**
1. Abrir o app → `SIGN UP` → preencher dados → verificar email → pronto.

---

### Conta Admin (administrador de canal)

O admin é promovido por um **admin já existente** ou por um **superadmin**. Não é possível se tornar admin pelo próprio signup.

**Pré-requisito:** A conta regular do usuário-alvo já deve existir e o canal já deve existir no sistema.

**Passos para promover a admin:**
1. Fazer login com uma conta **admin** ou **superadmin**.
2. Navegar até `Manage` (menu de gerenciamento).
3. Entrar em `Channels`.
4. Selecionar o canal desejado.
5. Tocar em `Manage Admins`.
6. Localizar o usuário pelo nome ou email e adicioná-lo como admin.

> **Nota:** O usuário promovido recebe as permissões de admin **somente naquele canal/organização**. Cada canal pode ter seus próprios admins.

---

### Conta Superadmin

O superadmin **não pode ser criado pelo app**. A promoção só é possível diretamente no banco de dados.

**Como promover via banco:**
```sql
-- Exemplo genérico — confirmar tabela e campo corretos com o time de backend
UPDATE user_roles SET role = 'superadmin' WHERE user_id = '<uuid do usuário>';
```

> **Importante:** Peça ao time de backend ou ao DBA para fazer a promoção em QA. Nunca fazer isso em produção sem processo formal de aprovação.

---

## 4. Onboarding (Tela Inicial)

### TC-001 — Exibição do onboarding na primeira abertura
**Prioridade:** 🟡 Alto
**Pré-condição:** App instalado pela primeira vez ou sem dados de sessão.

**Passos:**
1. Abrir o aplicativo.
2. Observar a tela inicial.

**Resultado esperado `[PASS]`:**
- Tela de boas-vindas (Welcome Screen) é exibida com os botões `LOGIN` e `SIGN UP` visíveis.
- Não é solicitado login automático.

---

### TC-002 — App salva sessão após login
**Prioridade:** 🔴 Crítico
**Pré-condição:** Usuário já fez login anteriormente.

**Passos:**
1. Fechar o app completamente.
2. Reabrir o app.

**Resultado esperado `[PASS]`:**
- App vai diretamente para a tela principal (chat/home), sem pedir login novamente.
- Token de sessão válido.

---

### TC-003 — App retorna à tela de login após expiração de sessão
**Prioridade:** 🔴 Crítico
**Pré-condição:** Sessão do usuário expirada ou revogada no backend.

**Passos:**
1. Revogar/expirar a sessão via painel admin ou aguardar expiração.
2. Abrir ou retornar ao app.

**Resultado esperado `[PASS]`:**
- App redireciona para a Welcome Screen.
- Nenhuma informação sensível é exibida.

---

## 5. Fluxo de Login — Email/Senha

### TC-101 — Login com credenciais válidas (usuário regular)
**Prioridade:** 🔴 Crítico
**Pré-condição:** App aberto na Welcome Screen. Usuário com conta ativa.

**Passos:**
1. Tocar no botão `LOGIN`.
2. Verificar se o botão `CONTINUE WITH EMAIL` aparece.
3. Tocar em `CONTINUE WITH EMAIL` (se visível).
4. No campo "Enter your email", digitar o email válido.
5. No campo "Enter your password", digitar a senha correta.
6. Tocar no botão `LOGIN`.
7. Aguardar resposta da API.

**Resultado esperado `[PASS]`:**
- Usuário é redirecionado para a tela principal (RealChatScreen/Home).
- Não é exibida nenhuma mensagem de erro.
- Token JWT é válido (verificável via logs do app em modo QA).

---

### TC-102 — Login com email inválido (formato incorreto)
**Prioridade:** 🟡 Alto
**Pré-condição:** App na tela de login.

**Passos:**
1. No campo de email, digitar: `emailinvalido` (sem @).
2. No campo de senha, digitar qualquer texto.
3. Tocar em `LOGIN`.

**Resultado esperado `[FAIL]`:**
- Exibe mensagem de erro de formato de email.
- Usuário permanece na tela de login.
- Nenhuma chamada de API é feita.

---

### TC-103 — Login com senha incorreta
**Prioridade:** 🔴 Crítico
**Pré-condição:** App na tela de login.

**Passos:**
1. Digitar um email de conta existente.
2. Digitar uma senha errada (ex.: `SenhaErrada123!`).
3. Tocar em `LOGIN`.

**Resultado esperado `[FAIL]`:**
- Exibe mensagem de erro: "Invalid credentials", "Login failed" ou equivalente.
- Usuário permanece na tela de login.
- **Nenhuma informação sobre a existência da conta** é revelada na mensagem de erro.

---

### TC-104 — Login com email inexistente
**Prioridade:** 🟡 Alto
**Pré-condição:** App na tela de login.

**Passos:**
1. Digitar um email que não existe no sistema (ex.: `naoexiste@teste.com`).
2. Digitar qualquer senha.
3. Tocar em `LOGIN`.

**Resultado esperado `[FAIL]`:**
- Exibe mensagem de erro genérica (não deve revelar se o email existe ou não).
- Usuário permanece na tela de login.

---

### TC-105 — Login com campos em branco
**Prioridade:** 🟡 Alto
**Pré-condição:** App na tela de login.

**Passos:**
1. Deixar ambos os campos (email e senha) vazios.
2. Tocar em `LOGIN`.

**Resultado esperado `[FAIL]`:**
- Exibe mensagem de validação para campo obrigatório.
- Nenhuma chamada de API é feita.

---

### TC-106 — Login com apenas email preenchido
**Prioridade:** 🟢 Médio
**Pré-condição:** App na tela de login.

**Passos:**
1. Preencher apenas o campo de email.
2. Deixar campo de senha vazio.
3. Tocar em `LOGIN`.

**Resultado esperado `[FAIL]`:**
- Exibe validação no campo de senha.
- Nenhuma chamada de API é feita.

---

### TC-107 — Login com caracteres especiais na senha
**Prioridade:** 🟢 Médio
**Pré-condição:** App na tela de login. Conta com senha contendo caracteres especiais criada previamente.

**Passos:**
1. Digitar email válido.
2. Digitar senha com caracteres especiais (ex.: `P@$$w0rd!#%`).
3. Tocar em `LOGIN`.

**Resultado esperado `[PASS]`:**
- Login realizado com sucesso.

---

### TC-108 — Visibilidade da senha (eye icon)
**Prioridade:** 🟢 Médio
**Pré-condição:** App na tela de login.

**Passos:**
1. Digitar uma senha no campo de senha.
2. Verificar que a senha está oculta (pontos/asteriscos).
3. Tocar no ícone de "olho" (eye icon) para revelar a senha.
4. Verificar que a senha está visível.
5. Tocar novamente no ícone para ocultar.

**Resultado esperado `[PASS]`:**
- Senha alterna entre oculta e visível a cada toque.

---

### TC-109 — Navegar de volta da tela de login para a Welcome Screen
**Prioridade:** 🟢 Médio
**Pré-condição:** App na tela de login.

**Passos:**
1. Tocar no botão de voltar (seta back) ou gesto de swipe.

**Resultado esperado `[PASS]`:**
- App retorna à Welcome Screen.
- Nenhum dado digitado é persistido na volta.

---

## 6. Fluxo de Signup — Email/Senha

### TC-201 — Cadastro com dados válidos (fluxo completo)
**Prioridade:** 🔴 Crítico
**Pré-condição:** App na Welcome Screen. Email temporário disponível.

**Passos:**
1. Tocar em `SIGN UP`.
2. Verificar se o modal/bottom sheet de "escolha de método" aparece.
3. Tocar em `CONTINUE WITH EMAIL`.
4. Preencher "Enter your full name" com um nome válido (ex.: `João Silva`).
5. Preencher "Enter your email" com um email único e válido.
6. Preencher "Enter your password" com senha forte (ex.: `Senha@Forte123`).
7. Preencher "Confirm your password" com a mesma senha.
8. Tocar em `SIGN UP`.

**Resultado esperado `[PASS]`:**
- App avança para a tela de explicação de OTP (SignUpOtpExplanationScreen) ou diretamente para a tela de verificação.
- Email de verificação é enviado para o endereço cadastrado.

---

### TC-202 — Signup com senhas que não conferem
**Prioridade:** 🔴 Crítico
**Pré-condição:** App no formulário de signup.

**Passos:**
1. Preencher nome, email e senha corretamente.
2. No campo "Confirm your password", digitar uma senha diferente.
3. Tocar em `SIGN UP`.

**Resultado esperado `[FAIL]`:**
- Exibe mensagem de erro: "Passwords do not match" ou equivalente.
- Usuário permanece no formulário de signup.
- Nenhuma conta é criada.

---

### TC-203 — Signup com email já cadastrado
**Prioridade:** 🔴 Crítico
**Pré-condição:** App no formulário de signup. Email já possui conta no sistema.

**Passos:**
1. Preencher todos os campos com dados válidos.
2. Usar um email que já existe no sistema.
3. Tocar em `SIGN UP`.

**Resultado esperado `[FAIL]`:**
- Exibe mensagem de erro: "Email already in use" ou equivalente.
- Usuário permanece no formulário.

---

### TC-204 — Signup com email com formato inválido
**Prioridade:** 🟡 Alto
**Pré-condição:** App no formulário de signup.

**Passos:**
1. Digitar em email: `usuario@` (sem domínio).
2. Preencher demais campos normalmente.
3. Tocar em `SIGN UP`.

**Resultado esperado `[FAIL]`:**
- Exibe erro de validação de formato de email.
- Nenhuma chamada à API.

---

### TC-205 — Signup com senha fraca
**Prioridade:** 🟡 Alto
**Pré-condição:** App no formulário de signup.

**Passos:**
1. Preencher nome e email válidos.
2. Digitar senha simples: `123456` ou `abc`.
3. Confirmar senha igual.
4. Tocar em `SIGN UP`.

**Resultado esperado `[FAIL]`:**
- Exibe mensagem indicando que a senha não atende aos requisitos mínimos (se houver validação de força de senha).
- Verificar se o app tem critérios de senha definidos.

---

### TC-206 — Signup com campos obrigatórios vazios
**Prioridade:** 🟡 Alto
**Pré-condição:** App no formulário de signup.

**Passos:**
1. Deixar todos os campos vazios.
2. Tocar em `SIGN UP`.

**Resultado esperado `[FAIL]`:**
- Exibe validação em todos os campos obrigatórios.
- Nenhuma chamada à API.

---

### TC-207 — Signup com nome contendo apenas espaços
**Prioridade:** 🟢 Médio
**Pré-condição:** App no formulário de signup.

**Passos:**
1. No campo de nome, digitar apenas espaços.
2. Preencher email e senhas válidas.
3. Tocar em `SIGN UP`.

**Resultado esperado `[FAIL]`:**
- App trata espaços como campo vazio ou exibe erro de validação.

---

### TC-208 — Navegar de volta do modal de escolha de método
**Prioridade:** 🟢 Médio
**Pré-condição:** Modal de "choose how you want to join" aberto.

**Passos:**
1. Com o modal aberto, fazer swipe para baixo ou tocar fora do modal.

**Resultado esperado `[PASS]`:**
- Modal fecha.
- App retorna à Welcome Screen.

---

## 7. Verificação por Email (OTP)

### TC-301 — Recebimento do email de verificação após signup
**Prioridade:** 🔴 Crítico
**Pré-condição:** Signup realizado com sucesso (TC-201).

**Passos:**
1. Verificar a caixa de entrada do email usado no cadastro.
2. Aguardar até 2 minutos pela chegada do email.

**Resultado esperado `[PASS]`:**
- Email recebido com assunto relacionado à verificação.
- Email contém código OTP de 6 dígitos (numérico).
- Email exibido de forma legível, sem problemas de formatação.

---

### TC-302 — Verificar email com código OTP correto
**Prioridade:** 🔴 Crítico
**Pré-condição:** Tela de verificação OTP exibida. Código válido em mãos.

**Passos:**
1. Na tela "Verify Your Email", digitar os 6 dígitos do código recebido por email.
2. O botão `Verify Code` deve ser ativado após inserir 6 dígitos.
3. Tocar em `Verify Code` (ou aguardar o auto-submit).

**Resultado esperado `[PASS]`:**
- SnackBar verde com mensagem de sucesso exibida.
- App redireciona automaticamente para a tela principal.
- Conta está verificada.

---

### TC-303 — Verificar email com código OTP incorreto
**Prioridade:** 🔴 Crítico
**Pré-condição:** Tela de verificação OTP exibida.

**Passos:**
1. Digitar um código incorreto (ex.: `000000`).
2. Tocar em `Verify Code`.

**Resultado esperado `[FAIL]`:**
- Exibe mensagem de erro em vermelho na tela.
- Campos de OTP continuam visíveis para nova tentativa.
- Usuário não é redirecionado.

---

### TC-304 — Auto-submit ao completar 6 dígitos
**Prioridade:** 🟡 Alto
**Pré-condição:** Tela de verificação OTP exibida.

**Passos:**
1. Digitar os 6 dígitos um a um nos campos.
2. Observar comportamento ao inserir o 6º dígito.

**Resultado esperado `[PASS]`:**
- Ao inserir o 6º dígito, o código é submetido automaticamente sem precisar tocar no botão.
- Animação de "bounce" nos campos de OTP é visível.

---

### TC-305 — Navegação automática entre campos OTP
**Prioridade:** 🟡 Alto
**Pré-condição:** Tela de verificação OTP exibida.

**Passos:**
1. Tocar no primeiro campo de OTP.
2. Digitar um dígito.

**Resultado esperado `[PASS]`:**
- Cursor avança automaticamente para o próximo campo.
- Ao apagar com backspace, cursor volta ao campo anterior.

---

### TC-306 — Reenvio do código OTP por email
**Prioridade:** 🔴 Crítico
**Pré-condição:** Tela de verificação OTP exibida. Código inicial recebido (ou não recebido).

**Passos:**
1. Localizar o link/botão "Resend" (ou "Didn't receive the code? Resend").
2. Tocar em `Resend`.

**Resultado esperado `[PASS]`:**
- Novo email de verificação é enviado para o endereço cadastrado.
- Mensagem de sucesso é exibida na tela (ex.: banner verde).
- Código anterior é invalidado (verificar no backend se possível).

---

### TC-307 — Reenvio múltiplos de OTP (rate limiting)
**Prioridade:** 🟡 Alto
**Pré-condição:** Tela de verificação OTP exibida.

**Passos:**
1. Tocar em `Resend` 3 ou mais vezes rapidamente.

**Resultado esperado:**
- Verificar se há rate limiting (bloqueio após X tentativas).
- Se houver: mensagem de erro informando que o reenvio foi limitado.
- Se não houver: **reportar como bug potencial** de segurança para o time.

---

### TC-308 — Limpar código OTP com botão "Clear Code"
**Prioridade:** 🟢 Médio
**Pré-condição:** Tela de OTP com campos preenchidos parcialmente.

**Passos:**
1. Digitar 3 ou 4 dígitos nos campos.
2. Tocar no botão `Clear Code`.

**Resultado esperado `[PASS]`:**
- Todos os campos são limpos.
- Foco retorna ao primeiro campo.

---

### TC-309 — OTP com código expirado
**Prioridade:** 🔴 Crítico
**Pré-condição:** Código OTP recebido. Aguardar o tempo de expiração (verificar tempo configurado no backend, geralmente 60 minutos).

**Passos:**
1. Aguardar o código expirar.
2. Digitar o código expirado.
3. Tocar em `Verify Code`.

**Resultado esperado `[FAIL]`:**
- Exibe mensagem de erro informando que o código expirou.
- Oferece opção de reenvio.

---

### TC-310 — Voltar da tela de verificação OTP
**Prioridade:** 🟢 Médio
**Pré-condição:** Tela de verificação OTP exibida.

**Passos:**
1. Tocar no botão de voltar (seta back no topo esquerdo).

**Resultado esperado `[PASS]`:**
- App retorna para a Welcome Screen (comportamento definido no AuthBloc via `NavigateToHomeEvent`).
- Conta não é verificada.

---

### TC-311 — Email de verificação não recebido (verificar spam)
**Prioridade:** 🟡 Alto
**Pré-condição:** Signup realizado. Email não aparece na caixa de entrada em 5 minutos.

**Passos:**
1. Verificar pasta de spam/lixo eletrônico.
2. Verificar se o email não está bloqueado pelo domínio (whitelist corporativa).

**Resultado esperado:**
- A tela de OTP explanation (SignUpOtpExplanationScreen) já instrui o usuário: "Please check your spam folder".
- Verificar se essa mensagem é exibida corretamente no fluxo de signup.

---

### TC-312 — Autofill de OTP por email no iOS
**Prioridade:** 🟡 Alto
**Plataforma:** iOS (device físico obrigatório)
**Pré-condição:** Usuário recebeu email com código OTP. iOS detecta o código SMS/email.

**Passos:**
1. Aguardar o iOS sugerir o código acima do teclado.
2. Tocar na sugestão do código.

**Resultado esperado `[PASS]`:**
- Campos de OTP são preenchidos automaticamente.
- Auto-submit é acionado.
- (Implementado via hidden field com `AutofillHints.oneTimeCode`).

---

## 8. Verificação por SMS (OTP)

> **Importante:** A verificação via SMS é controlada por **feature flag** (`smsVerificationEnabled`). Se a flag estiver desativada, o botão "Verify via SMS" aparece com badge "Soon" e está desabilitado. Confirme com o time dev se a flag está ativa no ambiente de QA antes de executar estes testes.

### Diferença entre QA e Produção

| Ambiente | Comportamento |
|---|---|
| **QA / Development** | Aceita números de qualquer país no formato E.164. Ex.: `+5511999990000` (Brasil), `+447911123456` (UK). |
| **Produção** | O prefixo `+1` é fixo no backend — **só funciona com números dos EUA**. Números de outros países serão rejeitados ou o SMS não chegará. |

> **Resumo prático:** Em QA você pode usar seu número brasileiro normalmente. Em produção, só é possível testar verificação SMS com um número americano real ou um serviço de número virtual dos EUA (ex.: Google Voice).

---

### TC-401 — Exibição do card SMS desabilitado (feature flag OFF)
**Prioridade:** 🟡 Alto
**Pré-condição:** Feature flag `smsVerificationEnabled = false` (padrão).

**Passos:**
1. Completar signup e chegar à tela de escolha de método de verificação.
2. Observar o card "Verify via SMS".

**Resultado esperado `[PASS]`:**
- Card "Verify via SMS" aparece com opacidade reduzida (55%).
- Badge "Soon" visível no canto direito.
- Card não é clicável (não abre o bottom sheet).
- Card "Verify via Email" está ativo e clicável normalmente.

---

### TC-402 — Abertura do bottom sheet de número de telefone (feature flag ON)
**Prioridade:** 🔴 Crítico
**Pré-condição:** Feature flag `smsVerificationEnabled = true`. Tela de escolha de método.

**Passos:**
1. Tocar no card "Verify via SMS".

**Resultado esperado `[PASS]`:**
- Bottom sheet abre com título "Enter Phone Number".
- Campo de telefone com placeholder `+1 234 567 8900` (formato internacional).
- Campo é auto-focado com teclado numérico aberto.
- Bottom sheet sobe junto com o teclado.

---

### TC-403 — Envio de SMS com número no formato internacional correto
**Prioridade:** 🔴 Crítico
**Pré-condição:** Bottom sheet de telefone aberto.

**Passos:**
1. Digitar número no formato E.164 (ex.: `+5511999990000` para BR).
2. Tocar em `Send SMS Code`.

**Resultado esperado `[PASS]`:**
- Loading indicator exibido no botão.
- SMS enviado para o número.
- Bottom sheet fecha automaticamente.
- App avança para tela de verificação SMS OTP ("Verify Your Phone").

---

### TC-404 — Envio de SMS com número sem código de país
**Prioridade:** 🟡 Alto
**Pré-condição:** Bottom sheet de telefone aberto.

**Passos:**
1. Digitar número sem o `+` e código do país (ex.: `11999990000`).
2. Tocar em `Send SMS Code`.

**Resultado esperado `[FAIL]`:**
- Exibe mensagem de erro sobre formato do número.
- **Verificar se o backend sanitiza o número ou retorna erro claro.**
- (Nota: o app realiza sanitização de números no backend — verificar comportamento real.)

---

### TC-405 — Envio de SMS com número de telefone inválido
**Prioridade:** 🟡 Alto
**Pré-condição:** Bottom sheet de telefone aberto.

**Passos:**
1. Digitar um número claramente inválido (ex.: `+0000000000`).
2. Tocar em `Send SMS Code`.

**Resultado esperado `[FAIL]`:**
- Exibe mensagem de erro do servidor ou validação.
- Bottom sheet permanece aberto.

---

### TC-406 — Verificar OTP de SMS com código correto
**Prioridade:** 🔴 Crítico
**Pré-condição:** SMS recebido. Tela "Verify Your Phone" exibida.

**Passos:**
1. Digitar os 6 dígitos do SMS.
2. Aguardar auto-submit ao completar o 6º dígito.

**Resultado esperado `[PASS]`:**
- SnackBar de sucesso exibida.
- Conta verificada.
- App redireciona para tela principal.

---

### TC-407 — Verificar OTP de SMS com código incorreto
**Prioridade:** 🔴 Crítico
**Pré-condição:** Tela "Verify Your Phone" exibida.

**Passos:**
1. Digitar código incorreto (ex.: `123456`).
2. Tocar em `Verify Code`.

**Resultado esperado `[FAIL]`:**
- Mensagem de erro em vermelho exibida.
- Campos permanecem para nova tentativa.

---

### TC-408 — Reenvio do SMS OTP
**Prioridade:** 🟡 Alto
**Pré-condição:** Tela "Verify Your Phone" exibida.

**Passos:**
1. Localizar o link "Didn't receive the SMS? Resend".
2. Tocar em `Resend`.

**Resultado esperado `[PASS]`:**
- Novo SMS é enviado.
- Mensagem de confirmação exibida.

---

### TC-409 — Voltar da tela de verificação SMS para escolha de método
**Prioridade:** 🟡 Alto
**Pré-condição:** Tela "Verify Your Phone" exibida.

**Passos:**
1. Tocar no botão de voltar (seta back).

**Resultado esperado `[PASS]`:**
- App retorna para a tela de escolha de método de verificação (via `GoBackEvent`).
- Não retorna para o Welcome Screen diretamente.

---

### TC-410 — Autofill de OTP via SMS no iOS (iMessage Code)
**Prioridade:** 🟡 Alto
**Plataforma:** iOS (device físico obrigatório)
**Pré-condição:** SMS recebido. Tela de verificação SMS exibida.

**Passos:**
1. Aguardar iOS detectar o código OTP no SMS.
2. Sugestão de código aparece acima do teclado.
3. Tocar na sugestão.

**Resultado esperado `[PASS]`:**
- Campos preenchidos automaticamente via hidden field com `AutofillHints.oneTimeCode`.
- Auto-submit acionado.

---

## 9. Tela de Escolha do Método de Verificação

### TC-501 — Exibição correta da tela de escolha
**Prioridade:** 🔴 Crítico
**Pré-condição:** Signup realizado com sucesso.

**Passos:**
1. Verificar a tela "Verify Your Account".

**Resultado esperado `[PASS]`:**
- Título: "Verify Your Account".
- Subtítulo: "Choose how you want to verify your account".
- Card "Verify via Email" ativo com subtitle mostrando o email do usuário.
- Card "Verify via SMS" com estado condicionado à feature flag.
- Botão de voltar funcional.

---

### TC-502 — Voltar da tela de escolha para Welcome Screen
**Prioridade:** 🟢 Médio
**Pré-condição:** Tela de escolha de método exibida.

**Passos:**
1. Tocar no botão de voltar.

**Resultado esperado `[PASS]`:**
- App retorna para a Welcome Screen (via `GoBackEvent` no `AuthBloc`).

---

## 10. Apple Login

> **Importante:** Apple Login só funciona em dispositivos físicos iOS ou macOS com Apple ID configurado. Não funciona em simulador sem ajustes específicos.

---

### TC-601 — Apple Login na tela de signup (botão "Continue with Apple")
**Prioridade:** 🔴 Crítico
**Plataforma:** iOS (device físico)
**Pré-condição:** Welcome Screen exibida. Apple ID válido disponível.

**Passos:**
1. Tocar em `SIGN UP` (ou verificar se há botão de Apple Login na Welcome Screen diretamente).
2. No modal de escolha de método, verificar se há opção de Apple Login.
3. Tocar na opção de Apple Login.
4. Autenticar com Face ID / Touch ID ou senha do Apple ID.
5. Confirmar permissões solicitadas pelo sistema.

**Resultado esperado `[PASS]`:**
- Sheet nativa da Apple é exibida.
- Após autenticação, app processa o callback via `AppleLoginCallbackEvent` ou `AppleWebLoginEvent`.
- Usuário é logado ou criado automaticamente.
- App redireciona para tela principal.
- **Verificar: usuário Apple não deve ser solicitado a verificar email via OTP** (ver TC-602).

---

### TC-602 — Apple Login não pede verificação de email
**Prioridade:** 🔴 Crítico
**Pré-condição:** Usuário que fez login pela primeira vez via Apple Login.

**Passos:**
1. Fazer Apple Login (TC-601).
2. Verificar se o app exibe tela de verificação OTP.

**Resultado esperado `[PASS]`:**
- App **não** redireciona para tela de verificação de email.
- Apple Login users são tratados como já verificados (`verified_at` definido no backend).
- (Referência: commit `bebcb0e` — "Fix app asking for verification for Apple Login users").

---

### TC-603 — Apple Login com conta já existente (re-login)
**Prioridade:** 🔴 Crítico
**Pré-condição:** Usuário já tem conta criada via Apple Login.

**Passos:**
1. Fazer logout.
2. Realizar Apple Login novamente.

**Resultado esperado `[PASS]`:**
- Usuário é logado na conta existente.
- Nenhuma conta duplicada é criada.

---

### TC-604 — Apple Login cancelado pelo usuário
**Prioridade:** 🟡 Alto
**Pré-condição:** Sheet nativa da Apple aberta.

**Passos:**
1. Na sheet da Apple, tocar em "Cancel".

**Resultado esperado `[PASS]`:**
- App retorna à tela anterior (Welcome Screen ou modal de escolha).
- Nenhuma mensagem de erro desnecessária.
- Estado do app permanece consistente.

---

### TC-605 — Apple Login com "Hide My Email" da Apple
**Prioridade:** 🟡 Alto
**Pré-condição:** Apple ID com opção "Hide My Email" disponível.

**Passos:**
1. Iniciar Apple Login.
2. Na sheet da Apple, selecionar "Hide My Email".
3. Confirmar o login.

**Resultado esperado `[PASS]`:**
- App aceita o email relay da Apple (formato: `xxxx@privaterelay.appleid.com`).
- Conta é criada normalmente.
- Verificar se o app lida bem com esse formato de email em exibições internas.

---

### TC-606 — Apple Web Login (para Android ou outros fluxos)
**Prioridade:** 🟡 Alto
**Pré-condição:** Usuário tenta fazer login com Apple em plataforma não-iOS.

**Passos:**
1. Verificar comportamento quando `AppleWebLoginEvent` é disparado.

**Resultado esperado:**
- Verificar com o time de dev se o fluxo de Apple Web Login está habilitado e como deve se comportar em cada plataforma.

---

## 11. Esqueci a Senha (Forgot Password)

### TC-701 — Navegar para a tela "Forgot Password"
**Prioridade:** 🔴 Crítico
**Pré-condição:** App na tela de login.

**Passos:**
1. Localizar o link "Forgot Password?" na tela de login.
2. Tocar nele.

**Resultado esperado `[PASS]`:**
- App navega para a tela de recuperação de senha.
- Campo de email visível.
- Botão de envio (SEND / Reset) visível.

---

### TC-702 — Enviar email de recuperação com email válido e existente
**Prioridade:** 🔴 Crítico
**Pré-condição:** Tela de Forgot Password. Email temporário válido disponível.

**Passos:**
1. Digitar o email cadastrado.
2. Tocar em `SEND` / `Reset`.

**Resultado esperado `[PASS]`:**
- Mensagem de sucesso exibida: "Check your email", "Email sent" ou equivalente.
- Email de reset recebido na caixa de entrada.
- Email contém link de redefinição de senha.

---

### TC-703 — Enviar email de recuperação com email não cadastrado
**Prioridade:** 🟡 Alto
**Pré-condição:** Tela de Forgot Password.

**Passos:**
1. Digitar um email que não existe no sistema.
2. Tocar em `SEND`.

**Resultado esperado `[FAIL]`:**
- Exibe mensagem de erro: "User not found", "Invalid email" ou equivalente.
- **Alternativa de segurança:** Alguns sistemas exibem sempre a mensagem de sucesso para não revelar se um email existe. Verificar com o time qual abordagem foi adotada e validar a consistência.

---

### TC-704 — Enviar email de recuperação com formato de email inválido
**Prioridade:** 🟡 Alto
**Pré-condição:** Tela de Forgot Password.

**Passos:**
1. Digitar email inválido (ex.: `usuario@`).
2. Tocar em `SEND`.

**Resultado esperado `[FAIL]`:**
- Validação de formato de email exibida.
- Nenhuma chamada à API.

---

### TC-705 — Enviar email de recuperação com campo vazio
**Prioridade:** 🟡 Alto
**Pré-condição:** Tela de Forgot Password.

**Passos:**
1. Deixar o campo de email vazio.
2. Tocar em `SEND`.

**Resultado esperado `[FAIL]`:**
- Validação de campo obrigatório.

---

### TC-706 — Email de reset recebido com link funcional
**Prioridade:** 🔴 Crítico
**Pré-condição:** Email de reset recebido (TC-702).

**Passos:**
1. Abrir o email.
2. Verificar o conteúdo do email.
3. Tocar/clicar no link de reset.

**Resultado esperado `[PASS]`:**
- Link está presente no corpo do email.
- Link contém parâmetro `token` válido na URL.
- Ao tocar no link, app é aberto na tela de redefinição de senha (deep link).

---

## 12. Redefinição de Senha (Reset Password)

### TC-801 — Acessar tela de redefinição via deep link
**Prioridade:** 🔴 Crítico
**Pré-condição:** Link de reset recebido por email. App instalado.

**Passos:**
1. Tocar no link de reset no email.
2. Confirmar abertura no app (se solicitado pelo SO).

**Resultado esperado `[PASS]`:**
- App abre na tela de redefinição de senha (`ResetPasswordScreen`).
- Dois campos de senha visíveis (nova senha e confirmação).
- Botão `UPDATE PASSWORD` visível.

---

### TC-802 — Redefinir senha com sucesso
**Prioridade:** 🔴 Crítico
**Pré-condição:** Tela de redefinição de senha aberta com token válido.

**Passos:**
1. Digitar nova senha (ex.: `NovaSenha@456`).
2. Confirmar a nova senha com o mesmo valor.
3. Tocar em `UPDATE PASSWORD`.
4. Se dialog de confirmação aparecer ("Yes, Update"), confirmar.

**Resultado esperado `[PASS]`:**
- Dialog de sucesso exibido.
- Após confirmar ("Continue"), app redireciona para a tela principal (usuário logado).
- Testar login com a senha antiga — deve falhar.
- Testar login com a nova senha — deve funcionar.

---

### TC-803 — Redefinir senha com senhas que não conferem
**Prioridade:** 🟡 Alto
**Pré-condição:** Tela de redefinição de senha aberta.

**Passos:**
1. Digitar nova senha.
2. Confirmar com senha diferente.
3. Tocar em `UPDATE PASSWORD`.

**Resultado esperado `[FAIL]`:**
- Mensagem de erro exibida.
- Senha não é alterada.

---

### TC-804 — Usar link de reset expirado
**Prioridade:** 🔴 Crítico
**Pré-condição:** Link de reset recebido por email. Aguardar a expiração do token.

**Passos:**
1. Aguardar o token expirar.
2. Tocar no link expirado.

**Resultado esperado `[FAIL]`:**
- Mensagem de erro informando que o link expirou.
- App oferece opção de solicitar novo email de reset.

---

### TC-805 — Usar link de reset já utilizado
**Prioridade:** 🔴 Crítico
**Pré-condição:** Link de reset já foi utilizado com sucesso.

**Passos:**
1. Tentar usar o mesmo link novamente.

**Resultado esperado `[FAIL]`:**
- Mensagem de erro informando que o link não é mais válido.

---

### TC-806 — Redefinição de senha com token inválido/manipulado
**Prioridade:** 🔴 Crítico
**Pré-condição:** Link de reset recebido.

**Passos:**
1. Copiar o link de reset.
2. Modificar manualmente o token na URL.
3. Abrir o link modificado no app.

**Resultado esperado `[FAIL]`:**
- App exibe erro de token inválido.
- Nenhuma senha é alterada.

---

## 13. Login por Perfis/Roles

### TC-901 — Login como usuário regular
**Prioridade:** 🔴 Crítico
**Pré-condição:** Credenciais de usuário `regular` disponíveis.

**Passos:**
1. Realizar login com conta de role `regular`.

**Resultado esperado `[PASS]`:**
- Login bem-sucedido.
- Interface exibe funcionalidades de usuário regular.
- Não há acesso a funcionalidades de admin.

---

### TC-902 — Login como usuário admin
**Prioridade:** 🔴 Crítico
**Pré-condição:** Credenciais de usuário `admin` disponíveis.

**Passos:**
1. Realizar login com conta de role `admin`.

**Resultado esperado `[PASS]`:**
- Login bem-sucedido.
- Interface exibe funcionalidades de administrador para a organização gerenciada.

---

### TC-903 — Login como superadmin
**Prioridade:** 🔴 Crítico
**Pré-condição:** Credenciais de usuário `superadmin` disponíveis.

**Passos:**
1. Realizar login com conta de role `superadmin`.

**Resultado esperado `[PASS]`:**
- Login bem-sucedido.
- Interface exibe funcionalidades de superadmin.

---

### TC-904 — Permissões por role após login
**Prioridade:** 🟡 Alto
**Pré-condição:** Login realizado com diferentes roles.

**Passos:**
1. Logar como `regular` — verificar que funcionalidades de admin não estão acessíveis.
2. Logar como `admin` — verificar que funcionalidades de superadmin não estão acessíveis.
3. Logar como `superadmin` — verificar acesso total.

**Resultado esperado `[PASS]`:**
- Cada role tem acesso estritamente às funcionalidades correspondentes.

---

## 14. Logout

### TC-1001 — Logout do usuário logado
**Prioridade:** 🔴 Crítico
**Pré-condição:** Usuário logado na tela principal.

**Passos:**
1. Localizar a opção de logout (menu, perfil, configurações).
2. Tocar em logout.
3. Confirmar se houver dialog de confirmação.

**Resultado esperado `[PASS]`:**
- Sessão encerrada.
- App retorna à Welcome Screen.
- Dados sensíveis da sessão limpos.
- Token inválido (não é possível fazer chamadas autenticadas).

---

### TC-1002 — Tentar acessar tela protegida após logout
**Prioridade:** 🔴 Crítico
**Pré-condição:** Logout realizado (TC-1001).

**Passos:**
1. Tentar navegar para tela principal via navegação do SO (botão voltar).

**Resultado esperado `[PASS]`:**
- App redireciona para Welcome Screen.
- Nenhuma tela protegida é acessível.

---

## 15. Testes de Falha e Edge Cases

### TC-1101 — Sem conexão com internet durante login
**Prioridade:** 🔴 Crítico
**Pré-condição:** Dispositivo sem conexão com internet (modo avião).

**Passos:**
1. Ativar modo avião.
2. Tentar fazer login com credenciais válidas.

**Resultado esperado `[FAIL]`:**
- Mensagem de erro de conexão exibida (não crash).
- Usuário permanece na tela de login.
- App não trava.

---

### TC-1102 — Sem conexão durante signup
**Prioridade:** 🔴 Crítico
**Pré-condição:** Dispositivo sem conexão.

**Passos:**
1. Ativar modo avião.
2. Tentar criar uma nova conta.

**Resultado esperado `[FAIL]`:**
- Mensagem de erro de conexão.
- App não trava.

---

### TC-1103 — Sem conexão durante verificação OTP
**Prioridade:** 🔴 Crítico
**Pré-condição:** Tela de OTP exibida. Desativar internet após receber o código.

**Passos:**
1. Ativar modo avião.
2. Digitar o código correto.
3. Tocar em `Verify Code`.

**Resultado esperado `[FAIL]`:**
- Mensagem de erro de conexão.
- App não trava.

---

### TC-1104 — Conexão lenta (simulação de 3G/Edge)
**Prioridade:** 🟡 Alto
**Pré-condição:** Usar ferramentas de throttling de rede no simulador/emulador.

**Passos:**
1. Configurar conexão lenta.
2. Realizar login.

**Resultado esperado `[PASS]`:**
- Loading indicator visível durante a espera.
- App não trava nem exibe timeout prematuro.
- Login é concluído quando a resposta chega.

---

### TC-1105 — Timeout de API durante login
**Prioridade:** 🟡 Alto
**Pré-condição:** Backend configurado para demorar mais que o timeout do cliente (ou simular).

**Passos:**
1. Tentar login em condição de timeout.

**Resultado esperado `[FAIL]`:**
- Mensagem de timeout/erro de rede exibida.
- App não trava.
- Botão de login volta ao estado interativo.

---

### TC-1106 — Múltiplos toques rápidos no botão de login
**Prioridade:** 🟢 Médio
**Pré-condição:** App na tela de login.

**Passos:**
1. Preencher campos válidos.
2. Tocar rapidamente no botão `LOGIN` múltiplas vezes.

**Resultado esperado `[PASS]`:**
- Apenas uma requisição é enviada.
- Botão desabilitado durante loading para prevenir duplo clique.

---

### TC-1107 — Texto muito longo nos campos
**Prioridade:** 🟢 Médio
**Pré-condição:** App na tela de login ou signup.

**Passos:**
1. Colar texto muito longo (500+ caracteres) nos campos de email e nome.
2. Tentar submeter.

**Resultado esperado `[PASS]`:**
- Campo trunca ou exibe erro de validação.
- App não trava.
- UI não quebra.

---

### TC-1108 — Injeção de caracteres especiais/scripts nos campos
**Prioridade:** 🔴 Crítico (segurança)
**Pré-condição:** App na tela de login ou signup.

**Passos:**
1. Digitar em email: `<script>alert('xss')</script>@teste.com`.
2. Digitar em nome: `'; DROP TABLE users; --`.
3. Tentar submeter.

**Resultado esperado `[PASS]`:**
- App trata como input inválido ou backend rejeita.
- Nenhum código é executado.
- Nenhum crash ocorre.

---

### TC-1109 — App em background e retorno durante verificação OTP
**Prioridade:** 🟡 Alto
**Pré-condição:** Tela de OTP exibida.

**Passos:**
1. Colocar app em background.
2. Abrir o email/SMS para copiar o código.
3. Retornar ao app.

**Resultado esperado `[PASS]`:**
- App está no mesmo estado (tela de OTP).
- Campos ainda visíveis e interativos.
- Código pode ser digitado normalmente.

---

### TC-1110 — Rotação de tela durante processo de login
**Prioridade:** 🟢 Médio
**Pré-condição:** App na tela de login ou signup com campos preenchidos.

**Passos:**
1. Rotacionar o dispositivo para landscape.
2. Verificar a UI.

**Resultado esperado `[PASS]`:**
- UI se adapta (ou mantém orientação se bloqueada).
- Dados digitados não são perdidos.

---

## 16. Testes de Acessibilidade e UX

### TC-1201 — Feedback tátil (haptic feedback) nos botões
**Prioridade:** ⚪ Baixo
**Passos:**
1. Verificar se botões de login/signup fornecem feedback tátil ao toque.

---

### TC-1202 — Contraste e legibilidade dos textos de erro
**Prioridade:** 🟢 Médio
**Passos:**
1. Verificar que mensagens de erro (vermelho) têm contraste suficiente com o fundo.

---

### TC-1203 — Teclado correto para cada campo
**Prioridade:** 🟡 Alto
**Passos:**
1. Verificar que o campo de email abre teclado com `@` acessível.
2. Verificar que campos de OTP abrem teclado numérico.
3. Verificar que campo de telefone abre teclado de telefone.
4. Verificar que campos de senha ocultam texto corretamente.

---

### TC-1204 — Mensagens de erro claras e em português (se app é PT-BR)
**Prioridade:** 🟡 Alto
**Passos:**
1. Provocar diferentes erros no fluxo de login/signup.
2. Verificar que as mensagens são compreensíveis pelo usuário final.
3. Reportar qualquer mensagem em inglês técnico ou código de erro que apareça para o usuário.

---

## 17. Testes em Plataformas Específicas

### iOS

| Teste | Prioridade |
|---|---|
| Face ID / Touch ID não bloqueia o fluxo de Apple Login | 🔴 |
| Autofill de OTP via iMessage (oneTimeCode) | 🟡 |
| Deep link de reset abre app corretamente | 🔴 |
| Modal bottom sheet responde ao swipe-to-dismiss | 🟢 |
| App não trava ao voltar do sistema de Apple Login | 🔴 |

### Android

| Teste | Prioridade |
|---|---|
| Deep link de reset abre app corretamente | 🔴 |
| Teclado numérico correto no OTP (sem letras) | 🟡 |
| Back button do Android no fluxo de login | 🟡 |
| SMS autofill (se configurado no Android) | 🟡 |

---

## 18. Checklist Geral de Regressão

Use esta lista após qualquer alteração no código de autenticação:

### Login
- [ ] Login com credenciais válidas (regular, admin, superadmin)
- [ ] Login com credenciais inválidas mostra erro
- [ ] Botão `CONTINUE WITH EMAIL` funciona
- [ ] Logout funcional e limpa sessão

### Signup
- [ ] Signup completo com email novo
- [ ] Validação de senhas que não conferem
- [ ] Validação de email já cadastrado
- [ ] Tela de explicação OTP exibida após signup

### Verificação de Email OTP
- [ ] Email de verificação recebido em até 2 minutos
- [ ] Código correto verifica a conta
- [ ] Código incorreto mostra erro
- [ ] Auto-submit ao completar 6 dígitos
- [ ] Reenvio de código funciona
- [ ] Botão "Clear Code" funciona

### Verificação SMS OTP (quando feature flag ON)
- [ ] Card SMS desabilitado quando flag OFF (badge "Soon")
- [ ] Bottom sheet de número de telefone abre corretamente
- [ ] SMS recebido após submissão
- [ ] Código SMS correto verifica conta
- [ ] Botão voltar retorna para escolha de método

### Apple Login
- [ ] Apple Login flui até a tela principal sem pedir OTP
- [ ] Conta existente não é duplicada no re-login
- [ ] Cancelamento não causa crash

### Forgot/Reset Password
- [ ] Email de reset recebido com link válido
- [ ] Link abre app na tela de redefinição
- [ ] Nova senha funciona no login
- [ ] Link expirado/usado mostra erro

### Edge Cases
- [ ] Sem internet mostra erro (não crash)
- [ ] Duplo clique no botão não duplica requisição

---

## Notas para o Time QA

1. **Feature flags:** Sempre confirmar com o time dev quais flags estão ativas no ambiente de QA antes de executar testes dependentes delas (`smsVerificationEnabled`, etc.).

2. **Contas de teste:** Nunca usar contas de produção. Usar o script `integration_test/scripts/create_test_user.py` para criar usuários de teste ou o script `setup_qa_test_users.sh`.

3. **Limpeza pós-teste:** Usar `delete_test_user.py` para limpar contas criadas durante os testes, especialmente em ambiente compartilhado.

4. **Deep links:** Para testar links de reset/verificação, verificar a configuração de deeplinks no arquivo `scripts/auth/deeplinks.sh`.

5. **Logs:** Em ambiente QA (flavor development), o app imprime logs detalhados no console. Use esses logs para confirmar o fluxo quando a UI não for conclusiva.

6. **Reporte de bugs:** Incluir sempre: plataforma (iOS/Android + versão), flavor do app, passos para reproduzir, resultado esperado vs. resultado obtido, e screenshots/vídeos.

---

*Documento mantido pelo time de Engenharia. Para atualizar, editar `docs/qa_login_signup_test_guide.md`.*
