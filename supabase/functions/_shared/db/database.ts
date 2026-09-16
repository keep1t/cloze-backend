// Pinned dependencies are re-exported by deps.ts: npm:drizzle-orm@0.45.2 and npm:postgres@3.4.9.
import { drizzle, postgres } from './deps.ts';
import { requireDatabaseUrl } from './config.ts';

type ClosableClient = {
  end(options?: { timeout?: number }): Promise<void>;
};

export type DatabaseDependencies<TDatabase> = {
  createClient(
    url: string,
    options: { prepare: false },
  ): ClosableClient;
  createDatabase(client: unknown): TDatabase;
};

export type DatabaseHandle<TDatabase> = {
  database: TDatabase;
  close(): Promise<void>;
};

function defaultDependencies(): DatabaseDependencies<unknown> {
  return {
    createClient(url, options) {
      return postgres(url, options);
    },
    createDatabase(client) {
      return drizzle({ client: client as never });
    },
  };
}

export function createDatabase<TDatabase>(
  databaseUrl: string,
  dependencies: DatabaseDependencies<TDatabase> = defaultDependencies() as DatabaseDependencies<
    TDatabase
  >,
): DatabaseHandle<TDatabase> {
  const client = dependencies.createClient(requireDatabaseUrl(databaseUrl), { prepare: false });
  const database = dependencies.createDatabase(client);

  return {
    database,
    close: () => client.end(),
  };
}
