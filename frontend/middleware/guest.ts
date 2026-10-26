// Login / register: signed-in users go straight to their dashboard
export default defineNuxtRouteMiddleware(async () => {
  if (import.meta.server) return

  const { user, fetchUser, loading } = useAuth()

  if (loading.value) {
    await fetchUser()
  }

  if (user.value) {
    return navigateTo('/dashboard')
  }
})
