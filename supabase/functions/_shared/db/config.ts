export class RuntimeConfigurationError extends Error {
  constructor(key: string) {
    super(`Missing or invalid configuration: ${key}`);
    this.name = 'RuntimeConfigurationError';
  }
}

export function requireDatabaseUrl(value: string | undefined): string {
  if (value === undefined || value.trim().length === 0) {
    throw new RuntimeConfigurationError('DRIZZLE_DATABASE_URL');
  }

  try {
    const url = new URL(value);
    if (url.protocol !== 'postgres:' && url.protocol !== 'postgresql:') {
      throw new RuntimeConfigurationError('DRIZZLE_DATABASE_URL');
    }
  } catch (error) {
    if (error instanceof RuntimeConfigurationError) {
      throw error;
    }
    throw new RuntimeConfigurationError('DRIZZLE_DATABASE_URL');
  }

  return value;
}
