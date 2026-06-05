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
      app_quota: {
        Row: {
          count: number
          provider: string
          window_kind: string
          window_start: string
        }
        Insert: {
          count?: number
          provider: string
          window_kind: string
          window_start: string
        }
        Update: {
          count?: number
          provider?: string
          window_kind?: string
          window_start?: string
        }
        Relationships: []
      }
      body_metrics: {
        Row: {
          created_at: string
          id: string
          recorded_at: string
          user_id: string
          weight_kg: number
        }
        Insert: {
          created_at?: string
          id?: string
          recorded_at?: string
          user_id: string
          weight_kg: number
        }
        Update: {
          created_at?: string
          id?: string
          recorded_at?: string
          user_id?: string
          weight_kg?: number
        }
        Relationships: []
      }
      club_members: {
        Row: {
          activity_waiver_ack_at: string | null
          club_id: string
          joined_at: string | null
          role: string
          status: string
          user_id: string
        }
        Insert: {
          activity_waiver_ack_at?: string | null
          club_id: string
          joined_at?: string | null
          role?: string
          status?: string
          user_id: string
        }
        Update: {
          activity_waiver_ack_at?: string | null
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
          is_verified: boolean
          join_policy: string
          location_label: string | null
          location_point: unknown
          member_count: number
          name: string
          owner_id: string
          requires_activity_waiver: boolean
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
          is_verified?: boolean
          join_policy?: string
          location_label?: string | null
          location_point?: unknown
          member_count?: number
          name: string
          owner_id: string
          requires_activity_waiver?: boolean
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
          is_verified?: boolean
          join_policy?: string
          location_label?: string | null
          location_point?: unknown
          member_count?: number
          name?: string
          owner_id?: string
          requires_activity_waiver?: boolean
          slug?: string
          updated_at?: string | null
        }
        Relationships: []
      }
      coach_athletes: {
        Row: {
          accepted_at: string | null
          athlete_id: string | null
          coach_id: string
          created_at: string
          ended_at: string | null
          id: string
          invite_token: string
          note: string | null
          status: string
        }
        Insert: {
          accepted_at?: string | null
          athlete_id?: string | null
          coach_id: string
          created_at?: string
          ended_at?: string | null
          id?: string
          invite_token: string
          note?: string | null
          status?: string
        }
        Update: {
          accepted_at?: string | null
          athlete_id?: string | null
          coach_id?: string
          created_at?: string
          ended_at?: string | null
          id?: string
          invite_token?: string
          note?: string | null
          status?: string
        }
        Relationships: []
      }
      coach_messages: {
        Row: {
          archived_at: string | null
          content: string
          created_at: string
          id: string
          plan_id: string | null
          reaction: string | null
          role: string
          user_id: string
        }
        Insert: {
          archived_at?: string | null
          content: string
          created_at?: string
          id?: string
          plan_id?: string | null
          reaction?: string | null
          role: string
          user_id: string
        }
        Update: {
          archived_at?: string | null
          content?: string
          created_at?: string
          id?: string
          plan_id?: string | null
          reaction?: string | null
          role?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "coach_messages_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "training_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      deletion_audit_log: {
        Row: {
          deleted_at: string
          hashed_user_id: string
          id: number
          notes: string | null
          result: string
          third_party_outcomes: Json | null
        }
        Insert: {
          deleted_at?: string
          hashed_user_id: string
          id?: number
          notes?: string | null
          result: string
          third_party_outcomes?: Json | null
        }
        Update: {
          deleted_at?: string
          hashed_user_id?: string
          id?: number
          notes?: string | null
          result?: string
          third_party_outcomes?: Json | null
        }
        Relationships: []
      }
      device_tokens: {
        Row: {
          app_version: string | null
          created_at: string
          id: string
          is_notifications_enabled: boolean
          last_seen_at: string
          locale: string | null
          platform: string
          token: string
          updated_at: string
          user_id: string
        }
        Insert: {
          app_version?: string | null
          created_at?: string
          id?: string
          is_notifications_enabled?: boolean
          last_seen_at?: string
          locale?: string | null
          platform: string
          token: string
          updated_at?: string
          user_id: string
        }
        Update: {
          app_version?: string | null
          created_at?: string
          id?: string
          is_notifications_enabled?: boolean
          last_seen_at?: string
          locale?: string | null
          platform?: string
          token?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      direct_messages: {
        Row: {
          body: string
          created_at: string
          id: string
          read_at: string | null
          recipient_id: string
          sender_id: string
        }
        Insert: {
          body: string
          created_at?: string
          id?: string
          read_at?: string | null
          recipient_id: string
          sender_id: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          read_at?: string | null
          recipient_id?: string
          sender_id?: string
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
      event_exceptions: {
        Row: {
          cancelled_at: string
          cancelled_by: string | null
          event_id: string
          instance_start: string
          reason: string | null
        }
        Insert: {
          cancelled_at?: string
          cancelled_by?: string | null
          event_id: string
          instance_start: string
          reason?: string | null
        }
        Update: {
          cancelled_at?: string
          cancelled_by?: string | null
          event_id?: string
          instance_start?: string
          reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "event_exceptions_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
        ]
      }
      event_result_claims: {
        Row: {
          claimant_id: string
          created_at: string
          decided_at: string | null
          decided_by: string | null
          id: string
          result_id: string
          status: string
        }
        Insert: {
          claimant_id: string
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          id?: string
          result_id: string
          status?: string
        }
        Update: {
          claimant_id?: string
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          id?: string
          result_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "event_result_claims_result_id_fkey"
            columns: ["result_id"]
            isOneToOne: false
            referencedRelation: "event_results"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_result_claims_result_id_fkey"
            columns: ["result_id"]
            isOneToOne: false
            referencedRelation: "event_results_redacted"
            referencedColumns: ["id"]
          },
        ]
      }
      event_results: {
        Row: {
          age_grade_pct: number | null
          bib: string | null
          created_at: string
          distance_m: number
          duration_s: number
          event_id: string
          finisher_name: string | null
          finisher_status: string
          id: string
          instance_start: string
          note: string | null
          organiser_approved: boolean
          organiser_approved_at: string | null
          organiser_approved_by: string | null
          rank: number | null
          run_id: string | null
          updated_at: string
          user_id: string | null
        }
        Insert: {
          age_grade_pct?: number | null
          bib?: string | null
          created_at?: string
          distance_m: number
          duration_s: number
          event_id: string
          finisher_name?: string | null
          finisher_status?: string
          id?: string
          instance_start: string
          note?: string | null
          organiser_approved?: boolean
          organiser_approved_at?: string | null
          organiser_approved_by?: string | null
          rank?: number | null
          run_id?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          age_grade_pct?: number | null
          bib?: string | null
          created_at?: string
          distance_m?: number
          duration_s?: number
          event_id?: string
          finisher_name?: string | null
          finisher_status?: string
          id?: string
          instance_start?: string
          note?: string | null
          organiser_approved?: boolean
          organiser_approved_at?: string | null
          organiser_approved_by?: string | null
          rank?: number | null
          run_id?: string | null
          updated_at?: string
          user_id?: string | null
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
            referencedRelation: "public_runs"
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
          author_id: string
          capacity: number | null
          club_id: string
          created_at: string | null
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
          author_id: string
          capacity?: number | null
          club_id: string
          created_at?: string | null
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
          author_id?: string
          capacity?: number | null
          club_id?: string
          created_at?: string | null
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
            referencedRelation: "public_routes"
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
      fitness_snapshots: {
        Row: {
          acute_load: number | null
          chronic_load: number | null
          computed_at: string
          created_at: string
          id: string
          notes: string | null
          qualifying_run_count: number
          source: string
          training_stress_bal: number | null
          user_id: string
          vdot: number | null
          vo2_max: number | null
        }
        Insert: {
          acute_load?: number | null
          chronic_load?: number | null
          computed_at?: string
          created_at?: string
          id?: string
          notes?: string | null
          qualifying_run_count?: number
          source?: string
          training_stress_bal?: number | null
          user_id: string
          vdot?: number | null
          vo2_max?: number | null
        }
        Update: {
          acute_load?: number | null
          chronic_load?: number | null
          computed_at?: string
          created_at?: string
          id?: string
          notes?: string | null
          qualifying_run_count?: number
          source?: string
          training_stress_bal?: number | null
          user_id?: string
          vdot?: number | null
          vo2_max?: number | null
        }
        Relationships: []
      }
      food_log: {
        Row: {
          calories: number | null
          carbs_g: number | null
          created_at: string
          external_id: string | null
          fat_g: number | null
          id: string
          is_public: boolean
          item_name: string
          last_modified_at: string
          meal_slot: string | null
          protein_g: number | null
          started_at: string
          user_id: string
        }
        Insert: {
          calories?: number | null
          carbs_g?: number | null
          created_at?: string
          external_id?: string | null
          fat_g?: number | null
          id?: string
          is_public?: boolean
          item_name: string
          last_modified_at?: string
          meal_slot?: string | null
          protein_g?: number | null
          started_at?: string
          user_id: string
        }
        Update: {
          calories?: number | null
          carbs_g?: number | null
          created_at?: string
          external_id?: string | null
          fat_g?: number | null
          id?: string
          is_public?: boolean
          item_name?: string
          last_modified_at?: string
          meal_slot?: string | null
          protein_g?: number | null
          started_at?: string
          user_id?: string
        }
        Relationships: []
      }
      gear: {
        Row: {
          brand: string | null
          created_at: string
          id: string
          is_default: boolean
          kind: string
          model: string | null
          name: string
          notes: string | null
          owner_id: string
          purchased_at: string | null
          retired_at: string | null
          target_distance_m: number | null
          updated_at: string
        }
        Insert: {
          brand?: string | null
          created_at?: string
          id?: string
          is_default?: boolean
          kind: string
          model?: string | null
          name: string
          notes?: string | null
          owner_id: string
          purchased_at?: string | null
          retired_at?: string | null
          target_distance_m?: number | null
          updated_at?: string
        }
        Update: {
          brand?: string | null
          created_at?: string
          id?: string
          is_default?: boolean
          kind?: string
          model?: string | null
          name?: string
          notes?: string | null
          owner_id?: string
          purchased_at?: string | null
          retired_at?: string | null
          target_distance_m?: number | null
          updated_at?: string
        }
        Relationships: []
      }
      gym_sets: {
        Row: {
          exercise_name: string
          id: string
          reps: number | null
          rpe: number | null
          set_index: number
          weight_kg: number | null
          workout_id: string
        }
        Insert: {
          exercise_name: string
          id?: string
          reps?: number | null
          rpe?: number | null
          set_index: number
          weight_kg?: number | null
          workout_id: string
        }
        Update: {
          exercise_name?: string
          id?: string
          reps?: number | null
          rpe?: number | null
          set_index?: number
          weight_kg?: number | null
          workout_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "gym_sets_workout_id_fkey"
            columns: ["workout_id"]
            isOneToOne: false
            referencedRelation: "gym_workouts"
            referencedColumns: ["id"]
          },
        ]
      }
      gym_workouts: {
        Row: {
          created_at: string
          duration_s: number | null
          external_id: string | null
          id: string
          is_public: boolean
          last_modified_at: string
          notes: string | null
          set_count: number
          started_at: string
          title: string | null
          user_id: string
          volume_kg: number
        }
        Insert: {
          created_at?: string
          duration_s?: number | null
          external_id?: string | null
          id?: string
          is_public?: boolean
          last_modified_at?: string
          notes?: string | null
          set_count?: number
          started_at?: string
          title?: string | null
          user_id: string
          volume_kg?: number
        }
        Update: {
          created_at?: string
          duration_s?: number | null
          external_id?: string | null
          id?: string
          is_public?: boolean
          last_modified_at?: string
          notes?: string | null
          set_count?: number
          started_at?: string
          title?: string | null
          user_id?: string
          volume_kg?: number
        }
        Relationships: []
      }
      integrations: {
        Row: {
          access_token_secret_id: string | null
          created_at: string | null
          disconnected_at: string | null
          disconnected_reason: string | null
          external_id: string | null
          id: string
          last_sync_at: string | null
          provider: string
          refresh_token_secret_id: string | null
          scope: string | null
          sync_cursor: string | null
          token_expiry: string | null
          updated_at: string | null
          user_id: string
        }
        Insert: {
          access_token_secret_id?: string | null
          created_at?: string | null
          disconnected_at?: string | null
          disconnected_reason?: string | null
          external_id?: string | null
          id?: string
          last_sync_at?: string | null
          provider: string
          refresh_token_secret_id?: string | null
          scope?: string | null
          sync_cursor?: string | null
          token_expiry?: string | null
          updated_at?: string | null
          user_id: string
        }
        Update: {
          access_token_secret_id?: string | null
          created_at?: string | null
          disconnected_at?: string | null
          disconnected_reason?: string | null
          external_id?: string | null
          id?: string
          last_sync_at?: string | null
          provider?: string
          refresh_token_secret_id?: string | null
          scope?: string | null
          sync_cursor?: string | null
          token_expiry?: string | null
          updated_at?: string | null
          user_id?: string
        }
        Relationships: []
      }
      jobs: {
        Row: {
          attempts: number
          created_at: string
          finished_at: string | null
          id: number
          kind: string
          last_error: string | null
          locked_at: string | null
          locked_by: string | null
          max_attempts: number
          payload: Json
          scheduled_at: string
          status: string
          updated_at: string
        }
        Insert: {
          attempts?: number
          created_at?: string
          finished_at?: string | null
          id?: never
          kind: string
          last_error?: string | null
          locked_at?: string | null
          locked_by?: string | null
          max_attempts?: number
          payload?: Json
          scheduled_at?: string
          status?: string
          updated_at?: string
        }
        Update: {
          attempts?: number
          created_at?: string
          finished_at?: string | null
          id?: never
          kind?: string
          last_error?: string | null
          locked_at?: string | null
          locked_by?: string | null
          max_attempts?: number
          payload?: Json
          scheduled_at?: string
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      lifecycle_email_log: {
        Row: {
          sent_at: string
          template: string
          user_id: string
        }
        Insert: {
          sent_at?: string
          template: string
          user_id: string
        }
        Update: {
          sent_at?: string
          template?: string
          user_id?: string
        }
        Relationships: []
      }
      live_run_pings: {
        Row: {
          at: string
          bpm: number | null
          distance_m: number | null
          elapsed_s: number | null
          ele: number | null
          id: number
          lat: number
          lng: number
          run_id: string
          user_id: string
        }
        Insert: {
          at?: string
          bpm?: number | null
          distance_m?: number | null
          elapsed_s?: number | null
          ele?: number | null
          id?: number
          lat: number
          lng: number
          run_id: string
          user_id: string
        }
        Update: {
          at?: string
          bpm?: number | null
          distance_m?: number | null
          elapsed_s?: number | null
          ele?: number | null
          id?: number
          lat?: number
          lng?: number
          run_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "live_run_pings_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "public_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "live_run_pings_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "runs"
            referencedColumns: ["id"]
          },
        ]
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
      notifications: {
        Row: {
          activity_id: string | null
          activity_kind: string | null
          actor_id: string | null
          club_id: string | null
          comment_id: string | null
          created_at: string
          email_sent_at: string | null
          event_id: string | null
          event_instance_start: string | null
          id: string
          kind: string
          plan_id: string | null
          read_at: string | null
          run_id: string | null
          user_id: string
          web_push_sent_at: string | null
        }
        Insert: {
          activity_id?: string | null
          activity_kind?: string | null
          actor_id?: string | null
          club_id?: string | null
          comment_id?: string | null
          created_at?: string
          email_sent_at?: string | null
          event_id?: string | null
          event_instance_start?: string | null
          id?: string
          kind: string
          plan_id?: string | null
          read_at?: string | null
          run_id?: string | null
          user_id: string
          web_push_sent_at?: string | null
        }
        Update: {
          activity_id?: string | null
          activity_kind?: string | null
          actor_id?: string | null
          club_id?: string | null
          comment_id?: string | null
          created_at?: string
          email_sent_at?: string | null
          event_id?: string | null
          event_instance_start?: string | null
          id?: string
          kind?: string
          plan_id?: string | null
          read_at?: string | null
          run_id?: string | null
          user_id?: string
          web_push_sent_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notifications_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_comment_id_fkey"
            columns: ["comment_id"]
            isOneToOne: false
            referencedRelation: "run_comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "training_plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "public_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "runs"
            referencedColumns: ["id"]
          },
        ]
      }
      personal_records: {
        Row: {
          achieved_at: string
          best_time_s: number
          distance: string
          run_id: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          achieved_at: string
          best_time_s: number
          distance: string
          run_id?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          achieved_at?: string
          best_time_s?: number
          distance?: string
          run_id?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "personal_records_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "public_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "personal_records_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "runs"
            referencedColumns: ["id"]
          },
        ]
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
          manually_completed: boolean
          notes: string | null
          pace_zone: string | null
          scheduled_date: string
          structure: Json | null
          target_distance_m: number | null
          target_duration_seconds: number | null
          target_pace_end_sec_per_km: number | null
          target_pace_sec_per_km: number | null
          target_pace_tolerance_sec: number | null
          updated_at: string | null
          updated_by: string | null
          week_id: string
        }
        Insert: {
          completed_at?: string | null
          completed_run_id?: string | null
          id?: string
          kind: Database["public"]["Enums"]["workout_kind"]
          manually_completed?: boolean
          notes?: string | null
          pace_zone?: string | null
          scheduled_date: string
          structure?: Json | null
          target_distance_m?: number | null
          target_duration_seconds?: number | null
          target_pace_end_sec_per_km?: number | null
          target_pace_sec_per_km?: number | null
          target_pace_tolerance_sec?: number | null
          updated_at?: string | null
          updated_by?: string | null
          week_id: string
        }
        Update: {
          completed_at?: string | null
          completed_run_id?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["workout_kind"]
          manually_completed?: boolean
          notes?: string | null
          pace_zone?: string | null
          scheduled_date?: string
          structure?: Json | null
          target_distance_m?: number | null
          target_duration_seconds?: number | null
          target_pace_end_sec_per_km?: number | null
          target_pace_sec_per_km?: number | null
          target_pace_tolerance_sec?: number | null
          updated_at?: string | null
          updated_by?: string | null
          week_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "plan_workouts_completed_run_id_fkey"
            columns: ["completed_run_id"]
            isOneToOne: false
            referencedRelation: "public_runs"
            referencedColumns: ["id"]
          },
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
          created_at: string
          event_id: string
          finished_at: string | null
          instance_start: string
          is_auto_approve: boolean
          started_at: string | null
          started_by: string | null
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          event_id: string
          finished_at?: string | null
          instance_start: string
          is_auto_approve?: boolean
          started_at?: string | null
          started_by?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          event_id?: string
          finished_at?: string | null
          instance_start?: string
          is_auto_approve?: boolean
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
      rate_limits: {
        Row: {
          bucket: string
          count: number
          user_id: string
          window_start: string
        }
        Insert: {
          bucket: string
          count?: number
          user_id: string
          window_start: string
        }
        Update: {
          bucket?: string
          count?: number
          user_id?: string
          window_start?: string
        }
        Relationships: []
      }
      reports: {
        Row: {
          created_at: string
          id: string
          notes: string | null
          reason: string
          reporter_id: string
          resolution: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          target_id: string
          target_kind: string
        }
        Insert: {
          created_at?: string
          id?: string
          notes?: string | null
          reason: string
          reporter_id: string
          resolution?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          target_id: string
          target_kind: string
        }
        Update: {
          created_at?: string
          id?: string
          notes?: string | null
          reason?: string
          reporter_id?: string
          resolution?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          target_id?: string
          target_kind?: string
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
            referencedRelation: "public_routes"
            referencedColumns: ["id"]
          },
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
          club_id: string | null
          created_at: string | null
          description: string | null
          distance_m: number
          elevation_m: number | null
          featured_at: string | null
          geom: unknown
          id: string
          is_featured: boolean
          is_public: boolean | null
          is_starred: boolean
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
          club_id?: string | null
          created_at?: string | null
          description?: string | null
          distance_m: number
          elevation_m?: number | null
          featured_at?: string | null
          geom?: unknown
          id?: string
          is_featured?: boolean
          is_public?: boolean | null
          is_starred?: boolean
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
          club_id?: string | null
          created_at?: string | null
          description?: string | null
          distance_m?: number
          elevation_m?: number | null
          featured_at?: string | null
          geom?: unknown
          id?: string
          is_featured?: boolean
          is_public?: boolean | null
          is_starred?: boolean
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
        Relationships: [
          {
            foreignKeyName: "routes_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
        ]
      }
      run_comments: {
        Row: {
          author_id: string
          body: string
          created_at: string
          id: string
          parent_comment_id: string | null
          run_id: string
          updated_at: string
        }
        Insert: {
          author_id: string
          body: string
          created_at?: string
          id?: string
          parent_comment_id?: string | null
          run_id: string
          updated_at?: string
        }
        Update: {
          author_id?: string
          body?: string
          created_at?: string
          id?: string
          parent_comment_id?: string | null
          run_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "run_comments_parent_comment_id_fkey"
            columns: ["parent_comment_id"]
            isOneToOne: false
            referencedRelation: "run_comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "run_comments_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "public_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "run_comments_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "runs"
            referencedColumns: ["id"]
          },
        ]
      }
      run_gear: {
        Row: {
          created_at: string
          gear_id: string
          run_id: string
        }
        Insert: {
          created_at?: string
          gear_id: string
          run_id: string
        }
        Update: {
          created_at?: string
          gear_id?: string
          run_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "run_gear_gear_id_fkey"
            columns: ["gear_id"]
            isOneToOne: false
            referencedRelation: "gear"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "run_gear_gear_id_fkey"
            columns: ["gear_id"]
            isOneToOne: false
            referencedRelation: "gear_with_distance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "run_gear_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "public_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "run_gear_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "runs"
            referencedColumns: ["id"]
          },
        ]
      }
      run_kudos: {
        Row: {
          given_at: string
          run_id: string
          user_id: string
        }
        Insert: {
          given_at?: string
          run_id: string
          user_id: string
        }
        Update: {
          given_at?: string
          run_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "run_kudos_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "public_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "run_kudos_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "runs"
            referencedColumns: ["id"]
          },
        ]
      }
      run_matched_tracks: {
        Row: {
          algorithm: string | null
          algorithm_version: string | null
          attempts: number
          created_at: string
          error_message: string | null
          matched_at: string | null
          matched_track_url: string | null
          run_id: string
          source_track_url: string | null
          status: string
          updated_at: string
        }
        Insert: {
          algorithm?: string | null
          algorithm_version?: string | null
          attempts?: number
          created_at?: string
          error_message?: string | null
          matched_at?: string | null
          matched_track_url?: string | null
          run_id: string
          source_track_url?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          algorithm?: string | null
          algorithm_version?: string | null
          attempts?: number
          created_at?: string
          error_message?: string | null
          matched_at?: string | null
          matched_track_url?: string | null
          run_id?: string
          source_track_url?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "run_matched_tracks_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: true
            referencedRelation: "public_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "run_matched_tracks_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: true
            referencedRelation: "runs"
            referencedColumns: ["id"]
          },
        ]
      }
      run_photos: {
        Row: {
          caption: string | null
          created_at: string
          event_id: string | null
          event_instance_start: string | null
          id: string
          owner_id: string
          position_idx: number
          run_id: string
          storage_path: string
          thumb_512_path: string | null
        }
        Insert: {
          caption?: string | null
          created_at?: string
          event_id?: string | null
          event_instance_start?: string | null
          id?: string
          owner_id: string
          position_idx?: number
          run_id: string
          storage_path: string
          thumb_512_path?: string | null
        }
        Update: {
          caption?: string | null
          created_at?: string
          event_id?: string | null
          event_instance_start?: string | null
          id?: string
          owner_id?: string
          position_idx?: number
          run_id?: string
          storage_path?: string
          thumb_512_path?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "run_photos_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "run_photos_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "public_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "run_photos_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "runs"
            referencedColumns: ["id"]
          },
        ]
      }
      runs: {
        Row: {
          activity_type: string
          created_at: string | null
          distance_m: number
          duration_s: number
          event_id: string | null
          external_id: string | null
          hr_series_url: string | null
          id: string
          is_dnf: boolean
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
          activity_type?: string
          created_at?: string | null
          distance_m: number
          duration_s: number
          event_id?: string | null
          external_id?: string | null
          hr_series_url?: string | null
          id?: string
          is_dnf?: boolean
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
          activity_type?: string
          created_at?: string | null
          distance_m?: number
          duration_s?: number
          event_id?: string | null
          external_id?: string | null
          hr_series_url?: string | null
          id?: string
          is_dnf?: boolean
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
            referencedRelation: "public_routes"
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
      safety_contacts: {
        Row: {
          confirm_token: string
          confirmed_at: string | null
          contact_email: string
          contact_user_id: string | null
          created_at: string
          id: string
          owner_id: string
          updated_at: string
        }
        Insert: {
          confirm_token?: string
          confirmed_at?: string | null
          contact_email: string
          contact_user_id?: string | null
          created_at?: string
          id?: string
          owner_id: string
          updated_at?: string
        }
        Update: {
          confirm_token?: string
          confirmed_at?: string | null
          contact_email?: string
          contact_user_id?: string | null
          created_at?: string
          id?: string
          owner_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      saved_routes: {
        Row: {
          route_id: string
          saved_at: string
          user_id: string
        }
        Insert: {
          route_id: string
          saved_at?: string
          user_id: string
        }
        Update: {
          route_id?: string
          saved_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "saved_routes_route_id_fkey"
            columns: ["route_id"]
            isOneToOne: false
            referencedRelation: "public_routes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "saved_routes_route_id_fkey"
            columns: ["route_id"]
            isOneToOne: false
            referencedRelation: "routes"
            referencedColumns: ["id"]
          },
        ]
      }
      segment_efforts: {
        Row: {
          created_at: string
          id: string
          run_id: string
          segment_id: string
          started_at: string
          time_seconds: number
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          run_id: string
          segment_id: string
          started_at: string
          time_seconds: number
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          run_id?: string
          segment_id?: string
          started_at?: string
          time_seconds?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "segment_efforts_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "public_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "segment_efforts_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "segment_efforts_segment_id_fkey"
            columns: ["segment_id"]
            isOneToOne: false
            referencedRelation: "segments"
            referencedColumns: ["id"]
          },
        ]
      }
      segments: {
        Row: {
          author_id: string | null
          created_at: string
          end_distance_m: number
          id: string
          length_m: number | null
          name: string
          route_id: string
          start_distance_m: number
        }
        Insert: {
          author_id?: string | null
          created_at?: string
          end_distance_m: number
          id?: string
          length_m?: number | null
          name: string
          route_id: string
          start_distance_m: number
        }
        Update: {
          author_id?: string | null
          created_at?: string
          end_distance_m?: number
          id?: string
          length_m?: number | null
          name?: string
          route_id?: string
          start_distance_m?: number
        }
        Relationships: [
          {
            foreignKeyName: "segments_route_id_fkey"
            columns: ["route_id"]
            isOneToOne: false
            referencedRelation: "public_routes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "segments_route_id_fkey"
            columns: ["route_id"]
            isOneToOne: false
            referencedRelation: "routes"
            referencedColumns: ["id"]
          },
        ]
      }
      training_plans: {
        Row: {
          club_id: string | null
          created_at: string | null
          current_5k_seconds: number | null
          days_per_week: number
          end_date: string
          goal_distance_m: number
          goal_event: Database["public"]["Enums"]["goal_event"]
          goal_time_seconds: number | null
          id: string
          is_template: boolean
          name: string
          notes: string | null
          parent_template_id: string | null
          rules: Json | null
          source: string
          start_date: string
          status: string
          updated_at: string | null
          user_id: string
          vdot: number | null
        }
        Insert: {
          club_id?: string | null
          created_at?: string | null
          current_5k_seconds?: number | null
          days_per_week?: number
          end_date: string
          goal_distance_m: number
          goal_event: Database["public"]["Enums"]["goal_event"]
          goal_time_seconds?: number | null
          id?: string
          is_template?: boolean
          name: string
          notes?: string | null
          parent_template_id?: string | null
          rules?: Json | null
          source?: string
          start_date: string
          status?: string
          updated_at?: string | null
          user_id: string
          vdot?: number | null
        }
        Update: {
          club_id?: string | null
          created_at?: string | null
          current_5k_seconds?: number | null
          days_per_week?: number
          end_date?: string
          goal_distance_m?: number
          goal_event?: Database["public"]["Enums"]["goal_event"]
          goal_time_seconds?: number | null
          id?: string
          is_template?: boolean
          name?: string
          notes?: string | null
          parent_template_id?: string | null
          rules?: Json | null
          source?: string
          start_date?: string
          status?: string
          updated_at?: string | null
          user_id?: string
          vdot?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "training_plans_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "training_plans_parent_template_id_fkey"
            columns: ["parent_template_id"]
            isOneToOne: false
            referencedRelation: "training_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      user_blocks: {
        Row: {
          blocked_id: string
          blocker_id: string
          created_at: string
          reason: string | null
        }
        Insert: {
          blocked_id: string
          blocker_id: string
          created_at?: string
          reason?: string | null
        }
        Update: {
          blocked_id?: string
          blocker_id?: string
          created_at?: string
          reason?: string | null
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
      user_follows: {
        Row: {
          followed_at: string
          followee_id: string
          follower_id: string
        }
        Insert: {
          followed_at?: string
          followee_id: string
          follower_id: string
        }
        Update: {
          followed_at?: string
          followee_id?: string
          follower_id?: string
        }
        Relationships: []
      }
      user_profiles: {
        Row: {
          age_confirmed_at: string | null
          avatar_url: string | null
          billing_issue_at: string | null
          coach_consent_at: string | null
          created_at: string | null
          date_of_birth: string | null
          display_name: string | null
          gender: string | null
          health_data_consent_at: string | null
          height_cm: number | null
          id: string
          onboarded_at: string | null
          parkrun_number: string | null
          preferred_unit: string | null
          subscription_at: string | null
          subscription_tier: string | null
          terms_accepted_at: string | null
        }
        Insert: {
          age_confirmed_at?: string | null
          avatar_url?: string | null
          billing_issue_at?: string | null
          coach_consent_at?: string | null
          created_at?: string | null
          date_of_birth?: string | null
          display_name?: string | null
          gender?: string | null
          health_data_consent_at?: string | null
          height_cm?: number | null
          id: string
          onboarded_at?: string | null
          parkrun_number?: string | null
          preferred_unit?: string | null
          subscription_at?: string | null
          subscription_tier?: string | null
          terms_accepted_at?: string | null
        }
        Update: {
          age_confirmed_at?: string | null
          avatar_url?: string | null
          billing_issue_at?: string | null
          coach_consent_at?: string | null
          created_at?: string | null
          date_of_birth?: string | null
          display_name?: string | null
          gender?: string | null
          health_data_consent_at?: string | null
          height_cm?: number | null
          id?: string
          onboarded_at?: string | null
          parkrun_number?: string | null
          preferred_unit?: string | null
          subscription_at?: string | null
          subscription_tier?: string | null
          terms_accepted_at?: string | null
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
      webhook_events: {
        Row: {
          event_id: string
          provider: string
          received_at: string
        }
        Insert: {
          event_id: string
          provider: string
          received_at?: string
        }
        Update: {
          event_id?: string
          provider?: string
          received_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      activities: {
        Row: {
          id: string | null
          is_public: boolean | null
          kind: string | null
          started_at: string | null
          summary: Json | null
          user_id: string | null
        }
        Relationships: []
      }
      event_results_redacted: {
        Row: {
          age_grade_pct: number | null
          bib: string | null
          created_at: string | null
          distance_m: number | null
          duration_s: number | null
          event_id: string | null
          finisher_name: string | null
          finisher_status: string | null
          id: string | null
          instance_start: string | null
          note: string | null
          organiser_approved: boolean | null
          rank: number | null
          run_id: string | null
          updated_at: string | null
          user_id: string | null
        }
        Insert: {
          age_grade_pct?: never
          bib?: string | null
          created_at?: string | null
          distance_m?: number | null
          duration_s?: number | null
          event_id?: string | null
          finisher_name?: string | null
          finisher_status?: string | null
          id?: string | null
          instance_start?: string | null
          note?: never
          organiser_approved?: boolean | null
          rank?: number | null
          run_id?: never
          updated_at?: string | null
          user_id?: string | null
        }
        Update: {
          age_grade_pct?: never
          bib?: string | null
          created_at?: string | null
          distance_m?: number | null
          duration_s?: number | null
          event_id?: string | null
          finisher_name?: string | null
          finisher_status?: string | null
          id?: string | null
          instance_start?: string | null
          note?: never
          organiser_approved?: boolean | null
          rank?: number | null
          run_id?: never
          updated_at?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "event_results_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
        ]
      }
      gear_with_distance: {
        Row: {
          brand: string | null
          created_at: string | null
          id: string | null
          is_default: boolean | null
          kind: string | null
          model: string | null
          name: string | null
          notes: string | null
          owner_id: string | null
          purchased_at: string | null
          retired_at: string | null
          run_count: number | null
          target_distance_m: number | null
          total_distance_m: number | null
          updated_at: string | null
        }
        Relationships: []
      }
      mv_weekly_mileage: {
        Row: {
          run_count: number | null
          total_distance_m: number | null
          user_id: string | null
          week_start: string | null
        }
        Relationships: []
      }
      public_profiles: {
        Row: {
          avatar_url: string | null
          display_name: string | null
          id: string | null
        }
        Insert: {
          avatar_url?: string | null
          display_name?: string | null
          id?: string | null
        }
        Update: {
          avatar_url?: string | null
          display_name?: string | null
          id?: string | null
        }
        Relationships: []
      }
      public_routes: {
        Row: {
          club_id: string | null
          created_at: string | null
          distance_m: number | null
          elevation_m: number | null
          featured_at: string | null
          id: string | null
          is_featured: boolean | null
          is_public: boolean | null
          name: string | null
          run_count: number | null
          slug: string | null
          surface: string | null
          tags: string[] | null
          updated_at: string | null
          user_id: string | null
        }
        Insert: {
          club_id?: never
          created_at?: string | null
          distance_m?: number | null
          elevation_m?: number | null
          featured_at?: string | null
          id?: string | null
          is_featured?: boolean | null
          is_public?: boolean | null
          name?: string | null
          run_count?: number | null
          slug?: string | null
          surface?: string | null
          tags?: string[] | null
          updated_at?: string | null
          user_id?: string | null
        }
        Update: {
          club_id?: never
          created_at?: string | null
          distance_m?: number | null
          elevation_m?: number | null
          featured_at?: string | null
          id?: string | null
          is_featured?: boolean | null
          is_public?: boolean | null
          name?: string | null
          run_count?: number | null
          slug?: string | null
          surface?: string | null
          tags?: string[] | null
          updated_at?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      public_runs: {
        Row: {
          activity_type: string | null
          created_at: string | null
          distance_m: number | null
          duration_s: number | null
          event_id: string | null
          has_track: boolean | null
          id: string | null
          is_dnf: boolean | null
          is_public: boolean | null
          metadata: Json | null
          route_id: string | null
          source: string | null
          started_at: string | null
          user_id: string | null
        }
        Insert: {
          activity_type?: string | null
          created_at?: string | null
          distance_m?: number | null
          duration_s?: number | null
          event_id?: never
          has_track?: never
          id?: string | null
          is_dnf?: boolean | null
          is_public?: boolean | null
          metadata?: never
          route_id?: never
          source?: string | null
          started_at?: string | null
          user_id?: string | null
        }
        Update: {
          activity_type?: string | null
          created_at?: string | null
          distance_m?: number | null
          duration_s?: number | null
          event_id?: never
          has_track?: never
          id?: string | null
          is_dnf?: boolean | null
          is_public?: boolean | null
          metadata?: never
          route_id?: never
          source?: string | null
          started_at?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      race_sessions_redacted: {
        Row: {
          created_at: string | null
          event_id: string | null
          finished_at: string | null
          instance_start: string | null
          is_auto_approve: boolean | null
          started_at: string | null
          started_by: string | null
          status: string | null
          updated_at: string | null
        }
        Insert: {
          created_at?: string | null
          event_id?: string | null
          finished_at?: string | null
          instance_start?: string | null
          is_auto_approve?: never
          started_at?: string | null
          started_by?: never
          status?: string | null
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          event_id?: string | null
          finished_at?: string | null
          instance_start?: string | null
          is_auto_approve?: never
          started_at?: string | null
          started_by?: never
          status?: string | null
          updated_at?: string | null
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
    }
    Functions: {
      _privacy_downsample: {
        Args: { arr: Json; max_out: number }
        Returns: Json
      }
      _run_comment_parent_is_top_level: {
        Args: { parent_id: string }
        Returns: boolean
      }
      approve_event_result: {
        Args: {
          p_approve: boolean
          p_event_id: string
          p_instance_start: string
          p_user_id: string
        }
        Returns: {
          age_grade_pct: number | null
          bib: string | null
          created_at: string
          distance_m: number
          duration_s: number
          event_id: string
          finisher_name: string | null
          finisher_status: string
          id: string
          instance_start: string
          note: string | null
          organiser_approved: boolean
          organiser_approved_at: string | null
          organiser_approved_by: string | null
          rank: number | null
          run_id: string | null
          updated_at: string
          user_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "event_results"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      block_user: {
        Args: { p_reason?: string; p_target: string }
        Returns: undefined
      }
      check_rate_limit: {
        Args: {
          p_bucket: string
          p_max: number
          p_user_id: string
          p_window_seconds: number
        }
        Returns: {
          allowed: boolean
          retry_after_seconds: number
        }[]
      }
      check_rate_limit_tiered: {
        Args: {
          p_bucket: string
          p_free_max: number
          p_pro_max: number
          p_user_id: string
          p_window_seconds: number
        }
        Returns: {
          allowed: boolean
          retry_after_seconds: number
          tier: string
        }[]
      }
      claim_event_result: {
        Args: { p_result_id: string }
        Returns: {
          claimant_id: string
          created_at: string
          decided_at: string | null
          decided_by: string | null
          id: string
          result_id: string
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "event_result_claims"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      claim_next_job: {
        Args: { kind_filter?: string; worker_id: string }
        Returns: {
          attempts: number
          id: number
          kind: string
          payload: Json
        }[]
      }
      cleanup_stale_export_blobs: { Args: never; Returns: number }
      cleanup_stale_live_run_pings: { Args: never; Returns: number }
      cleanup_stale_race_pings: { Args: never; Returns: number }
      cleanup_stale_rate_limits: { Args: never; Returns: number }
      cleanup_stale_user_coach_usage: { Args: never; Returns: number }
      clear_push_subscription: {
        Args: { p_device_id: string; p_user_id: string }
        Returns: undefined
      }
      clip_route_for_viewer: { Args: { p_route_id: string }; Returns: Json }
      clip_track_for_user: {
        Args: { points: Json; target_user_id: string }
        Returns: Json
      }
      clone_plan_template: {
        Args: { new_start_date: string; template_id: string }
        Returns: string
      }
      clubs_in_bbox: {
        Args: {
          p_limit?: number
          p_max_lat: number
          p_max_lng: number
          p_min_lat: number
          p_min_lng: number
        }
        Returns: {
          avatar_url: string
          id: string
          lat: number
          lng: number
          location_label: string
          member_count: number
          name: string
          slug: string
        }[]
      }
      confirm_age_and_terms: { Args: never; Returns: undefined }
      confirm_safety_contact: { Args: { p_id: string }; Returns: boolean }
      confirm_safety_contact_by_token: {
        Args: { p_token: string }
        Returns: boolean
      }
      cron_schedule_status: { Args: { p_jobname: string }; Returns: Json }
      decide_event_result_claim: {
        Args: { p_approve: boolean; p_claim_id: string }
        Returns: {
          claimant_id: string
          created_at: string
          decided_at: string | null
          decided_by: string | null
          id: string
          result_id: string
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "event_result_claims"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      decline_safety_contact: { Args: { p_id: string }; Returns: boolean }
      decrement_coach_usage: { Args: { p_user_id: string }; Returns: number }
      defer_job: {
        Args: { delay_seconds: number; err?: string; job_id: number }
        Returns: string
      }
      delete_user_integration_secrets: {
        Args: { p_user_id: string }
        Returns: number
      }
      delete_user_provider_secrets: {
        Args: { p_provider: string; p_user_id: string }
        Returns: number
      }
      discoverable_routes_in_bbox: {
        Args: {
          p_dist_max?: number[]
          p_dist_min?: number[]
          p_filter?: string
          p_limit?: number
          p_max_lat: number
          p_max_lng: number
          p_min_lat: number
          p_min_lng: number
        }
        Returns: {
          distance_m: number
          elevation_m: number
          id: string
          is_featured: boolean
          lat: number
          lng: number
          name: string
          run_count: number
          slug: string
          surface: string
        }[]
      }
      duplicate_plan_week: {
        Args: { p_plan_id: string; p_week_index: number }
        Returns: string
      }
      end_coach_link: { Args: { p_id: string }; Returns: boolean }
      enforce_create_rate_limit: {
        Args: {
          p_bucket: string
          p_max: number
          p_user_id: string
          p_window_seconds: number
        }
        Returns: undefined
      }
      enqueue_event_reminders: { Args: never; Returns: undefined }
      enqueue_run_rematch: { Args: { p_run_id: string }; Returns: Json }
      find_failed_jobs: {
        Args: { p_failed_within?: string }
        Returns: {
          age: string
          attempts: number
          finished_at: string
          id: number
          kind: string
          last_error: string
        }[]
      }
      find_stuck_jobs: {
        Args: { p_stuck_after?: string }
        Returns: {
          age: string
          attempts: number
          id: number
          kind: string
          locked_at: string
          locked_by: string
        }[]
      }
      finish_job: {
        Args: { err?: string; job_id: number; result_status: string }
        Returns: undefined
      }
      get_club_invite_token: { Args: { target_club: string }; Returns: string }
      get_coach_usage: { Args: { p_user_id: string }; Returns: number }
      get_event_meet_point: {
        Args: { p_event_id: string }
        Returns: {
          meet_lat: number
          meet_lng: number
        }[]
      }
      get_integration_tokens: {
        Args: { p_provider: string; p_user_id: string }
        Returns: {
          access_token: string
          refresh_token: string
          token_expiry: string
        }[]
      }
      get_my_profile: {
        Args: never
        Returns: {
          age_confirmed_at: string | null
          avatar_url: string | null
          billing_issue_at: string | null
          coach_consent_at: string | null
          created_at: string | null
          date_of_birth: string | null
          display_name: string | null
          gender: string | null
          health_data_consent_at: string | null
          height_cm: number | null
          id: string
          onboarded_at: string | null
          parkrun_number: string | null
          preferred_unit: string | null
          subscription_at: string | null
          subscription_tier: string | null
          terms_accepted_at: string | null
        }
        SetofOptions: {
          from: "*"
          to: "user_profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      grant_health_data_consent: { Args: never; Returns: string }
      heatmap_points_in_bbox: {
        Args: {
          p_max_lat: number
          p_max_lng: number
          p_max_points?: number
          p_min_lat: number
          p_min_lng: number
        }
        Returns: {
          lat: number
          lng: number
        }[]
      }
      increment_coach_usage: { Args: { p_user_id: string }; Returns: number }
      is_blocked_either_way: {
        Args: { a: string; b: string }
        Returns: boolean
      }
      is_pro: { Args: never; Returns: boolean }
      is_public_club_by_id: { Args: { p_club_id: string }; Returns: boolean }
      is_public_event_by_id: { Args: { p_event_id: string }; Returns: boolean }
      is_public_route_by_id: { Args: { p_route_id: string }; Returns: boolean }
      job_scheduled_at_for_user: {
        Args: { p_user_id: string }
        Returns: string
      }
      jobs_failed_summary: { Args: { p_failed_within?: string }; Returns: Json }
      jobs_stuck_summary: { Args: { p_stuck_after?: string }; Returns: Json }
      join_club_by_token: { Args: { token: string }; Returns: string }
      latest_fitness_snapshot: {
        Args: never
        Returns: {
          acute_load: number | null
          chronic_load: number | null
          computed_at: string
          created_at: string
          id: string
          notes: string | null
          qualifying_run_count: number
          source: string
          training_stress_bal: number | null
          user_id: string
          vdot: number | null
          vo2_max: number | null
        }
        SetofOptions: {
          from: "*"
          to: "fitness_snapshots"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      my_pending_safety_requests: {
        Args: never
        Returns: {
          created_at: string
          id: string
          owner_name: string
        }[]
      }
      nearby_routes: {
        Args: {
          lat: number
          lng: number
          max_results?: number
          radius_m?: number
        }
        Returns: {
          club_id: string | null
          created_at: string | null
          distance_m: number | null
          elevation_m: number | null
          featured_at: string | null
          id: string | null
          is_featured: boolean | null
          is_public: boolean | null
          name: string | null
          run_count: number | null
          slug: string | null
          surface: string | null
          tags: string[] | null
          updated_at: string | null
          user_id: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "public_routes"
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
      privacy_aware_start_point: {
        Args: { p_waypoints: Json; p_zones: Json }
        Returns: unknown
      }
      privacy_distance_m: {
        Args: { lat1: number; lat2: number; lng1: number; lng2: number }
        Returns: number
      }
      privacy_in_any_zone: {
        Args: { lat: number; lng: number; zones_json: Json }
        Returns: boolean
      }
      public_profile_by_id: {
        Args: { p_id: string }
        Returns: {
          avatar_url: string
          display_name: string
          id: string
        }[]
      }
      public_run_gear: {
        Args: { p_run_id: string }
        Returns: {
          brand: string
          id: string
          kind: string
          model: string
          name: string
        }[]
      }
      recompute_event_ranks: {
        Args: { p_event_id: string; p_instance_start: string }
        Returns: undefined
      }
      record_coach_consent: { Args: never; Returns: string }
      redeem_coach_invite: { Args: { token: string }; Returns: string }
      refresh_gym_workout_totals: {
        Args: { p_workout_id: string }
        Returns: undefined
      }
      refresh_personal_records_for_user: {
        Args: { p_user_id: string }
        Returns: undefined
      }
      routes_intersecting_track: {
        Args: {
          caller_user_id: string
          max_results?: number
          tolerance_m?: number
          track_geojson: Json
        }
        Returns: {
          distance_m: number
          end_offset_m: number
          id: string
          name: string
          start_offset_m: number
        }[]
      }
      routes_within_box: {
        Args: {
          max_lat: number
          max_lng: number
          max_results?: number
          min_lat: number
          min_lng: number
        }
        Returns: {
          club_id: string | null
          created_at: string | null
          distance_m: number | null
          elevation_m: number | null
          featured_at: string | null
          id: string | null
          is_featured: boolean | null
          is_public: boolean | null
          name: string | null
          run_count: number | null
          slug: string | null
          surface: string | null
          tags: string[] | null
          updated_at: string | null
          user_id: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "public_routes"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      search_clubs: {
        Args: {
          p_center_lat?: number
          p_center_lng?: number
          p_limit?: number
          p_query?: string
          p_radius_m?: number
        }
        Returns: {
          avatar_url: string | null
          created_at: string | null
          description: string | null
          id: string
          invite_token: string | null
          is_public: boolean | null
          is_verified: boolean
          join_policy: string
          location_label: string | null
          location_point: unknown
          member_count: number
          name: string
          owner_id: string
          requires_activity_waiver: boolean
          slug: string
          updated_at: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "clubs"
          isOneToOne: false
          isSetofReturn: true
        }
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
          club_id: string | null
          created_at: string | null
          distance_m: number | null
          elevation_m: number | null
          featured_at: string | null
          id: string | null
          is_featured: boolean | null
          is_public: boolean | null
          name: string | null
          run_count: number | null
          slug: string | null
          surface: string | null
          tags: string[] | null
          updated_at: string | null
          user_id: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "public_routes"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      search_user_profiles: {
        Args: { p_limit?: number; p_query: string }
        Returns: {
          avatar_url: string
          display_name: string
          id: string
        }[]
      }
      segment_leaderboard_tiered: {
        Args: {
          p_age_band?: string
          p_club_id?: string
          p_gender?: string
          p_limit?: number
          p_segment_id: string
        }
        Returns: {
          age: number
          avatar_url: string
          display_name: string
          effort_id: string
          gender: string
          run_id: string
          started_at: string
          time_seconds: number
          user_id: string
        }[]
      }
      set_integration_tokens: {
        Args: {
          p_access_token: string
          p_provider: string
          p_refresh_token: string
          p_token_expiry?: string
          p_user_id: string
        }
        Returns: undefined
      }
      set_integration_tokens_cas: {
        Args: {
          p_access_token: string
          p_expected_refresh_token: string
          p_provider: string
          p_refresh_token: string
          p_token_expiry?: string
          p_user_id: string
        }
        Returns: boolean
      }
      submit_report: {
        Args: {
          p_notes?: string
          p_reason: string
          p_target_id: string
          p_target_kind: string
        }
        Returns: string
      }
      try_consume_strava_quota: {
        Args: { p_day_limit?: number; p_short_limit?: number }
        Returns: boolean
      }
      unblock_user: { Args: { p_target: string }; Returns: undefined }
      weekly_mileage: {
        Args: { weeks_back?: number }
        Returns: {
          total_distance_m: number
          week_start: string
        }[]
      }
      withdraw_coach_consent: { Args: never; Returns: undefined }
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
        | "walk_run"
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
        "walk_run",
      ],
    },
  },
} as const

