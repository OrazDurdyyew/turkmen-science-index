import type { PickedAuthor } from '~/components/AuthorPicker.vue'

// Turn picker entries into profile ids (creating unclaimed profiles for new names) and save the order
export const usePublicationAuthors = () => {
  const supabase = useSupabase()

  const saveAuthors = async (publicationId: string, authors: PickedAuthor[]) => {
    const ids: string[] = []
    for (const a of authors) {
      if (a.id) {
        ids.push(a.id)
        continue
      }
      const { data, error } = await supabase.rpc('find_or_create_author', { p_full_name: a.full_name })
      if (error) throw error
      ids.push(data as string)
    }
    const { error } = await supabase.rpc('set_publication_authors', {
      p_publication_id: publicationId,
      p_profile_ids: ids,
    })
    if (error) throw error
  }

  return { saveAuthors }
}
