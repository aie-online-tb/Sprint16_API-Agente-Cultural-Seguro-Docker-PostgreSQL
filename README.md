![Cabecera](./assets/cabecera_thebridge.png)

# Workout — API agente cultural + Docker + PostgreSQL

**La API y el agente ya vienen dados** (tools, RAG, historial, API key, rate limit, CORS, timeout).  
Aquí el foco es: **PostgreSQL** (contenedor) + **pgAdmin** + **Docker** de la API + (opcional) **Render**.

```text
cliente → /ask?api_key=... → agente (uvicorn o contenedor)
                                    │
                                    ▼
                            PostgreSQL (:5432)
                                    ▲
                               pgAdmin (visor)
```

## Estructura

```text
.
├── app.py
├── schemas.py
├── config.py          # DATABASE_URL (Postgres), API_KEY, GEMINI, …
├── security.py
├── rate_limit.py
├── gemini_auth.py
├── src/               # agente + SQLModel (dado)
├── data/              # guía + fallback eventos
├── assets/            # cartel_demo.jpg
├── Dockerfile
├── .dockerignore
├── requirements.txt
├── .env.example
└── README.md
```

---

## 1) PostgreSQL en Docker

Levantamos un contenedor con el servidor de PostgreSQL en local (Docker Desktop debe estar abierto).

```bash
docker run --name agente-pg -e POSTGRES_PASSWORD=123456 -d -p 5432:5432 postgres
```

| Pieza | Significado |
|-------|-------------|
| `--name agente-pg` | Nombre del contenedor |
| `POSTGRES_PASSWORD=123456` | Contraseña del usuario `postgres` |
| `-p 5432:5432` | Acceso desde el PC en `localhost:5432` |
| `-d` | En segundo plano |

Por defecto la BD se llama `postgres` (igual que el usuario).  
Comprobad: `docker ps` → debe aparecer `agente-pg`.

La password del contenedor debe coincidir con la de `DATABASE_URL` en el `.env`.

---

## 2) pgAdmin (visor)

