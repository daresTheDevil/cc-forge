# Nuxt / Vue 3 Development Skill
# ~/.claude/forge/skills/frameworks/nuxt.md
# Load this skill before working on Nuxt applications.

## Stack Context

- Nuxt 3 (SSR, TypeScript strict mode)
- `bun` as package manager — never `npm`
- Vitest + `@nuxt/test-utils` for testing
- ESLint + TypeScript strict — zero warnings on commit

## Environment Variables

```
# Runtime config — DO NOT expose secrets to client
NUXT_SECRET_KEY          → available server-side only via useRuntimeConfig()
NUXT_PUBLIC_API_BASE_URL → safe for client (NUXT_PUBLIC_ prefix = public)
```

Configure in `nuxt.config.ts`:
```typescript
export default defineNuxtConfig({
  runtimeConfig: {
    // Server-only (not sent to client)
    dbPassword: process.env.DB_PASSWORD,
    apiSecret:  process.env.API_SECRET,
    // Public (sent to client — safe values only)
    public: {
      apiBaseUrl: process.env.NUXT_PUBLIC_API_BASE_URL ?? '/api',
    }
  }
})
```

Never put secrets in `runtimeConfig.public`. They will be sent to the browser.

## Composables (The Right Pattern)

```typescript
// composables/usePlayerSession.ts
// Rule: composables always start with `use`, live in composables/, are auto-imported

export function usePlayerSession(playerId: MaybeRef<string>) {
  const id = toRef(playerId) // supports both ref and plain string
  const session = ref<PlayerSession | null>(null)
  const loading = ref(false)
  const error = ref<Error | null>(null)

  const fetch = async () => {
    loading.value = true
    error.value = null
    try {
      session.value = await $fetch<PlayerSession>(`/api/players/${id.value}/session`)
    } catch (e) {
      error.value = e instanceof Error ? e : new Error(String(e))
    } finally {
      loading.value = false
    }
  }

  // Re-fetch automatically when the ID changes
  watch(id, fetch, { immediate: true })

  return { session, loading, error, refresh: fetch }
}
```

## Server Routes

```typescript
// server/api/players/[id]/session.get.ts
// File naming: {resource}.{method}.ts — Nuxt auto-routes by convention

import { z } from 'zod'

const ParamsSchema = z.object({
  id: z.string().uuid('Player ID must be a UUID')
})

export default defineEventHandler(async (event) => {
  // Always validate params — never trust URL inputs
  const { id } = await getValidatedRouterParams(event, ParamsSchema.parse)

  // Runtime config for DB connections — not process.env directly
  const config = useRuntimeConfig()

  const session = await fetchActiveSession(id)

  if (!session) {
    throw createError({
      statusCode: 404,
      statusMessage: 'No active session found for this player'
    })
  }

  return session
})
```

### Server Route Conventions

- `server/api/` — auto-prefixed `/api/`
- `server/routes/` — any path (use for non-API routes)
- File naming: `resource.get.ts`, `resource.post.ts`, `resource.put.ts`, `resource.[id].get.ts`
- Always validate with Zod: `getValidatedRouterParams`, `getValidatedQuery`, `readValidatedBody`
- Always use `createError` for errors — never `throw new Error()` in handlers

## Server Utilities (Auto-imported from `server/utils/`)

```typescript
// server/utils/db.ts — shared DB connection, auto-imported across all server routes
import sql from 'mssql'

let pool: sql.ConnectionPool | null = null

export function useDatabase(): sql.ConnectionPool {
  if (!pool) {
    const config = useRuntimeConfig()
    pool = new sql.ConnectionPool({
      server:   config.mssqlHost,
      database: config.mssqlDatabase,
      user:     config.mssqlUser,
      password: config.mssqlPassword,
      options: { encrypt: true, trustServerCertificate: false },
    })
  }
  return pool
}
```

All files in `server/utils/` are auto-imported in server routes. No explicit imports needed.

## Middleware

