import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '~/types/database.types'

let client: SupabaseClient<Database> | null = null

export const useSupabase = () => {
  if (client) return client

  const config = useRuntimeConfig()

  client = createClient<Database>(
    config.public.supabaseUrl,
    config.public.supabaseKey,
  )

  return client
}
