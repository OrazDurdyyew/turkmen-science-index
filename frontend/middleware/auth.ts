// Pages that need a signed-in user: upload, dashboard, admin
export default defineNuxtRouteMiddleware(async (to) => {
  if (import.meta.server) return

  const { user, fetchUser, loading } = useAuth()

  if (loading.value) {
    await fetchUser()
  }

  if (!user.value) {
    return navigateTo({ path: '/login', query: { redirect: to.fullPath } })
  }
})
