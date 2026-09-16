export type AdapterComposition<TRepository> = {
  repository: TRepository;
};

export function composeRepository<TRepository>(
  repository: TRepository,
): AdapterComposition<TRepository> {
  return { repository };
}
