export const LANGUAGES: Record<string, string> = {
  tk: 'Туркменский',
  ru: 'Русский',
  en: 'Английский',
}

export function initials(name?: string | null): string {
  if (!name) return '?'
  return name
    .split(/\s+/)
    .filter(Boolean)
    .map(n => n[0])
    .join('')
    .toUpperCase()
    .slice(0, 2)
}

export function year(date?: string | null): string {
  return date ? String(new Date(date).getFullYear()) : ''
}

export function formatDate(date?: string | null): string {
  if (!date) return ''
  return new Date(date).toLocaleDateString('ru-RU', { day: 'numeric', month: 'long', year: 'numeric' })
}

export function formatDateTime(date?: string | null): string {
  if (!date) return '—'
  return new Date(date).toLocaleString('ru-RU', { dateStyle: 'medium', timeStyle: 'short' })
}

// "1 цитирование", "2 цитирования", "5 цитирований"
export function plural(n: number, one: string, few: string, many: string): string {
  const mod10 = n % 10
  const mod100 = n % 100
  if (mod10 === 1 && mod100 !== 11) return one
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return few
  return many
}

export function errorMessage(e: unknown, fallback = 'Что-то пошло не так'): string {
  const err = e as { data?: { detail?: unknown }; message?: string }
  const detail = err?.data?.detail
  if (typeof detail === 'string') return detail
  if (detail && typeof detail === 'object' && 'message' in detail) return String((detail as { message: unknown }).message)
  // The server is unreachable: the browser's "Failed to fetch" means nothing to a user
  if (err?.message && /Failed to fetch|<no response>|NetworkError|Load failed/.test(err.message)) {
    return `${fallback} Сервер недоступен — попробуйте позже.`
  }
  return err?.message || fallback
}

// Escape user input for PostgREST ilike / or() filters
export function ilikePattern(q: string): string {
  return `%${q.replace(/[\\%_,()]/g, ' ').trim()}%`
}

// Exact, case-insensitive match through PostgREST ilike: escape the LIKE wildcards
export function ilikeExact(s: string): string {
  return s.trim().replace(/[\\%_]/g, c => `\\${c}`)
}
