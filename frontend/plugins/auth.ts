export default defineNuxtPlugin(async () => {
  if (import.meta.server) return

  const { user, fetchUser, fetchProfile } = useAuth()
  await fetchUser()

  // Keep state in sync with sign-out / sign-in in other tabs and token expiry
  useSupabase().auth.onAuthStateChange((event, session) => {
    const next = session?.user ?? null
    if (next?.id === user.value?.id && event !== 'USER_UPDATED') return
    user.value = next
    void fetchProfile()
  })
})
