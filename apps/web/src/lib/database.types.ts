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
      club_members: {
        Row: {
          club_id: string
          joined_at: string | null
          role: string
          status: string
          user_id: string
        }
        Insert: {
          club_id: string
          joined_at?: string | null
          role?: string
          status?: string
          user_id: string
        }
        Update: {
          club_id?: string
          joined_at?: string | null
          role?: string
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "club_members_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
        ]
      }
      club_posts: {
        Row: {
          author_id: string
          body: string
          club_id: string
          created_at: string | null
          event_id: string | null
          event_instance_start: string | null
          id: string
          parent_post_id: string | null
        }
        Insert: {
          author_id: string
          body: string
          club_id: string
          created_at?: string | null
          event_id?: string | null
          event_instance_start?: string | null
          id?: string
          parent_post_id?: string | null
        }
        Update: {
          author_id?: string
          body?: string
          club_id?: string
          created_at?: string | null
          event_id?: string | null
          event_instance_start?: string | null
          id?: string
          parent_post_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "club_posts_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "club_posts_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "club_posts_parent_post_id_fkey"
            columns: ["parent_post_id"]
            isOneToOne: false
            referencedRelation: "club_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      clubs: {
        Row: {
          avatar_url: string | null
          created_at: string | null
          description: string | null
          id: string
          invite_token: string | null
          is_public: boolean | null
          join_policy: string
          location_label: string | null
          name: string
          owner_id: string
          slug: string
          updated_at: string | null
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string | null
          description?: string | null
          id?: string
          invite_token?: string | null
          is_public?: boolean | null
          join_policy?: string
          location_label?: string | null
          name: string
          owner_id: string
          slug: string
          updated_at?: string | null
        }
        Update: {
          avatar_url?: string | null
          created_at?: string | null
          description?: string | null
          id?: string
          invite_token?: string | null
          is_public?: boolean | null
          join_policy?: string
          location_label?: string | null
          name?: string
          owner_id?: string
          slug?: string
          updated_at?: string | null
        }
        Relationships: []
      }
      event_attendees: {
        Row: {
          event_id: string
          instance_start: string
          joined_at: string | null
          status: string
          user_id: string
        }
        Insert: {
          event_id: string
          instance_start: string
          joined_at?: string | null
          status?: string
          user_id: string
        }
        Update: {
          event_id?: string
          instance_start?: string
          joined_at?: string | null
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "event_attendees_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
        ]
      }
      events: {
        Row: {
          capacity: number | null
          club_id: string
          created_at: string | null
          created_by: string
          description: string | null
          distance_m: number | null
          duration_min: number | null
          id: string
          meet_label: string | null
          meet_lat: number | null
          meet_lng: number | null
          pace_target_sec: number | null
          recurrence_byday: string[] | null
          recurrence_count: number | null
          recurrence_freq: string | null
          recurrence_until: string | null
          route_id: string | null
          starts_at: string
          title: string
          updated_at: string | null
        }
        Insert: {
          capacity?: number | null
          club_id: string
          created_at?: string | null
          created_by: string
          description?: string | null
          distance_m?: number | null
          duration_min?: number | null
          id?: string
          meet_label?: string | null
          meet_lat?: number | null
          meet_lng?: number | null
          pace_target_sec?: number | null
          recurrence_byday?: string[] | null
          recurrence_count?: number | null
          recurrence_freq?: string | null
          recurrence_until?: string | null
          route_id?: string | null
          starts_at: string
          title: string
          updated_at?: string | null
        }
        Update: {
          capacity?: number | null
          club_id?: string
          created_at?: string | null
          created_by?: string
          description?: string | null
          distance_m?: number | null
          duration_min?: number | null
          id?: string
          meet_label?: string | null
          meet_lat?: number | null
          meet_lng?: number | null
          pace_target_sec?: number | null
          recurrence_byday?: string[] | null
          recurrence_count?: number | null
          recurrence_freq?: string | null
          recurrence_until?: string | null
          route_id?: string | null
          starts_at?: string
          title?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "events_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_route_id_fkey"
            columns: ["route_id"]
            isOneToOne: false
            referencedRelation: "routes"
            referencedColumns: ["id"]
          },
        ]
      }
      integrations: {
        Row: {
          access_token: string | null
          created_at: string | null
          external_id: string | null
          id: string
          last_sync_at: string | null
          provider: string
          refresh_token: string | null
          scope: string | null
          sync_cursor: string | null
          token_expiry: string | null
          updated_at: string | null
          user_id: string
        }
        Insert: {
          access_token?: string | null
          created_at?: string | null
          external_id?: string | null
          id?: string
          last_sync_at?: string | null
          provider: string
          refresh_token?: string | null
          scope?: string | null
          sync_cursor?: string | null
          token_expiry?: string | null
          updated_at?: string | null
          user_id: string
        }
        Update: {
          access_token?: string | null
          created_at?: string | null
          external_id?: string | null
          id?: string
          last_sync_at?: string | null
          provider?: string
          refresh_token?: string | null
          scope?: string | null
          sync_cursor?: string | null
          token_expiry?: string | null
          updated_at?: string | null
          user_id?: string
        }
        Relationships: []
      }
      route_reviews: {
        Row: {
          comment: string | null
          created_at: string | null
          id: string
          rating: number
          route_id: string
          updated_at: string | null
          user_id: string
        }
        Insert: {
          comment?: string | null
          created_at?: string | null
          id?: string
          rating: number
          route_id: string
          updated_at?: string | null
          user_id: string
        }
        Update: {
          comment?: string | null
          created_at?: string | null
          id?: string
          rating?: number
          route_id?: string
          updated_at?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "route_reviews_route_id_fkey"
            columns: ["route_id"]
            isOneToOne: false
            referencedRelation: "routes"
            referencedColumns: ["id"]
          },
        ]
      }
      routes: {
        Row: {
          created_at: string | null
          distance_m: number
          elevation_m: number | null
          id: string
          is_public: boolean | null
          name: string
          slug: string | null
          start_point: unknown
          surface: string | null
          updated_at: string | null
          user_id: string
          waypoints: Json
        }
        Insert: {
          created_at?: string | null
          distance_m: number
          elevation_m?: number | null
          id?: string
          is_public?: boolean | null
          name: string
          slug?: string | null
          start_point?: unknown
          surface?: string | null
          updated_at?: string | null
          user_id: string
          waypoints: Json
        }
        Update: {
          created_at?: string | null
          distance_m?: number
          elevation_m?: number | null
          id?: string
          is_public?: boolean | null
          name?: string
          slug?: string | null
          start_point?: unknown
          surface?: string | null
          updated_at?: string | null
          user_id?: string
          waypoints?: Json
        }
        Relationships: []
      }
      runs: {
        Row: {
          created_at: string | null
          distance_m: number
          duration_s: number
          external_id: string | null
          id: string
          is_public: boolean | null
          metadata: Json | null
          route_id: string | null
          source: string
          started_at: string
          track_url: string | null
          updated_at: string | null
          user_id: string
        }
        Insert: {
          created_at?: string | null
          distance_m: number
          duration_s: number
          external_id?: string | null
          id?: string
          is_public?: boolean | null
          metadata?: Json | null
          route_id?: string | null
          source: string
          started_at: string
          track_url?: string | null
          updated_at?: string | null
          user_id: string
        }
        Update: {
          created_at?: string | null
          distance_m?: number
          duration_s?: number
          external_id?: string | null
          id?: string
          is_public?: boolean | null
          metadata?: Json | null
          route_id?: string | null
          source?: string
          started_at?: string
          track_url?: string | null
          updated_at?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "runs_route_id_fkey"
            columns: ["route_id"]
            isOneToOne: false
            referencedRelation: "routes"
            referencedColumns: ["id"]
          },
        ]
      }
      user_profiles: {
        Row: {
          avatar_url: string | null
          created_at: string | null
          display_name: string | null
          id: string
          parkrun_number: string | null
          preferred_unit: string | null
          subscription_at: string | null
          subscription_tier: string | null
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string | null
          display_name?: string | null
          id: string
          parkrun_number?: string | null
          preferred_unit?: string | null
          subscription_at?: string | null
          subscription_tier?: string | null
        }
        Update: {
          avatar_url?: string | null
          created_at?: string | null
          display_name?: string | null
          id?: string
          parkrun_number?: string | null
          preferred_unit?: string | null
          subscription_at?: string | null
          subscription_tier?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      mv_weekly_mileage: {
        Row: {
          run_count: number | null
          total_distance_m: number | null
          user_id: string | null
          week_start: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      is_club_admin: { Args: { target_club: string }; Returns: boolean }
      is_club_member: { Args: { target_club: string }; Returns: boolean }
      join_club_by_token: { Args: { token: string }; Returns: string }
      nearby_routes: {
        Args: {
          lat: number
          lng: number
          max_results?: number
          radius_m?: number
        }
        Returns: {
          created_at: string | null
          distance_m: number
          elevation_m: number | null
          id: string
          is_public: boolean | null
          name: string
          slug: string | null
          start_point: unknown
          surface: string | null
          updated_at: string | null
          user_id: string
          waypoints: Json
        }[]
        SetofOptions: {
          from: "*"
          to: "routes"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      personal_records: {
        Args: never
        Returns: {
          achieved_at: string
          best_time_s: number
          distance: string
        }[]
      }
      weekly_mileage: {
        Args: { weeks_back?: number }
        Returns: {
          total_distance_m: number
          week_start: string
        }[]
      }
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

