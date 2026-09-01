# Suporte a downloads por commit / PR (plano)

Este documento registra o plano para adicionar suporte a downloads por commit SHA ou PR específico no projeto.

Checklist
- [ ] Detectar input do tipo commit SHA ou referência de PR
- [ ] Implementar fluxo padrão: clone + checkout do commit (recomendado)
- [ ] Implementar fluxo alternativo: download de archive (/tarball|/zipball) com suporte a ExpectedDigest
- [ ] Adicionar flags/flags equivalentes em PowerShell e Bash (-CloneCommit/--commit-clone, -ArchiveCommit/--commit-archive, -NoVerify/--no-verify, -ExpectedDigest)
- [ ] Emitir aviso claro quando verificação estiver desativada
- [ ] Garantir que releases com `asset.digest` mantenham verificação obrigatória quando configurado
- [ ] Adicionar testes unitários (bats + Pester) cobrindo clone, archive com digest, archive sem digest + aviso
- [ ] Atualizar README/docs com seção "downloads por commit/PR"

Resumo da decisão recomendada

- Para commits/PRs: tornar a verificação opcional, porém usar por padrão o fluxo mais seguro (clone + checkout) quando o `git` estiver disponível.
- Para downloads de release que possuem `asset.digest`: manter verificação automática como hoje.
- Quando o usuário pedir explicitamente o download de archive sem digest, mostrar aviso e exigir opt-in via flag.

Design técnico (alto nível)

1. Detecção
   - Reconhecer SHA/PR por regex (ex.: `^[0-9a-f]{7,40}$` para SHA; `refs/pull/` ou `pr/` para PRs) e via parâmetro explícito.

2. Fluxo recomendado (padrão) — Clone + checkout
   - Requer `git`.
   - Criar diretório temporário, `git init`, `git remote add origin <repo>`, `git fetch --depth=1 origin <sha>` (ou `git fetch origin <sha>`) e `git checkout FETCH_HEAD`.
   - Vantagem: obtém exatamente o commit e permite inspeção local; não depende de digests publicados.

3. Fluxo alternativo — Download de archive
   - Construir URL do GitHub: `https://github.com/<owner>/<repo>/tarball/<sha>` ou via API.
   - Se `ExpectedDigest` for fornecido, verificar; se não for, exigir flag `--no-verify`/`-NoVerify` e emitir aviso claro.

4. Flags e variáveis
   - Bash: `--commit-clone` (default para SHA), `--commit-archive`, `--no-verify`, `--expected-digest <sha256>`
   - PowerShell: `-CloneCommit` (default), `-ArchiveCommit`, `-NoVerify`, `-ExpectedDigest`
   - Variáveis de ambiente (opcionais): `REQUIRE_VERIFY`, `ALLOW_COMMIT_NO_VERIFY` — preferir flags CLI para clareza.

5. Mensagens e documentação
   - Mensagem padrão ao desativar verificação: "AVISO: verificação de integridade desativada para commits/PRs — use com cautela."
   - Documentar riscos e exemplos no README.

Arquivos-alvo para alteração

- `Download-Llvm-Enhanced.ps1` — detectar SHA/PR, implementar clone path, adicionar flags e mensagens
- `Download-Llvm.ps1` — pequena adaptação para parity
- `llvm-prebuilt` (bash) — detectar SHA e chamar fluxo correto (ou delegar para `llvm-build`)
- `llvm-build` (bash) — aceitar commit SHA (fetch + checkout) além de tags
- `Install-Llvm.ps1` — expor flags novos para fluxo de instalação
- `tests/unit/*` (bats) e `tests/unit/Download-Llvm.Tests.ps1` (Pester) — adicionar testes

Testes sugeridos (rápidos)

- Clone-by-commit (mock `git`): verifica que o script usa `git fetch` e `git checkout` quando a versão é SHA.
- Archive-with-digest: simula download do archive + verifica quando `--expected-digest` fornecido.
- Commit-without-verify: simula archive sem digest e `--no-verify`, checa que há aviso e que o download procede somente com opt-in.

Próximos passos

- (A) Implementar alterações no `Download-Llvm-Enhanced.ps1` e em `llvm-build` (espelhar em outros scripts)
- (B) Escrever os testes unitários correspondentes (bats e Pester)
- (C) Atualizar README.md com seção curta sobre riscos e flags

Notas finais

Esta abordagem equilibra segurança e praticidade para desenvolvedores que testam commits/PRs upstream. A verificação pode ser opcional para commits/PRs, desde que o comportamento seja explícito e que o clone+checkout seja o padrão quando possível.
