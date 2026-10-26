// Admin area. RLS and admin RPCs enforce this server-side; the check here only hides the UI.
export default defineNuxtRouteMiddleware(async (to) => {
  if (import.meta.server) return

  const { user, isAdmin, fetchUser, loading } = useAuth()

  if (loading.value) {
    await fetchUser()
  }

  if (!user.value) {
    return navigateTo({ path: '/login', query: { redirect: to.fullPath } })
  }

  if (!isAdmin.value) {
    return abortNavigation(createError({ statusCode: 403, statusMessage: 'Доступ только для администраторов' }))
  }
})
