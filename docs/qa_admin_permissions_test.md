# Roteiro de Teste QA — Promoção de Admin e Permissões de Canal

> **Aplicativo:** mvc_app (Flutter)
> **Ambiente de referência:** QA / Development (Flavor)
> **Última atualização:** 2026-05-05
> **Pré-requisito:** Ter acesso às contas QA Admin QA (duas contas separadas — Admin A e Admin B).

---

## Sumário

1. [Contas utilizadas neste roteiro](#1-contas-utilizadas-neste-roteiro)
2. [Roteiro base — Criar usuário, promover a admin e verificar permissões](#2-roteiro-base--criar-usuário-promover-a-admin-e-verificar-permissões)
3. [Branch A — O próprio usuário se remove da lista de admins](#3-branch-a--o-próprio-usuário-se-remove-da-lista-de-admins)
4. [Branch B — Outro admin remove o usuário da lista de admins](#4-branch-b--outro-admin-remove-o-usuário-da-lista-de-admins)

---

## 1. Contas utilizadas neste roteiro

| Referência neste doc | Role | Descrição |
|---|---|---|
| **Usuário Teste** | Regular (novo) | Conta criada durante o roteiro |
| **Admin A** | Admin QA | Primeira conta QA Admin QA — usada para promover o Usuário Teste |
| **Admin B** | Admin QA | Segunda conta QA Admin QA — usada na Branch B para remover o Usuário Teste |

> Confirme as credenciais das contas Admin A e Admin B com o time antes de começar. As duas devem ser administradoras do mesmo canal no ambiente QA.

---

## 2. Roteiro base — Criar usuário, promover a admin e verificar permissões

### Parte 1 — Criar o Usuário Teste (conta regular)

**Dispositivo:** qualquer (iOS ou Android).

1. Abrir o app no flavor **QA/Development**.
2. Tocar em `SIGN UP`.
3. Tocar em `CONTINUE WITH EMAIL`.
4. Preencher os dados:
   - **Nome:** `Teste Admin Permissão` (ou qualquer nome identificável)
   - **Email:** use um alias Gmail, ex.: `seuemail+qa_perm_01@gmail.com`
   - **Senha:** `Senha@Forte123` (ou qualquer senha que atenda aos requisitos)
5. Tocar em `SIGN UP`.
6. Verificar o email e completar a verificação via OTP.
7. Confirmar que o app redireciona para a tela principal — o usuário está logado como regular.
8. **Anotar:** o email e senha usados. Você precisará logar nessa conta mais tarde.
9. Fazer **logout** desse dispositivo.

---

### Parte 2 — Promover o Usuário Teste a admin (usando Admin A)

**Dispositivo:** mesmo ou outro — logar como **Admin A**.

1. Fazer login com a conta **Admin A**.
2. Navegar até `Manage` (menu de gerenciamento da organização).
3. Entrar em `Channels`.
4. Selecionar o canal de teste QA.
5. Tocar em `Manage Admins`.
6. Localizar o **Usuário Teste** (pelo nome ou email cadastrado).
7. Adicioná-lo como admin do canal.
8. Confirmar que o nome aparece na lista de admins.
9. Fazer **logout** do Admin A (ou trocar de dispositivo).

---

### Parte 3 — Verificar permissões do Usuário Teste como admin

**Dispositivo:** logar como **Usuário Teste**.

1. Fazer login com o email e senha do Usuário Teste.
2. Navegar até o canal onde foi promovido.

Verificar cada permissão abaixo e anotar o resultado (`OK` / `Não aparece` / `Erro`):

| # | Permissão | Como testar | Resultado |
|---|---|---|---|
| P-01 | Criar post | Tentar publicar uma nova mensagem/post no canal | |
| P-02 | Responder mensagem | Tocar em uma mensagem existente e usar a opção de resposta (reply/thread) | |
| P-03 | Ver seguidores do próprio canal | Acessar o perfil do canal e verificar se a lista de seguidores (followers) está visível | |

> **Resultado esperado:** todas as três permissões devem estar disponíveis e funcionando para um usuário admin.

---

A partir daqui o roteiro se divide em duas branches. **Escolha uma e execute até o fim antes de executar a outra** (ou use dois dispositivos separados para não misturar estados de sessão).

---

## 3. Branch A — O próprio usuário se remove da lista de admins

**Contexto:** verificar o que acontece com as permissões quando o admin se auto-remove, tanto sem fechar o app quanto após reiniciá-lo.

**Dispositivo:** logado como **Usuário Teste**.

### Passo A-1 — Auto-remoção da lista de admins

1. Ainda logado como Usuário Teste, navegar até `Manage` → `Channels` → canal de teste QA → `Manage Admins`.
2. Localizar o próprio nome na lista de admins.
3. Remover-se da lista (tocar na opção de remover/revogar admin).
4. Confirmar a remoção.

---

### Passo A-2 — Verificar permissões SEM fechar o app

> **Não feche o app ainda.** Permaneça na mesma sessão ativa.

Retornar ao canal e tentar cada ação abaixo. Anotar o que acontece imediatamente após a remoção:

| # | Ação | O que acontece? (descrever) |
|---|---|---|
| A-01 | Tentar criar um novo post no canal | |
| A-02 | Tentar responder uma mensagem existente | |
| A-03 | Tentar visualizar a lista de seguidores do canal | |

> **O que observar:** as permissões são revogadas imediatamente na UI? Aparece algum erro ou loading? Os botões somem ou ficam desabilitados? A mudança é instantânea ou o app parece não ter percebido ainda?

---

### Passo A-3 — Fechar e reabrir o app, verificar permissões novamente

1. Fechar o app completamente (remover da lista de apps recentes).
2. Reabrir o app.
3. Confirmar que o login é restaurado automaticamente (sessão persistida).
4. Navegar até o mesmo canal.

Verificar novamente cada ação:

| # | Ação | O que acontece após reiniciar? (descrever) |
|---|---|---|
| A-04 | Tentar criar um novo post no canal | |
| A-05 | Tentar responder uma mensagem existente | |
| A-06 | Tentar visualizar a lista de seguidores do canal | |

> **O que observar:** o comportamento após reiniciar é igual ao observado em A-01/A-02/A-03? Houve diferença? O estado de permissões foi atualizado corretamente após o restart?

---

### Checklist Branch A

- [ ] Usuário conseguiu se auto-remover da lista de admins
- [ ] Permissões verificadas imediatamente após a remoção (sem fechar o app)
- [ ] Permissões verificadas após fechar e reabrir o app
- [ ] Diferença entre os dois momentos anotada (se houver)

---

## 4. Branch B — Outro admin remove o usuário da lista de admins

**Contexto:** verificar o que acontece com as permissões do Usuário Teste quando outro admin (Admin B) o remove, enquanto ele está com o app aberto — e depois do restart.

**Dispositivos necessários:** idealmente dois dispositivos em paralelo (ou alternando rapidamente).

---

### Passo B-1 — Deixar o Usuário Teste logado e ativo no canal

**Dispositivo 1 (Usuário Teste):**
1. Fazer login como Usuário Teste.
2. Navegar até o canal de teste QA.
3. Deixar o app em primeiro plano, aberto no canal.

---

### Passo B-2 — Admin B remove o Usuário Teste da lista de admins

**Dispositivo 2 (Admin B):**
1. Fazer login como **Admin B**.
2. Navegar até `Manage` → `Channels` → canal de teste QA → `Manage Admins`.
3. Localizar o **Usuário Teste** na lista de admins.
4. Remover o Usuário Teste da lista.
5. Confirmar a remoção.

---

### Passo B-3 — Verificar permissões no Dispositivo 1 SEM fechar o app

**Dispositivo 1 (Usuário Teste) — app ainda aberto:**

> **Não feche o app.** Retornar ao canal no Dispositivo 1 e tentar cada ação.

| # | Ação | O que acontece? (descrever) |
|---|---|---|
| B-01 | Tentar criar um novo post no canal | |
| B-02 | Tentar responder uma mensagem existente | |
| B-03 | Tentar visualizar a lista de seguidores do canal | |

> **O que observar:** o app reagiu em tempo real à remoção feita por Admin B? Houve alguma notificação ou mudança de UI imediata? As permissões foram revogadas automaticamente sem o Usuário Teste precisar reiniciar?

---

### Passo B-4 — Fechar e reabrir o app no Dispositivo 1, verificar novamente

**Dispositivo 1 (Usuário Teste):**
1. Fechar o app completamente.
2. Reabrir o app.
3. Confirmar que o login é restaurado.
4. Navegar até o mesmo canal.

| # | Ação | O que acontece após reiniciar? (descrever) |
|---|---|---|
| B-04 | Tentar criar um novo post no canal | |
| B-05 | Tentar responder uma mensagem existente | |
| B-06 | Tentar visualizar a lista de seguidores do canal | |

> **O que observar:** o comportamento após reiniciar é diferente de B-01/B-02/B-03? O app buscou as permissões atualizadas do servidor ao reiniciar?

---

### Checklist Branch B

- [ ] Admin B conseguiu remover o Usuário Teste da lista de admins
- [ ] Permissões verificadas no Dispositivo 1 enquanto o app estava aberto (em tempo real)
- [ ] Permissões verificadas no Dispositivo 1 após fechar e reabrir o app
- [ ] Diferença de comportamento entre "tempo real" e "após restart" anotada

---

## Comparação final entre branches

Após executar as duas branches, preencher a tabela comparativa:

| Cenário | Permissões revogadas em tempo real? | Permissões revogadas após restart? | Observações |
|---|---|---|---|
| Branch A — auto-remoção | | | |
| Branch B — remoção por outro admin | | | |

> Compartilhe essa tabela preenchida com o time de engenharia — especialmente se houver inconsistência entre os cenários.

---

*Documento mantido pelo time de QA. Para atualizar, editar `docs/qa_admin_permissions_test.md`.*
