ALTER TABLE "abuse_report" ADD COLUMN "ip_hash" text;--> statement-breakpoint
CREATE INDEX "abuse_report_link_created_idx" ON "abuse_report" USING btree ("share_link_id","created_at");