1. Descargad e instalad [pgAdmin 4](https://www.pgadmin.org/download/).
2. Abríd pgAdmin → **Add New Server**.
3. Pestaña **General**: un nombre cualquiera (p. ej. `local-agente`).
4. Pestaña **Connection**:

| Campo | Valor |
|-------|--------|
| Host name/address | `localhost` |
| Port | `5432` |
| Maintenance database | `postgres` |
| Username | `postgres` |
| Password | `123456` (la del contenedor) |

5. Save. En el árbol de la izquierda debería verse el servidor y la BD `postgres`.

Tras unos `/ask`, en esa BD aparecerán las tablas del historial (p. ej. `conversation`, `message`).

---

## 3) Arranque de la API (uvicorn en el PC)

La API corre **en el host** y habla con Postgres por `localhost` (puerto publicado).

Ejecutamos siempre **desde esta carpeta** (donde está `app.py`).

```bash
cp .env.example .env
# Completad: GEMINI_API_KEY, API_KEY
# GEMINI_MODEL ya viene como gemini-3.5-flash-lite (el defecto de config.py)
# Con uvicorn en el PC: usad 127.0.0.1 en DATABASE_URL (descomentad esa línea
# y comentad la de host.docker.internal)

python -m venv .venv
source .venv/bin/activate          # Git Bash / macOS / Linux
# .venv\Scripts\Activate.ps1       # Windows PowerShell

pip install -r requirements.txt
uvicorn app:app --reload --port 8000
```

- Health: [http://127.0.0.1:8000/health](http://127.0.0.1:8000/health) → `storage: postgres`  
- Docs: [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs) — en rutas protegidas: *Try it out* → query **`api_key`**

Sin `DATABASE_URL` la app **no arranca**.

Este es el camino **principal** en local: simple y alineado con pgAdmin en `localhost`.

---

## 4) Empaquetar la API en Docker

Para practicar la imagen (y luego la nube). Postgres sigue en el contenedor `agente-pg` con `-p 5432:5432`.

Desde el contenedor de la API, `127.0.0.1` **no** es vuestro PC. En Windows/macOS usad **`host.docker.internal`** en `DATABASE_URL`:

```text
DATABASE_URL=postgresql://postgres:123456@host.docker.internal:5432/postgres
```

Construimos la imagen de la API.

```bash
docker build -t agente-cultural .
```

Lanza el contenedor de la API con los secretos en runtime.
```bash
docker run --rm --name agente-api -p 8000:8000 --env-file .env agente-cultural
```

| Pieza | Por qué |
|-------|---------|
| `--name agente-api` | Nombre fijo del contenedor |
| `--env-file .env` | Secretos en runtime (no van en la imagen) |
| `.dockerignore` | Evita meter `.env`, `.venv`, `.git` |

### Volver a lanzar tras cambiar código

La imagen se construye con una copia del código (`COPY . .` en el Dockerfile). Un contenedor que ya está en marcha no ve los cambios del editor. Para aplicarlos, en este orden:

```bash
docker rm -f agente-api
docker build -t agente-cultural .
docker run --rm --name agente-api -p 8000:8000 --env-file .env agente-cultural
```

| Comando | Qué hace |
|---------|----------|
| `docker rm -f agente-api` | Para el contenedor anterior y lo borra. Libera el nombre `agente-api`. Sin `-f` solo se puede borrar uno que ya esté parado. Si nunca lo habéis lanzado, este comando avisa que no existe: seguid con el `build`. |
| `docker build -t agente-cultural .` | Reconstruye la imagen con el código actual de esta carpeta. El `.` final es «usa este directorio». `-t` le pone el nombre `agente-cultural`. |
| `docker run …` | Crea un contenedor nuevo a partir de esa imagen. `-p 8000:8000` publica el puerto en vuestro PC. `--env-file .env` inyecta las variables al arrancar (no quedan grabadas en la imagen). `--rm` borra el contenedor al pararlo. |

La terminal se queda mostrando los logs: la API está en marcha. `Ctrl+C` la para y, por el `--rm`, el contenedor desaparece.

### Alternativa: `-e` una a una

```bash
docker run --rm --name agente-api -p 8000:8000 \
  -e API_KEY=cambia-esta-clave \
  -e GEMINI_API_KEY=tu-clave-gemini \
  -e GEMINI_MODEL=gemini-3.5-flash-lite \
  -e DATABASE_URL=postgresql://postgres:123456@host.docker.internal:5432/postgres \
  -e ASK_TIMEOUT_SECONDS=300 \
  -e CORS_ORIGINS=http://127.0.0.1:8501,http://localhost:8501 \
  agente-cultural
```

### Cómo leer el Dockerfile

```dockerfile
# Imagen base oficial de Python (ligera)
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

EXPOSE 8000
CMD uvicorn app:app --host 0.0.0.0 --port ${PORT:-8000}
```

### Comandos útiles

También Docker Desktop: Stop / Start (Play) / Delete.

```bash
docker ps
docker ps -a

docker stop agente-api
# docker stop a1b3c4d5e6f7
# docker stop a1b

docker start agente-api
docker rm agente-api

docker stop agente-pg
docker start agente-pg

docker images
docker rmi agente-cultural
```

**Nota `--rm`:** al hacer `stop` de `agente-api`, el contenedor se borra. Para practicar stop→start, lanzad sin `--rm`.

---

## Rutas

| Método | Ruta | ¿Clave? | Qué hace |
|--------|------|---------|----------|
| GET | `/health` | No | Pulso + `storage: postgres` |
| GET | `/docs` | No | Swagger |
| POST | `/ask` | **Sí** | Un turno; timeout → 504 |
| GET | `/threads/{id}/messages` | **Sí** | Historial en Postgres |

---

## Práctica guiada

Con la API en marcha (uvicorn **o** contenedor `agente-api`) y Postgres en `agente-pg`.  
Sustituid `<CLAVE>` por el valor de `API_KEY` en vuestro `.env`.

Podéis usar **Swagger** ([http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs)) o las URLs de abajo.

### 1) Health sin clave

GET [http://127.0.0.1:8000/health](http://127.0.0.1:8000/health)

→ **200** y algo como:

```json
{"status": "ok", "storage": "postgres"}
```

Si `storage` no es `postgres`, revisad `DATABASE_URL` y que `agente-pg` esté en marcha (`docker ps`).

### 2) Ask sin API KEY → 401

POST `http://127.0.0.1:8000/ask` con body:

```json
{
  "pregunta": "¿Hay algo cultural esta tarde?",
  "thread_id": "demo-1",
  "auto_aprobar": true
}
```

→ **401** (sin `?api_key=`).

### 3) Ask con API KEY → 200

POST `http://127.0.0.1:8000/ask?api_key=<CLAVE>` con el **mismo body** → **200** y una `respuesta`.

Hace falta `GEMINI_API_KEY` válida en el `.env`.

En consola deberíais ver un log tipo `POST /ask thread_id=demo-1 duration_ms=...`.

### 4) Historial con clave

GET `http://127.0.0.1:8000/threads/demo-1/messages?api_key=<CLAVE>`

→ lista de mensajes `user` / `assistant` guardados en PostgreSQL.

### 5) Comprobar en pgAdmin

1. Abríd el servidor → BD `postgres` → Schemas → Tables.
2. Tras el `/ask` del paso 3 deberían existir tablas del historial (p. ej. `conversation`, `message`) con filas nuevas.
3. Refrescad el árbol (F5) si no las veis aún.

### 6) Tras empaquetar en Docker

1. Parad uvicorn (Ctrl+C) para liberar el puerto `8000`.
2. En `.env`, `DATABASE_URL` con `host.docker.internal` (como en `.env.example`).
3. `docker build` + `docker run` (sección 4).
4. Repetid los pasos 1–4 contra `http://127.0.0.1:8000` (mismo puerto, ahora el contenedor).

---

## Render (nube)

Primero la base de datos. Después el servicio web, en la **misma región** que el Postgres.

### 1) Crear PostgreSQL en Render

1. Entrad en el [dashboard de Render](https://dashboard.render.com/).
2. **New** → **PostgreSQL**.
3. Poned un nombre (p. ej. `agente-pg`), la región y el plan. El resto puede quedarse por defecto (usuario, nombre de la BD y versión).
4. **Create Database**. Esperad a que el estado pase a **Available**.

En la ficha de la base, pestaña **Connections**, Render muestra los datos reales. Los de abajo son un **ejemplo** (sustituidlos por los vuestros):

- **Host**: `dpg-abc123xyz.render.com`
- **Puerto**: `5432`
- **Usuario**: `render_user`
- **Contraseña**: `render_password`
- **Base de datos**: `render_db`

Con esos mismos datos, la variable de la API queda así. Pegadla en el Web Service como `DATABASE_URL` (o copiad la **Internal Database URL** del panel, que ya viene montada):

```text
DATABASE_URL=postgresql://render_user:render_password@dpg-abc123xyz.render.com:5432/render_db
```

`127.0.0.1` y `host.docker.internal` aquí no valen: Postgres ya no está en el portátil. Si la URL de Render empieza por `postgres://`, `config.py` la pasa a `postgresql://`.

Para la API **dentro de Render** usad la **Internal Database URL** (el host corto, solo resoluble desde Render). Para pgAdmin en el PC, el host externo del ejemplo. Las tablas (`conversation`, `message`) no hace falta crearlas a mano: la API las crea al arrancar.

### 2) Verla en pgAdmin

1. En el panel izquierdo, clic derecho en **Servers** → **Create** → **Server**.
2. Pestaña **General**: un nombre, por ejemplo `RenderDB`.
3. Pestaña **Connection**, con los datos del ejemplo:

| Campo | Valor |
|-------|--------|
| Host name/address | `dpg-abc123xyz.render.com` |
| Port | `5432` |
| Maintenance database | `render_db` |
| Username | `render_user` |
| Password | `render_password` |

4. Pestaña **SSL**: **SSL mode** = `Require`. Sin esto pgAdmin no entra.
5. **Save**. Tras un `/ask` contra la API en Render, en esa BD aparecen `conversation` y `message`.

### 3) Desplegar la API

1. **New** → **Web Service** → el repo, con **esta carpeta** como raíz (donde está el `Dockerfile`). Entorno **Docker**.
2. Environment: `API_KEY`, `GEMINI_API_KEY`, `GEMINI_MODEL` (opcional; por defecto `gemini-3.5-flash-lite`), `ASK_TIMEOUT_SECONDS`, `CORS_ORIGINS`, `DATABASE_URL` (el ejemplo de arriba, o la Internal Database URL).
3. El hosting inyecta `PORT`; el Dockerfile ya lo usa.

Nunca subáis `.env` con secretos reales. Las variables van en el panel de Render.

---

## Checklist

- [ ] Contenedor `agente-pg` en marcha (`docker ps`)
- [ ] pgAdmin conecta a `localhost:5432`
- [ ] API con uvicorn: `/health` → `"storage":"postgres"`
- [ ] `/ask` sin `api_key` → 401; con `?api_key=` → 200
- [ ] GET `/threads/demo-1/messages` con clave → mensajes
- [ ] Historial visible en pgAdmin
- [ ] Imagen Docker de la API
- [ ] Deploy en Render con las mismas variables
