import type { Principal } from '../services/auth';

export type HonoEnvironment = {
  Bindings: Env;
  Variables: { principal: Principal };
};
