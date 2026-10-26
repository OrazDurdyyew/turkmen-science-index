import type { User } from '@supabase/supabase-js'
import type { Database } from '~/types/database.types'

type Profile = Database['public']['Tables']['profiles']['Row']

export const useAuth = () => {
  const supabase = useSupabase()
  const user = useState<User | null>('auth-user', () => null)
  const profile = useState<Profile | null>('auth-profile', () => null)
  const loading = useState('auth-loading', () => true)

  const isAdmin = computed(() => profile.value?.role === 'admin')

  const fetchProfile = async () => {
    if (!user.value) {
      profile.value = null
      return
    }
    const { data } = await supabase
      .from('profiles')
      .select('*')
      .eq('user_id', user.value.id)
      .maybeSingle()
    profile.value = data
  }

  const fetchUser = async () => {
    const { data } = await supabase.auth.getUser()
    user.value = data.user
    await fetchProfile()
    loading.value = false
  }

  const signUp = async (email: string, password: string, fullName: string) => {
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { full_name: fullName },
      },
    })
    if (error) throw error
    user.value = data.session ? data.user : null
    await fetchProfile()
    return data
  }

  const signIn = async (email: string, password: string) => {
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    })
    if (error) throw error
    user.value = data.user
    await fetchProfile()
    return data
  }

  const signOut = async () => {
    const { error } = await supabase.auth.signOut()
    if (error) throw error
    user.value = null
    profile.value = null
  }

  // Access token for calls to the parser service
  const getAccessToken = async () => {
    const { data } = await supabase.auth.getSession()
    return data.session?.access_token ?? null
  }

  return { user, profile, isAdmin, loading, fetchUser, fetchProfile, signUp, signIn, signOut, getAccessToken }
}
