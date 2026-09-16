export interface UseCase<TInput, TOutput> {
  execute(input: TInput): Promise<TOutput>;
}

export function invoke<TInput, TOutput>(
  useCase: UseCase<TInput, TOutput>,
  input: TInput,
): Promise<TOutput> {
  return useCase.execute(input);
}
