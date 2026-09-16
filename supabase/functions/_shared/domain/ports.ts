export interface Repository<TId, TRecord> {
  findById(id: TId): Promise<TRecord | null>;
  save(record: TRecord): Promise<void>;
}
