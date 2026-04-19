import { neon } from '@neondatabase/serverless';
import { drizzle } from 'drizzle-orm/neon-http';
import * as schema from '~/db/schema';

// New client per request — Neon's HTTP driver is fetch-based and cheap to create.
export const createDb = (url: string) => drizzle(neon(url), { schema });

export type Db = ReturnType<typeof createDb>;
