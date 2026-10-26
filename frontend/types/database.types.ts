export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      citations: {
        Row: {
          created_at: string
          id: string
          source_publication_id: string
          target_publication_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          source_publication_id: string
          target_publication_id: string
        }
        Update: {
          created_at?: string
          id?: string
          source_publication_id?: string
          target_publication_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "citations_source_publication_id_fkey"
            columns: ["source_publication_id"]
            isOneToOne: false
            referencedRelation: "publications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "citations_target_publication_id_fkey"
            columns: ["target_publication_id"]
            isOneToOne: false
            referencedRelation: "publications"
            referencedColumns: ["id"]
          },
        ]
      }
      journals: {
        Row: {
          created_at: string
          id: string
          issn: string | null
          publisher: string | null
          title: string
          title_en: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          issn?: string | null
          publisher?: string | null
          title: string
          title_en?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          issn?: string | null
          publisher?: string | null
          title?: string
          title_en?: string | null
        }
        Relationships: []
      }
      profile_claims: {
        Row: {
          created_at: string
          id: string
          profile_id: string | null
          profile_name: string
          resolved_at: string | null
          status: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          profile_id?: string | null
          profile_name: string
          resolved_at?: string | null
          status?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          profile_id?: string | null
          profile_name?: string
          resolved_at?: string | null
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "profile_claims_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          created_at: string
          full_name: string
          full_name_en: string | null
          h_index: number
          h_index_updated_at: string | null
          i10_index: number
          id: string
          institution: string | null
          orcid: string | null
          role: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          created_at?: string
          full_name: string
          full_name_en?: string | null
          h_index?: number
          h_index_updated_at?: string | null
          i10_index?: number
          id?: string
          institution?: string | null
          orcid?: string | null
          role?: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          created_at?: string
          full_name?: string
          full_name_en?: string | null
          h_index?: number
          h_index_updated_at?: string | null
          i10_index?: number
          id?: string
          institution?: string | null
          orcid?: string | null
          role?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: []
      }
      publication_authors: {
        Row: {
          is_corresponding: boolean
          position: number
          profile_id: string
          publication_id: string
        }
        Insert: {
          is_corresponding?: boolean
          position?: number
          profile_id: string
          publication_id: string
        }
        Update: {
          is_corresponding?: boolean
          position?: number
          profile_id?: string
          publication_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "publication_authors_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_authors_publication_id_fkey"
            columns: ["publication_id"]
            isOneToOne: false
            referencedRelation: "publications"
            referencedColumns: ["id"]
          },
        ]
      }
      publications: {
        Row: {
          abstract: string | null
          citation_count: number
          created_at: string
          created_by: string | null
          doi: string | null
          id: string
          journal_id: string | null
          language: string | null
          pdf_path: string | null
          published_date: string | null
          title: string
          title_en: string | null
          updated_at: string
        }
        Insert: {
          abstract?: string | null
          citation_count?: number
          created_at?: string
          created_by?: string | null
          doi?: string | null
          id?: string
          journal_id?: string | null
          language?: string | null
          pdf_path?: string | null
          published_date?: string | null
          title: string
          title_en?: string | null
          updated_at?: string
        }
        Update: {
          abstract?: string | null
          citation_count?: number
          created_at?: string
          created_by?: string | null
          doi?: string | null
          id?: string
          journal_id?: string | null
          language?: string | null
          pdf_path?: string | null
          published_date?: string | null
          title?: string
          title_en?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "publications_journal_id_fkey"
            columns: ["journal_id"]
            isOneToOne: false
            referencedRelation: "journals"
            referencedColumns: ["id"]
          },
        ]
      }
      raw_references: {
        Row: {
          created_at: string
          excluded_publication_ids: string[]
          id: string
          match_score: number | null
          matched_at: string | null
          matched_publication_id: string | null
          parsed_authors: string | null
          parsed_title: string | null
          parsed_year: number | null
          raw_text: string
          source_publication_id: string
          status: string
        }
        Insert: {
          created_at?: string
          excluded_publication_ids?: string[]
          id?: string
          match_score?: number | null
          matched_at?: string | null
          matched_publication_id?: string | null
          parsed_authors?: string | null
          parsed_title?: string | null
          parsed_year?: number | null
          raw_text: string
          source_publication_id: string
          status?: string
        }
        Update: {
          created_at?: string
          excluded_publication_ids?: string[]
          id?: string
          match_score?: number | null
          matched_at?: string | null
          matched_publication_id?: string | null
          parsed_authors?: string | null
          parsed_title?: string | null
          parsed_year?: number | null
          raw_text?: string
          source_publication_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "raw_references_matched_publication_id_fkey"
            columns: ["matched_publication_id"]
            isOneToOne: false
            referencedRelation: "publications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "raw_references_source_publication_id_fkey"
            columns: ["source_publication_id"]
            isOneToOne: false
            referencedRelation: "publications"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      admin_link_reference: {
        Args: { p_publication_id: string; p_ref_id: string }
        Returns: undefined
      }
      admin_resolve_claim: {
        Args: { p_approve: boolean; p_claim_id: string }
        Returns: undefined
      }
      admin_set_reference_status: {
        Args: { p_ref_id: string; p_status: string }
        Returns: undefined
      }
      admin_stats: { Args: never; Returns: Json }
      assert_admin: { Args: never; Returns: undefined }
      autocomplete: {
        Args: { p_limit?: number; p_query: string }
        Returns: {
          id: string
          label: string
          sublabel: string
          type: string
        }[]
      }
      can_manage_publication: {
        Args: { p_publication_id: string }
        Returns: boolean
      }
      clamp_limit: {
        Args: { p_limit: number; p_max?: number }
        Returns: number
      }
      cleanup_orphan_profiles: { Args: never; Returns: number }
      drop_orphan_citation: {
        Args: { p_source: string; p_target: string }
        Returns: undefined
      }
      find_duplicate_publication: {
        Args: { p_doi?: string; p_title: string }
        Returns: string
      }
      find_or_create_author: { Args: { p_full_name: string }; Returns: string }
      is_admin: { Args: never; Returns: boolean }
      is_end_user_non_admin: { Args: never; Returns: boolean }
      is_trusted_write: { Args: never; Returns: boolean }
      journals_with_counts: {
        Args: never
        Returns: {
          citation_count: number
          id: string
          issn: string
          publication_count: number
          publisher: string
          title: string
          title_en: string
        }[]
      }
      match_raw_references: {
        Args: { p_batch_size?: number; p_threshold?: number }
        Returns: {
          matched_count: number
          total_pending: number
        }[]
      }
      merge_profiles: {
        Args: { p_source: string; p_target: string }
        Returns: undefined
      }
      public_stats: { Args: never; Returns: Json }
      recalculate_all_h_indexes: { Args: never; Returns: number }
      recalculate_h_index: {
        Args: { p_profile_id: string }
        Returns: undefined
      }
      recalculate_publication_authors: {
        Args: { p_publication_id: string }
        Returns: undefined
      }
      reconcile_citation_counts: { Args: never; Returns: number }
      reference_candidates: {
        Args: { p_limit?: number; p_ref_id: string }
        Returns: {
          id: string
          published_date: string
          score: number
          title: string
        }[]
      }
      resolve_author_profile: {
        Args: {
          p_full_name: string
          p_full_name_en?: string
          p_institution?: string
        }
        Returns: string
      }
      run_h_index_update: { Args: never; Returns: Json }
      run_matching: { Args: never; Returns: Json }
      search_authors: {
        Args: { p_limit?: number; p_offset?: number; p_query: string }
        Returns: {
          full_name: string
          full_name_en: string
          h_index: number
          i10_index: number
          id: string
          institution: string
          is_registered: boolean
          publication_count: number
          rank: number
          total_count: number
        }[]
      }
      search_publications: {
        Args: {
          p_journal_id?: string
          p_language?: string
          p_limit?: number
          p_offset?: number
          p_query: string
          p_sort?: string
          p_year_from?: number
          p_year_to?: number
        }
        Returns: {
          abstract: string
          authors: string
          citation_count: number
          id: string
          journal_title: string
          language: string
          published_date: string
          rank: number
          title: string
          total_count: number
        }[]
      }
      set_publication_authors: {
        Args: { p_profile_ids: string[]; p_publication_id: string }
        Returns: undefined
      }
      show_limit: { Args: never; Returns: number }
      show_trgm: { Args: { "": string }; Returns: string[] }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const

