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
      event_results: {
        Row: {
          age_grade_pct: number | null
          created_at: string
          distance_m: number
          duration_s: number
          event_id: string
          finisher_status: string
          instance_start: string
          note: string | null
          organiser_approved: boolean
          organiser_approved_at: string | null
          organiser_approved_by: string | null
          rank: number | null
          run_id: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          age_grade_pct?: number | null
          created_at?: string
          distance_m: number
          duration_s: number
          event_id: string
          finisher_status?: string
          instance_start: string
          note?: string | null
          organiser_approved?: boolean
          organiser_approved_at?: string | null
          organiser_approved_by?: string | null
          rank?: number | null
          run_id?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          age_grade_pct?: number | null
          created_at?: string
          distance_m?: number
          duration_s?: number
          event_id?: string
          finisher_status?: string
          instance_start?: string
          note?: string | null
          organiser_approved?: boolean
          organiser_approved_at?: string | null
          organiser_approved_by?: string | null
          rank?: number | null
          run_id?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "event_results_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_results_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "runs"
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
      monthly_funding: {
        Row: {
          amount_received: number
          donor_count: number
          month: string
          updated_at: string
        }
        Insert: {
          amount_received?: number
          donor_count?: number
          month: string
          updated_at?: string
        }
        Update: {
          amount_received?: number
          donor_count?: number
          month?: string
          updated_at?: string
        }
        Relationships: []
      }
      plan_weeks: {
        Row: {
          id: string
          notes: string | null
          phase: Database["public"]["Enums"]["plan_phase"]
          plan_id: string
          target_volume_m: number | null
          week_index: number
        }
        Insert: {
          id?: string
          notes?: string | null
          phase?: Database["public"]["Enums"]["plan_phase"]
          plan_id: string
          target_volume_m?: number | null
          week_index: number
        }
        Update: {
          id?: string
          notes?: string | null
          phase?: Database["public"]["Enums"]["plan_phase"]
          plan_id?: string
          target_volume_m?: number | null
          week_index?: number
        }
        Relationships: [
          {
            foreignKeyName: "plan_weeks_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "training_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      plan_workouts: {
        Row: {
          completed_at: string | null
          completed_run_id: string | null
          id: string
          kind: Database["public"]["Enums"]["workout_kind"]
          notes: string | null
          pace_zone: string | null
          scheduled_date: string
          structure: Json | null
          target_distance_m: number | null
          target_duration_seconds: number | null
          target_pace_end_sec_per_km: number | null
          target_pace_sec_per_km: number | null
          target_pace_tolerance_sec: number | null
          week_id: string
        }
        Insert: {
          completed_at?: string | null
          completed_run_id?: string | null
          id?: string
          kind: Database["public"]["Enums"]["workout_kind"]
          notes?: string | null
          pace_zone?: string | null
          scheduled_date: string
          structure?: Json | null
          target_distance_m?: number | null
          target_duration_seconds?: number | null
          target_pace_end_sec_per_km?: number | null
          target_pace_sec_per_km?: number | null
          target_pace_tolerance_sec?: number | null
          week_id: string
        }
        Update: {
          completed_at?: string | null
          completed_run_id?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["workout_kind"]
          notes?: string | null
          pace_zone?: string | null
          scheduled_date?: string
          structure?: Json | null
          target_distance_m?: number | null
          target_duration_seconds?: number | null
          target_pace_end_sec_per_km?: number | null
          target_pace_sec_per_km?: number | null
          target_pace_tolerance_sec?: number | null
          week_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "plan_workouts_completed_run_id_fkey"
            columns: ["completed_run_id"]
            isOneToOne: false
            referencedRelation: "runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "plan_workouts_week_id_fkey"
            columns: ["week_id"]
            isOneToOne: false
            referencedRelation: "plan_weeks"
            referencedColumns: ["id"]
          },
        ]
      }
      race_pings: {
        Row: {
          at: string
          bpm: number | null
          distance_m: number | null
          elapsed_s: number | null
          event_id: string
          id: number
          instance_start: string
          lat: number
          lng: number
          user_id: string
        }
        Insert: {
          at?: string
          bpm?: number | null
          distance_m?: number | null
          elapsed_s?: number | null
          event_id: string
          id?: number
          instance_start: string
          lat: number
          lng: number
          user_id: string
        }
        Update: {
          at?: string
          bpm?: number | null
          distance_m?: number | null
          elapsed_s?: number | null
          event_id?: string
          id?: number
          instance_start?: string
          lat?: number
          lng?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "race_pings_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
        ]
      }
      race_sessions: {
        Row: {
          auto_approve: boolean
          created_at: string
          event_id: string
          finished_at: string | null
          instance_start: string
          started_at: string | null
          started_by: string | null
          status: string
          updated_at: string
        }
        Insert: {
          auto_approve?: boolean
          created_at?: string
          event_id: string
          finished_at?: string | null
          instance_start: string
          started_at?: string | null
          started_by?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          auto_approve?: boolean
          created_at?: string
          event_id?: string
          finished_at?: string | null
          instance_start?: string
          started_at?: string | null
          started_by?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "race_sessions_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
        ]
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
          featured: boolean
          featured_at: string | null
          id: string
          is_public: boolean | null
          name: string
          run_count: number
          slug: string | null
          start_point: unknown
          surface: string | null
          tags: string[]
          updated_at: string | null
          user_id: string
          waypoints: Json
        }
        Insert: {
          created_at?: string | null
          distance_m: number
          elevation_m?: number | null
          featured?: boolean
          featured_at?: string | null
          id?: string
          is_public?: boolean | null
          name: string
          run_count?: number
          slug?: string | null
          start_point?: unknown
          surface?: string | null
          tags?: string[]
          updated_at?: string | null
          user_id: string
          waypoints: Json
        }
        Update: {
          created_at?: string | null
          distance_m?: number
          elevation_m?: number | null
          featured?: boolean
          featured_at?: string | null
          id?: string
          is_public?: boolean | null
          name?: string
          run_count?: number
          slug?: string | null
          start_point?: unknown
          surface?: string | null
          tags?: string[]
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
          event_id: string | null
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
          event_id?: string | null
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
          event_id?: string | null
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
            foreignKeyName: "runs_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "runs_route_id_fkey"
            columns: ["route_id"]
            isOneToOne: false
            referencedRelation: "routes"
            referencedColumns: ["id"]
          },
        ]
      }
      training_plans: {
        Row: {
          created_at: string | null
          current_5k_seconds: number | null
          days_per_week: number
          end_date: string
          goal_distance_m: number
          goal_event: Database["public"]["Enums"]["goal_event"]
          goal_time_seconds: number | null
          id: string
          name: string
          notes: string | null
          rules: Json | null
          source: string
          start_date: string
          status: string
          updated_at: string | null
          user_id: string
          vdot: number | null
        }
        Insert: {
          created_at?: string | null
          current_5k_seconds?: number | null
          days_per_week?: number
          end_date: string
          goal_distance_m: number
          goal_event: Database["public"]["Enums"]["goal_event"]
          goal_time_seconds?: number | null
          id?: string
          name: string
          notes?: string | null
          rules?: Json | null
          source?: string
          start_date: string
          status?: string
          updated_at?: string | null
          user_id: string
          vdot?: number | null
        }
        Update: {
          created_at?: string | null
          current_5k_seconds?: number | null
          days_per_week?: number
          end_date?: string
          goal_distance_m?: number
          goal_event?: Database["public"]["Enums"]["goal_event"]
          goal_time_seconds?: number | null
          id?: string
          name?: string
          notes?: string | null
          rules?: Json | null
          source?: string
          start_date?: string
          status?: string
          updated_at?: string | null
          user_id?: string
          vdot?: number | null
        }
        Relationships: []
      }
      user_coach_usage: {
        Row: {
          message_count: number
          usage_date: string
          user_id: string
        }
        Insert: {
          message_count?: number
          usage_date?: string
          user_id: string
        }
        Update: {
          message_count?: number
          usage_date?: string
          user_id?: string
        }
        Relationships: []
      }
      user_device_settings: {
        Row: {
          device_id: string
          label: string | null
          last_seen_at: string
          platform: string
          prefs: Json
          updated_at: string
          user_id: string
        }
        Insert: {
          device_id: string
          label?: string | null
          last_seen_at?: string
          platform: string
          prefs?: Json
          updated_at?: string
          user_id: string
        }
        Update: {
          device_id?: string
          label?: string | null
          last_seen_at?: string
          platform?: string
          prefs?: Json
          updated_at?: string
          user_id?: string
        }
        Relationships: []
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
      user_settings: {
        Row: {
          prefs: Json
          updated_at: string
          user_id: string
        }
        Insert: {
          prefs?: Json
          updated_at?: string
          user_id: string
        }
        Update: {
          prefs?: Json
          updated_at?: string
          user_id?: string
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
      approve_event_result: {
        Args: {
          p_approve: boolean
          p_event_id: string
          p_instance_start: string
          p_user_id: string
        }
        Returns: {
          age_grade_pct: number | null
          created_at: string
          distance_m: number
          duration_s: number
          event_id: string
          finisher_status: string
          instance_start: string
          note: string | null
          organiser_approved: boolean
          organiser_approved_at: string | null
          organiser_approved_by: string | null
          rank: number | null
          run_id: string | null
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "event_results"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      get_coach_usage: { Args: { p_user_id: string }; Returns: number }
      increment_coach_usage: { Args: { p_user_id: string }; Returns: number }
      is_club_admin: { Args: { target_club: string }; Returns: boolean }
      is_club_member: { Args: { target_club: string }; Returns: boolean }
      is_event_organiser: { Args: { target_club: string }; Returns: boolean }
      is_pro: { Args: never; Returns: boolean }
      is_race_director: { Args: { target_club: string }; Returns: boolean }
      is_user_pro: { Args: { p_user_id: string }; Returns: boolean }
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
          featured: boolean
          featured_at: string | null
          id: string
          is_public: boolean | null
          name: string
          run_count: number
          slug: string | null
          start_point: unknown
          surface: string | null
          tags: string[]
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
      popular_route_tags: {
        Args: { tag_limit?: number }
        Returns: {
          route_count: number
          tag: string
        }[]
      }
      recompute_event_ranks: {
        Args: { p_event_id: string; p_instance_start: string }
        Returns: undefined
      }
      search_public_routes: {
        Args: {
          p_featured_only?: boolean
          p_limit?: number
          p_max_distance_m?: number
          p_min_distance_m?: number
          p_offset?: number
          p_query?: string
          p_sort?: string
          p_surface?: string
          p_tags?: string[]
        }
        Returns: {
          created_at: string | null
          distance_m: number
          elevation_m: number | null
          featured: boolean
          featured_at: string | null
          id: string
          is_public: boolean | null
          name: string
          run_count: number
          slug: string | null
          start_point: unknown
          surface: string | null
          tags: string[]
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
      weekly_mileage: {
        Args: { weeks_back?: number }
        Returns: {
          total_distance_m: number
          week_start: string
        }[]
      }
    }
    Enums: {
      goal_event:
        | "distance_5k"
        | "distance_10k"
        | "distance_half"
        | "distance_full"
        | "custom"
      plan_phase: "base" | "build" | "peak" | "taper" | "race"
      workout_kind:
        | "easy"
        | "long"
        | "recovery"
        | "tempo"
        | "interval"
        | "marathon_pace"
        | "race"
        | "rest"
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
    Enums: {
      goal_event: [
        "distance_5k",
        "distance_10k",
        "distance_half",
        "distance_full",
        "custom",
      ],
      plan_phase: ["base", "build", "peak", "taper", "race"],
      workout_kind: [
        "easy",
        "long",
        "recovery",
        "tempo",
        "interval",
        "marathon_pace",
        "race",
        "rest",
      ],
    },
  },
} as const

