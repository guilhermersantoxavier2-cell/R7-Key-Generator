# R7 Key Generator — Vercel + Supabase

Esta versão substitui o armazenamento em `data.json` por PostgreSQL no Supabase, necessário para não perder as Keys em funções serverless da Vercel.

## 1. Criar o banco
1. Crie um projeto no Supabase.
2. Abra **SQL Editor**.
3. Cole e execute todo o conteúdo de `supabase.sql`.

## 2. Configurar o projeto na Vercel
1. Coloque o conteúdo desta pasta em um repositório GitHub.
2. Na Vercel, importe esse repositório como um novo projeto.
3. Em **Settings → Environment Variables**, adicione:
   - `SUPABASE_URL` = URL do projeto Supabase.
   - `SUPABASE_SECRET_KEY` = chave secreta do projeto Supabase (`sb_secret_...`).
4. Salve e faça um novo Deploy.

A chave secreta fica apenas no backend. Nunca coloque `SUPABASE_SECRET_KEY` em `public/`, no JavaScript do navegador ou no código da GUI.

## 3. Testar
Abra o endereço `.vercel.app` e:
- clique em Começar Missões;
- aguarde 2 minutos em cada missão;
- conclua as quatro;
- copie a KEY;
- teste em Validar uma KEY.

Endpoints:
- `POST /api/start`
- `GET /api/status` com header `x-session-id`
- `POST /api/continue` com header `x-session-id`
- `POST /api/validate` com JSON `{ "key": "R7-..." }`

## Observações importantes
- Cada missão exige 2 minutos confirmados pelo banco de dados; o navegador não controla o relógio oficial.
- A validade de 24 horas começa quando a quarta missão é concluída.
- O banco guarda o hash SHA-256 da KEY, não o texto original.
- A KEY em texto é mostrada uma vez e salva no armazenamento local do navegador para permitir copiá-la novamente no mesmo navegador.
- Esta etapa ainda não vincula a KEY a uma conta Roblox. A vinculação por `UserId` será feita na integração posterior com a GUI, por um endpoint de resgate atômico no backend.
- Para produção, acrescente limitação de requisições, monitoramento e política contra abuso.

## Rodar localmente
Requer Node.js 20+:
1. `npm.cmd install`
2. Defina `SUPABASE_URL` e `SUPABASE_SECRET_KEY` no ambiente.
3. `npm.cmd start`
4. Abra `http://localhost:3000`.
