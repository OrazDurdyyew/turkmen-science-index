// Minimal global notifications: useToast().show('Сохранено'), show('Ошибка', 'error')
type Toast = { id: number; text: string; kind: 'success' | 'error' }

let next = 1

export const useToast = () => {
  const toasts = useState<Toast[]>('toasts', () => [])

  const show = (text: string, kind: Toast['kind'] = 'success') => {
    const id = next++
    toasts.value = [...toasts.value, { id, text, kind }]
    setTimeout(() => {
      toasts.value = toasts.value.filter(t => t.id !== id)
    }, kind === 'error' ? 6000 : 3000)
  }

  return { toasts, show }
}
