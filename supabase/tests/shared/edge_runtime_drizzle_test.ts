import {
  requireDatabaseUrl,
  RuntimeConfigurationError,
} from '../../functions/_shared/db/config.ts';
import { createDatabase, type DatabaseDependencies } from '../../functions/_shared/db/database.ts';
import type { Repository } from '../../functions/_shared/domain/ports.ts';
import type { DomainError, DomainResult } from '../../functions/_shared/domain/result.ts';
import { invoke, type UseCase } from '../../functions/_shared/application/invoke.ts';
import {
  type AdapterComposition,
  composeRepository,
} from '../../functions/_shared/adapters/composition.ts';

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (!Object.is(actual, expected)) {
    throw new Error(`${message}: expected ${String(expected)}, received ${String(actual)}`);
  }
}

function captureError(operation: () => unknown): Error {
  try {
    operation();
  } catch (error) {
    assert(error instanceof Error, 'Expected an Error instance');
    return error;
  }
  throw new Error('Expected operation to throw');
}

async function sourceFiles(directory: URL): Promise<URL[]> {
  const files: URL[] = [];
  for await (const entry of Deno.readDir(directory)) {
    const entryUrl = new URL(entry.name, directory);
    if (entry.isDirectory) {
      entryUrl.pathname += '/';
      files.push(...await sourceFiles(entryUrl));
    } else if (entry.isFile && entry.name.endsWith('.ts')) {
      files.push(entryUrl);
    }
  }
  return files;
}

Deno.test('shared runtime modules import without configuration or database I/O', async () => {
  const [configModule, databaseModule, domainModule, applicationModule] = await Promise.all([
    import('../../functions/_shared/db/config.ts'),
    import('../../functions/_shared/db/database.ts'),
    import('../../functions/_shared/domain/ports.ts'),
    import('../../functions/_shared/application/invoke.ts'),
  ]);

  assertEquals(
    typeof configModule.requireDatabaseUrl,
    'function',
    'Configuration module exposes explicit validation',
  );
  assertEquals(
    typeof databaseModule.createDatabase,
    'function',
    'Database adapter exposes explicit construction',
  );
  assertEquals(
    Object.keys(domainModule).length,
    0,
    'Domain port module has no runtime adapter exports',
  );
  assertEquals(
    typeof applicationModule.invoke,
    'function',
    'Application module exposes the invocation boundary',
  );
});

Deno.test('database URL configuration fails closed without leaking a value', () => {
  const missingError = captureError(() => requireDatabaseUrl(undefined));
  assert(
    missingError instanceof RuntimeConfigurationError,
    'Missing URL must raise RuntimeConfigurationError',
  );
  assert(
    missingError.message.includes('DRIZZLE_DATABASE_URL'),
    'Missing URL error must name DRIZZLE_DATABASE_URL',
  );

  const blankError = captureError(() => requireDatabaseUrl('   \t'));
  assert(
    blankError instanceof RuntimeConfigurationError,
    'Blank URL must raise RuntimeConfigurationError',
  );
  assert(
    blankError.message.includes('DRIZZLE_DATABASE_URL'),
    'Blank URL error must name DRIZZLE_DATABASE_URL',
  );
  assert(
    !blankError.message.includes('synthetic-password'),
    'Configuration errors must never include a database URL value',
  );

  const syntheticUrl = 'postgresql://synthetic-user:synthetic-password@invalid.test/synthetic';
  assertEquals(
    requireDatabaseUrl(syntheticUrl),
    syntheticUrl,
    'A supplied non-blank URL is returned for explicit adapter construction',
  );
});

Deno.test('database construction validates URL before invoking injected factories', () => {
  let clientFactoryCalls = 0;
  let databaseFactoryCalls = 0;
  const dependencies: DatabaseDependencies<{ kind: 'unreachable' }> = {
    createClient() {
      clientFactoryCalls += 1;
      return { end: () => Promise.resolve() };
    },
    createDatabase() {
      databaseFactoryCalls += 1;
      return { kind: 'unreachable' };
    },
  };

  const rejectedValues: Array<string | undefined> = [
    undefined,
    '',
    '   \t',
    'https://synthetic-user:synthetic-password@invalid.test/database',
    'mysql://synthetic-user:synthetic-password@invalid.test/database',
    'not-a-database-url',
  ];
  for (const value of rejectedValues) {
    const error = captureError(() => createDatabase(value as string, dependencies));
    assert(
      error instanceof RuntimeConfigurationError,
      'Invalid construction URL must raise RuntimeConfigurationError',
    );
    assert(
      error.message.includes('DRIZZLE_DATABASE_URL'),
      'Construction error must name DRIZZLE_DATABASE_URL',
    );
    if (value !== undefined && value.trim().length > 0) {
      assert(
        !error.message.includes(value),
        'Construction error must not leak the rejected database URL',
      );
    }
  }

  assertEquals(clientFactoryCalls, 0, 'Rejected URLs must not invoke the client factory');
  assertEquals(databaseFactoryCalls, 0, 'Rejected URLs must not invoke the database factory');
});

