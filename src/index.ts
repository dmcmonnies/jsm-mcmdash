/**
 * Setup Manager HUD Worker Entry Point
 *
 * This file re-exports the core package. Customize by wrapping
 * the app.fetch handler or adding your own routes.
 */
import { app, DashboardRoom } from '@motionbug/setupmanagerhud-core';
import type { Env } from '@motionbug/setupmanagerhud-core';

// Re-export Durable Object class (required by Cloudflare)
export { DashboardRoom };

// Default export for Cloudflare Workers
export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return app.fetch(request, env);
  },
};
