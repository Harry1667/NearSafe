CREATE TYPE "public"."feedback_type" AS ENUM('helpful', 'too_noisy');--> statement-breakpoint
CREATE TYPE "public"."relationship_status" AS ENUM('pending', 'accepted', 'rejected', 'revoked');--> statement-breakpoint
CREATE TYPE "public"."safety_category" AS ENUM('fire', 'violence', 'traffic');--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "events" (
	"id" uuid PRIMARY KEY DEFAULT uuid_generate_v4() NOT NULL,
	"category" "safety_category" NOT NULL,
	"severity" integer NOT NULL,
	"point" "geography(Point, 4326)" NOT NULL,
	"title" text NOT NULL,
	"summary" text NOT NULL,
	"sources" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"fingerprint" text NOT NULL,
	"occurred_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "events_fingerprint_unique" UNIQUE("fingerprint")
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "invite_codes" (
	"code" text PRIMARY KEY NOT NULL,
	"watcher_user_id" uuid NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"consumed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "notifications" (
	"id" uuid PRIMARY KEY DEFAULT uuid_generate_v4() NOT NULL,
	"user_id" uuid NOT NULL,
	"event_id" uuid NOT NULL,
	"watched_location_id" uuid NOT NULL,
	"distance_m" integer NOT NULL,
	"feedback" "feedback_type",
	"action_taken" text,
	"sent_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "relationships" (
	"id" uuid PRIMARY KEY DEFAULT uuid_generate_v4() NOT NULL,
	"watcher_user_id" uuid NOT NULL,
	"watched_user_id" uuid NOT NULL,
	"status" "relationship_status" DEFAULT 'pending' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"responded_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "users" (
	"id" uuid PRIMARY KEY DEFAULT uuid_generate_v4() NOT NULL,
	"device_id" text NOT NULL,
	"display_name" text,
	"push_token" text,
	"push_platform" text,
	"settings" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "users_device_id_unique" UNIQUE("device_id")
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "watched_locations" (
	"id" uuid PRIMARY KEY DEFAULT uuid_generate_v4() NOT NULL,
	"watcher_user_id" uuid NOT NULL,
	"relationship_id" uuid,
	"name" text NOT NULL,
	"address" text NOT NULL,
	"point" "geography(Point, 4326)" NOT NULL,
	"radius_m" integer NOT NULL,
	"is_paused" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "invite_codes" ADD CONSTRAINT "invite_codes_watcher_user_id_users_id_fk" FOREIGN KEY ("watcher_user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "notifications" ADD CONSTRAINT "notifications_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "notifications" ADD CONSTRAINT "notifications_event_id_events_id_fk" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "notifications" ADD CONSTRAINT "notifications_watched_location_id_watched_locations_id_fk" FOREIGN KEY ("watched_location_id") REFERENCES "public"."watched_locations"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "relationships" ADD CONSTRAINT "relationships_watcher_user_id_users_id_fk" FOREIGN KEY ("watcher_user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "relationships" ADD CONSTRAINT "relationships_watched_user_id_users_id_fk" FOREIGN KEY ("watched_user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "watched_locations" ADD CONSTRAINT "watched_locations_watcher_user_id_users_id_fk" FOREIGN KEY ("watcher_user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "watched_locations" ADD CONSTRAINT "watched_locations_relationship_id_relationships_id_fk" FOREIGN KEY ("relationship_id") REFERENCES "public"."relationships"("id") ON DELETE set null ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "events_point_gist" ON "events" USING gist ("point");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "events_occurred_idx" ON "events" USING btree ("occurred_at" DESC NULLS LAST);--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "relationships_pair_unique" ON "relationships" USING btree ("watcher_user_id","watched_user_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "watched_locations_point_gist" ON "watched_locations" USING gist ("point");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "watched_locations_watcher_idx" ON "watched_locations" USING btree ("watcher_user_id");