Deno.test('database construction is injected, lazy, transaction-pool safe, and explicitly closed', async () => {
  const syntheticUrl = 'postgresql://synthetic-user:synthetic-password@invalid.test/synthetic';
  const syntheticDatabase = { kind: 'synthetic-database' } as const;
  let clientFactoryCalls = 0;
  let databaseFactoryCalls = 0;
  let closeCalls = 0;
  let capturedClient: unknown;

  const syntheticClient = {
    end(_options?: { timeout?: number }): Promise<void> {
      closeCalls += 1;
      return Promise.resolve();
    },
  };
  const dependencies: DatabaseDependencies<typeof syntheticDatabase> = {
    createClient(url, options) {
      clientFactoryCalls += 1;
      assertEquals(url, syntheticUrl, 'Injected client receives only the supplied URL');
      assertEquals(options.prepare, false, 'postgres client must disable prepared statements');
      return syntheticClient;
    },
    createDatabase(client) {
      databaseFactoryCalls += 1;
      capturedClient = client;
      return syntheticDatabase;
    },
  };

  assertEquals(clientFactoryCalls, 0, 'Importing modules must not construct a database client');
  assertEquals(databaseFactoryCalls, 0, 'Importing modules must not construct a Drizzle database');

  const handle = createDatabase(syntheticUrl, dependencies);

  assertEquals(clientFactoryCalls, 1, 'Explicit construction creates one postgres client');
  assertEquals(databaseFactoryCalls, 1, 'Explicit construction creates one Drizzle database');
  assertEquals(capturedClient, syntheticClient, 'Drizzle receives the injected postgres client');
  assertEquals(handle.database, syntheticDatabase, 'Handle exposes the constructed database');
  assertEquals(closeCalls, 0, 'Construction performs no close or query-like side effect');

  await handle.close();
  assertEquals(closeCalls, 1, 'Explicit close ends the underlying client exactly once');
});

Deno.test('repository port remains a generic domain-only contract', async () => {
  type SyntheticRecord = { id: string; value: string };
  const records = new Map<string, SyntheticRecord>();
  const repository: Repository<string, SyntheticRecord> = {
    findById(id) {
      return Promise.resolve(records.get(id) ?? null);
    },
    save(record) {
      records.set(record.id, record);
      return Promise.resolve();
    },
  };

  const record = { id: 'synthetic-id', value: 'synthetic-value' };
  await repository.save(record);
  assertEquals(
    await repository.findById(record.id),
    record,
    'Repository port supports an adapter without persistence dependencies',
  );
  assertEquals(
    await repository.findById('missing-id'),
    null,
    'Repository port represents a missing record explicitly',
  );
});

Deno.test('domain result and adapter composition contracts are explicit and narrow', () => {
  const repository: Repository<string, { id: string }> = {
    findById: () => Promise.resolve(null),
    save: () => Promise.resolve(),
  };
  const composition: AdapterComposition<typeof repository> = composeRepository(repository);
  assertEquals(
    composition.repository,
    repository,
    'Composition root returns only the injected repository port',
  );

  const success: DomainResult<number> = { ok: true, value: 42 };
  const domainError: DomainError = {
    code: 'SYNTHETIC_DOMAIN_ERROR',
  };
  const failure: DomainResult<number> = { ok: false, error: domainError };

  assert(success.ok, 'Domain success uses the ok discriminator');
  if (success.ok) {
    assertEquals(success.value, 42, 'Domain success exposes its value');
  }
  assert(!failure.ok, 'Domain failure uses the ok discriminator');
  if (!failure.ok) {
    assertEquals(
      failure.error.code,
      'SYNTHETIC_DOMAIN_ERROR',
      'Domain errors expose a stable machine-readable code',
    );
  }
});

Deno.test('invoke calls the application use case exactly once and returns its result', async () => {
  let executions = 0;
  const useCase: UseCase<{ value: number }, { doubled: number }> = {
    execute(input) {
      executions += 1;
      return Promise.resolve({ doubled: input.value * 2 });
    },
  };

  const result = await invoke(useCase, { value: 21 });

  assertEquals(executions, 1, 'Application boundary executes the use case exactly once');
  assertEquals(result.doubled, 42, 'Application boundary returns the use case result');
});

Deno.test('domain, application, and composition sources preserve architecture boundaries', async () => {
  const sharedRoot = new URL('../../functions/_shared/', import.meta.url);
  const boundaryDirectories = [
    new URL('domain/', sharedRoot),
    new URL('application/', sharedRoot),
    new URL('adapters/', sharedRoot),
  ];
  const forbiddenBoundaryPattern =
    /(?:from\s+['"][^'"]*(?:\/db\/|drizzle|postgres|supabase|providers?\/)|npm:(?:drizzle-orm|postgres)|\bDeno\.env\b|\bfetch\s*\(|\b(?:pgTable|pgSchema|sqliteTable|mysqlTable|sql)\s*(?:`|\())/i;

  for (const directory of boundaryDirectories) {
    for (const file of await sourceFiles(directory)) {
      const source = await Deno.readTextFile(file);
      assert(
        !forbiddenBoundaryPattern.test(source),
        `${file.pathname} must not import or declare database/provider infrastructure`,
      );
    }
  }

  const dependencyImport = /(?:from\s+|import\s*)['"]npm:(?:drizzle-orm|postgres)(?:@|\/|['"])/i;
  for (const file of await sourceFiles(sharedRoot)) {
    const source = await Deno.readTextFile(file);
    if (dependencyImport.test(source)) {
      assert(
        file.pathname.endsWith('/db/deps.ts'),
        'Pinned Drizzle and postgres imports must remain isolated in db/deps.ts',
      );
    }
  }
});
