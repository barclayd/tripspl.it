// Zod optional inputs allow an explicit undefined in TypeScript. JSON cannot
// represent that value, and parsed stops have always omitted an undefined zone.
// Derive the exact optional output type without maintaining a second model.
type ExactOptional<T extends object> = {
  [K in keyof T as undefined extends T[K] ? never : K]: T[K];
} & {
  [K in keyof T as undefined extends T[K] ? K : never]?: Exclude<T[K], undefined>;
};

export function omitUndefined<T extends object>(value: T): ExactOptional<T> {
  return Object.fromEntries(Object.entries(value).filter(([, field]) => field !== undefined)) as ExactOptional<T>;
}
