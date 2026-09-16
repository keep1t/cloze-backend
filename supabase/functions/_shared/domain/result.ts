export type DomainSuccess<TValue> = {
  ok: true;
  value: TValue;
};

export type DomainError = {
  code: string;
};

export type DomainFailure = {
  ok: false;
  error: DomainError;
};

export type DomainResult<TValue> = DomainSuccess<TValue> | DomainFailure;
