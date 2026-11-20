CREATE TABLE "device_link_code" (
	"code_hash" text PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"created_by_device_id" uuid,
	"expires_at" timestamp with time zone NOT NULL,
	"consumed_at" timestamp with time zone,
	"consumed_by_device_id" uuid,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "device_link_code" ADD CONSTRAINT "device_link_code_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "device_link_code" ADD CONSTRAINT "device_link_code_created_by_device_id_device_id_fk" FOREIGN KEY ("created_by_device_id") REFERENCES "public"."device"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "device_link_code" ADD CONSTRAINT "device_link_code_consumed_by_device_id_device_id_fk" FOREIGN KEY ("consumed_by_device_id") REFERENCES "public"."device"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "device_link_code_user_idx" ON "device_link_code" USING btree ("user_id");