```typescript
// server/middleware/auth.ts — runs on EVERY request (no name = global middleware)
// server/middleware/01.auth.ts — numbered prefix controls execution order

export default defineEventHandler(async (event) => {
  const publicPaths = ['/api/health', '/api/auth/login']
  if (publicPaths.some(p => event.path.startsWith(p))) return

  const token = getRequestHeader(event, 'Authorization')?.replace('Bearer ', '')
  if (!token) {
    throw createError({ statusCode: 401, statusMessage: 'Unauthorized' })
  }
  // Set context for downstream handlers
  event.context.userId = await validateToken(token)
})
```

## SSR Gotchas

These cause subtle bugs — memorize them:

```typescript
// ❌ WRONG — `window` doesn't exist on server
if (window.innerWidth < 768) { ... }

// ✅ CORRECT — guard with process.client or onMounted
onMounted(() => {
  if (window.innerWidth < 768) { ... }
})
// OR
if (process.client) { ... }  // for non-component code

// ❌ WRONG — localStorage throws on server
const saved = localStorage.getItem('key')

// ✅ CORRECT
const saved = process.client ? localStorage.getItem('key') : null

// ❌ WRONG — cookies must use useCookie() in Nuxt, not document.cookie
document.cookie = 'session=abc'

// ✅ CORRECT — works server AND client, SSR-safe
const session = useCookie('session', { sameSite: 'strict', secure: true })
session.value = 'abc'
```

## State Management

```typescript
// Prefer useState for SSR-safe shared state (no Pinia needed for simple cases)
// composables/useAppState.ts
export const useAppState = () => useState('app', () => ({
  currentPlayer: null as Player | null,
  notifications: [] as Notification[],
}))

// For complex state with actions: use Pinia
// stores/player.ts
export const usePlayerStore = defineStore('player', () => {
  const current = ref<Player | null>(null)
  const isLoading = ref(false)

  async function load(id: string) {
    isLoading.value = true
    current.value = await $fetch(`/api/players/${id}`)
    isLoading.value = false
  }

  return { current, isLoading, load }
})
```

## Testing with Vitest + @nuxt/test-utils

```typescript
// tests/server/api/players.test.ts
import { describe, it, expect, vi } from 'vitest'
import { setup, $fetch } from '@nuxt/test-utils/e2e'

await setup({ rootDir: fileURLToPath(new URL('../..', import.meta.url)) })

describe('GET /api/players/:id/session', () => {
  it('returns 404 for unknown player', async () => {
    const response = await $fetch('/api/players/00000000-0000-0000-0000-000000000000/session', {
      ignoreResponseError: true,
      responseType: 'json',
      onResponseError({ response }) {
        expect(response.status).toBe(404)
      }
    })
  })
})

// Unit test a composable
import { usePlayerSession } from '~/composables/usePlayerSession'
import { mountSuspended } from '@nuxt/test-utils/runtime'

it('loads session for player', async () => {
  vi.mocked($fetch).mockResolvedValueOnce({ id: 'sess-1', playerId: 'p-1' })
  const { session, loading } = usePlayerSession('p-1')
  await nextTick()
  expect(loading.value).toBe(false)
  expect(session.value?.id).toBe('sess-1')
})
```

## TypeScript Patterns

```typescript
// Type DB results — don't use `any`
interface PlayerRow {
  player_id: string
  first_name: string
  last_name: string
  active: boolean
}

// Use satisfies for config objects (catches type errors without widening)
const config = {
  maxRetries: 3,
  timeout: 5000,
} satisfies Partial<RequestConfig>

// Return types on server routes (auto-validated by TypeScript)
export default defineEventHandler(async (): Promise<PlayerSession> => {
  // TypeScript verifies the return matches PlayerSession
})
```

## Common Mistakes

- Using `process.env` in server routes — use `useRuntimeConfig()` instead
- Putting secrets in `runtimeConfig.public` — they go to the browser
- `import` in `server/utils/` from outside `server/` — circular dependency risk
- Forgetting `await nextTick()` in tests after reactive state changes
- Using `$fetch` without type parameter — always `$fetch<ResponseType>(...)`
- Defining composables outside `composables/` — they won't auto-import
